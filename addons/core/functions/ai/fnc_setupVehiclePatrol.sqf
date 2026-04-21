#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_setupVehiclePatrol
 * Description:
 *     Spawns a motorized/mechanized patrol group and starts the vehicle patrol
 *     state machine. The vehicle drives along roads, stops to dismount infantry
 *     for local foot patrols, then remounts and repeats.
 *
 *     QRF-capable: set group variable DSC_vehPatrol_qrf to true to interrupt.
 *
 * Arguments:
 *     0: _locationPos <ARRAY> - Patrol center position
 *     1: _groupTemplate <HASHMAP> - Classified group hashmap (MOTORIZED or MECHANIZED)
 *     2: _side <SIDE> - Side to spawn on
 *     3: _config <HASHMAP> - Configuration:
 *        - "patrolRadius": [min, max] driving leg distance (default: [400, 800])
 *        - "dismountRadius": [min, max] foot patrol radius (default: [50, 100])
 *        - "dismountDuration": [min, max] seconds of foot patrol (default: [90, 180])
 *        - "speed": "LIMITED" or "NORMAL" (default: "LIMITED")
 *
 * Return Value:
 *     <HASHMAP>:
 *        "group"    - The spawned group
 *        "vehicle"  - The group's vehicle
 *        "units"    - All units (crew + dismounts)
 *        "scriptHandle" - Handle to the spawned patrol loop
 *
 * Example:
 *     private _vp = [_pos, _mechGroup, east, _config] call DSC_core_fnc_setupVehiclePatrol;
 */

params [
    ["_locationPos", [], [[]]],
    ["_groupTemplate", createHashMap, [createHashMap]],
    ["_side", east, [east]],
    ["_config", createHashMap, [createHashMap]]
];

private _emptyResult = createHashMapFromArray [["group", grpNull], ["vehicle", objNull], ["units", []], ["scriptHandle", scriptNull]];

if (_locationPos isEqualTo []) exitWith {
    diag_log "DSC: fnc_setupVehiclePatrol - No location position provided";
    _emptyResult
};

private _patrolRadius = _config getOrDefault ["patrolRadius", [400, 800]];
private _dismountRadius = _config getOrDefault ["dismountRadius", [50, 100]];
private _dismountDuration = _config getOrDefault ["dismountDuration", [90, 180]];
private _speed = _config getOrDefault ["speed", "LIMITED"];

// ============================================================================
// Spawn group from template
// ============================================================================
private _groupPath = _groupTemplate get "path";
private _groupName = _groupTemplate get "groupName";

private _pathParts = _groupPath splitString "/";
private _groupConfig = configFile >> "CfgGroups";
{ _groupConfig = _groupConfig >> _x } forEach _pathParts;

// Find a road near the location to spawn on
private _spawnPos = _locationPos;
private _nearRoads = _locationPos nearRoads 500;
if (_nearRoads isNotEqualTo []) then {
    // Pick a road at the edge of the patrol area for a natural start
    private _edgeRoads = _nearRoads select {
        private _d = _x distance2D _locationPos;
        _d > 200 && _d < 600
    };
    if (_edgeRoads isNotEqualTo []) then {
        _spawnPos = getPosATL (selectRandom _edgeRoads);
    } else {
        _spawnPos = getPosATL (selectRandom _nearRoads);
    };
};

private _spawnedGroup = [_spawnPos, _side, _groupConfig] call BIS_fnc_spawnGroup;

if (isNull _spawnedGroup) exitWith {
    diag_log format ["DSC: fnc_setupVehiclePatrol - Failed to spawn group %1", _groupName];
    _emptyResult
};

// ============================================================================
// Identify vehicle, crew, and dismounts
// ============================================================================
private _vehicle = objNull;
private _crew = [];
private _dismounts = [];

// Find the vehicle — should be the first vehicle any unit is in
{
    if (!isNull (objectParent _x)) exitWith {
        _vehicle = vehicle _x;
    };
} forEach units _spawnedGroup;

if (isNull _vehicle) exitWith {
    diag_log format ["DSC: fnc_setupVehiclePatrol - Group %1 has no vehicle, aborting", _groupName];
    { deleteVehicle _x } forEach units _spawnedGroup;
    deleteGroup _spawnedGroup;
    _emptyResult
};

// Separate crew from dismounts
{
    if (_x in crew _vehicle) then {
        _crew pushBack _x;
    } else {
        _dismounts pushBack _x;
    };
} forEach units _spawnedGroup;

// Check cargo capacity — trim excess dismounts that won't fit
private _cargoCapacity = _vehicle emptyPositions "cargo";
if (count _dismounts > _cargoCapacity) then {
    private _excess = count _dismounts - _cargoCapacity;
    diag_log format ["DSC: fnc_setupVehiclePatrol - Vehicle has %1 cargo seats but %2 dismounts, removing %3 excess",
        _cargoCapacity, count _dismounts, _excess];
    for "_i" from 1 to _excess do {
        private _unit = _dismounts deleteAt (count _dismounts - 1);
        deleteVehicle _unit;
    };
};

// Need at least 2 dismounts for a meaningful foot patrol
if (count _dismounts < 2) exitWith {
    diag_log format ["DSC: fnc_setupVehiclePatrol - Only %1 dismounts after seat check, aborting", count _dismounts];
    { deleteVehicle _x } forEach units _spawnedGroup;
    deleteVehicle _vehicle;
    deleteGroup _spawnedGroup;
    _emptyResult
};

// Store patrol data on group
_spawnedGroup setVariable ["DSC_vehPatrol_vehicle", _vehicle];
_spawnedGroup setVariable ["DSC_vehPatrol_crew", _crew];
_spawnedGroup setVariable ["DSC_vehPatrol_dismounts", _dismounts];
_spawnedGroup setVariable ["DSC_vehPatrol_state", "DRIVING"];
_spawnedGroup setVariable ["DSC_vehPatrol_qrf", false];
_spawnedGroup setVariable ["DSC_vehPatrol_center", _locationPos];

diag_log format ["DSC: fnc_setupVehiclePatrol - Spawned %1: vehicle %2, crew %3, dismounts %4",
    _groupName, typeOf _vehicle, count _crew, count _dismounts];

// ============================================================================
// Start patrol loop
// ============================================================================
private _scriptHandle = [_spawnedGroup, _locationPos, _patrolRadius, _dismountRadius, _dismountDuration, _speed] spawn DSC_core_fnc_vehiclePatrolLoop;

private _result = createHashMapFromArray [
    ["group", _spawnedGroup],
    ["vehicle", _vehicle],
    ["units", units _spawnedGroup],
    ["scriptHandle", _scriptHandle]
];

_result
