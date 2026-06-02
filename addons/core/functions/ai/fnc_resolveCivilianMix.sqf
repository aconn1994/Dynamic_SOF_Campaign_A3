#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_resolveCivilianMix
 * Description:
 *     Builds a weighted civilian-resolver-key mix from a location's character
 *     tags + primary functional category. Output feeds the "classMix" config
 *     of fnc_setupCivilians.
 *
 *     Each entry is [resolverKey, weight]:
 *       "civilian"          generic civvy (always seeded as baseline)
 *       "civilian_worker"   blue-collar (industrial/agricultural/port)
 *       "civilian_suit"     formal/business (commercial/religious leaders)
 *       "civilian_labcoat"  medical/scientific (medical/research)
 *
 *     Resolver keys are consumed by fnc_resolveEntityClass which scans the
 *     civilian manPool for keyword-matching classnames; if none match it
 *     falls back to a random civilian, so the mix degrades gracefully on
 *     factions/mods with limited civilian variety.
 *
 *     First-pass tag→mix mapping. Populated areas (cities/towns/settlements)
 *     intentionally lean heavy on baseline civilians with a *sprinkle* of
 *     specialty types from the character tags — the goal is "this town has
 *     factories so I sometimes see a worker," not "this town is 50% workers."
 *     Specialized presence zones (planned: industrial sites, ports, farms)
 *     should call this helper with their own tag set and will naturally
 *     produce specialty-heavy mixes because the baseline ratio dominates
 *     less when the specialty tags are denser.
 *
 *     Extend as new archetypes (e.g. civilian_youth, civilian_dockworker)
 *     come online.
 *
 * Arguments:
 *     0: _tags            <ARRAY>  Location/zone tags (default [])
 *     1: _primaryFunction <STRING> Dominant functional category (default "")
 *
 * Return Value:
 *     <ARRAY> - [[resolverKey, weight], ...]. Always contains at least a
 *               "civilian" entry so the mix is never empty.
 *
 * Example:
 *     private _mix = [_zone get "tags", _zone get "primaryFunction"] call
 *         DSC_core_fnc_resolveCivilianMix;
 *     // _mix: [["civilian", 4], ["civilian_worker", 6]] for industrial_zone
 */

params [
    ["_tags", [], [[]]],
    ["_primaryFunction", "", [""]]
];

// Baseline: every zone gets generic civilians as the dominant background
// presence. Specialty tags only sprinkle (~10-25% per category) so towns
// still read as "normal residents going about their day."
private _mix = [["civilian", 20]];

private _addOrBoost = {
    params ["_key", "_weight"];
    private _idx = _mix findIf { (_x select 0) == _key };
    if (_idx >= 0) then {
        private _entry = _mix select _idx;
        _entry set [1, (_entry select 1) + _weight];
    } else {
        _mix pushBack [_key, _weight];
    };
};

// --- Specialty character tags — sprinkle weights ---
// Each tag adds ~1-3 against the 20-weight baseline (≈5-15% per tag).
// Multiple specialty tags can stack (an industrial port adds both).
if ("industrial_zone"   in _tags) then { ["civilian_worker", 2] call _addOrBoost };
if ("industrial_hub"    in _tags) then { ["civilian_worker", 2] call _addOrBoost };
if ("agricultural_zone" in _tags) then { ["civilian_worker", 2] call _addOrBoost };
if ("port_zone"         in _tags) then { ["civilian_worker", 2] call _addOrBoost };

if ("commercial_hub"    in _tags) then { ["civilian_suit",   2] call _addOrBoost };

if ("medical_zone"      in _tags) then { ["civilian_labcoat", 2] call _addOrBoost };
if ("religious_site"    in _tags) then { ["civilian_suit",    1] call _addOrBoost };

// --- Primary-function reinforcement (very light) ---
// Adds at most +1 on top of the tag sprinkle for the dominant flavor.
switch (_primaryFunction) do {
    case "industrial":   { ["civilian_worker",  1] call _addOrBoost };
    case "agricultural": { ["civilian_worker",  1] call _addOrBoost };
    case "port":         { ["civilian_worker",  1] call _addOrBoost };
    case "commercial":   { ["civilian_suit",    1] call _addOrBoost };
    case "medical":      { ["civilian_labcoat", 1] call _addOrBoost };
    default {};
};

_mix
