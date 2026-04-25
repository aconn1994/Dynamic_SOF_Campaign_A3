#include "script_component.hpp"

/*
 * Guard overhaul — visible deterrents at building entry points.
 *
 * Guards are anchored to ground-floor building positions (Z < threshold),
 * facing outward toward likely approach routes. They are a visible threat
 * the player can spot and plan around — not hidden perimeter sentries.
 *
 * Works for both military and civilian locations using the same core logic.
 * Each building gets 1-2 guards based on config. All guards at a location
 * share one group for knowledge sharing and coordinated response.
 *
 * Unit classes are extracted from group templates (same pool approach as
 * garrison overhaul) for authentic faction variety.
 *
 * Arguments:
 *   0: Location position <ARRAY> - Center of the location
 *   1: Group templates <ARRAY> - Classified group hashmaps (foot infantry)
 *   2: Side <SIDE>
 *   3: Config overrides <HASHMAP>
 *      - "garrisonClusters": Cluster data from fnc_setupGarrison results
 *      - "mainStructures": Main structures at location
 *      - "sideStructures": Side structures at location
 *      - "guardsPerBuilding": [min, max] guards per building (default: [1, 2])
 *      - "buildingCoverage": 0.0-1.0 fraction of buildings that get guards (default: 0.5)
 *      - "groundFloorThreshold": Max Z height for ground-floor positions (default: 1.5)
 *      - "skillProfile": Skill profile name (default: "cqb_baseline")
 *      - "skillVariance": Per-unit variance (default: 0.05)
 *      - "combatActivation": Enable FiredNear activation (default: true)
 *      - "reactionDelay": Seconds before PATH enables (default: 0.5)
 *
 * Returns:
 *   Hashmap: "units", "groups"
 *
 * Examples:
 *   [_locationPos, _footGroups, east] call DSC_core_fnc_setupGuards
 *   [_locationPos, _footGroups, east, createHashMapFromArray [["guardsPerBuilding", [2, 2]]]] call DSC_core_fnc_setupGuards
 */

params [
    ["_locationPos", [], [[]]],
    ["_groupTemplates", [], [[]]],
    ["_side", east, [east]],
    ["_configOverrides", createHashMap, [createHashMap]]
];

// ============================================================================
// GUARD CONFIG — tune these values for testing
// ============================================================================
private _config = createHashMapFromArray [
    // --- Guard Placement ---
    ["guardsPerBuilding", [0, 2]],    // [min, max] guards at each guarded building
    ["buildingCoverage", 0.6],        // Fraction of cluster buildings that get guards
    ["guardOffset", 10],               // Meters from building center to place guard
    ["roadSearchRadius", 50],         // Radius to search for nearest road (urban front detection)

    // --- Skill Profile ---
    ["skillProfile", "realism"],
    ["skillVariance", 0],

    // --- Combat Activation ---
    ["combatActivation", true],
    ["reactionDelay", 0.5]
];

{ _config set [_x, _y] } forEach _configOverrides;

// ============================================================================
// VALIDATION
// ============================================================================
private _result = createHashMapFromArray [
    ["units", []],
    ["groups", []]
];

if (_locationPos isEqualTo []) exitWith {
    diag_log "DSC: setupGuards - No location position";
    _result
};

if (_groupTemplates isEqualTo []) exitWith {
    diag_log "DSC: setupGuards - No group templates";
    _result
};

// ============================================================================
// READ CONFIG
// ============================================================================
private _guardsRange = _config get "guardsPerBuilding";
private _buildingCoverage = _config get "buildingCoverage";
private _guardOffset = _config get "guardOffset";
private _roadSearchRadius = _config get "roadSearchRadius";
private _skillProfile = _config get "skillProfile";
private _skillVariance = _config get "skillVariance";
private _useCombatActivation = _config get "combatActivation";
private _reactionDelay = _config get "reactionDelay";

// ============================================================================
// BUILD UNIT CLASS POOL
// ============================================================================
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
    diag_log "DSC: setupGuards - No unit classes extracted from templates";
    _result
};

// ============================================================================
// COLLECT BUILDINGS TO GUARD
// ============================================================================
// Use garrison clusters if available (guards the same buildings garrison uses).
// Otherwise fall back to mainStructures + sideStructures from config.
private _garrisonClusters = _config getOrDefault ["garrisonClusters", []];
private _buildingsToGuard = [];

if (_garrisonClusters isNotEqualTo []) then {
    {
        private _buildings = _x get "buildings";
        { _buildingsToGuard pushBackUnique _x } forEach _buildings;
    } forEach _garrisonClusters;
} else {
    private _mainStructures = _config getOrDefault ["mainStructures", []];
    private _sideStructures = _config getOrDefault ["sideStructures", []];
    _buildingsToGuard = _mainStructures + _sideStructures;
};

