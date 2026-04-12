#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_cleanupMission
 * Description:
 *     Cleans up all mission assets (units, vehicles, groups, markers).
 *
 * Arguments:
 *     0: _mission <HASHMAP> - Mission data from generateKillCaptureMission
 *
 * Return Value:
 *     <BOOL> - True if cleanup succeeded
 *
 * Example:
 *     [_mission] call DSC_core_fnc_cleanupMission
 */

params [
    ["_mission", createHashMap, [createHashMap]]
];

if (count _mission == 0) exitWith {
    diag_log "DSC: Cleanup - No mission data provided";
    false
};

diag_log "DSC: Mission cleanup starting...";

private _units = _mission getOrDefault ["units", []];
private _vehicles = _mission getOrDefault ["vehicles", []];
private _groups = _mission getOrDefault ["groups", []];
private _marker = _mission getOrDefault ["marker", ""];

// Delete all tracked units including dead bodies
{
    if (!isNull _x) then {
        deleteVehicle _x;
    };
    sleep 0.05;
} forEach _units;

// Delete all tracked vehicles (works even if destroyed)
{
    if (!isNull _x) then {
        deleteVehicle _x;
    };
    sleep 0.05;
} forEach _vehicles;

// Delete groups after units and vehicles
{
    if (!isNull _x) then {
        deleteGroup _x;
    };
} forEach _groups;

// Delete mission marker
if (_marker isEqualType "") then {
    if (_marker != "") then {
        deleteMarker _marker;
    };
} else {
    if (!isNil "_marker") then {
        deleteMarker _marker;
    };
};

// Delete player drop markers
{
    deleteMarker format ["dsc_drop_%1", getPlayerUID _x];
} forEach allPlayers;

// Clear global mission variable
missionNamespace setVariable ["DSC_currentMission", nil, true];

diag_log format ["DSC: Cleanup complete - %1 units, %2 vehicles, %3 groups deleted", 
    count _units, count _vehicles, count _groups];

true
