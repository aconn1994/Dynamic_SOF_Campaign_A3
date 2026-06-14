#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_rovingSpawnAir
 * Description:
 *     Spawns a single ambient air rover (rotary or fixed-wing) and starts its
 *     transit. Picks an origin and destination hotspot from the registry and
 *     plots a flight path that visibly transits the player's vicinity. The
 *     entity is registered to the active-rover tracker so the despawn sweep
 *     can cull it later.
 *
 *     Behavior:
 *       - AWARE + disableAI "AUTOCOMBAT" (ambient, no engagement unless fired
 *         upon directly — matches persistentUAV pattern)
 *       - flyInHeight per type (rotary 100m, fixed-wing 800m)
 *       - 2-3 transit waypoints with a MOVE through, then a "leave the map"
 *         waypoint past the despawn ring so we have a graceful exit if the
 *         worker never picks them up
 *       - opt-in to dynamic simulation
 *
 *     Hotspot selection rules (density bias your way):
 *       1. Pick a side from `_sideMix` (weighted random across east / west)
 *       2. Build a candidate list = side hotspots within 6km of player + 30%
 *          of side hotspots beyond 6km (the "rare ambient overflight" floor)
 *       3. Weighted pick by `hotspot.weight * (1 + influence)`
 *       4. Destination = different hotspot within 4-15km of origin; if no
 *          such hotspot, synth one on the far side of the player
 *
 * Arguments:
 *     0: _airType    <STRING>  - "rotary" | "fixedWing"
 *     1: _hotspots   <HASHMAP> - from fnc_resolveRovingHotspots
 *     2: _factionData<HASHMAP> - role -> data (used to pick aircraft classes)
 *     3: _sideKey    <STRING>  - "east" | "west" — which side this air rover belongs to
 *
 * Return Value:
 *     <HASHMAP> - rover record, or empty hashmap on failure
 *       "id"        <STRING>  unique rover id
 *       "type"      <STRING>  "rotary" | "fixedWing"
 *       "vehicle"   <OBJECT>  spawned aircraft
 *       "group"     <GROUP>   the group
 *       "side"      <SIDE>    east / west
 *       "spawnTime" <NUMBER>  diag_tickTime
 *       "origin"    <ARRAY>   spawn position
 *       "destination" <ARRAY> final waypoint position
 *
 * Example:
 *     [["rotary"], _hotspots, _factionData, "east"] call DSC_core_fnc_rovingSpawnAir;
 */

params [
    ["_airType",     "rotary",      [""]],
    ["_hotspots",    createHashMap, [createHashMap]],
    ["_factionData", createHashMap, [createHashMap]]
];

private _empty = createHashMap;

if !(_airType in ["rotary", "fixedWing"]) exitWith {
    diag_log format ["DSC: rovingSpawnAir - Invalid air type '%1'", _airType];
    _empty
};

private _player = call CBA_fnc_currentUnit;
if (isNull _player) exitWith { _empty };
private _playerPos = getPosASL _player;

// ============================================================================
// Step 1: nearest hotspot to the player → side / faction pool
// ============================================================================
// Same ambient model as ground rovers: player's local controlling installation
// drives the air faction. opFor territory → opFor air; bluFor → bluFor air.
// All hotspot types eligible for air (airbases included).
private _allHotspots = _hotspots getOrDefault ["all", []];
if (_allHotspots isEqualTo []) exitWith {
    diag_log "DSC: rovingSpawnAir - No hotspots registered";
    _empty
};
private _sortedHotspots = [_allHotspots, [], { (_x get "position") distance2D _playerPos }, "ASCEND"] call BIS_fnc_sortBy;
private _nearestHotspot = _sortedHotspots select 0;
private _side = _nearestHotspot get "side";
private _sideKey = ["west", "east"] select (_side isEqualTo east);

private _origin = _nearestHotspot;
private _originPos = _nearestHotspot get "position";

// ============================================================================
// Step 2: synth destination on the far side of the player
// ============================================================================
// Aircraft transit through the player's vicinity to a distant exit point.
// Pick a random direction biased toward an arbitrary far heading so the
// flight path crosses the player area.
private _spawnDir = random 360;            // angle from player to spawn point
private _exitDir  = _spawnDir + 180;       // opposite side of player
private _destPos  = _playerPos getPos [(6000 + random 4000), _exitDir];

