#include "script_component.hpp"

/*
 * Garrison overhaul — individual units in building positions.
 *
 * Each unit gets its own group for independent AI behavior. No formation
 * logic pulling units out of buildings during CQB. Unit classes extracted
 * from group templates for authentic faction variety.
 *
 * Anchor + Satellites model scaled by structure count at location.
 *
 * Arguments:
 *   0: Location position <ARRAY> - Center position [x, y, z]
 *   1: Group templates <ARRAY> - Classified group hashmaps from fnc_classifyGroups
 *   2: Side <SIDE> - e.g. east, west, independent
 *   3: (Optional) Config overrides <HASHMAP> - Override any config value below
 *
 * Returns:
 *   Hashmap: "units", "groups", "tags", "clusters"
 *
 * Examples:
 *   [_locationPos, _infantryGroups, east] call DSC_core_fnc_setupGarrison
 *   [_locationPos, _infantryGroups, east, createHashMapFromArray [["density", "heavy"]]] call DSC_core_fnc_setupGarrison
 */

params [
    ["_locationPos", [], [[]]],
    ["_groupTemplates", [], [[]]],
    ["_side", east, [east]],
    ["_configOverrides", createHashMap, [createHashMap]]
];

// ============================================================================
// GARRISON CONFIG — tune these values for testing
// ============================================================================
private _config = createHashMapFromArray [
    // --- Per-Building Unit Caps ---
    ["mainStructureCap", 3],            // Max units in a main (large) structure
    ["sideStructureCap", 2],            // Max units in a side (small) structure

    // --- Cluster Scaling by Structure Count at Location ---
    // Each row: [maxStructureCount, [minAnchors, maxAnchors], [minSatPerAnchor, maxSatPerAnchor]]
    ["scalingTable", [
        [4,    [1, 2], [0, 2]],         // Compound  (1-4 structures)
        [10,   [1, 2], [0, 2]],         // Village   (5-10)
        [20,   [1, 3], [0, 3]],         // Town      (11-20)
        [1000, [1, 3], [0, 3]]          // City      (21+)
    ]],

    // --- Satellite Selection ---
    ["satelliteRadius", 50],            // Max distance from anchor to claim a satellite

    // --- Density Modifier ---
    // Controls where within scaling bands values are picked
    // "light" = low end of range, "medium" = midpoint, "heavy" = high end
    ["density", "medium"],

    // --- Skill Profile ---
    ["skillProfile", "cqb_baseline"],   // Profile name from fnc_getSkillProfile
    ["skillVariance", 0],            // Per-unit random variance on each skill value

    // --- Combat Activation ---
    ["combatActivation", false],         // PATH disabled until nearby gunfire triggers FiredNear EH
    ["reactionDelay", 0.5]              // Seconds after FiredNear before PATH enables
];

// Merge caller overrides into config
{ _config set [_x, _y] } forEach _configOverrides;

// ============================================================================
// VALIDATION
// ============================================================================
private _result = createHashMapFromArray [
    ["units", []],
    ["groups", []],
    ["tags", []],
    ["clusters", []]
];

if (_locationPos isEqualTo []) exitWith {
    diag_log "DSC: setupGarrison - No location position";
    _result
};

if (_groupTemplates isEqualTo []) exitWith {
    diag_log "DSC: setupGarrison - No group templates";
    _result
};

// ============================================================================
// READ CONFIG
// ============================================================================
private _mainCap = _config get "mainStructureCap";
private _sideCap = _config get "sideStructureCap";
private _scalingTable = _config get "scalingTable";
private _satRadius = _config get "satelliteRadius";
private _density = _config get "density";
private _skillProfile = _config get "skillProfile";
private _skillVariance = _config get "skillVariance";
private _useCombatActivation = _config get "combatActivation";
private _reactionDelay = _config get "reactionDelay";

private _densityFactor = switch (_density) do {
    case "light":  { 0.0 };
    case "medium": { 0.5 };
    case "heavy":  { 1.0 };
    default        { 0.5 };
};

