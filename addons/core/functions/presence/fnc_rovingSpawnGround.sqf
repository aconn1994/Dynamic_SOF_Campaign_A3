#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_rovingSpawnGround
 * Description:
 *     Sprint E Phase 2 — Roving ground patrol spawner.
 *
 *     Spawns a motorized or mechanized patrol group on a road at the spawn
 *     bubble edge and gives it a sequence of road waypoints that route it
 *     through the player's vicinity and onward. The aircraft equivalent of
 *     a transit overflight — they drive past, not toward, the player.
 *
 *     Phase 2 keeps the same ambient posture as Phase 1 air (AWARE +
 *     disableAI AUTOCOMBAT) so ground rovers don't actively engage the
 *     player. They will return fire if attacked first.
 *
 *     Selection rules (redesigned for ambient world):
 *       1. Nearest non-airbase hotspot to the player determines the SIDE and
 *          the faction pool. Player in opFor territory sees opFor patrols;
 *          player in bluFor territory sees bluFor patrols. Faction influence
 *          → faction roving presence.
 *       2. Spawn position is a random road **0.8–2.5 km** from the player in
 *          any direction. Same close-spawn convention as garrison/guard
 *          spawn locations — the rover starts inside the encounter window.
 *       3. Patrol via `fnc_rovingGroundPatrolLoop`: single road-bound MOVE
 *          waypoint at a time via `fnc_buildRoadRoute`, brief hold, repeat.
 *          Adapted from the proven `fnc_setupVehiclePatrol` pattern.
 *       4. Group pool = classified groups tagged MOTORIZED or MECHANIZED,
 *          with PATROL tag preferred; AT_TEAM / AA_TEAM excluded.
 *
 *     Behavior:
 *       - BIS_fnc_spawnGroup (vehicle + crew + dismounts, ~5-7 units total)
 *       - AWARE + BLUE combat mode + disable AUTOCOMBAT/TARGET/AUTOTARGET
 *       - Speed LIMITED so they actually navigate the road network without
 *         flipping at every corner
 *       - Road waypoints via fnc_buildRoadRoute from spawn through player
 *         direction; final waypoint past the despawn ring
 *       - Dynamic simulation opt-in
 *
 * Arguments:
 *     0: _hotspots   <HASHMAP> - from fnc_resolveRovingHotspots
 *     1: _factionData<HASHMAP> - role -> data (groups + assets)
 *
 * Note: _sideKey is no longer required — side is derived from the nearest
 * non-airbase hotspot to the player at spawn time.
 *
 * Return Value:
 *     <HASHMAP> - rover record, or empty hashmap on failure
 *       "id"        <STRING>
 *       "type"      <STRING>  "ground"
 *       "vehicle"   <OBJECT>
 *       "group"     <GROUP>
 *       "side"      <SIDE>
 *       "spawnTime" <NUMBER>
 *       "origin"    <ARRAY>
 *       "destination" <ARRAY>
 *
 * Example:
 *     [_hotspots, _factionData] call DSC_core_fnc_rovingSpawnGround;
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
// Step 1: nearest non-airbase hotspot to the player → side / faction pool
// ============================================================================
// Player's local controlling installation drives the roving faction. Player
// in opFor territory sees opFor patrols; bluFor territory → bluFor patrols.
private _nonAirbase = (_hotspots getOrDefault ["all", []]) select { (_x get "type") != "airbase" };
if (_nonAirbase isEqualTo []) exitWith {
    diag_log "DSC: rovingSpawnGround - No non-airbase hotspots registered";
    _empty
};
private _sortedHotspots = [_nonAirbase, [], { (_x get "position") distance2D _playerPos }, "ASCEND"] call BIS_fnc_sortBy;
private _nearestHotspot = _sortedHotspots select 0;
private _side = _nearestHotspot get "side";
private _sideKey = ["west", "east"] select (_side isEqualTo east);

// ============================================================================
// Step 2: pick a road 800-2500 m from the player in a random direction
// ============================================================================
// Same model as garrisons/guards: spawn position is independent of the
// hotspot's geographic location. The hotspot only decides who shows up;
// the spawn radius keeps the rover within the player's ambient zone.
// Tightened to 800-2500m (was 2500-4000m) so motorized rovers don't have
// to travel far before being visible — ambient world presence beats
// realistic "coming from base" distance.
private _spawnPos = [];
private _spawnAttempts = 5;
for "_attempt" from 0 to (_spawnAttempts - 1) do {
    if (_spawnPos isEqualTo []) then {
        private _angle = random 360;
        private _dist = 800 + random 1700;
        private _searchCenter = _playerPos getPos [_dist, _angle];
        private _roads = _searchCenter nearRoads 1000;
        if (_roads isNotEqualTo []) then {
            _spawnPos = getPosATL (selectRandom _roads);
        };
    };
};

if (_spawnPos isEqualTo []) exitWith {
    diag_log "DSC: rovingSpawnGround - No roads found in 800-2500m ring around player";
    _empty
};

// Origin label retained for backward-compat with stats/record schema.
private _origin = _nearestHotspot;
private _originPos = _nearestHotspot get "position";

// ============================================================================
// Step 3: resolve a motorized/mechanized PATROL group for the side
// ============================================================================
// Side / role key already resolved from nearest hotspot above.
private _roleKey = ["bluFor", "opFor"] select (_sideKey == "east");
private _roleData = _factionData getOrDefault [_roleKey, createHashMap];
private _groupsByFaction = _roleData getOrDefault ["groups", createHashMap];

