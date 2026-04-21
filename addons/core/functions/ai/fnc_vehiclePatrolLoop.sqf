#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_vehiclePatrolLoop
 * Description:
 *     Simple vehicle patrol: drives to a road point, holds for ~2 minutes,
 *     then drives to the next point. Repeats until combat or QRF interrupt.
 *
 *     Future: dismount/remount cycle (see .crush/vehicle-systems.md)
 *
 * Arguments (passed via spawn):
 *     0: _group <GROUP> - The patrol group
 *     1: _center <ARRAY> - Patrol center position
 *     2: _patrolRadius <ARRAY> - [min, max] driving leg distance
 *     3: _dismountRadius <ARRAY> - (unused, reserved for future dismount cycle)
 *     4: _dismountDuration <ARRAY> - (unused, reserved for future dismount cycle)
 *     5: _speed <STRING> - "LIMITED" or "NORMAL"
 */

params ["_group", "_center", "_patrolRadius", "_dismountRadius", "_dismountDuration", "_speed"];

private _vehicle = _group getVariable ["DSC_vehPatrol_vehicle", objNull];

if (isNull _vehicle || { isNull _group }) exitWith {
    diag_log "DSC: vehiclePatrolLoop - Invalid group or vehicle, exiting";
};

// Combat interrupt: release all AI on contact
{
    _x addEventHandler ["FiredNear", {
        params ["_unit"];
        private _grp = group _unit;
        if (_grp getVariable ["DSC_vehPatrol_combat", false]) exitWith {};
        _grp setVariable ["DSC_vehPatrol_combat", true];
        _grp setBehaviour "COMBAT";
        _grp setCombatMode "RED";
        diag_log format ["DSC: vehiclePatrolLoop - Combat triggered for %1", _grp];
    }];
} forEach units _group;

private _fnc_shouldAbort = {
    _group getVariable ["DSC_vehPatrol_qrf", false]
    || { _group getVariable ["DSC_vehPatrol_combat", false] }
    || { !alive _vehicle }
    || { isNull _group }
    || { {alive _x} count units _group == 0 }
};

diag_log format ["DSC: vehiclePatrolLoop - Starting for %1", _group];

while { !(call _fnc_shouldAbort) } do {

    // Find a distant road point
    private _legDist = (_patrolRadius select 0) + random ((_patrolRadius select 1) - (_patrolRadius select 0));
    private _routeDir = ((getPos _vehicle) getDir _center) + (random 120) - 60;
    private _route = [getPos _vehicle, _legDist, _routeDir] call DSC_core_fnc_buildRoadRoute;

    if (_route isEqualTo []) then {
        diag_log "DSC: vehiclePatrolLoop - No road route found, retrying";
        sleep 10;
        continue;
    };

    private _destination = _route select -1;

    // Single waypoint — driver follows roads naturally
    while { (waypoints _group) isNotEqualTo [] } do {
        deleteWaypoint [_group, 0];
    };

    private _wp = _group addWaypoint [_destination, 0];
    _wp setWaypointType "MOVE";
    _wp setWaypointSpeed _speed;
    _wp setWaypointBehaviour "SAFE";
    _wp setWaypointCompletionRadius 30;

    diag_log format ["DSC: vehiclePatrolLoop - Driving to point %1m away", round (_vehicle distance2D _destination)];

    // Wait for arrival
    waitUntil {
        sleep 3;
        (call _fnc_shouldAbort) || { _vehicle distance2D _destination < 50 }
    };

    if (call _fnc_shouldAbort) then { continue };

    // Hold position for ~2 minutes
    diag_log format ["DSC: vehiclePatrolLoop - Holding at %1", getPos _vehicle];
    private _holdTime = 100 + random 40;
    private _holdEnd = time + _holdTime;

    waitUntil {
        sleep 5;
        (call _fnc_shouldAbort) || { time > _holdEnd }
    };

    if (call _fnc_shouldAbort) then { continue };

    diag_log "DSC: vehiclePatrolLoop - Hold complete, moving to next point";
};

// Release AI on exit
private _exitReason = "unknown";
if (_group getVariable ["DSC_vehPatrol_combat", false]) then { _exitReason = "combat" };
if (_group getVariable ["DSC_vehPatrol_qrf", false]) then { _exitReason = "qrf" };
if (!alive _vehicle) then { _exitReason = "vehicle destroyed" };
if (isNull _group || { {alive _x} count units _group == 0 }) then { _exitReason = "group dead" };

diag_log format ["DSC: vehiclePatrolLoop - Ended for %1 (reason: %2)", _group, _exitReason];

// ======================================================================
// FUTURE: Dismount/Remount Cycle
// ======================================================================
// The full vision is documented in .crush/vehicle-systems.md:
//   - After arriving at hold point, dismount infantry one at a time
//   - Infantry does a short foot patrol loop returning near the vehicle
//   - Infantry remounts one at a time
//   - Vehicle drives to next point
//
// Key issues from initial implementation attempts:
//   - BIS_fnc_spawnGroup vehicle role assignment is unreliable
//   - AI remounting requires aggressive retry + force teleport fallback
//   - Crew disableAI "PATH"/"MOVE" must be re-enabled before each driving leg
//   - Foot patrol early-exit check must enforce minimum time before proximity check
//   - Combat interrupt must fully release all AI (enableAI + behaviour COMBAT)
