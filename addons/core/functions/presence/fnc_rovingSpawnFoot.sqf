#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_rovingSpawnFoot
 * Description:
 *     Sprint E Phase 3 — Roving foot patrol spawner.
 *
 *     Spawns an infantry patrol group near the player and assigns a
 *     wide-area `BIS_fnc_taskPatrol`. Foot patrols are slower and less
 *     dynamic than vehicles, so spawn closer (600-1500m) with a tighter
 *     patrol radius (1000m) so the player actually encounters them.
 *
 *     Selection rules (same model as ground/air):
 *       1. Nearest non-airbase hotspot to the player determines SIDE and
 *          faction. opFor territory → opFor patrols; bluFor → bluFor.
 *       2. Spawn position is a `BIS_fnc_findSafePos` result 600-1500m from
 *          the player in a random direction.
 *       3. Patrol via `BIS_fnc_taskPatrol` centered on the player position,
 *          radius 1000m. Foot AI handles findSafePos waypoints cleanly
 *          (the issue that broke it for vehicles).
 *       4. Group pool = classified groups tagged FOOT + PATROL, with
 *          AT_TEAM / AA_TEAM excluded.
 *
 *     Behavior posture: AWARE + autocombat disabled — same as air/ground.
 *     Ambient world presence, not forced encounter.
 *
 * Arguments:
 *     0: _hotspots   <HASHMAP> - from fnc_resolveRovingHotspots
 *     1: _factionData<HASHMAP> - role -> data (groups + assets)
 *
 * Return Value:
 *     <HASHMAP> - rover record, or empty hashmap on failure
 *
 * Example:
 *     [_hotspots, _factionData] call DSC_core_fnc_rovingSpawnFoot;
 */

params [
    ["_hotspots",    createHashMap, [createHashMap]],
    ["_factionData", createHashMap, [createHashMap]]
];

private _empty = createHashMap;

private _player = call CBA_fnc_currentUnit;
if (isNull _player) exitWith { _empty };
private _playerPos = getPosASL _player;

// ============================================================================
// Step 1: nearest non-airbase hotspot → side / faction pool
// ============================================================================
private _nonAirbase = (_hotspots getOrDefault ["all", []]) select { (_x get "type") != "airbase" };
if (_nonAirbase isEqualTo []) exitWith {
    WARNING("rovingSpawnFoot - No non-airbase hotspots registered");
    _empty
};
private _sortedHotspots = [_nonAirbase, [], { (_x get "position") distance2D _playerPos }, "ASCEND"] call BIS_fnc_sortBy;
private _nearestHotspot = _sortedHotspots select 0;
private _side = _nearestHotspot get "side";
private _sideKey = ["west", "east"] select (_side isEqualTo east);
private _origin = _nearestHotspot;
private _originPos = _nearestHotspot get "position";

// ============================================================================
// Step 2: pick a safe ground position 600-1500m from the player
// ============================================================================
private _spawnPos = [];
private _spawnAttempts = 5;
for "_attempt" from 0 to (_spawnAttempts - 1) do {
    if (_spawnPos isEqualTo []) then {
        private _angle = random 360;
        private _dist = 600 + random 900;
        private _approxPos = _playerPos getPos [_dist, _angle];
        // _waterMode=0 → avoid water; minDist=10 from objects; shore=0
        private _safePos = [_approxPos, 0, 200, 10, 0, 0.3, 0] call BIS_fnc_findSafePos;
        if (count _safePos >= 2) then {
            _spawnPos = _safePos;
        };
    };
};

if (_spawnPos isEqualTo []) exitWith {
    LOG("rovingSpawnFoot - No safe position found in 600-1500m ring around player");
    _empty
};

// ============================================================================
// Step 3: resolve a FOOT PATROL group for the side
// ============================================================================
private _roleKey = ["bluFor", "opFor"] select (_sideKey == "east");
private _roleData = _factionData getOrDefault [_roleKey, createHashMap];
private _groupsByFaction = _roleData getOrDefault ["groups", createHashMap];