// ============================================================================
// Step 3: resolve aircraft class for the side
// ============================================================================
// Roving air pulls from opFor / bluFor only (not partner roles) per design.
private _roleKey = ["bluFor", "opFor"] select (_sideKey == "east");
private _roleData = _factionData getOrDefault [_roleKey, createHashMap];
private _assetsByFaction = _roleData getOrDefault ["assets", createHashMap];

private _airPool = [];
{
    private _assets = _y;
    private _airBucket = if (_airType == "rotary") then {
        _assets getOrDefault ["helicopters", createHashMap]
    } else {
        _assets getOrDefault ["planes", createHashMap]
    };
    // Phase 1 picks from both attack and transport buckets — variety beats
    // strict role-realism for ambient overflight.
    {
        { _airPool pushBackUnique _x } forEach _y;
    } forEach _airBucket;
} forEach _assetsByFaction;

if (_airPool isEqualTo []) exitWith {
    diag_log format ["DSC: rovingSpawnAir - No %1 aircraft in %2 pool", _airType, _roleKey];
    _empty
};

private _airClass = selectRandom _airPool;

// ============================================================================
// Step 4: spawn at altitude on the spawn-direction side of the player
// ============================================================================
// _spawnDir is a random angle from player. Aircraft spawns there at altitude,
// flies through player area to _destPos on the opposite side.
private _altitude = if (_airType == "rotary") then { 100 + random 50 } else { 600 + random 400 };
private _spawnDistFromPlayer = if (_airType == "rotary") then { 2500 + random 2000 } else { 4000 + random 2000 };

private _spawnPos2D = _playerPos getPos [_spawnDistFromPlayer, _spawnDir];
private _spawnPos = [_spawnPos2D select 0, _spawnPos2D select 1, _altitude];

// ============================================================================
// Step 5: create vehicle + crew
// ============================================================================
private _vehicle = createVehicle [_airClass, _spawnPos, [], 0, "FLY"];
if (isNull _vehicle) exitWith {
    diag_log format ["DSC: rovingSpawnAir - Failed to createVehicle %1 at %2", _airClass, _spawnPos];
    _empty
};

_vehicle setPosASL _spawnPos;
_vehicle setDir (_spawnPos2D getDir _destPos);
_vehicle flyInHeight _altitude;
_vehicle allowDamage true;

private _group = createVehicleCrew _vehicle;
if (isNull _group) exitWith {
    deleteVehicle _vehicle;
    diag_log format ["DSC: rovingSpawnAir - createVehicleCrew failed for %1", _airClass];
    _empty
};

// Ambient posture — see persistentUAV gotcha note: CARELESS makes flyers
// cling to current waypoint. AWARE + disable AUTOCOMBAT gives clean transit
// without firing on player vehicles passively.
_group setBehaviour "AWARE";
_group setCombatMode "BLUE";
_group setSpeedMode "NORMAL";
{
    _x disableAI "AUTOCOMBAT";
    _x disableAI "TARGET";
    _x disableAI "AUTOTARGET";
} forEach units _group;

_group enableDynamicSimulation true;
_vehicle enableDynamicSimulation true;

// ============================================================================
// Step 6: waypoints — vary between transit flyover and loiter behavior
// ============================================================================
// Behavior roll for variety:
//   - 55% TRANSIT: aircraft passes through player area and exits on the far
//     side. Reads as "going somewhere, just happens to fly over."
//   - 45% LOITER: aircraft circles a point near the player for 90-180s
//     before continuing onward. Reads as "patrol/monitoring/deterrent
//     orbit." Implemented via 3-4 waypoints in a CYCLE around a near-
//     player point, with the cycle dropped after the loiter timer expires.
//
// All air retains AWARE + autocombat-disabled posture, so loitering is
// non-threatening to the player.
private _behavior = ["loiter", "transit"] select (random 1 < 0.05);

