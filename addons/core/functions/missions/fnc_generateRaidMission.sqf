#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_generateRaidMission
 * Description:
 *     Generic raid mission generator. Consumes a raid config that describes
 *     entities to place, objects to place, the completion condition, and
 *     marker style. The raid pattern (single AO, attacker role) covers
 *     ~80% of planned mission types — kill/capture, supply destroy,
 *     hostage rescue, sabotage, intel gathering, dryholes — all expressed
 *     as data, not branching code.
 *
 *     Entity placement:
 *       - Each entity spec resolves its classname via fnc_resolveEntityClass
 *         using the archetype's "unitClassResolver" key.
 *       - The FIRST entity gets the bodyguard path (joins existing garrison
 *         group). Subsequent entities get fresh groups so each can carry
 *         independent behavior (HVT + hostages in same mission, etc.).
 *       - Behavior: "captive" applies setCaptive true + disableAI for AI/MOVE.
 *       - Animation: if archetype carries an "animation" key, the unit is
 *         switched to it.
 *
 *     Object placement:
 *       - Each object spec dispatches through fnc_placeObjects, which
 *         routes to the appropriate strategy (INTERIOR_FLOOR / OUTDOOR_PILE).
 *
 *     Markers:
 *       - markerStyle "compound" -> fnc_drawCompoundMarkers (default).
 *       - markerStyle "none"     -> no markers drawn.
 *
 *     Completion:
 *       - Completion config is stored on the mission hashmap; the monitor
 *         loop (caller) drives evaluation via fnc_evaluateCompletion.
 *
 * Arguments:
 *     0: _location <HASHMAP> - Location object from fnc_scanLocations
 *     1: _ao <HASHMAP> - Populated AO data from fnc_populateAO
 *     2: _config <HASHMAP> - Raid config:
 *        "entities"          <ARRAY>    Array of entity specs:
 *                                       { "archetype": "OFFICER", ...overrides }
 *        "objects"           <ARRAY>    Array of object specs (see
 *                                       fnc_placeObjects).
 *        "completion"        <STRING|HASHMAP>  Completion condition (see
 *                                              fnc_evaluateCompletion).
 *        "markerStyle"       <STRING>   "compound" | "none" (default "compound")
 *        "briefingArchetype" <STRING>   Briefing fragment key (consumed by
 *                                       briefing system; passed through).
 *        "targetFaction"     <STRING>   Faction for entity classname resolution
 *        "targetSide"        <SIDE>     Side for fresh entity groups
 *
 * Return Value:
 *     <HASHMAP> - Mission data:
 *        "type"             - String. "RAID/<completionType>" composite for
 *                             back-compat dispatch in briefing/UAV.
 *        "archetype"        - "RAID"
 *        "completion"       - Completion config (for monitor)
 *        "completionState"  - Hashmap populated with state keys for the
 *                             condition (hvt, objects, hostages, etc.)
 *        "briefingArchetype"- Passed through from config
 *        "location"         - Position array
 *        "locationName"     - String name
 *        "locationTags"     - Tags from location object
 *        "entity"           - First placed entity (back-compat / UAV target)
 *        "entityBuilding"   - Building of first entity (back-compat)
 *        "entities"         - Array of all placed entities
 *        "objects"          - Array of all placed objects
 *        "groups"           - All groups (AO + entity groups)
 *        "patrolGroups"     - Patrol groups (for QRF)
 *        "defenderUnits"    - Guard + garrison units
 *        "units"            - All units (AO + entities)
 *        "vehicles"         - All vehicles
 *        "marker"           - "" (legacy)
 *        "markers"          - All marker names (for cleanup)
 *        "startTime"        - serverTime at creation
 *        "status"           - "ACTIVE"
 */

params [
    ["_location", createHashMap, [createHashMap]],
    ["_ao", createHashMap, [createHashMap]],
    ["_config", createHashMap, [createHashMap]]
];

private _targetFaction = _config getOrDefault ["targetFaction", missionNamespace getVariable ["opForFaction", "OPF_F"]];
private _targetSide = _config getOrDefault ["targetSide", east];
private _entitySpecs = _config getOrDefault ["entities", []];
private _objectSpecs = _config getOrDefault ["objects", []];
private _completion = _config getOrDefault ["completion", "KILL_CAPTURE"];
private _markerStyle = _config getOrDefault ["markerStyle", "compound"];
private _briefingArchetype = _config getOrDefault ["briefingArchetype", ""];

private _locationPos = _location get "position";
private _locationName = _location get "name";
private _locationTags = [];
if (_location getOrDefault ["isMilitary", false]) then { _locationTags pushBack "military" };
private _milTier = _location getOrDefault ["militaryTier", ""];
if (_milTier != "") then { _locationTags pushBack _milTier };
_locationTags pushBack (_location getOrDefault ["locType", ""]);

private _aoGroups = _ao get "groups";
private _aoUnits = _ao get "units";
private _aoVehicles = _ao get "vehicles";
private _defenderUnits = _ao get "defenderUnits";
private _patrolGroups = _ao get "patrolGroups";

