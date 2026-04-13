#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_simulateFastTravel
 * Description:
 *     Simulates fast travel for a helicopter transport. Fades screen out,
 *     teleports vehicle to approach position near destination, fades back in.
 *     Called on a specific player's machine.
 *
 * Arguments:
 *     0: _vehicle <OBJECT> - The helicopter
 *     1: _destinationPos <ARRAY> - Final destination [x, y, z]
 *     2: _config <HASHMAP> - Optional configuration
 *        - "approachDistance": Distance from destination to reappear (default: 1000)
 *        - "fadeTime": Fade duration in seconds (default: 2)
 *        - "altitude": Flight altitude (default: 150)
 *
 * Return Value:
 *     None (blocks until teleport complete)
 *
 * Example:
 *     [_helo, _destPos] call DSC_core_fnc_simulateFastTravel;
 */

params [
    ["_vehicle", objNull, [objNull]],
    ["_destinationPos", [], [[]]],
    ["_config", createHashMap, [createHashMap]]
];

if (isNull _vehicle || _destinationPos isEqualTo []) exitWith {};

private _approachDistance = _config getOrDefault ["approachDistance", 2500];
private _fadeTime = _config getOrDefault ["fadeTime", 2];
private _altitude = _config getOrDefault ["altitude", 150];

// Calculate approach position (come from current direction toward destination)
private _vehiclePos = getPos _vehicle;
private _dirToDestination = _vehiclePos getDir _destinationPos;
private _approachPos = _destinationPos getPos [_approachDistance, _dirToDestination + 180];
_approachPos set [2, _altitude];

// Fade out
titleText ["", "BLACK OUT", _fadeTime];
sleep _fadeTime;

// Teleport while blacked out
_vehicle setPos _approachPos;
_vehicle setDir _dirToDestination;
_vehicle flyInHeight _altitude;
_vehicle setVelocityModelSpace [0, 60, 0];

// Hold black screen while helicopter gets up to speed
sleep 4;

// Fade in while moving
titleText ["", "BLACK IN", _fadeTime];
sleep _fadeTime;

diag_log format ["DSC: Fast travel complete - vehicle at %1, heading to %2", _approachPos, _destinationPos];
