#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_populateAO
 * Description:
 *     Populates a location with enemy forces using a multi-faction model.
 *     Target faction fills the objective compound (garrison + guards).
 *     Area faction provides ambient presence (patrols + outlying garrison)
 *     with probability driven by area influence.
 *
 *     Mission-type agnostic — objectives (HVT, sabotage, etc.) are layered on top.
 *
 * Arguments:
 *     0: _missionConfig <HASHMAP> - Mission config from fnc_selectMission
 *
 * Return Value:
 *     <HASHMAP> - Populated AO data:
 *        "location"       - The location hashmap
 *        "groups"         - All spawned groups
 *        "units"          - All spawned units
 *        "vehicles"       - All spawned vehicles (static weapons etc.)
 *        "defenderUnits"  - Guard + garrison units (for combat response triggers)
 *        "patrolGroups"   - Patrol groups specifically (for QRF convergence)
 *        "garrisonUnits"  - Garrison units specifically (for HVT placement)
 *        "tags"           - Doctrine tags per group (parallel to groups)
 *
 * Example:
 *     private _ao = [_missionConfig] call DSC_core_fnc_populateAO;
 */

params [
    ["_missionConfig", createHashMap, [createHashMap]]
];

if (_missionConfig isEqualTo createHashMap) exitWith {
    diag_log "DSC: populateAO - No mission config provided";
    createHashMapFromArray [["location", createHashMap], ["groups", []], ["units", []], ["vehicles", []], ["defenderUnits", []], ["patrolGroups", []], ["garrisonUnits", []], ["tags", []]]
};

// ============================================================================
// Read mission config
// ============================================================================
private _location = _missionConfig get "location";
private _targetFaction = _missionConfig get "targetFaction";
private _targetSide = _missionConfig get "targetSide";
private _targetGroups = _missionConfig get "targetGroups";
private _targetAssets = _missionConfig getOrDefault ["targetAssets", createHashMap];
private _areaFaction = _missionConfig get "areaFaction";
private _areaSide = _missionConfig get "areaSide";
private _areaInfluence = _missionConfig getOrDefault ["areaInfluence", 0.5];
private _areaGroups = _missionConfig getOrDefault ["areaGroups", []];
private _areaAssets = _missionConfig getOrDefault ["areaAssets", createHashMap];
private _density = _missionConfig getOrDefault ["density", "medium"];
private _areaPresenceChance = _missionConfig getOrDefault ["areaPresenceChance", 0.7];

// Read from location object
private _locationPos = _location get "position";
private _locationName = _location get "name";
private _locationRadius = _location get "radius";
private _buildingCount = _location get "buildingCount";
private _structures = _location get "structures";
private _isMilitary = _location getOrDefault ["isMilitary", false];

// If area faction is same as target, use target for everything (no split)
private _hasAreaFaction = _areaFaction != _targetFaction && { _areaGroups isNotEqualTo [] };

// Extract assets if not provided in mission config
if (_targetAssets isEqualTo createHashMap) then {
    _targetAssets = [_targetFaction] call DSC_core_fnc_extractAssets;
};
if (_hasAreaFaction && { _areaAssets isEqualTo createHashMap }) then {
    _areaAssets = [_areaFaction] call DSC_core_fnc_extractAssets;
};

// Align sides so mixed factions (e.g. opFor east + irregulars independent) don't fight each other
// Always align to east when mixing east and independent
if (_hasAreaFaction && { _areaSide != _targetSide }) then {
    private _alignedSide = if (_areaSide == east || _targetSide == east) then { east } else { _targetSide };
    diag_log format ["DSC: populateAO - Aligning sides to %1 (target was %2, area was %3)", _alignedSide, _targetSide, _areaSide];
    _targetSide = _alignedSide;
    _areaSide = _alignedSide;
};

// Force diplomatic friendship between east and independent for this mission
// Standard approach used by dynamic missions (Antistasi, ALiVE) to prevent
// faction-level hostility between cooperating forces (e.g. opFor + irregulars)
east setFriend [independent, 1];
independent setFriend [east, 1];

diag_log format ["DSC: populateAO - %1 (%2 buildings, density: %3, target: %4, area: %5)",
    _locationName, _buildingCount, _density, _targetFaction, ["same", _areaFaction] select _hasAreaFaction];