// ============================================================================
// GET STRUCTURES (pre-classified from populateAO, or scan as fallback)
// ============================================================================
private _mainStructures = _config getOrDefault ["mainStructures", []];
private _sideStructures = _config getOrDefault ["sideStructures", []];

if (_mainStructures isEqualTo [] && _sideStructures isEqualTo []) then {
    private _structureTypes = call DSC_core_fnc_getStructureTypes;
    private _mainTypes = _structureTypes get "main";
    private _sideTypes = _structureTypes get "side";
    private _exclusions = _structureTypes get "exclusions";

    private _locationStructures = [_locationPos, ["House"], _config getOrDefault ["radius", 200]] call DSC_core_fnc_getMapStructures;

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
    } forEach _locationStructures;
};

private _totalStructures = (count _mainStructures) + (count _sideStructures);

if (_totalStructures == 0) exitWith {
    diag_log "DSC: setupGarrison - No structures found";
    _result
};

diag_log format ["DSC: setupGarrison - %1 main + %2 side = %3 total structures",
    count _mainStructures, count _sideStructures, _totalStructures];

// ============================================================================
// SCALING TABLE LOOKUP
// ============================================================================
private _anchorRange = [1, 2];
private _satelliteRange = [1, 2];

{
    _x params ["_maxCount", "_aRange", "_sRange"];
    if (_totalStructures <= _maxCount) exitWith {
        _anchorRange = _aRange;
        _satelliteRange = _sRange;
    };
} forEach _scalingTable;

