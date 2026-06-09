#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_rovingSpawnBoat
 * Description:
 *     Sprint E Phase 3 — Roving boat patrol spawner.
 *
 *     Spawns a boat on water within the player's coastal/littoral zone
 *     and assigns it a 3-4 waypoint patrol along the shoreline near the
 *     player. Bails gracefully if no water is found within the spawn ring
 *     (player is inland), so this is map-aware: works on Altis / Tanoa /
 *     Stratis / Malden, silently skips on Livonia.
 *
 *     Selection rules:
 *       1. Nearest hotspot to the player determines SIDE and the boat
 *          asset pool. opFor coast → opFor boat; bluFor coast → bluFor.
 *       2. Spawn position is a water position 800-2000m from the player
 *          (`surfaceIsWater` check) in a random direction.
 *       3. Boat created directly via `createVehicle` + `createVehicleCrew`
 *          (no CfgGroups for naval — boat assets live in `extractAssets`
 *          as a flat `boats` array).
 *       4. Patrol: 3-4 water waypoints generated around the player in a
 *          ring 1000-2000m out, set as CYCLE so the boat loops.
 *
 *     Behavior posture: AWARE + autocombat disabled — ambient world
 *     presence, not forced encounter. Coastal boats engaging land targets
 *     across 1+ km of water is awkward; we suppress.
 *
 * Arguments:
 *     0: _hotspots   <HASHMAP> - from fnc_resolveRovingHotspots
 *     1: _factionData<HASHMAP> - role -> data (groups + assets)
 *
 * Return Value:
 *     <HASHMAP> - rover record, or empty hashmap on failure / inland map
 *
 * Example:
 *     [_hotspots, _factionData] call DSC_core_fnc_rovingSpawnBoat;
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
// Step 1: nearest hotspot → side / faction (airbases included for boats too)
// ============================================================================
private _allHotspots = _hotspots getOrDefault ["all", []];
if (_allHotspots isEqualTo []) exitWith {
    diag_log "DSC: rovingSpawnBoat - No hotspots registered";
    _empty
};
private _sortedHotspots = [_allHotspots, [], { (_x get "position") distance2D _playerPos }, "ASCEND"] call BIS_fnc_sortBy;
private _nearestHotspot = _sortedHotspots select 0;
private _side = _nearestHotspot get "side";
private _sideKey = ["west", "east"] select (_side isEqualTo east);
private _origin = _nearestHotspot;
private _originPos = _nearestHotspot get "position";

// ============================================================================
// Step 2: find a water spawn position 800-2000m from the player
// ============================================================================
// Sample several random angles; bail if no water in range (inland map).
private _spawnPos = [];
private _spawnAttempts = 12;
for "_attempt" from 0 to (_spawnAttempts - 1) do {
    if (_spawnPos isEqualTo []) then {
        private _angle = random 360;
        private _dist = 800 + random 1200;
        private _testPos = _playerPos getPos [_dist, _angle];
        if (surfaceIsWater _testPos) then {
            _spawnPos = [_testPos select 0, _testPos select 1, 0];
        };
    };
};

if (_spawnPos isEqualTo []) exitWith {
    // Inland / no coast in range — silently skip
    _empty
};

// ============================================================================
// Step 3: resolve a boat asset class for the side
// ============================================================================
private _roleKey = ["bluFor", "opFor"] select (_sideKey == "east");
private _roleData = _factionData getOrDefault [_roleKey, createHashMap];
private _assetsByFaction = _roleData getOrDefault ["assets", createHashMap];

private _boatPool = [];
{
    private _assets = _y;
    private _boats = _assets getOrDefault ["boats", []];
    { _boatPool pushBackUnique _x } forEach _boats;
} forEach _assetsByFaction;

if (_boatPool isEqualTo []) exitWith {
    diag_log format ["DSC: rovingSpawnBoat - No boat assets in %1 pool", _roleKey];
    _empty
};