// ============================================================================
// Result tracking
// ============================================================================
private _aoResult = createHashMapFromArray [
    ["location", _location],
    ["groups", []],
    ["units", []],
    ["vehicles", []],
    ["defenderUnits", []],
    ["patrolGroups", []],
    ["garrisonUnits", []],
    ["garrisonClusters", []],
    ["tags", []]
];

if (_locationPos isEqualTo []) exitWith {
    diag_log "DSC: populateAO - No location position provided";
    _aoResult
};

// ============================================================================
// Classify structures into main/side using structure types
// ============================================================================
private _structureTypes = call DSC_core_fnc_getStructureTypes;
private _mainTypes = _structureTypes get "main";
private _sideTypes = _structureTypes get "side";
private _exclusions = _structureTypes get "exclusions";

private _mainStructures = [];
private _sideStructures = [];

{
    private _struct = _x;
    if ((_struct buildingPos -1) isEqualTo []) then { continue };

    private _isExcluded = false;
    { if (_struct isKindOf _x) exitWith { _isExcluded = true } } forEach _exclusions;
    if (_isExcluded) then { continue };

    private _isMain = false;
    { if (_struct isKindOf _x) exitWith { _isMain = true } } forEach _mainTypes;

    if (_isMain) then {
        _mainStructures pushBack _struct;
    } else {
        private _isSide = false;
        { if (_struct isKindOf _x) exitWith { _isSide = true } } forEach _sideTypes;
        if (_isSide) then {
            _sideStructures pushBack _struct;
        };
    };
} forEach _structures;

diag_log format ["DSC: populateAO - Classified %1 main, %2 side structures", count _mainStructures, count _sideStructures];

// ============================================================================
// Filter group templates (target faction)
// ============================================================================
private _targetFootGroups = [_targetGroups, ["FOOT"], ["AMPHIBIOUS", "NAVAL"]] call DSC_core_fnc_getGroupsByTag;
if (_targetFootGroups isEqualTo []) then {
    _targetFootGroups = [_targetGroups, ["PATROL"], ["ARMOR", "ARMORED", "AMPHIBIOUS", "NAVAL"]] call DSC_core_fnc_getGroupsByTag;
};
if (_targetFootGroups isEqualTo []) then {
    _targetFootGroups = _targetGroups select {
        private _tags = _x get "doctrineTags";
        !("ARMOR" in _tags) && !("ARMORED" in _tags) && !("NAVAL" in _tags)
    };
};

private _targetSpecialGroups = ([_targetGroups, ["FOOT", "AT_TEAM"], ["AMPHIBIOUS"]] call DSC_core_fnc_getGroupsByTag)
    + ([_targetGroups, ["FOOT", "AA_TEAM"], ["AMPHIBIOUS"]] call DSC_core_fnc_getGroupsByTag);

// Filter group templates (area faction) — only if different faction
private _areaFootGroups = [];
private _areaSpecialGroups = [];

if (_hasAreaFaction) then {
    _areaFootGroups = [_areaGroups, ["FOOT"], ["AMPHIBIOUS", "NAVAL"]] call DSC_core_fnc_getGroupsByTag;
    if (_areaFootGroups isEqualTo []) then {
        _areaFootGroups = [_areaGroups, ["PATROL"], ["ARMOR", "ARMORED", "AMPHIBIOUS", "NAVAL"]] call DSC_core_fnc_getGroupsByTag;
    };
    if (_areaFootGroups isEqualTo []) then {
        _areaFootGroups = _areaGroups select {
            private _tags = _x get "doctrineTags";
            !("ARMOR" in _tags) && !("ARMORED" in _tags) && !("NAVAL" in _tags)
        };
    };

    _areaSpecialGroups = ([_areaGroups, ["FOOT", "AT_TEAM"], ["AMPHIBIOUS"]] call DSC_core_fnc_getGroupsByTag)
        + ([_areaGroups, ["FOOT", "AA_TEAM"], ["AMPHIBIOUS"]] call DSC_core_fnc_getGroupsByTag);
};

diag_log format ["DSC: populateAO - Target foot: %1, Area foot: %2", count _targetFootGroups, count _areaFootGroups];

