#include "script_component.hpp"
/*
 * Function: DSC_core_fnc_diagSideDump
 * Description:
 *     TEMPORARY DIAGNOSTIC — August 2026. Remove once the faction/side
 *     overhaul (Plan A) is complete.
 *
 *     Dumps the ACTUAL runtime side state of spawned units, rather than the
 *     side our code believed it asked for. Three sessions were spent inferring
 *     the cause of same-faction fratricide from spawn-time log lines; those
 *     lines only ever recorded our *intent*. This records what the engine
 *     actually did.
 *
 *     Questions this answers definitively:
 *
 *       1. Is `side _unit` the side we asked for?
 *          If not, a spawn path is overriding it, or createGroup received the
 *          wrong value.
 *
 *       2. Does `side _unit` become ENEMY (sideEnemy) over time?
 *          sideEnemy IS the renegade state — hostile to everything INCLUDING
 *          other renegades. It is the only engine state that produces a
 *          genuine free-for-all among units of a single faction.
 *
 *       3. Does `rating` drift negative?
 *          Below roughly -2000 triggers the renegade flip. If rating stays
 *          high and the free-for-all still happens, renegade is RULED OUT and
 *          the cause must be side mismatch.
 *
 *       4. Are all objective defenders actually on ONE side?
 *          A side histogram makes a split instantly visible. Same-side units
 *          cannot fight in Arma.
 *
 *       5. What does the LIVE diplomacy matrix say?
 *          mission.sqm sets independent allegiance (confirmed: independent is
 *          friendly to BLUFOR there) and we ALSO call setFriend at runtime in
 *          fnc_initPresenceManager. Dumping getFriend shows which won.
 *
 *       6. Does the unit's CLASS native side match the side it spawned on?
 *          Exposes exactly where the two-layer override model fights itself.
 *
 *     Sampling runs at T+0, T+45, T+75 and T+120 so rating drift and side
 *     flips are visible across the window in which the free-for-all develops.
 *     A T+0-only dump would miss the renegade transition entirely — which is
 *     precisely why earlier log-reading failed.
 *
 *     Output is via raw `diag_log` with a `DSCDIAG` prefix rather than the CBA
 *     macros, deliberately: this must appear regardless of the configured
 *     debug tier, and `DSCDIAG` greps cleanly out of a noisy RPT.
 *
 * Arguments:
 *     0: _label  <STRING> - context tag ("missionAO", "garrison", ...)
 *     1: _units  <ARRAY>  - units to sample
 *     2: _expect <SIDE>   - the side the calling code BELIEVES it requested
 *
 * Return Value:
 *     None
 *
 * Example:
 *     ["missionAO", _allUnits, _targetSide] call DSC_core_fnc_diagSideDump;
 */

params [
    ["_label",  "?",   [""]],
    ["_units",  [],    [[]]],
    ["_expect", sideUnknown, [sideUnknown]]
];

if (_units isEqualTo []) exitWith {
    diag_log format ["DSCDIAG [%1] no units to sample", _label];
};

diag_log format ["DSCDIAG ================ %1 (%2 units) ================", _label, count _units];

// ============================================================================
// Diplomacy matrix
// ============================================================================
// setFriend is DIRECTIONAL, so every pair is printed both ways. A pair that
// disagrees with itself is a bug on its own and is invisible unless both
// directions are read. This is also where a mission.sqm-vs-runtime conflict
// becomes visible.
private _pairs = [
    ["west",  west,        "east", east],
    ["west",  west,        "indep", independent],
    ["east",  east,        "indep", independent],
    ["west",  west,        "civ",  civilian],
    ["east",  east,        "civ",  civilian],
    ["indep", independent, "civ",  civilian]
];
{
    _x params ["_aName", "_aSide", "_bName", "_bSide"];
    private _ab = _aSide getFriend _bSide;
    private _ba = _bSide getFriend _aSide;
    private _flag = ["", "  <== ASYMMETRIC"] select (_ab != _ba);
    diag_log format [
        "DSCDIAG [%1] DIPLOMACY  %2->%3 = %4   %3->%2 = %5%6",
        _label, _aName, _bName, _ab, _ba, _flag
    ];
} forEach _pairs;

// ============================================================================
// Faction role side table — what DSC_factionData actually holds
// ============================================================================
// Confirms whether the normalization pass in fnc_initServer produced what we
// think. Also catches the `"side"` key TYPE COLLISION: fnc_extractGroups writes
// a NUMBER under "side" on group hashmaps, while fnc_initFactionData writes a
// SIDE object under "side" on role hashmaps. typeName makes that obvious.
private _fd = missionNamespace getVariable ["DSC_factionData", createHashMap];
{
    private _roleKey  = _x;
    private _roleData = _y;
    private _rSide    = _roleData getOrDefault ["side", "MISSING"];
    private _rFacs    = _roleData getOrDefault ["factions", []];
    diag_log format [
        "DSCDIAG [%1] ROLE %2  side=%3 (type=%4)  factions=%5",
        _label, _roleKey, _rSide, typeName _rSide, _rFacs
    ];
} forEach _fd;

// ============================================================================
// Samples
// ============================================================================
[_label, _units, _expect, "T+0"] call DSC_core_fnc_diagSideSample;

// Delayed samples — rating drift and renegade flips only appear over time.
// Cumulative elapsed time is tracked so the tag reads T+45 / T+75 / T+120
// rather than repeating the per-step sleep value.
[_label, _units, _expect] spawn {
    params ["_lbl", "_u", "_e"];
    private _elapsed = 0;
    {
        uiSleep _x;
        _elapsed = _elapsed + _x;
        [_lbl, _u, _e, format ["T+%1", _elapsed]] call DSC_core_fnc_diagSideSample;
    } forEach [45, 30, 45];
};