private _boatClass = selectRandom _boatPool;

// ============================================================================
// Step 4: create boat + crew
// ============================================================================
private _vehicle = createVehicle [_boatClass, _spawnPos, [], 0, "NONE"];
if (isNull _vehicle) exitWith {
    diag_log format ["DSC: rovingSpawnBoat - Failed to createVehicle %1 at %2", _boatClass, _spawnPos];
    _empty
};

_vehicle setPosASL _spawnPos;
_vehicle allowDamage true;

private _group = createVehicleCrew _vehicle;
if (isNull _group) exitWith {
    deleteVehicle _vehicle;
    diag_log format ["DSC: rovingSpawnBoat - createVehicleCrew failed for %1", _boatClass];
    _empty
};

// Ambient posture
_group setBehaviour "AWARE";
_group setCombatMode "BLUE";
_group setSpeedMode "LIMITED";
{
    _x disableAI "AUTOCOMBAT";
    _x disableAI "TARGET";
    _x disableAI "AUTOTARGET";
} forEach units _group;

_group enableDynamicSimulation true;
_vehicle enableDynamicSimulation true;

// ============================================================================
// Step 5: generate water patrol waypoints in a ring around the player
// ============================================================================
// Try to find up to 4 water positions distributed roughly evenly around
// the player. CYCLE waypoint loops the patrol.
private _waterPoints = [];
private _wpAttempts = 24;
for "_attempt" from 0 to (_wpAttempts - 1) do {
    if (count _waterPoints < 4) then {
        // Roughly even angular distribution
        private _baseAngle = (count _waterPoints) * 90;
        private _angle = _baseAngle + (random 60) - 30;
        private _dist = 1000 + random 1000;
        private _testPos = _playerPos getPos [_dist, _angle];
        if (surfaceIsWater _testPos) then {
            _waterPoints pushBack [_testPos select 0, _testPos select 1, 0];
        };
    };
};

if (count _waterPoints < 2) then {
    // Coastline too narrow for a meaningful patrol — give the boat a single
    // waypoint near the spawn position so it idles in place instead of
    // pathfinding to nothing.
    _waterPoints = [_spawnPos];
};

{
    private _wp = _group addWaypoint [_x, 0];
    _wp setWaypointType "MOVE";
    _wp setWaypointSpeed "LIMITED";
    _wp setWaypointBehaviour "AWARE";
    _wp setWaypointCombatMode "BLUE";
    _wp setWaypointCompletionRadius 80;
} forEach _waterPoints;

if (count _waterPoints >= 2) then {
    private _wpCycle = _group addWaypoint [_waterPoints select 0, 0];
    _wpCycle setWaypointType "CYCLE";
};

private _destPos = _waterPoints select 0;

// ============================================================================
// Step 6: register on tracker
// ============================================================================
private _id = format ["roving_boat_%1_%2", _sideKey, diag_tickTime];
private _record = createHashMapFromArray [
    ["id",          _id],
    ["type",        "boat"],
    ["vehicle",     _vehicle],
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
    private _zeusEntities = [_vehicle] + (units _group);
    _curator addCuratorEditableObjects [_zeusEntities, true];
    diag_log format ["DSC: rovingSpawnBoat - added %1 entities to Zeus", count _zeusEntities];
} else {
    diag_log "DSC: rovingSpawnBoat - no curator available, skipping Zeus add";
};

// Stats
private _stats = missionNamespace getVariable ["DSC_rovingStats", createHashMap];
_stats set ["spawned", (_stats getOrDefault ["spawned", 0]) + 1];
_stats set ["boatSpawned", (_stats getOrDefault ["boatSpawned", 0]) + 1];

diag_log format ["DSC: roving spawned [boat] %1 src=%2/%3 spawn=%4m waypoints=%5 sideKey=%6",
    typeOf _vehicle, _origin get "type", _origin get "id",
    round (_spawnPos distance2D _playerPos), count _waterPoints, _sideKey];

_record