// ============================================================================
// GARRISON — target faction fills objective structures
// ============================================================================
if (_targetFootGroups isNotEqualTo [] && { _mainStructures isNotEqualTo [] || _sideStructures isNotEqualTo [] }) then {
    private _garrisonConfig = createHashMapFromArray [
        ["density", _density],
        ["mainStructures", _mainStructures],
        ["sideStructures", _sideStructures]
    ];

    // Profile overrides: force specific anchor/satellite counts
    private _garrisonAnchors = _missionConfig getOrDefault ["garrisonAnchors", []];
    if (_garrisonAnchors isNotEqualTo []) then {
        private _garrisonSatellites = _missionConfig getOrDefault ["garrisonSatellites", [0, 3]];
        _garrisonConfig set ["scalingTable", [
            [1000, _garrisonAnchors, _garrisonSatellites]
        ]];
        diag_log format ["DSC: populateAO - Garrison override: anchors %1, satellites %2", _garrisonAnchors, _garrisonSatellites];
    };

    private _garrisonResult = [_locationPos, _targetFootGroups, _targetSide, _garrisonConfig] call DSC_core_fnc_setupGarrison;

    (_aoResult get "groups") append (_garrisonResult get "groups");
    (_aoResult get "units") append (_garrisonResult get "units");
    (_aoResult get "defenderUnits") append (_garrisonResult get "units");
    (_aoResult get "garrisonUnits") append (_garrisonResult get "units");
    (_aoResult get "garrisonClusters") append (_garrisonResult get "clusters");
    (_aoResult get "tags") append (_garrisonResult get "tags");

    diag_log format ["DSC: populateAO - Garrison (target): %1 units in %2 groups", count (_garrisonResult get "units"), count (_garrisonResult get "groups")];
};

// ============================================================================
// GUARDS — target faction at entry points of garrisoned buildings
// ============================================================================
// Placed AFTER garrison so we can pass garrisonClusters for building selection.
// Guards anchor to ground-floor positions facing outward — visible deterrent.
if (_targetFootGroups isNotEqualTo [] && { (_aoResult get "garrisonClusters") isNotEqualTo [] }) then {
    private _guardConfig = createHashMapFromArray [
        ["garrisonClusters", _aoResult get "garrisonClusters"],
        ["mainStructures", _mainStructures],
        ["sideStructures", _sideStructures]
    ];

    // Profile overrides: guard coverage and density
    if ("guardCoverage" in _missionConfig) then {
        _guardConfig set ["buildingCoverage", _missionConfig get "guardCoverage"];
    };
    if ("guardsPerBuilding" in _missionConfig) then {
        _guardConfig set ["guardsPerBuilding", _missionConfig get "guardsPerBuilding"];
    };

    private _guardResult = [_locationPos, _targetFootGroups, _targetSide, _guardConfig] call DSC_core_fnc_setupGuards;

    (_aoResult get "groups") append (_guardResult get "groups");
    (_aoResult get "units") append (_guardResult get "units");
    (_aoResult get "defenderUnits") append (_guardResult get "units");

    diag_log format ["DSC: populateAO - Guards (target): %1 units", count (_guardResult get "units")];
};

// ============================================================================
// STATIC DEFENSES — military locations only (towers, bunkers, static weapons)
// ============================================================================
// if (_isMilitary && _targetFootGroups isNotEqualTo []) then {
//     private _staticConfig = createHashMapFromArray [
//         ["assets", _targetAssets],
//         ["structures", _mainStructures + _sideStructures]
//     ];
//
//     private _staticResult = [_locationPos, _targetFaction, _targetSide, _staticConfig] call DSC_core_fnc_setupStaticDefenses;
//
//     (_aoResult get "groups") append (_staticResult get "groups");
//     (_aoResult get "units") append (_staticResult get "units");
//     (_aoResult get "vehicles") append (_staticResult get "vehicles");
//     (_aoResult get "defenderUnits") append (_staticResult get "units");
//
//     diag_log format ["DSC: populateAO - Static defenses: %1 units, %2 vehicles", count (_staticResult get "units"), count (_staticResult get "vehicles")];
// };

// ============================================================================
// PARKED VEHICLES — target faction vehicles near garrison clusters
// ============================================================================
private _maxVehicles = _missionConfig getOrDefault ["maxVehicles", 4];
private _vehicleArmedChance = _missionConfig getOrDefault ["vehicleArmedChance",
    [0.2, 0.3, 0.4] select ((["light", "medium", "heavy"] find _density) max 0)];

private _vehConfig = createHashMapFromArray [
    ["assets", _targetAssets],
    ["structures", _mainStructures + _sideStructures],
    ["density", _density],
    ["maxVehicles", _maxVehicles],
    ["armedChance", _vehicleArmedChance]
];

private _vehResult = [_locationPos, _targetFaction, _targetSide, _vehConfig] call DSC_core_fnc_setupVehicles;

