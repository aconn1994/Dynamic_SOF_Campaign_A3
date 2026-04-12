#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_spawnTransportHelo
 * Description:
 *     Spawns a transport helicopter at a position with crew.
 *     Helicopter is invincible by default (utility transport, not combat).
 *
 * Arguments:
 *     0: _spawnPos <ARRAY> - [x, y, z] spawn position
 *     1: _config <HASHMAP> - Optional configuration
 *        - "vehicleClass": Helicopter classname (default: "B_Heli_Transport_03_F" - Chinook)
 *        - "side": Side for crew (default: west)
 *        - "altitude": Spawn altitude AGL (default: 200)
 *        - "invincible": Make vehicle and crew invincible (default: true)
 *
 * Return Value:
 *     <HASHMAP> - Keys: "vehicle", "group", "crew"
 *
 * Example:
 *     private _helo = [_spawnPos] call DSC_core_fnc_spawnTransportHelo;
 */

params [
    ["_spawnPos", [], [[]]],
    ["_config", createHashMap, [createHashMap]]
];

private _vehicleClass = _config getOrDefault ["vehicleClass", "B_Heli_Transport_03_F"];
private _side = _config getOrDefault ["side", west];
private _altitude = _config getOrDefault ["altitude", 200];
private _invincible = _config getOrDefault ["invincible", true];

private _spawnPosAir = [_spawnPos select 0, _spawnPos select 1, _altitude];

private _heloArray = [_spawnPosAir, 0, _vehicleClass, _side] call BIS_fnc_spawnVehicle;
private _vehicle = _heloArray select 0;
private _crew = _heloArray select 1;
private _group = _heloArray select 2;

_vehicle setPos _spawnPosAir;
_vehicle flyInHeight _altitude;

if (_invincible) then {
    _vehicle allowDamage false;
    { _x allowDamage false } forEach _crew;
};

// Crew should not dismount
{ _x disableAI "AUTOCOMBAT"; _x setBehaviour "CARELESS" } forEach _crew;
_group setCombatMode "BLUE";

diag_log format ["DSC: Spawned transport helo %1 at %2", _vehicleClass, _spawnPosAir];

createHashMapFromArray [
    ["vehicle", _vehicle],
    ["group", _group],
    ["crew", _crew]
]