private _entityRegistry = call DSC_core_fnc_getEntityArchetypes;

// ============================================================================
// Place Entities
// ============================================================================
// Each spec may declare "count" > 1 to place multiple instances (hostages
// in a single rescue mission). The first slot of the first spec gets the
// bodyguard path if its archetype allows; everyone else gets a fresh group.
private _placedEntities = [];
private _firstEntity = objNull;
private _firstBuilding = objNull;
private _globalSlot = 0;

{
    private _spec = _x;
    private _archetypeName = _spec getOrDefault ["archetype", ""];
    private _archetype = _spec getOrDefault ["archetypeData", createHashMap];
    if (_archetype isEqualTo createHashMap && _archetypeName != "") then {
        _archetype = _entityRegistry getOrDefault [_archetypeName, createHashMap];
    };

    if (_archetype isEqualTo createHashMap) then {
        diag_log format ["DSC: generateRaidMission - skipping unknown entity archetype '%1'", _archetypeName];
        continue;
    };

    // Resolve classname (spec override > archetype resolver)
    private _resolverKey = _spec getOrDefault ["unitClassResolver", _archetype get "unitClassResolver"];
    private _unitClass = [
        _resolverKey,
        createHashMapFromArray [
            ["faction", _targetFaction],
            ["side", _targetSide],
            ["fallback", _spec getOrDefault ["fallback", "O_officer_F"]]
        ]
    ] call DSC_core_fnc_resolveEntityClass;

    if (_unitClass isEqualTo "") then {
        diag_log format ["DSC: generateRaidMission - no class resolved for archetype '%1'", _archetypeName];
        continue;
    };

    // Count expansion ([min, max] or fixed number)
    private _countSpec = _spec getOrDefault ["count", 1];
    private _instanceCount = if (_countSpec isEqualType []) then {
        (_countSpec select 0) + (floor (random ((_countSpec select 1) - (_countSpec select 0) + 1)))
    } else {
        _countSpec
    };

    private _placementKey = _spec getOrDefault ["placement", _archetype getOrDefault ["placement", "DEEP_BUILDING"]];

    for "_instance" from 1 to _instanceCount do {
        private _placement = createHashMap;

        switch (_placementKey) do {
            case "DEEP_BUILDING": {
                // Bodyguard path only for the very first global slot.
                private _hasBodyguards = (_archetype getOrDefault ["hasBodyguards", true]) && (_globalSlot == 0);
                _placement = [
                    createHashMapFromArray [
                        ["unitClass", _unitClass],
                        ["side", _targetSide],
                        ["hasBodyguards", _hasBodyguards],
                        ["minPositions", _spec getOrDefault ["minPositions", 3]]
                    ],
                    _location,
                    _ao
                ] call DSC_core_fnc_placeInDeepBuilding;
            };
            case "GROUND_SIT": {
                _placement = [
                    createHashMapFromArray [
                        ["unitClass", _unitClass],
                        ["side", _targetSide],
                        ["stance", "SIT"]
                    ],
                    _location,
                    _ao
                ] call DSC_core_fnc_placeOnGround;
            };
            case "GROUND_KNEEL": {
                _placement = [
                    createHashMapFromArray [
                        ["unitClass", _unitClass],
                        ["side", _targetSide],
                        ["stance", "KNEEL"]
                    ],
                    _location,
                    _ao
                ] call DSC_core_fnc_placeOnGround;
            };
            // Future: ON_TABLE, IN_VEHICLE
            default {
                diag_log format ["DSC: generateRaidMission - placement '%1' not implemented for archetype '%2', skipping", _placementKey, _archetypeName];
            };
        };

        if (_placement isEqualTo createHashMap) then { continue };

        private _unit = _placement get "unit";
        if (isNull _unit) then { continue };

        // Apply behavior wiring
        private _behavior = _archetype getOrDefault ["behavior", "default"];
        switch (_behavior) do {
            case "captive": {
                _unit setCaptive true;
                _unit disableAI "AUTOTARGET";
                _unit disableAI "TARGET";
                _unit disableAI "MOVE";
                _unit disableAI "PATH";
                _unit disableAI "FSM";
            };
            // "default" intentionally does nothing
        };

        // Apply animation if archetype specifies one
        private _animation = _archetype getOrDefault ["animation", ""];
        if (_animation != "") then {
            [_unit, _animation] remoteExec ["switchMove", 0, _unit];
        };

        // If placement returned a fresh group (not bodyguard host), apply
        // entity-style "stay put, don't engage" behavior unless captive
        // (captives shouldn't trigger combat activation either way).
        private _withBodyguards = _placement get "withBodyguards";
        if (!_withBodyguards) then {
            private _entGroup = _placement get "group";
            if (!isNull _entGroup) then {
                _entGroup setBehaviour "SAFE";
                _entGroup setCombatMode "GREEN";
                _entGroup enableAttack false;
                if (_behavior != "captive") then {
                    [_entGroup] call DSC_core_fnc_addCombatActivation;
                };
                if (!(_entGroup in _aoGroups)) then { _aoGroups pushBack _entGroup };
            };
        };

        // Track entity
        _unit setVariable ["DSC_isEntity", true, true];
        _unit setVariable ["DSC_entityArchetype", _archetypeName, true];
        _unit setVariable ["DSC_entityName", format ["%1 %2", _archetype getOrDefault ["briefingTitle", "Target"], floor (random 1000)], true];
        _aoUnits pushBack _unit;
        _placedEntities pushBack _unit;

        if (_globalSlot == 0) then {
            _firstEntity = _unit;
            _firstBuilding = _placement get "building";
        };
        _globalSlot = _globalSlot + 1;
    };
} forEach _entitySpecs;

