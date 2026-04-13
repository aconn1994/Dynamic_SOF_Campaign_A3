#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_recruitMedic
 * Description:
 *     Spawns an invincible medic unit at the player base and adds to
 *     the player's group. Limited to one medic per player.
 *
 * Arguments:
 *     0: _player <OBJECT> - Player requesting the medic
 *     1: _config <HASHMAP> - Optional configuration
 *        - "medicClass": Unit classname (default: "B_medic_F")
 *        - "spawnObject": Object to spawn near (default: jointOperationCenter)
 *
 * Return Value:
 *     <OBJECT> - The spawned medic unit, or objNull if failed
 *
 * Example:
 *     [player] call DSC_core_fnc_recruitMedic;
 */

params [
    ["_player", objNull, [objNull]],
    ["_config", createHashMap, [createHashMap]]
];

if (isNull _player) exitWith { objNull };

// Check if player already has a medic
private _existingMedic = _player getVariable ["DSC_assignedMedic", objNull];
if (!isNull _existingMedic && alive _existingMedic) exitWith {
    hint "You already have a medic assigned.";
    _existingMedic
};

private _medicClass = _config getOrDefault ["medicClass", "B_medic_F"];
private _spawnObj = _config getOrDefault ["spawnObject", jointOperationCenter];
private _spawnPos = (getPos _spawnObj) getPos [3, random 360];

// Create medic in player's group
private _medic = (group _player) createUnit [_medicClass, _spawnPos, [], 0, "FORM"];
_medic setPos _spawnPos;

// Make invincible (belt and suspenders - allowDamage + HandleDamage EH)
_medic allowDamage false;
_medic addEventHandler ["HandleDamage", { 0 }];

// Tag as medic for identification
_medic setVariable ["DSC_isMedic", true, true];
_medic setVariable ["DSC_assignedPlayer", _player, true];

// Store reference on player
_player setVariable ["DSC_assignedMedic", _medic, true];

// Set custom name
_medic setName "Combat Medic";

diag_log format ["DSC: Medic recruited for %1 at %2", name _player, _spawnPos];
systemChat format ["Combat Medic assigned to %1.", name _player];
hint "Combat Medic recruited and assigned to your squad.";

_medic