private _groupPool = [];
{
    private _classifiedGroups = _y;
    // Prefer MOTORIZED+PATROL; broaden to MOTORIZED or MECHANIZED if needed.
    private _matches = [_classifiedGroups, ["MOTORIZED", "PATROL"], ["AT_TEAM", "AA_TEAM"]] call DSC_core_fnc_getGroupsByTag;
    if (_matches isEqualTo []) then {
        _matches = [_classifiedGroups, ["MECHANIZED", "PATROL"], ["AT_TEAM", "AA_TEAM"]] call DSC_core_fnc_getGroupsByTag;
    };
    if (_matches isEqualTo []) then {
        _matches = [_classifiedGroups, ["MOTORIZED"], ["AT_TEAM", "AA_TEAM"]] call DSC_core_fnc_getGroupsByTag;
    };
    { _groupPool pushBack _x } forEach _matches;
} forEach _groupsByFaction;

if (_groupPool isEqualTo []) exitWith {
    diag_log format ["DSC: rovingSpawnGround - No motorized/mechanized PATROL groups in %1 pool", _roleKey];
    _empty
};

private _groupTemplate = selectRandom _groupPool;
private _groupPath = _groupTemplate get "path";
private _groupName = _groupTemplate get "groupName";

// Walk path to CfgGroups entry
private _pathParts = _groupPath splitString "/";
private _groupConfig = configFile >> "CfgGroups";
{ _groupConfig = _groupConfig >> _x } forEach _pathParts;

if (!isClass _groupConfig) exitWith {
    diag_log format ["DSC: rovingSpawnGround - Invalid CfgGroups path: %1", _groupPath];
    _empty
};

// ============================================================================
// Step 4: spawn the group on the road
// ============================================================================
private _group = [_spawnPos, _side, _groupConfig] call BIS_fnc_spawnGroup;
if (isNull _group) exitWith {
    diag_log format ["DSC: rovingSpawnGround - BIS_fnc_spawnGroup failed for %1", _groupName];
    _empty
};

// Identify the lead vehicle (first unit with objectParent)
private _vehicle = objNull;
{
    if (!isNull (objectParent _x)) exitWith { _vehicle = vehicle _x };
} forEach units _group;

if (isNull _vehicle) exitWith {
    diag_log format ["DSC: rovingSpawnGround - Group %1 spawned with no vehicle, aborting", _groupName];
    { deleteVehicle _x } forEach units _group;
    deleteGroup _group;
    _empty
};

// Force-mount all dismounts into the vehicle's cargo so the whole group
// transits together. BIS_fnc_spawnGroup only mounts driver/gunner from the
// CfgGroups vehicle entry — dismounts spawn on foot, which previously left
// motorized teams with a stationary truck and infantry standing around.
// Trim any units that don't fit (rare; cargo capacity usually >= dismount count).
{
    private _u = _x;
    if (_u != driver _vehicle && {!(_u in crew _vehicle)}) then {
        private _cargoCapacity = _vehicle emptyPositions "cargo";
        if (_cargoCapacity > 0) then {
            _u moveInCargo _vehicle;
        } else {
            deleteVehicle _u;
        };
    };
} forEach (units _group);

// Make the vehicle's driver the group leader so taskPatrol waypoints
// route through the driver's control loop, not a foot soldier's.
private _driver = driver _vehicle;
if (!isNull _driver) then { _group selectLeader _driver };

// Ambient posture — match air rover behavior
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
} forEach (units _group + [_vehicle]);

// ============================================================================
// Step 5: launch the patrol loop
// ============================================================================
// Drop-in replacement for the failed BIS_fnc_taskPatrol approach. The loop
// drives the rover via a single road-bound MOVE waypoint at a time using
// fnc_buildRoadRoute, holds briefly, then picks a new destination. Same
// proven pattern as fnc_setupVehiclePatrol (mission AO vehicle patrols).
private _patrolHandle = [_group, _vehicle, _playerPos, [800, 1800]] spawn DSC_core_fnc_rovingGroundPatrolLoop;

// Destination value retained for stats/log compatibility — not a real
// destination since the rover patrols dynamically.
private _destPos = _playerPos;

// ============================================================================
// Step 6: register on tracker
// ============================================================================
private _id = format ["roving_ground_%1_%2", _sideKey, diag_tickTime];
private _record = createHashMapFromArray [
    ["id",          _id],
    ["type",        "ground"],
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

// Zeus integration — register vehicle + crew so Zeus can edit ambient ground patrols.
// addCuratorEditableObjects accepts Objects only — groups are not supported.
private _curator = if (allCurators isNotEqualTo []) then { allCurators select 0 } else { objNull };
if (!isNull _curator) then {
    private _zeusEntities = [_vehicle] + (units _group);
    _curator addCuratorEditableObjects [_zeusEntities, true];
    diag_log format ["DSC: rovingSpawnGround - added %1 entities to Zeus", count _zeusEntities];
} else {
    diag_log "DSC: rovingSpawnGround - no curator available, skipping Zeus add";
};

// Stats
private _stats = missionNamespace getVariable ["DSC_rovingStats", createHashMap];
_stats set ["spawned", (_stats getOrDefault ["spawned", 0]) + 1];
_stats set ["groundSpawned", (_stats getOrDefault ["groundSpawned", 0]) + 1];
private _nearHotspot = (_originPos distance2D _playerPos) < 7000;
if (_nearHotspot) then {
    _stats set ["nearHotspotSpawns", (_stats getOrDefault ["nearHotspotSpawns", 0]) + 1];
};

diag_log format ["DSC: roving spawned [ground] %1 (%2) src=%3/%4 spawn=%5m units=%6 sideKey=%7",
    typeOf _vehicle, _groupName, _origin get "type", _origin get "id",
    round (_spawnPos distance2D _playerPos), count (units _group), _sideKey];

_record