(_aoResult get "groups") append (_vehResult get "groups");
(_aoResult get "units") append (_vehResult get "units");
(_aoResult get "vehicles") append (_vehResult get "vehicles");

diag_log format ["DSC: populateAO - Vehicles: %1 parked, %2 with crew", count (_vehResult get "vehicles"), count (_vehResult get "units")];

// ============================================================================
// PATROLS — area faction if present, otherwise target faction
// ============================================================================
// Each patrol slot rolls independently: areaPresenceChance * areaInfluence
// determines if the patrol uses area faction or is skipped.
// Target faction always gets at least 1 patrol regardless.

private _areaPatrolSlots = switch (_density) do {
    case "light":  { [0, 1] };
    case "medium": { [1, 2] };
    case "heavy":  { [2, 3] };
    default        { [0, 1] };
};

private _patrolSpawnMin = (_locationRadius max 100) min 300;
private _patrolSpawnMax = (_patrolSpawnMin + 200) min 400;
private _patrolWaypointMin = _patrolSpawnMin + 50;
private _patrolWaypointMax = _patrolSpawnMax + 100;

// Target faction patrols — count from profile or default [1, 1]
private _targetPatrolCount = _missionConfig getOrDefault ["patrolCount", [1, 1]];

if (_targetFootGroups isNotEqualTo []) then {
    private _targetPatrolConfig = createHashMapFromArray [
        ["patrolCount", _targetPatrolCount],
        ["spawnRadius", [_patrolSpawnMin, _patrolSpawnMax]],
        ["patrolRadius", [_patrolWaypointMin, _patrolWaypointMax]],
        ["specialGroups", _targetSpecialGroups],
        ["specialChance", 0.15]
    ];

    private _targetPatrolResult = [_locationPos, _targetFootGroups, _targetSide, _targetPatrolConfig] call DSC_core_fnc_setupPatrols;

    (_aoResult get "groups") append (_targetPatrolResult get "groups");
    (_aoResult get "units") append (_targetPatrolResult get "units");
    (_aoResult get "patrolGroups") append (_targetPatrolResult get "groups");
    (_aoResult get "tags") append (_targetPatrolResult get "tags");

    diag_log format ["DSC: populateAO - Patrols (target): %1 units", count (_targetPatrolResult get "units")];
};

// Area faction patrols (probabilistic based on influence)
private _numAreaPatrols = (_areaPatrolSlots select 0) + floor random ((_areaPatrolSlots select 1) - (_areaPatrolSlots select 0) + 1);
private _effectiveChance = _areaPresenceChance * _areaInfluence;

private _patrolTemplates = [_targetFootGroups, _areaFootGroups] select _hasAreaFaction;
private _patrolSide = [_targetSide, _areaSide] select _hasAreaFaction;
private _patrolSpecial = [_targetSpecialGroups, _areaSpecialGroups] select _hasAreaFaction;
private _areaPatrolsSpawned = 0;

if (_patrolTemplates isNotEqualTo []) then {
    for "_i" from 1 to _numAreaPatrols do {
        if (random 1 > _effectiveChance) then {
            diag_log format ["DSC: populateAO - Area patrol slot %1 skipped (roll > %2)", _i, _effectiveChance toFixed 2];
            continue;
        };

        private _slotConfig = createHashMapFromArray [
            ["patrolCount", [1, 1]],
            ["spawnRadius", [_patrolSpawnMin + 100, _patrolSpawnMax + 200]],
            ["patrolRadius", [_patrolWaypointMin + 100, _patrolWaypointMax + 200]],
            ["specialGroups", _patrolSpecial],
            ["specialChance", 0.15]
        ];

        private _slotResult = [_locationPos, _patrolTemplates, _patrolSide, _slotConfig] call DSC_core_fnc_setupPatrols;

        (_aoResult get "groups") append (_slotResult get "groups");
        (_aoResult get "units") append (_slotResult get "units");
        (_aoResult get "patrolGroups") append (_slotResult get "groups");
        (_aoResult get "tags") append (_slotResult get "tags");
        _areaPatrolsSpawned = _areaPatrolsSpawned + 1;
    };

    diag_log format ["DSC: populateAO - Area patrols: %1/%2 slots filled (chance: %3)", _areaPatrolsSpawned, _numAreaPatrols, _effectiveChance toFixed 2];
};