if (_behavior == "transit") then {
    // Mid-waypoint near the player keeps the flight visible. Final waypoint
    // past the destination heading off-map ensures the aircraft doesn't
    // hang around if the despawn sweep is delayed.
    private _midPos = [
        (_playerPos select 0) + (-500 + random 1000),
        (_playerPos select 1) + (-500 + random 1000),
        _altitude
    ];

    private _wpMid = _group addWaypoint [_midPos, 0];
    _wpMid setWaypointType "MOVE";
    _wpMid setWaypointSpeed "NORMAL";
    _wpMid setWaypointBehaviour "AWARE";
    _wpMid setWaypointCombatMode "BLUE";

    private _wpDest = _group addWaypoint [_destPos, 0];
    _wpDest setWaypointType "MOVE";
    _wpDest setWaypointSpeed "NORMAL";
} else {
    // LOITER: pick a point 800-1500m offset from the player at altitude,
    // generate 3 orbital waypoints around it, set CYCLE so the aircraft
    // circles indefinitely. A short scheduled scope kills the cycle after
    // 90-180s and pushes the aircraft toward the exit, so it doesn't
    // loiter forever.
    private _loiterCenter = [
        (_playerPos select 0) + (-1000 + random 2000),
        (_playerPos select 1) + (-1000 + random 2000),
        _altitude
    ];
    private _loiterRadius = [1500, 600] select (_airType == "rotary");

    for "_i" from 0 to 2 do {
        private _ang = (_i * 120) + (random 30);
        private _ringPos = [
            (_loiterCenter select 0) + _loiterRadius * sin _ang,
            (_loiterCenter select 1) + _loiterRadius * cos _ang,
            _altitude
        ];
        private _wp = _group addWaypoint [_ringPos, 0];
        _wp setWaypointType "MOVE";
        _wp setWaypointSpeed "LIMITED";
        _wp setWaypointBehaviour "AWARE";
        _wp setWaypointCombatMode "BLUE";
    };
    // CYCLE waypoint sends the AI back to the first waypoint
    private _wpCycle = _group addWaypoint [_loiterCenter, 0];
    _wpCycle setWaypointType "CYCLE";

    // Loiter timer: after 90-180s, drop the cycle and add the exit run.
    private _loiterDuration = 90 + random 90;
    [_group, _destPos, _loiterDuration] spawn {
        params ["_g", "_dPos", "_dur"];
        sleep _dur;
        if (isNull _g) exitWith {};
        while { (waypoints _g) isNotEqualTo [] } do {
            deleteWaypoint [_g, 0];
        };
        private _wpExit = _g addWaypoint [_dPos, 0];
        _wpExit setWaypointType "MOVE";
        _wpExit setWaypointSpeed "NORMAL";
    };
};

// Final "leave" waypoint — extend beyond destination so the rover keeps
// flying outbound until despawn culls it. Transit only — loiter behavior
// builds its own exit via the scheduled scope above.
if (_behavior == "transit") then {
    private _exitPos = _destPos getPos [6000, _exitDir];
    private _wpExit = _group addWaypoint [_exitPos, 0];
    _wpExit setWaypointType "MOVE";
    _wpExit setWaypointSpeed "NORMAL";
};

// ============================================================================
// Step 7: register on tracker
// ============================================================================
private _id = format ["roving_air_%1_%2", _sideKey, diag_tickTime];
private _record = createHashMapFromArray [
    ["id",          _id],
    ["type",        _airType],
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

// Zeus integration — register vehicle + crew so Zeus operators can see and
// edit ambient air traffic. Matches the pattern used by presence handlers.
// addCuratorEditableObjects accepts Objects only — groups are not supported.
private _curator = if (allCurators isNotEqualTo []) then { allCurators select 0 } else { objNull };
if (!isNull _curator) then {
    private _zeusEntities = [_vehicle] + (units _group);
    _curator addCuratorEditableObjects [_zeusEntities, true];
    diag_log format ["DSC: rovingSpawnAir - added %1 entities to Zeus", count _zeusEntities];
} else {
    diag_log "DSC: rovingSpawnAir - no curator available, skipping Zeus add";
};

// Stats
private _stats = missionNamespace getVariable ["DSC_rovingStats", createHashMap];
_stats set ["spawned", (_stats getOrDefault ["spawned", 0]) + 1];
_stats set [_airType + "Spawned", (_stats getOrDefault [_airType + "Spawned", 0]) + 1];
private _nearHotspot = (_originPos distance2D _playerPos) < 6000;
if (_nearHotspot) then {
    _stats set ["nearHotspotSpawns", (_stats getOrDefault ["nearHotspotSpawns", 0]) + 1];
};

diag_log format ["DSC: roving spawned [%1/%2] %3 src=%4/%5 dst=%6m alt=%7m sideKey=%8",
    _airType, _behavior, _airClass, _origin get "type", _origin get "id",
    round (_originPos distance2D _destPos), round _altitude, _sideKey];

_record
