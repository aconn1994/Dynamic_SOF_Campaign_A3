#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_applySkillProfile
 * Description:
 *     Applies a skill profile to a unit or array of units.
 *     Adds slight randomization per unit so not every AI feels identical.
 *
 * Arguments:
 *     0: _units <OBJECT or ARRAY> - Unit(s) to apply profile to
 *     1: _profileName <STRING> - "moderate", "hard", or "realism"
 *     2: _variance <NUMBER> - Random variance applied to each skill (default: 0.05)
 *
 * Return Value:
 *     None
 *
 * Examples:
 *     [_unit, "hard"] call DSC_core_fnc_applySkillProfile;
 *     [_aoUnits, "realism", 0.1] call DSC_core_fnc_applySkillProfile;
 */

params [
    ["_units", [], [[], objNull]],
    ["_profileName", "moderate", [""]],
    ["_variance", 0.05, [0]]
];

// Handle single unit
if (_units isEqualType objNull) then {
    _units = [_units];
};

private _profile = [_profileName] call DSC_core_fnc_getSkillProfile;

{
    private _unit = _x;
    {
        private _baseValue = _y;
        private _finalValue = (_baseValue + (random _variance) - (_variance / 2)) max 0 min 1;
        _unit setSkill [_x, _finalValue];
    } forEach _profile;
} forEach _units;
