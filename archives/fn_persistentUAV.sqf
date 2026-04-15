/*
    File: fn_persistentUAV.sqf
    Description: Inits Persistent UAV for player faction

    Call Logic:
        [] spawn {
            waitUntil { missionInProgress };
            sleep 5;
            [] call DJC_fnc_persistentUAV;
        };
*/
params ["_loiterLocation"];
diag_log "UAV spawning in...";

private _playerGroups = missionNamespace getVariable "playerGroups";
private _loiterPosition = []; // getPos ((units (_playerGroups select 0)) select 0);
private _uavClassName = (friendlyFactionSerialized get "fixedWingISRDrone") select 1;

if (!isNil "_loiterLocation") then {
    _loiterPosition = _loiterLocation;
} else {
    _loiterPosition = getPos ((units (_playerGroups select 0)) select 0);
};

// private _spawnPosition = [10000, 200, 2000];
private _spawnPosition = [18000, 11000, 2000];
private _fuelThreshold = 0.2;

// Spawn UAV with connection
private _uav = createVehicle [_uavClassName, _spawnPosition, [], 0, "FLY"];
createVehicleCrew _uav;
_uav lockCameraTo [_loiterPosition, [0]];
_uav flyInHeight 1250;

// Set initial UAV waypoint to Loiter around player
private _uavGroup = group _uav;
private _uavWp = _uavGroup addWaypoint [_loiterPosition, 0];
_uavWp setWaypointType "LOITER";
_uavWp setWaypointLoiterAltitude 1250;
_uavWp setWaypointLoiterRadius 1250;
_uavWp setWaypointLoiterType "CIRCLE";
RadioQueue pushBack [isrCallsign, format ["%1 on station in 5 minutes.", isrCallsign]];

missionNamespace setVariable ["activeUavGroup", _uavGroup, true];

waitUntil {
    (!alive _uav) || ((fuel _uav) < _fuelThreshold);
};

if (!alive _uav) then
{
    // Add logic to recover drone parts
    RadioQueue pushBack [headquartersCallsign, format ["%1 has been shot down.  It will be at least 30 minutes before we get another drone up.", isrCallsign]];
    sleep 1800
} else {
    _uav move _spawnPosition;
    RadioQueue pushBack [isrCallsign, "We are at bingo fuel.  Going off station now.  We will be back up in 10 minutes."];
    sleep 600;
    deleteVehicle _uav;
};

missionNamespace setVariable ["activeUavGroup", nil, true];

[_loiterPosition] call DJC_fnc_persistentUAV;