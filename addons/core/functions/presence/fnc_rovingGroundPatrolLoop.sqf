#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_rovingGroundPatrolLoop
 * Description:
 *     Lightweight patrol loop for roving ground rovers. Repeats a simple
 *     drive-to-road-point → hold → drive-to-next-point cycle until the
 *     vehicle is destroyed, the crew is dead, or the rover is far from
 *     the player (caller despawn sweep handles the latter via deletion).
 *
 *     Adapted from `fnc_vehiclePatrolLoop` (mission AO vehicle patrols) —
 *     same proven pattern: single MOVE waypoint to a real road
 *     destination via `fnc_buildRoadRoute`, completion radius for arrival
 *     detection, brief hold, next leg. `BIS_fnc_taskPatrol` was tried
 *     earlier but its `findSafePos`-driven waypoints sent rovers
 *     off-road and into pathfinding deadlocks.
 *
 *     Unlike the mission vehicle patrol, this loop:
 *       - Does NOT do a dismount/remount cycle (rovers are pure transit)
 *       - Does NOT add a combat-activation EH (ambient posture preserved)
 *       - Holds only 30-60s between legs (not 100-140s)
 *
 * Arguments (passed via spawn):
 *     0: _group <GROUP>  - The spawned roving group
 *     1: _vehicle <OBJECT> - The lead vehicle
 *     2: _patrolCenter <ARRAY> - Center of the patrol area (player position
 *                                at spawn time; intentionally not updated
 *                                during the loop)
 *     3: _legDistRange <ARRAY> - [min, max] meters per leg (default [800, 1800])
 */

params [
    ["_group", grpNull, [grpNull]],
    ["_vehicle", objNull, [objNull]],
    ["_patrolCenter", [], [[]]],
    ["_legDistRange", [800, 1800], [[]]]
];

if (isNull _group || isNull _vehicle || _patrolCenter isEqualTo []) exitWith {
    ERROR("rovingGroundPatrolLoop - Invalid args, exiting");
};

private _fnc_shouldAbort = {
    isNull _group
    || { isNull _vehicle }
    || { !alive _vehicle }
    || { {alive _x} count units _group == 0 }
};

private _legMin = _legDistRange select 0;
private _legMax = _legDistRange select 1;

// A rover that spawned on an isolated road segment can fail route planning
// on every attempt. Rather than idle until the despawn sweep collects it,
// fall back to a direct move toward the patrol center after a few failures —
// that almost always puts it back on the connected network, and the next
// plan succeeds.
private _consecutiveRouteFailures = 0;

while { !(call _fnc_shouldAbort) } do {
    private _legDist = _legMin + random (_legMax - _legMin);

    // Bias the route direction toward the patrol center so the rover
    // doesn't wander off to infinity. ±90° spread around "toward center"
    // gives variety without losing the patrol anchor.
    private _vehPos = getPos _vehicle;
    private _dirToCenter = _vehPos getDir _patrolCenter;
    private _routeDir = _dirToCenter + (random 180) - 90;

    private _route = [_vehPos, _legDist, _routeDir] call DSC_core_fnc_buildRoadRoute;

    if (_route isEqualTo []) then {
        _consecutiveRouteFailures = _consecutiveRouteFailures + 1;

        if (_consecutiveRouteFailures < 3) then {
            // No usable road route from here — wait and retry. The direction
            // bias is re-rolled each pass, so a retry is a genuinely
            // different attempt.
            sleep 8;
            continue;
        };

        // Unstick: drive straight at the patrol center and re-plan on arrival.
        LOG_1("rovingGroundPatrolLoop - %1 route failures, forcing move toward patrol center",_consecutiveRouteFailures);
        _route = [_patrolCenter];
        _consecutiveRouteFailures = 0;
    } else {
        _consecutiveRouteFailures = 0;
    };

    private _destination = _route select -1;

    // Clear existing waypoints, add one new MOVE with completion radius
    while { (waypoints _group) isNotEqualTo [] } do {
        deleteWaypoint [_group, 0];
    };

    private _wp = _group addWaypoint [_destination, 0];
    _wp setWaypointType "MOVE";
    _wp setWaypointSpeed "LIMITED";
    _wp setWaypointBehaviour "SAFE";
    _wp setWaypointCompletionRadius 40;

    // Wait for arrival, with timeout failsafe so a stuck rover doesn't
    // hang the loop forever (caller despawn sweep also kicks in eventually).
    private _legStart = time;
    private _legTimeout = 240; // 4 min max per leg
    waitUntil {
        sleep 3;
        (call _fnc_shouldAbort)
        || { _vehicle distance2D _destination < 60 }
        || { time - _legStart > _legTimeout }
    };

    if (call _fnc_shouldAbort) then { continue };

    // Brief hold (30-60s) — gives the rover a "patrol stop" feel without
    // making it appear stuck for too long.
    private _holdTime = 30 + random 30;
    private _holdEnd = time + _holdTime;
    waitUntil {
        sleep 4;
        (call _fnc_shouldAbort) || { time > _holdEnd }
    };
};