// ============================================================================
// VEHICLE PATROLS — motorized/mechanized groups driving road loops
// ============================================================================
// Uses area faction if present, otherwise target faction.
// 1 vehicle patrol for medium density, 1-2 for heavy. None for light.

// private _vehPatrolCount = switch (_density) do {
//     case "light":  { 0 };
//     case "medium": { parseNumber (random 1 < 0.6) };
//     case "heavy":  { 1 + parseNumber (random 1 < 0.4) };
//     default        { 0 };
// };

// if (_vehPatrolCount > 0) then {
//     // Select motorized/mechanized group templates
//     private _vehPatrolSourceGroups = [_patrolTemplates, _areaGroups] select _hasAreaFaction;
//     private _vehPatrolSide = [_targetSide, _areaSide] select _hasAreaFaction;

//     // Broad filter: any group with a vehicle that has dismounts
//     private _motorizedGroups = _vehPatrolSourceGroups select {
//         private _tags = _x get "doctrineTags";
//         ("MOTORIZED" in _tags || "MECHANIZED" in _tags) && { !("ARMOR" in _tags) } && { !("NAVAL" in _tags) }
//     };

//     // Fallback: any group with vehicles and infantry
//     if (_motorizedGroups isEqualTo []) then {
//         _motorizedGroups = _vehPatrolSourceGroups select {
//             private _ua = _x get "unitAnalysis";
//             (_ua getOrDefault ["vehicleCount", 0]) > 0 && { (_ua getOrDefault ["infantryCount", 0]) >= 3 }
//         };
//     };

//     if (_motorizedGroups isNotEqualTo []) then {
//         for "_i" from 1 to _vehPatrolCount do {
//             private _template = selectRandom _motorizedGroups;

//             private _vpConfig = createHashMapFromArray [
//                 ["patrolRadius", [800, 1200, 1600]],
//                 ["dismountRadius", [200, 300, 400]],
//                 ["dismountDuration", [90, 180]],
//                 ["speed", "LIMITED"]
//             ];

//             private _vpResult = [_locationPos, _template, _vehPatrolSide, _vpConfig] call DSC_core_fnc_setupVehiclePatrol;

//             private _vpGroup = _vpResult get "group";
//             if (!isNull _vpGroup) then {
//                 (_aoResult get "groups") pushBack _vpGroup;
//                 (_aoResult get "units") append (_vpResult get "units");
//                 (_aoResult get "vehicles") pushBack (_vpResult get "vehicle");
//                 (_aoResult get "patrolGroups") pushBack _vpGroup;

//                 diag_log format ["DSC: populateAO - Vehicle patrol %1: %2 (%3)", _i, _template get "groupName", typeOf (_vpResult get "vehicle")];
//             };
//         };
//     } else {
//         diag_log "DSC: populateAO - No motorized/mechanized groups available for vehicle patrols";
//     };
// };

// ============================================================================
// Side Alignment — fix groups spawned on wrong side by BIS_fnc_spawnGroup
// ============================================================================
// BIS_fnc_spawnGroup may ignore the side parameter and use the CfgGroups
// config path side instead. Reassign any mismatched groups via joinSilent.
private _allGroups = _aoResult get "groups";
private _realignedCount = 0;

{
    private _grp = _x;
    if (side _grp != _targetSide) then {
        private _newGroup = createGroup [_targetSide, true];
        (units _grp) joinSilent _newGroup;

        // Update all tracking arrays that reference this group
        private _idx = (_aoResult get "groups") find _grp;
        if (_idx >= 0) then { (_aoResult get "groups") set [_idx, _newGroup] };

        private _patIdx = (_aoResult get "patrolGroups") find _grp;
        if (_patIdx >= 0) then { (_aoResult get "patrolGroups") set [_patIdx, _newGroup] };

        deleteGroup _grp;
        _realignedCount = _realignedCount + 1;
    };
} forEach +_allGroups;

if (_realignedCount > 0) then {
    diag_log format ["DSC: populateAO - Realigned %1 groups to side %2", _realignedCount, _targetSide];
};

// ============================================================================
// Summary
// ============================================================================
private _totalGroups = count (_aoResult get "groups");
private _totalUnits = count (_aoResult get "units");
private _totalVehicles = count (_aoResult get "vehicles");

diag_log format ["DSC: populateAO - Complete: %1 groups, %2 units, %3 vehicles at %4",
    _totalGroups, _totalUnits, _totalVehicles, _locationName];

_aoResult