// ============================================================================
// Place Objects
// ============================================================================
private _placedObjects = [];
private _objectMeta = [];

{
    private _result = [_x, _location, _ao] call DSC_core_fnc_placeObjects;
    private _objs = _result get "objects";
    _placedObjects append _objs;
    _objectMeta pushBack _result;

    // Wire interaction handlers for interactable archetypes (intel objects).
    if (_result get "interactable") then {
        private _interactionResult = _result getOrDefault ["interactionResult", "GATHER_INTEL"];
        private _archName = _result getOrDefault ["archetype", ""];
        private _objArchetypes = call DSC_core_fnc_getObjectArchetypes;
        private _objArch = _objArchetypes getOrDefault [_archName, createHashMap];
        private _actionText = _objArch getOrDefault ["actionText", "Recover Intel"];
        {
            [_x, createHashMapFromArray [
                ["result", _interactionResult],
                ["actionText", _actionText],
                ["removeOnUse", true]
            ]] call DSC_core_fnc_addInteractionHandler;
        } forEach _objs;
    };
} forEach _objectSpecs;

// ============================================================================
// Markers
// ============================================================================
private _missionMarkers = switch (_markerStyle) do {
    case "compound": {
        [_ao getOrDefault ["garrisonClusters", []], _location] call DSC_core_fnc_drawCompoundMarkers
    };
    case "none": { [] };
    default {
        diag_log format ["DSC: generateRaidMission - unknown markerStyle '%1', falling back to compound", _markerStyle];
        [_ao getOrDefault ["garrisonClusters", []], _location] call DSC_core_fnc_drawCompoundMarkers
    };
};

// ============================================================================
// Build completion state for the monitor
// ============================================================================
// The monitor reads keys based on the chosen condition. We populate every key
// any current condition could need; unused keys are harmless.
//
// extractPos defaults to player base flagpole if available; the caller can
// override via _config "extractPos" before calling this generator.
private _extractPos = _config getOrDefault ["extractPos", []];
if (_extractPos isEqualTo [] && { !isNull (missionNamespace getVariable ["jointOperationCenter", objNull]) }) then {
    _extractPos = getPos (missionNamespace getVariable ["jointOperationCenter", objNull]);
};

private _completionState = createHashMapFromArray [
    ["hvt", _firstEntity],
    ["objects", _placedObjects],
    ["hostages", _placedEntities],          // captive-behavior entities; condition will filter
    ["defenders", _defenderUnits],
    ["intelGathered", false],               // toggled by interaction handler
    ["extractPos", _extractPos]
];

// ============================================================================
// Build Mission Data
// ============================================================================
// Compose "type" as RAID/<completionTypeName> so existing briefing/UAV
// switches that expect "KILL_CAPTURE" keep matching until step 7 generalizes
// the briefing system.
private _completionTypeName = if (_completion isEqualType "") then {
    _completion
} else {
    _completion getOrDefault ["type", "CUSTOM"]
};

private _mission = createHashMapFromArray [
    ["type", _completionTypeName],
    ["archetype", "RAID"],
    ["completion", _completion],
    ["completionState", _completionState],
    ["briefingArchetype", _briefingArchetype],
    ["location", _locationPos],
    ["locationName", _locationName],
    ["locationTags", _locationTags],
    ["entity", _firstEntity],
    ["entityBuilding", _firstBuilding],
    ["entities", _placedEntities],
    ["objects", _placedObjects],
    ["objectMeta", _objectMeta],
    ["groups", _aoGroups],
    ["patrolGroups", _patrolGroups],
    ["defenderUnits", _defenderUnits],
    ["units", _aoUnits],
    ["vehicles", _aoVehicles],
    ["marker", ""],
    ["markers", _missionMarkers],
    ["startTime", serverTime],
    ["status", "ACTIVE"]
];

missionNamespace setVariable ["DSC_currentMission", _mission, true];

diag_log format ["DSC: Raid mission generated [%1] at %2 - %3 entities, %4 objects, %5 groups, %6 units",
    _completionTypeName, _locationName, count _placedEntities, count _placedObjects, count _aoGroups, count _aoUnits];

_mission
