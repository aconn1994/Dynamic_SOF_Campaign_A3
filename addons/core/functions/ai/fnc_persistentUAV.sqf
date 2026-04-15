#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_persistentUAV
 * Description:
 *     Manages a persistent ISR drone over the mission area. Spawns a UAV that
 *     loiters over the target, locks camera to objective. Handles refuel cycle
 *     (goes off-station at low fuel, returns after delay) and shoot-down recovery.
 *
 *     Runs as a persistent loop - call once, it manages itself forever.
 *     Checks for existing drone before spawning a new one.
 *
 * Arguments:
 *     0: _targetPos <ARRAY> - Position to loiter over and lock camera to
 *     1: _config <HASHMAP> - Optional configuration
 *        - "uavClass": UAV classname (default: "B_UAV_02_dynamicLoadout_F")
 *        - "altitude": Loiter altitude (default: 1250)
 *        - "loiterRadius": Orbit radius (default: 1250)
 *        - "fuelThreshold": Fuel level to trigger RTB (default: 0.2)
 *        - "refuelTime": Seconds off-station for refuel (default: 600)
 *        - "destroyedDelay": Seconds before replacement after shoot-down (default: 1800)
 *
 * Return Value:
 *     None (runs as persistent loop)
 *
 * Example:
 *     [_missionPos] spawn DSC_core_fnc_persistentUAV;
 */

params [
    ["_targetPos", [], [[]]],
    ["_config", createHashMap, [createHashMap]]
];

if (_targetPos isEqualTo []) exitWith {
    diag_log "DSC: persistentUAV - No target position";
};

private _uavClass = _config getOrDefault ["uavClass", "B_UAV_02_dynamicLoadout_F"];
private _altitude = _config getOrDefault ["altitude", 1250];
private _loiterRadius = _config getOrDefault ["loiterRadius", 1250];
private _fuelThreshold = _config getOrDefault ["fuelThreshold", 0.2];
private _refuelTime = _config getOrDefault ["refuelTime", 600];
private _destroyedDelay = _config getOrDefault ["destroyedDelay", 1800];

// Spawn position - far off map edge
private _spawnPos = [_targetPos select 0, (_targetPos select 1) - 5000, _altitude];

diag_log format ["DSC: Persistent UAV spawning - target: %1, class: %2", _targetPos, _uavClass];

// Spawn UAV
private _uav = createVehicle [_uavClass, _spawnPos, [], 0, "FLY"];
createVehicleCrew _uav;
_uav flyInHeight _altitude;
_uav allowDamage true;

// Connect to player terminal
private _uavGroup = group _uav;
{
    _x setBehaviour "CARELESS";
    _x disableAI "AUTOCOMBAT";
} forEach units _uavGroup;

// Make undetectable by enemy AI
_uav setCaptive true;

// Set loiter waypoint
private _wp = _uavGroup addWaypoint [_targetPos, 0];
_wp setWaypointType "LOITER";
_wp setWaypointLoiterAltitude _altitude;
_wp setWaypointLoiterRadius _loiterRadius;
_wp setWaypointLoiterType "CIRCLE";

// Lock camera to target
_uav lockCameraTo [_targetPos, [0]];

// Store globally for reference
missionNamespace setVariable ["DSC_activeUAV", _uav, true];
missionNamespace setVariable ["DSC_activeUAVGroup", _uavGroup, true];

systemChat "ISR drone on station in approximately 5 minutes.";
diag_log "DSC: UAV on approach to station";

// ============================================================================
// Monitor loop - fuel and alive status
// ============================================================================
waitUntil {
    sleep 5;
    // Re-lock camera if target has changed
    private _currentTarget = missionNamespace getVariable ["DSC_uavTargetPos", _targetPos];
    if (_currentTarget isNotEqualTo (_uav getVariable ["DSC_lastTarget", []])) then {
        _uav lockCameraTo [_currentTarget, [0]];
        _uav setVariable ["DSC_lastTarget", _currentTarget];

        // Update loiter waypoint
        while { (waypoints _uavGroup) isNotEqualTo [] } do {
            deleteWaypoint [_uavGroup, 0];
        };
        private _newWp = _uavGroup addWaypoint [_currentTarget, 0];
        _newWp setWaypointType "LOITER";
        _newWp setWaypointLoiterAltitude _altitude;
        _newWp setWaypointLoiterRadius _loiterRadius;
        _newWp setWaypointLoiterType "CIRCLE";

        diag_log format ["DSC: UAV retargeted to %1", _currentTarget];
    };

    !alive _uav || (fuel _uav) < _fuelThreshold
};

// ============================================================================
// Handle off-station / destroyed
// ============================================================================
private _nextTargetPos = missionNamespace getVariable ["DSC_uavTargetPos", _targetPos];

if (!alive _uav) then {
    systemChat "ISR drone has been shot down. Replacement in 30 minutes.";
    diag_log "DSC: UAV destroyed - replacement delayed";

    // Cleanup wreck
    sleep 30;
    deleteVehicle _uav;

    missionNamespace setVariable ["DSC_activeUAV", nil, true];
    missionNamespace setVariable ["DSC_activeUAVGroup", nil, true];

    sleep (_destroyedDelay - 30);
} else {
    systemChat "ISR drone at bingo fuel. Going off-station. Back in 10 minutes.";
    diag_log "DSC: UAV RTB for refuel";

    // Fly away
    while { (waypoints _uavGroup) isNotEqualTo [] } do {
        deleteWaypoint [_uavGroup, 0];
    };
    _uav move _spawnPos;

    sleep _refuelTime;

    // Cleanup old UAV
    { deleteVehicle _x } forEach crew _uav;
    deleteVehicle _uav;
    deleteGroup _uavGroup;

    missionNamespace setVariable ["DSC_activeUAV", nil, true];
    missionNamespace setVariable ["DSC_activeUAVGroup", nil, true];
};

// Respawn if there's still an active mission
_nextTargetPos = missionNamespace getVariable ["DSC_uavTargetPos", []];
if (_nextTargetPos isNotEqualTo []) then {
    [_nextTargetPos, _config] spawn DSC_core_fnc_persistentUAV;
} else {
    diag_log "DSC: UAV cycle ended - no active target";
};
