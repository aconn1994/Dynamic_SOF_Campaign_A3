#include "script_component.hpp"

/*
 * Setup garrison units in structures at a location.
 * 
 * Uses Anchor + Satellites model to place infantry in buildings:
 * - Anchors: Main structures (5+ positions or military towers)
 * - Satellites: Nearby smaller structures within 50m of anchor
 * - Groups spawn and fill positions based on density config
 * 
 * Arguments:
 *   0: Location position <ARRAY> - Center position [x, y, z]
 *   1: Group templates <ARRAY> - Classified group hashmaps from fnc_classifyGroups
 *   2: Side <SIDE> - e.g. east, west, independent
 *   3: (Optional) Config overrides <HASHMAP> - Override default settings
 *      - "radius": Search radius for structures (default: 200)
 *      - "density": "light", "medium", "heavy", or "random" (default: "random")
 *      - "anchorCount": [min, max] anchors (overrides density)
 *      - "groupsPerAnchor": [min, max] groups per anchor (overrides density)
 *      - "satelliteCount": [min, max] satellites per anchor (overrides density)
 *      - "positionFill": 0.0-1.0 percentage of positions to fill (overrides density)
 * 
 * Returns:
 *   Hashmap containing:
 *     - "units": Array of spawned units
 *     - "groups": Array of created groups
 *     - "tags": Array of doctrine tags per group (parallel to groups array)
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

// Result tracking
private _result = createHashMapFromArray [
    ["units", []],
    ["groups", []],
    ["tags", []]
];

if (_locationPos isEqualTo []) exitWith {
    diag_log "DSC: fnc_setupGarrison - No location position provided";
    _result
};

if (_groupTemplates isEqualTo []) exitWith {
    diag_log "DSC: fnc_setupGarrison - No group templates provided";
    _result
};

// Config defaults
private _radius = _configOverrides getOrDefault ["radius", 200];
private _densityChoice = _configOverrides getOrDefault ["density", "random"];

// ============================================================================
// DENSITY CONFIGURATION
// ============================================================================
private _densityProfile = if (_densityChoice == "random") then {
    selectRandomWeighted [
        "light", 0.30,
        "medium", 0.45,
        "heavy", 0.25
    ]
} else {
    _densityChoice
};

private _defaultDensityConfig = switch (_densityProfile) do {
    case "light": {
        createHashMapFromArray [
            ["anchorCount", [2, 4]],
            ["groupsPerAnchor", [1, 1]],
            ["satelliteCount", [0, 1]],
            ["positionFill", 0.5]
        ]
    };
    case "medium": {
        createHashMapFromArray [
            ["anchorCount", [3, 5]],
            ["groupsPerAnchor", [1, 2]],
            ["satelliteCount", [1, 2]],
            ["positionFill", 0.7]
        ]
    };
    case "heavy": {
        createHashMapFromArray [
            ["anchorCount", [4, 6]],
            ["groupsPerAnchor", [1, 2]],
            ["satelliteCount", [2, 3]],
            ["positionFill", 0.9]
        ]
    };
    default {
        // Default to medium if invalid
        createHashMapFromArray [
            ["anchorCount", [2, 4]],
            ["groupsPerAnchor", [1, 2]],
            ["satelliteCount", [1, 2]],
            ["positionFill", 0.7]
        ]
    };
};

// Allow individual overrides
private _anchorRange = _configOverrides getOrDefault ["anchorCount", _defaultDensityConfig get "anchorCount"];
private _groupsPerAnchorRange = _configOverrides getOrDefault ["groupsPerAnchor", _defaultDensityConfig get "groupsPerAnchor"];
private _satelliteRange = _configOverrides getOrDefault ["satelliteCount", _defaultDensityConfig get "satelliteCount"];
private _positionFill = _configOverrides getOrDefault ["positionFill", _defaultDensityConfig get "positionFill"];

diag_log format ["DSC: fnc_setupGarrison - Density: %1", _densityProfile];

// ============================================================================
// FIND AND CATEGORIZE STRUCTURES
// ============================================================================
private _structureCategories = ["BUILDING", "HOUSE", "BUNKER", "FORTRESS", "HOSPITAL", "VIEW-TOWER", "MILITARY", "VILLAGE", "CITY"];
private _locationStructures = nearestObjects [_locationPos, _structureCategories, _radius];

private _mainStructures = [];
private _sideStructures = [];

// Military tower/lookout structure types (count as main structures)
private _towerTypes = ["Cargo_HQ_base_F", "Cargo_Patrol_base_F", "Cargo_Tower_base_F"];

{
    private _struct = _x;
    private _noOfPositions = count (_x buildingPos -1);

    if (_noOfPositions == 0) then { continue };

    // Check if this is a military tower structure
    private _isTower = false;
    {
        if (_struct isKindOf _x) exitWith { _isTower = true };
    } forEach _towerTypes;

    if (_isTower || _noOfPositions >= 5) then {
        _mainStructures pushBack _struct;
    } else {
        _sideStructures pushBack _struct;
    };
} forEach _locationStructures;

diag_log format ["DSC: fnc_setupGarrison - Main: %1, Side: %2 structures", count _mainStructures, count _sideStructures];

if (_mainStructures isEqualTo []) exitWith {
    diag_log "DSC: fnc_setupGarrison - No main structures found";
    _result
};

// ============================================================================
// SELECT ANCHOR BUILDINGS
// ============================================================================
private _numAnchors = (_anchorRange select 0) + floor random ((_anchorRange select 1) - (_anchorRange select 0) + 1);
_numAnchors = _numAnchors min (count _mainStructures);

private _availableMain = +_mainStructures;
private _availableSide = +_sideStructures;
private _anchors = [];

// Pick anchors spread apart (not all clustered together)
for "_i" from 1 to _numAnchors do {
    if (_availableMain isEqualTo []) exitWith {};
    
    private _anchor = if (_anchors isEqualTo []) then {
        selectRandom _availableMain
    } else {
        private _sorted = [_availableMain, [], {
            private _struct = _x;
            private _minDist = 999999;
            { _minDist = _minDist min (_struct distance2D _x) } forEach _anchors;
            -_minDist
        }, "ASCEND"] call BIS_fnc_sortBy;
        _sorted select 0
    };
    
    _anchors pushBack _anchor;
    _availableMain = _availableMain - [_anchor];
};

diag_log format ["DSC: fnc_setupGarrison - Selected %1 anchors", count _anchors];

// ============================================================================
// SPAWN GROUPS AT ANCHORS WITH SATELLITES
// ============================================================================
{
    private _anchor = _x;
    private _anchorPos = getPos _anchor;
    
    // Determine satellites for this anchor (nearby side structures)
    private _numSatellites = (_satelliteRange select 0) + floor random ((_satelliteRange select 1) - (_satelliteRange select 0) + 1);
    
    // Get closest side structures to this anchor
    private _nearbySide = [_availableSide, [], { _x distance2D _anchorPos }, "ASCEND"] call BIS_fnc_sortBy;
    private _satellites = [];
    
    for "_j" from 0 to (_numSatellites - 1) do {
        if (_j >= count _nearbySide) exitWith {};
        private _sat = _nearbySide select _j;
        if (_sat distance2D _anchorPos < 50) then {
            _satellites pushBack _sat;
            _availableSide = _availableSide - [_sat];
        };
    };
    
    diag_log format ["DSC: fnc_setupGarrison - Anchor %1 has %2 satellites", _anchor, count _satellites];
    
    // Collect all positions for this cluster (anchor + satellites)
    private _clusterBuildings = [_anchor] + _satellites;
    private _allPositions = [];
    
    {
        private _positions = _x buildingPos -1;
        _allPositions append _positions;
    } forEach _clusterBuildings;
    
    // Determine how many groups for this anchor
    private _numGroups = (_groupsPerAnchorRange select 0) + floor random ((_groupsPerAnchorRange select 1) - (_groupsPerAnchorRange select 0) + 1);
    
    // Calculate target unit count based on position fill
    private _targetUnits = floor ((count _allPositions) * _positionFill);
    private _unitsSpawned = 0;
    
    diag_log format ["DSC: fnc_setupGarrison - Cluster has %1 positions, targeting %2 units", count _allPositions, _targetUnits];
    
    // Spawn groups until we hit target or run out of groups
    for "_g" from 1 to _numGroups do {
        if (_unitsSpawned >= _targetUnits) exitWith {};
        if (_groupTemplates isEqualTo []) exitWith {};
        
        private _remainingPositions = (count _allPositions) - _unitsSpawned;
        
        // Filter to groups that fit, or if none fit, use smallest available
        private _fittingGroups = _groupTemplates select { 
            (_x get "unitAnalysis" get "infantryCount") <= _remainingPositions 
        };
        
        private _selectedGroup = if (_fittingGroups isNotEqualTo []) then {
            selectRandom _fittingGroups
        } else {
            // No groups fit - pick smallest group
            private _sorted = [_groupTemplates, [], { _x get "unitAnalysis" get "infantryCount" }, "ASCEND"] call BIS_fnc_sortBy;
            _sorted select 0
        };
        
        private _groupPath = _selectedGroup get "path";
        private _groupName = _selectedGroup get "groupName";
        private _doctrineTags = _selectedGroup get "doctrineTags";
        private _unitAnalysis = _selectedGroup get "unitAnalysis";
        private _groupSize = _unitAnalysis get "infantryCount";
        
        diag_log format ["DSC: fnc_setupGarrison - Spawning %1 (%2 units)", _groupName, _groupSize];
        
        // Parse the group path and spawn
        private _pathParts = _groupPath splitString "/";
        private _groupConfig = configFile >> "CfgGroups";
        { _groupConfig = _groupConfig >> _x } forEach _pathParts;
        
        private _spawnedGroup = [_anchorPos, _side, _groupConfig] call BIS_fnc_spawnGroup;
        (_result get "groups") pushBack _spawnedGroup;
        (_result get "tags") pushBack _doctrineTags;
        
        // Place units in building positions
        {
            if (_unitsSpawned >= count _allPositions) exitWith {};
            
            _x allowDamage false;
            _x setPos (_allPositions select _unitsSpawned);
            
            _unitsSpawned = _unitsSpawned + 1;
        } forEach units _spawnedGroup;
        
        // Add combat activation - garrison stays in place until shots fired nearby
        [_spawnedGroup] call DSC_core_fnc_addCombatActivation;
        
        (_result get "units") append (units _spawnedGroup);
    };
    
    diag_log format ["DSC: fnc_setupGarrison - Spawned %1 units in cluster", _unitsSpawned];
    
} forEach _anchors;

diag_log format ["DSC: fnc_setupGarrison - Total: %1 units, %2 groups", count (_result get "units"), count (_result get "groups")];

_result
