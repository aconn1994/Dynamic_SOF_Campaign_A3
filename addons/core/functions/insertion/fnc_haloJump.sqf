#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_haloJump
 * Description:
 *     Initiates a HALO jump for a unit. Teleports to altitude above target position,
 *     swaps backpack for parachute, and restores original gear on landing.
 *
 *     Part of the insertion module - designed to be expanded with other
 *     ingress/egress methods (helo transport, boat insertion, etc.)
 *
 * Arguments:
 *     0: _unit <OBJECT> - Unit to perform HALO jump
 *     1: _targetPos <ARRAY> - [x, y, z] target position on ground
 *     2: _config <HASHMAP> - Optional configuration
 *        - "altitude": Jump altitude in meters (default: 2000)
 *        - "offset": Lateral offset per unit index for group jumps (default: 6)
 *
 * Return Value:
 *     None
 *
 * Example:
 *     [player, getPos player] call DSC_core_fnc_haloJump;
 */

params [
    ["_unit", objNull, [objNull]],
    ["_targetPos", [], [[]]],
    ["_config", createHashMap, [createHashMap]]
];

if (isNull _unit || _targetPos isEqualTo []) exitWith {
    diag_log "DSC: fnc_haloJump - Invalid parameters";
};

private _altitude = _config getOrDefault ["altitude", 2000];

private _startPosition = [_targetPos select 0, _targetPos select 1, (_targetPos select 2) + _altitude];
_unit setPos _startPosition;

// Store and swap backpack
private _originalBackpackClass = "";
private _originalBackpackItems = [];
private _backpack = backpack _unit;

if (count _backpack > 0) then {
    _originalBackpackClass = _backpack call BIS_fnc_basicBackpack;
    _originalBackpackItems = backpackItems _unit;
    removeBackpack _unit;
};

_unit addBackpack "B_Parachute";
_unit allowDamage false;
_unit disableAI "ANIM";

if (count _originalBackpackClass > 0) then {
    waitUntil { isNull (objectParent _unit) };

    private _backpackDummy = _originalBackpackClass createVehicle position _unit;
    private _backpackHolder = objectParent _backpackDummy;
    _backpackHolder attachTo [_unit, [-0.1, 0, -0.7], "Pelvis"];
    _backpackHolder setVectorDirAndUp [[0, -1, 0], [0, 0, -1]];

    waitUntil { !isNull (objectParent _unit) };

    deleteVehicle _backpackDummy;
    deleteVehicle _backpackHolder;

    _backpackDummy = _originalBackpackClass createVehicle position _unit;
    _backpackHolder = objectParent _backpackDummy;
    _backpackHolder attachTo [vehicle _unit, [-0.1, 0.7, 0]];
    _backpackHolder setVectorDirAndUp [[0, 0, -1], [0, 1, 0]];

    _unit allowDamage true;
    _unit enableAI "ANIM";

    waitUntil { isNull (objectParent _unit) };

    deleteVehicle _backpackDummy;
    deleteVehicle _backpackHolder;

    removeBackpack _unit;
    _unit addBackpackGlobal _originalBackpackClass;
    { _unit addItemToBackpack _x } forEach _originalBackpackItems;
} else {
    waitUntil { isNull (objectParent _unit) };

    _unit allowDamage true;
    _unit enableAI "ANIM";

    waitUntil { !isNull (objectParent _unit) };
    waitUntil { isNull (objectParent _unit) };
};
