#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_applySkillProfile
 * Description:
 *     Applies a skill profile to a unit or array of units.
 *     Adds slight randomization per unit so not every AI feels identical.
 *
 *     Also installs renegade protection — see the rating block below. This
 *     function is the single code path every spawned AI combat unit passes
 *     through (garrison, guards, statics, anchored guard/patrol, mortar, QRF,
 *     and all mission AO units via fnc_generateMission), which makes it the
 *     correct place for a blanket safety property.
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

    // ========================================================================
    // Renegade protection — stops "same faction AI killing each other"
    // ========================================================================
    // Arma tracks a per-unit `rating`. Killing a friendly applies a large
    // negative penalty, and once a unit's rating falls below roughly -2000 the
    // engine flips it to RENEGADE: hostile to every side including its own.
    //
    // DSC hits this constantly because of how defenders are structured.
    // `fnc_setupGarrison` gives every garrison unit its OWN group (2 units ->
    // 2 groups, 3 units -> 3 groups in the RPT), and then packs them onto
    // `buildingPos` slots inside the same small building. Arma's AI only
    // deconflicts line of fire WITHIN a group, so these units freely shoot
    // through and past each other at the player.
    //
    // The result is a cascade, not an isolated incident:
    //   friendly-fire hit -> rating drops -> unit flips renegade ->
    //   it now deliberately engages its own faction -> more friendly kills ->
    //   more renegades. A compound tears itself apart with no player
    //   involvement, and every one of those deaths fires real C2 signals,
    //   which is what made the network impossible to test.
    //
    // Symptom signature: defenders of a single faction (all correctly on
    // `east`, zero side realignments logged) fighting each other on the
    // objective. Side resolution is NOT the cause here — this is the rating
    // system, and it looks identical from the outside.
    //
    // A large positive buffer makes the threshold unreachable. This does not
    // change targeting, accuracy or behaviour; it only prevents the flip.
    //
    // NOTE: the real root cause is one-group-per-unit garrisons. Merging them
    // needs `disableAI "PATH"` + `setUnitPos` on every unit first, or they
    // form up on their leader and abandon their firing positions. That belongs
    // in the mission/AI overhaul, not here.
    _unit addRating 1000000;
} forEach _units;