if (_buildingsToGuard isEqualTo []) exitWith {
    diag_log "DSC: setupGuards - No buildings to guard";
    _result
};

// Select subset based on coverage
private _shuffled = _buildingsToGuard call BIS_fnc_arrayShuffle;
private _numToGuard = (ceil ((count _buildingsToGuard) * _buildingCoverage)) max 1;
private _selectedBuildings = _shuffled select [0, _numToGuard];

diag_log format ["DSC: setupGuards - Guarding %1/%2 buildings (coverage: %3)",
    count _selectedBuildings, count _buildingsToGuard, _buildingCoverage];

// ============================================================================
// SPAWN GUARDS — exterior positions at building fronts
// ============================================================================
// Priority chain for determining the "front" of a building:
//   1. Nearest road within searchRadius → guard between building and road
//   2. Building model direction (getDir) → guard offset in facing direction
//   3. Cluster-outward → guard on approach side away from location center
// Guards are placed OUTSIDE on open ground, standing, clearly visible.

private _guardsGroup = createGroup [_side, true];
private _totalGuards = 0;
private _usedPositions = [];

{
    private _building = _x;
    private _buildingPos = getPos _building;

    private _numGuards = (_guardsRange select 0) + floor random ((_guardsRange select 1) - (_guardsRange select 0) + 1);

    // Determine the "front" direction for this building
    // Priority 1: Nearest road
    private _nearRoads = _buildingPos nearRoads _roadSearchRadius;
    private _frontDir = -1;
    private _placementMethod = "";

    if (_nearRoads isNotEqualTo []) then {
        private _nearestRoad = _nearRoads select 0;
        _frontDir = _buildingPos getDir (getPos _nearestRoad);
        _placementMethod = "road";
    } else {
        // Priority 2: Building model facing direction
        private _bDir = getDir _building;
        if (_bDir != 0 || { typeOf _building != "" }) then {
            _frontDir = _bDir;
            _placementMethod = "facing";
        } else {
            // Priority 3: Cluster-outward
            _frontDir = _locationPos getDir _buildingPos;
            _placementMethod = "outward";
        };
    };

    // Place guards outside the building front
    private _guardPositions = [];

    // Primary: directly in front
    private _primaryPos = _buildingPos getPos [_guardOffset, _frontDir];
    _primaryPos set [2, 0];

    if !(surfaceIsWater _primaryPos) then {
        _guardPositions pushBack [_primaryPos, _frontDir];
    };

    // Secondary: offset to the side (90 degrees from front) for a different angle
    if (_numGuards >= 2) then {
        private _secondaryDir = _frontDir + 90 + (random 40) - 20;
        private _secondaryPos = _buildingPos getPos [_guardOffset, _secondaryDir];
        _secondaryPos set [2, 0];

        if !(surfaceIsWater _secondaryPos) then {
            _guardPositions pushBack [_secondaryPos, _secondaryDir];
        };
    };

    // Spawn guards at determined positions
    {
        _x params ["_pos", "_facing"];

        // Skip if too close to an existing guard
        private _tooClose = false;
        { if (_pos distance2D _x < 3) exitWith { _tooClose = true } } forEach _usedPositions;
        if (_tooClose) then { continue };

        private _unitClass = selectRandom _unitPool;
        private _unit = _guardsGroup createUnit [_unitClass, _pos, [], 0, "NONE"];

        _unit allowDamage false;
        _unit setPos _pos;
        _unit allowDamage true;

        _unit setDir _facing;
        _unit disableAI "PATH";
        _unit setUnitPos "UP";

        [_unit, _skillProfile, _skillVariance] call DSC_core_fnc_applySkillProfile;

        (_result get "units") pushBack _unit;
        _usedPositions pushBack _pos;
        _totalGuards = _totalGuards + 1;
    } forEach _guardPositions;

    if (_guardPositions isNotEqualTo []) then {
        diag_log format ["DSC: setupGuards - %1: %2 guards (%3)", typeOf _building, count _guardPositions, _placementMethod];
    };

} forEach _selectedBuildings;

// ============================================================================
// FINALIZE
// ============================================================================
if ((units _guardsGroup) isNotEqualTo []) then {
    (_result get "groups") pushBack _guardsGroup;

    if (_useCombatActivation) then {
        [_guardsGroup, _reactionDelay] call DSC_core_fnc_addCombatActivation;
    };
} else {
    deleteGroup _guardsGroup;
};

diag_log format ["DSC: setupGuards - Complete: %1 guards across %2 buildings",
    _totalGuards, count _selectedBuildings];

_result
