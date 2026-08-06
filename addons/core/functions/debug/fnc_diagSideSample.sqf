#include "script_component.hpp"
/*
 * Function: DSC_core_fnc_diagSideSample
 * Description:
 *     TEMPORARY DIAGNOSTIC — August 2026. Remove with fnc_diagSideDump once
 *     the faction/side overhaul (Plan A) is complete.
 *
 *     One sampling pass over a set of units, dumping the ACTUAL engine side
 *     state rather than what the spawning code believed it requested.
 *
 *     Split out from fnc_diagSideDump so the delayed samples can call it from
 *     a spawned scope (a local `_fnc_` closure is not reachable across spawn).
 *
 * Arguments:
 *     0: _label      <STRING> - context tag
 *     1: _units      <ARRAY>  - units to sample
 *     2: _expectSide <SIDE>   - side the calling code believed it requested
 *     3: _tag        <STRING> - sample label ("T+0", "T+45", ...)
 *
 * Return Value:
 *     None
 */

params [
    ["_label",      "?", [""]],
    ["_units",      [],  [[]]],
    ["_expectSide", sideUnknown, [sideUnknown]],
    ["_tag",        "T+?", [""]]
];

private _alive = _units select { !isNull _x && { alive _x } };
if (_alive isEqualTo []) exitWith {
    diag_log format ["DSCDIAG [%1] %2 - all sampled units dead/null", _label, _tag];
};

private _sideHist    = createHashMap;
private _factionHist = createHashMap;
private _mismatched  = 0;
private _renegade    = 0;
private _lowRating   = 0;

{
    private _u      = _x;
    private _uSide  = side _u;
    private _gSide  = side (group _u);
    private _cls    = typeOf _u;
    private _rating = rating _u;

    // Native side of the CLASS per config — independent of the group it was
    // forced into. An I_C_Soldier_Bandit_F (native GUER) in an east group is
    // functionally east but cosmetically independent; this exposes that.
    private _nativeFaction  = getText (configFile >> "CfgVehicles" >> _cls >> "faction");
    private _nativeSideNum  = getNumber (configFile >> "CfgFactionClasses" >> _nativeFaction >> "side");
    private _nativeSideName = switch (_nativeSideNum) do {
        case 0: { "EAST" };
        case 1: { "WEST" };
        case 2: { "GUER" };
        case 3: { "CIV"  };
        default { "?"    };
    };

    private _sideKey = str _uSide;
    _sideHist    set [_sideKey, (_sideHist getOrDefault [_sideKey, 0]) + 1];
    _factionHist set [_nativeFaction, (_factionHist getOrDefault [_nativeFaction, 0]) + 1];

    private _flags = "";
    // `setCaptive true` makes the engine report `side _unit` as CIVILIAN
    // regardless of the unit's group. Hostages and surrendered HVTs are
    // therefore expected to read side=CIV with grpSide=EAST — that is the
    // captive system working, not a spawn bug. Suppress the mismatch flags for
    // captives so they don't look like the createUnit side-inheritance defect.
    private _isCaptive = captive _u;

    if (!_isCaptive && {_uSide isNotEqualTo _expectSide}) then {
        _flags = _flags + " SIDE!=EXPECTED";
        _mismatched = _mismatched + 1;
    };
    if (!_isCaptive && {_uSide isNotEqualTo _gSide}) then {
        _flags = _flags + " UNIT!=GROUPSIDE";
    };
    if (_isCaptive) then {
        _flags = _flags + " (captive - side reads CIV by design)";
    };
    // sideEnemy IS the renegade state — hostile to everything including other
    // renegades. This is the only engine state that yields a true free-for-all.
    if (_uSide isEqualTo sideEnemy) then {
        _flags = _flags + " *** RENEGADE ***";
        _renegade = _renegade + 1;
    };
    if (_rating < 0) then {
        _flags = _flags + " NEGRATING";
        _lowRating = _lowRating + 1;
    };
    if (_nativeSideName != str _uSide) then {
        _flags = _flags + format [" NATIVE=%1", _nativeSideName];
    };

    diag_log format [
        "DSCDIAG [%1] %2  side=%3 grpSide=%4 rating=%5 cls=%6 nativeFac=%7 grp=%8 capt=%9%10",
        _label, _tag, _uSide, _gSide, round _rating, _cls, _nativeFaction,
        groupId (group _u), captive _u, _flags
    ];
} forEach _alive;

diag_log format [
    "DSCDIAG [%1] %2 SUMMARY  alive=%3 expected=%4 | sides=%5 | factions=%6 | mismatched=%7 renegade=%8 negRating=%9",
    _label, _tag, count _alive, _expectSide,
    _sideHist, _factionHist, _mismatched, _renegade, _lowRating
];

// ============================================================================
// Hostility matrix across the sampled set
// ============================================================================
// Every distinct side pair present is checked. If the histogram shows a single
// side and nothing is hostile, then any observed fighting CANNOT be diplomacy
// or side allocation — it must be renegade or a scripted engagement. That is
// the fact that ends the guessing.
private _sidesPresent = [];
{
    private _s = side _x;
    if !(_s in _sidesPresent) then { _sidesPresent pushBack _s };
} forEach _alive;

diag_log format ["DSCDIAG [%1] %2 SIDES-PRESENT %3", _label, _tag, _sidesPresent];

if (count _sidesPresent > 1) then {
    {
        private _a = _x;
        {
            private _b = _x;
            if (_a isNotEqualTo _b) then {
                private _f = _a getFriend _b;
                private _verdict = ["HOSTILE", "friendly"] select (_f >= 0.6);
                diag_log format [
                    "DSCDIAG [%1] %2 CROSS-SIDE  %3 -> %4 friend=%5 %6",
                    _label, _tag, _a, _b, _f, _verdict
                ];
            };
        } forEach _sidesPresent;
    } forEach _sidesPresent;
} else {
    diag_log format [
        "DSCDIAG [%1] %2 SINGLE-SIDE (%3) — any fighting here is RENEGADE or scripted, not diplomacy",
        _label, _tag, _sidesPresent select 0
    ];
};