private _groupPool = [];
{
    private _classifiedGroups = _y;
    private _matches = [_classifiedGroups, ["FOOT", "PATROL"], ["AT_TEAM", "AA_TEAM", "MOTORIZED", "MECHANIZED", "ARMORED"]] call DSC_core_fnc_getGroupsByTag;
    if (_matches isEqualTo []) then {
        // Broaden to FOOT only — most factions have at least one foot group
        _matches = [_classifiedGroups, ["FOOT"], ["AT_TEAM", "AA_TEAM", "MOTORIZED", "MECHANIZED", "ARMORED"]] call DSC_core_fnc_getGroupsByTag;
    };
    { _groupPool pushBack _x } forEach _matches;
} forEach _groupsByFaction;

if (_groupPool isEqualTo []) exitWith {
    LOG_1("rovingSpawnFoot - No FOOT PATROL groups in %1 pool",_roleKey);
    _empty
};

private _groupTemplate = selectRandom _groupPool;
private _groupPath = _groupTemplate get "path";
private _groupName = _groupTemplate get "groupName";

private _pathParts = _groupPath splitString "/";
private _groupConfig = configFile >> "CfgGroups";
{ _groupConfig = _groupConfig >> _x } forEach _pathParts;

if (!isClass _groupConfig) exitWith {
    ERROR_1("rovingSpawnFoot - Invalid CfgGroups path: %1",_groupPath);
    _empty
};

// ============================================================================
// Step 4: spawn the group (yielding to avoid spawn-burst stutter)
// ============================================================================
private _group = [_spawnPos, _side, _groupPath] call DSC_core_fnc_spawnGroupYielding;
if (isNull _group || {(units _group) isEqualTo []}) exitWith {
    ERROR_1("rovingSpawnFoot - spawnGroupYielding failed for %1",_groupName);
    _empty
};

// Ambient posture — same as air/ground rovers. Foot patrols are armed but
// not actively hunting; they react only if fired upon.
_group setBehaviour "AWARE";
_group setCombatMode "BLUE";
_group setSpeedMode "LIMITED";
{
    _x disableAI "AUTOCOMBAT";
    _x disableAI "TARGET";
    _x disableAI "AUTOTARGET";
} forEach units _group;

_group enableDynamicSimulation true;
{
    if (!isNull _x) then { _x enableDynamicSimulation true };
} forEach units _group;

// ============================================================================
// Step 5: assign patrol task — BIS_fnc_taskPatrol centered on the player
// ============================================================================
// Unlike vehicles, foot AI handles findSafePos waypoints cleanly. The wider
// patrol radius (1000m) lets the patrol drift in and out of the player's
// immediate area as ambient flavor.
private _patrolRadius = 1000;
[_group, _playerPos, _patrolRadius] call BIS_fnc_taskPatrol;

private _destPos = _playerPos;

// ============================================================================
// Step 6: register on tracker
// ============================================================================
private _id = format ["roving_foot_%1_%2", _sideKey, diag_tickTime];
// Vehicle field stays objNull for foot rovers — despawn sweep handles units.
private _record = createHashMapFromArray [
    ["id",          _id],
    ["type",        "foot"],
    ["vehicle",     objNull],
    ["group",       _group],
    ["side",        _side],
    ["spawnTime",   diag_tickTime],
    ["origin",      _originPos],
    ["destination", _destPos]
];

private _active = missionNamespace getVariable ["DSC_rovingActive", []];
_active pushBack _record;
missionNamespace setVariable ["DSC_rovingActive", _active, true];

// Zeus integration
private _curator = if (allCurators isNotEqualTo []) then { allCurators select 0 } else { objNull };
if (!isNull _curator) then {
    private _zeusEntities = units _group;
    _curator addCuratorEditableObjects [_zeusEntities, true];
    LOG_1("rovingSpawnFoot - added %1 entities to Zeus",count _zeusEntities);
} else {
    LOG("rovingSpawnFoot - no curator available, skipping Zeus add");
};

// Stats
private _stats = missionNamespace getVariable ["DSC_rovingStats", createHashMap];
_stats set ["spawned", (_stats getOrDefault ["spawned", 0]) + 1];
_stats set ["footSpawned", (_stats getOrDefault ["footSpawned", 0]) + 1];

LOG_6("roving spawned [foot] %1 src=%2/%3 spawn=%4m units=%5 sideKey=%6",_groupName,_origin get "type",_origin get "id",round (_spawnPos distance2D _playerPos),count (units _group),_sideKey);

_record
