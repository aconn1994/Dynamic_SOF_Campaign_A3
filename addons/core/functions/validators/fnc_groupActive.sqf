/*
 * Group Active Checker
 * 
 * Checks whether a group is "Active" (Alive or non-captives) and returns a boolean
 * 
 * Arguments:
 *   0: Group <OBJECT>
 * 
 * Returns: boolean
 * 
 * Example:
 *   [_unitGroup] call DSC_core_fnc_groupActive
 */
params ["_grp"];

private _grpAlive = false;
{
    if ((alive _x) && !(captive _x)) then {
        _grpAlive = true;
    };
} forEach units _grp;

_grpAlive;
