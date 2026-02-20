#include "script_component.hpp"

/*
 * Setup patrol units around a location.
 * 
 * Spawns groups that patrol around the target location at varying distances.
 * Can include special groups (AT/AA teams) with configurable probability.
 * 
 * Arguments:
 *   0: Location position <ARRAY> - Center position [x, y, z]
 *   1: Group templates <ARRAY> - Classified group hashmaps for standard patrols
 *   2: Side <SIDE> - e.g. east, west, independent
 *   3: (Optional) Config overrides <HASHMAP> - Override default settings
 *      - "patrolCount": [min, max] number of patrol groups (default: [3, 6])
 *      - "spawnRadius": [min, max] radius from location to spawn (default: [100, 400])
 *      - "patrolRadius": [min, max] patrol waypoint radius (default: [200, 500])
 *      - "specialGroups": Array of special group templates (AT/AA teams)
 *      - "specialChance": 0.0-1.0 chance to use special group (default: 0.15)
 * 
 * Returns:
 *   Hashmap containing:
 *     - "units": Array of spawned units
 *     - "groups": Array of created groups
 *     - "tags": Array of doctrine tags per group (parallel to groups array)
 * 
 * Examples:
 *   [_locationPos, _infantryGroups, east] call DSC_core_fnc_setupPatrols
 *   [_locationPos, _infantryGroups, east, createHashMapFromArray [
 *       ["patrolCount", [2, 4]],
 *       ["spawnRadius", [50, 200]],
 *       ["patrolRadius", [150, 400]],
 *       ["specialGroups", _atGroups + _aaGroups],
 *       ["specialChance", 0.25]
 *   ]] call DSC_core_fnc_setupPatrols
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
    diag_log "DSC: fnc_setupPatrols - No location position provided";
    _result
};

if (_groupTemplates isEqualTo []) exitWith {
    diag_log "DSC: fnc_setupPatrols - No group templates provided";
    _result
};

// Config defaults with overrides
private _patrolCountRange = _configOverrides getOrDefault ["patrolCount", [3, 10]];
private _spawnRadiusRange = _configOverrides getOrDefault ["spawnRadius", [600, 1200, 1800, 2400, 3200]];
private _patrolRadiusRange = _configOverrides getOrDefault ["patrolRadius", [600, 1200, 1800, 2400, 3200]];
private _specialGroups = _configOverrides getOrDefault ["specialGroups", []];
private _specialChance = _configOverrides getOrDefault ["specialChance", 0.15];

// Calculate number of patrols
private _numPatrols = (_patrolCountRange select 0) + floor random ((_patrolCountRange select 1) - (_patrolCountRange select 0) + 1);

diag_log format ["DSC: fnc_setupPatrols - Spawning %1 patrol groups", _numPatrols];

// Spawn patrol groups
for "_i" from 1 to _numPatrols do {
    // Select group template - chance for special groups if available
    private _selectedGroup = if (random 1 < _specialChance && _specialGroups isNotEqualTo []) then {
        selectRandom _specialGroups
    } else {
        selectRandom _groupTemplates
    };
    
    private _groupPath = _selectedGroup get "path";
    private _groupName = _selectedGroup get "groupName";
    private _doctrineTags = _selectedGroup get "doctrineTags";

    diag_log format ["DSC: fnc_setupPatrols - Patrol %1: %2", _i, _groupName];

    // Find safe spawn position with random radius
    private _spawnRadius = (_spawnRadiusRange select 0) + random ((_spawnRadiusRange select 1) - (_spawnRadiusRange select 0));
    private _groupSpawnPos = [_locationPos, 0, _spawnRadius, 5, 0, 20, 0] call BIS_fnc_findSafePos;

    // Parse the group path and spawn
    private _pathParts = _groupPath splitString "/";
    private _groupConfig = configFile >> "CfgGroups";
    { _groupConfig = _groupConfig >> _x } forEach _pathParts;
    
    private _spawnedGroup = [_groupSpawnPos, _side, _groupConfig] call BIS_fnc_spawnGroup;
    (_result get "groups") pushBack _spawnedGroup;
    (_result get "tags") pushBack _doctrineTags;
    (_result get "units") append (units _spawnedGroup);

    // Assign patrol task with random radius
    private _patrolRadius = (_patrolRadiusRange select 0) + random ((_patrolRadiusRange select 1) - (_patrolRadiusRange select 0));
    [_spawnedGroup, _locationPos, _patrolRadius] call BIS_fnc_taskPatrol;

    sleep 1;
};

diag_log format ["DSC: fnc_setupPatrols - Total: %1 units, %2 groups", count (_result get "units"), count (_result get "groups")];

_result