private _numAnchors = round ((_anchorRange # 0) + ((_anchorRange # 1) - (_anchorRange # 0)) * _densityFactor);
_numAnchors = _numAnchors min _totalStructures;

diag_log format ["DSC: setupGarrison - Scaling: %1 structures -> %2 anchors (density: %3, factor: %4)",
    _totalStructures, _numAnchors, _density, _densityFactor];

// ============================================================================
// BUILD UNIT CLASS POOL FROM GROUP TEMPLATES
// ============================================================================
// Walks CfgGroups configs to extract infantry classnames. Natural weighting:
// a squad with 4 riflemen and 1 MG means riflemen appear 4x more in the pool.
private _unitPool = [];

{
    private _pathParts = (_x get "path") splitString "/";
    private _groupCfg = configFile >> "CfgGroups";
    { _groupCfg = _groupCfg >> _x } forEach _pathParts;

    {
        if (isClass _x) then {
            private _class = getText (_x >> "vehicle");
            if (_class != "" && { isClass (configFile >> "CfgVehicles" >> _class) } && { _class isKindOf "Man" }) then {
                _unitPool pushBack _class;
            };
        };
    } forEach configProperties [_groupCfg, "isClass _x"];
} forEach _groupTemplates;

if (_unitPool isEqualTo []) exitWith {
    diag_log "DSC: setupGarrison - No unit classes extracted from templates";
    _result
};

private _uniqueClasses = _unitPool arrayIntersect _unitPool;
diag_log format ["DSC: setupGarrison - Unit pool: %1 total entries, %2 unique classes",
    count _unitPool, count _uniqueClasses];

// ============================================================================
// SELECT ANCHORS (main structures first, maximize spread)
// ============================================================================
private _availableMain = +_mainStructures;
private _availableSide = +_sideStructures;
private _anchors = [];

private _mainAnchors = _numAnchors min (count _availableMain);
for "_i" from 1 to _mainAnchors do {
    if (_availableMain isEqualTo []) exitWith {};

    private _anchor = if (_anchors isEqualTo []) then {
        selectRandom _availableMain
    } else {
        private _sorted = [_availableMain, [], {
            private _struct = _x;
            private _minDist = 100;
            { _minDist = _minDist min (_struct distance2D _x) } forEach _anchors;
            -_minDist
        }, "ASCEND"] call BIS_fnc_sortBy;
        _sorted select 0
    };

    _anchors pushBack _anchor;
    _availableMain = _availableMain - [_anchor];
};

private _remainingAnchors = _numAnchors - (count _anchors);
for "_i" from 1 to _remainingAnchors do {
    if (_availableSide isEqualTo []) exitWith {};

    private _anchor = if (_anchors isEqualTo []) then {
        selectRandom _availableSide
    } else {
        private _sorted = [_availableSide, [], {
            private _struct = _x;
            private _minDist = 100;
            { _minDist = _minDist min (_struct distance2D _x) } forEach _anchors;
            -_minDist
        }, "ASCEND"] call BIS_fnc_sortBy;
        _sorted select 0
    };

    _anchors pushBack _anchor;
    _availableSide = _availableSide - [_anchor];
};

diag_log format ["DSC: setupGarrison - %1 anchors selected (%2 main, %3 promoted side)",
    count _anchors, _mainAnchors, (count _anchors) - _mainAnchors];

// ============================================================================
// SPAWN UNITS — one group per unit, one unit per building position
// ============================================================================
{
    private _anchor = _x;
    private _anchorPos = getPos _anchor;

    // Attach satellites within radius
    private _numSatellites = round ((_satelliteRange # 0) + ((_satelliteRange # 1) - (_satelliteRange # 0)) * _densityFactor);
    private _nearbySide = [_availableSide, [], { _x distance2D _anchorPos }, "ASCEND"] call BIS_fnc_sortBy;
    private _satellites = [];

    {
        if ((count _satellites) >= _numSatellites) exitWith {};
        if (_x distance2D _anchorPos <= _satRadius) then {
            _satellites pushBack _x;
            _availableSide = _availableSide - [_x];
        };
    } forEach _nearbySide;

    private _clusterBuildings = [_anchor] + _satellites;
    private _clusterUnits = 0;

    (_result get "clusters") pushBack createHashMapFromArray [
        ["anchor", _anchor],
        ["satellites", _satellites],
        ["buildings", _clusterBuildings],
        ["center", _anchorPos]
    ];

    // Garrison each building in the cluster
    {
        private _building = _x;
        private _positions = _building buildingPos -1;
        if (_positions isEqualTo []) then { continue };

        private _isMain = _building in _mainStructures;
        private _cap = [_sideCap, _mainCap] select _isMain;
        private _numUnits = _cap min (count _positions);

        private _shuffled = _positions call BIS_fnc_arrayShuffle;
        private _spawnPositions = _shuffled select [0, _numUnits];

        diag_log format ["DSC: setupGarrison - Building %1 (%2): %3 positions, spawning %4",
            typeOf _building, ["side", "main"] select _isMain, count _positions, _numUnits];

        {
            private _pos = _x;
            private _unitClass = selectRandom _unitPool;
            private _grp = createGroup [_side, true];
            private _unit = _grp createUnit [_unitClass, _pos, [], 0, "NONE"];

            _unit allowDamage false;
            _unit setPos _pos;
            _unit allowDamage true;

            [_unit, _skillProfile, _skillVariance] call DSC_core_fnc_applySkillProfile;

            if (_useCombatActivation) then {
                [_grp, _reactionDelay] call DSC_core_fnc_addCombatActivation;
            };

            (_result get "groups") pushBack _grp;
            (_result get "units") pushBack _unit;
            (_result get "tags") pushBack ["GARRISON", "FOOT"];

            _clusterUnits = _clusterUnits + 1;
        } forEach _spawnPositions;

    } forEach _clusterBuildings;

    diag_log format ["DSC: setupGarrison - Cluster at %1: %2 buildings, %3 units",
        _anchorPos, count _clusterBuildings, _clusterUnits];

} forEach _anchors;

// ============================================================================
// SUMMARY
// ============================================================================
diag_log format ["DSC: setupGarrison - Complete: %1 units, %2 groups, %3 clusters",
    count (_result get "units"), count (_result get "groups"), count (_result get "clusters")];

_result
