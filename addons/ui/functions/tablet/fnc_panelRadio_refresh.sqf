#include "..\..\script_component.hpp"
#include "..\..\dialog\idc.hpp"
/*
 * Function: DSC_ui_fnc_panelRadio_refresh
 * Description:
 *     C2 Sprint F.4 — repaints the Radio Feed list, the coverage header and
 *     the alerted-node strip.
 *
 *     COVERAGE IS APPLIED AT READ TIME
 *
 *     `DSC_c2Feed` deliberately contains everything the enemy network said,
 *     including lines the player never earned. Filtering here (rather than at
 *     write time) lets one buffer serve both the honest player view and an
 *     omniscient debug view, and means the gating rule lives in one place that
 *     is easy to reason about.
 *
 *     LOST lines are the important case: a transmission that never arrived is
 *     precisely the information the player should not have, because "did they
 *     get a report out before we killed them?" is the central tension of the
 *     whole report-timer mechanic. Showing it would hand the player the answer.
 *
 * Arguments:
 *     0: _display <DISPLAY> - tablet display
 */

params [["_display", displayNull, [displayNull]]];
if (isNull _display) exitWith {};

private _list = _display displayCtrl DSC_TABLET_IDC_RADIO_LIST;
if (isNull _list) exitWith {};

private _showAll = _display getVariable ["DSC_radioShowAll", false];

// ============================================================================
// Coverage header
// ============================================================================
// Reported at the player's own position. This is an honest summary of the
// player's CURRENT capability rather than a per-line breakdown, so the reason
// the feed is quiet is always visible.
([getPosASL player] call DSC_core_fnc_c2IsrCoverage) params ["_tier", "_tierName", "_why"];

private _covCtrl = _display displayCtrl DSC_TABLET_IDC_RADIO_COVERAGE;
if (!isNull _covCtrl) then {
    private _uav = missionNamespace getVariable ["DSC_activeUAV", objNull];
    private _uavState = if (isNull _uav) then {
        "no drone"
    } else {
        ["drone lost", "drone on station"] select (alive _uav)
    };
    _covCtrl ctrlSetText format ["COVERAGE: %1 (%2)  |  %3", _tierName, _why, _uavState];

    // Amber when the player has no meaningful coverage — a quiet feed with no
    // explanation is the single most confusing state this page can be in.
    private _col = [[0.85, 0.65, 0.20, 1], [0.55, 0.62, 0.66, 1]] select (_tier > 0);
    _covCtrl ctrlSetTextColor _col;
};

// ============================================================================
// Feed list
// ============================================================================
lbClear _list;

private _feed = missionNamespace getVariable ["DSC_c2Feed", []];
private _nodes = missionNamespace getVariable ["DSC_c2Nodes", createHashMap];

private _sourceColor = createHashMapFromArray [
    ["INTERCEPT", [0.85, 0.85, 0.85, 1.00]],   // enemy talking — neutral white
    ["ISR",       [0.30, 0.80, 0.95, 1.00]],   // your operator — accent cyan
    ["COMMAND",   [0.95, 0.55, 0.25, 1.00]],   // enemy orders — orange, the
                                               //   lines that predict violence
    ["PARTNER",   [0.45, 0.85, 0.45, 1.00]],   // friendly forces — green
    ["LOST",      [0.45, 0.35, 0.35, 1.00]]    // debug-only — deliberately dim
];

private _shown = 0;
private _withheld = 0;

{
    private _entry  = _x;
    private _source = _entry getOrDefault ["source", "INTERCEPT"];
    private _text   = _entry getOrDefault ["text", ""];
    private _stamp  = _entry getOrDefault ["stamp", ""];
    private _from   = _entry getOrDefault ["from", ""];
    private _to     = _entry getOrDefault ["to", ""];
    private _nodeId = _entry getOrDefault ["nodeId", ""];

    private _visible = true;

    if (!_showAll) then {
        // LOST never reaches the player view — see header.
        if (_source isEqualTo "LOST") then { _visible = false };

        // Coverage gate via the SHARED resolver, so this scrollback and the
        // live systemChat surface can never disagree about what was earned.
        // Best-of {event position, node LKP, node position} — see
        // fnc_c2IsrEntryTier for why node-only was wrong.
        if (_visible) then {
            ([_entry] call DSC_core_fnc_c2IsrEntryTier) params ["_tier", "_reqRank"];
            if (_tier < _reqRank) then { _visible = false };
        };
    };

    if (_visible) then {
        private _line = if (_from != "" && {_to != ""}) then {
            format ["[%1]  %2  %3 >> %4   %5", _stamp, _source, _from, _to, _text]
        } else {
            format ["[%1]  %2   %3", _stamp, _source, _text]
        };

        private _idx = _list lbAdd _line;
        _list lbSetColor [_idx, _sourceColor getOrDefault [_source, [0.85, 0.85, 0.85, 1]]];

        // Stash the node id so a future click handler can slew the BFT map to
        // the originating installation.
        _list lbSetData [_idx, _nodeId];

        _shown = _shown + 1;
    } else {
        _withheld = _withheld + 1;
    };
} forEach _feed;

if (_shown == 0) then {
    private _msg = if (_withheld > 0) then {
        format ["-- no intercepts at current coverage (%1 lines withheld) --", _withheld]
    } else {
        "-- no traffic intercepted --"
    };
    private _idx = _list lbAdd _msg;
    _list lbSetColor [_idx, [0.45, 0.50, 0.55, 1]];
};

// Auto-scroll to the newest line. A scrollback that opens at the top of a
// 200-entry history and requires manual scrolling to reach the useful end is
// worse than no scrollback.
if (_shown > 0) then {
    _list lbSetCurSel (_shown - 1);
};

// ============================================================================
// Alerted node strip
// ============================================================================
// "Who is hot right now" is the actionable counterpart to the transcript.
// Only nodes above GREEN are listed — a full roster would be 30+ entries of
// mostly nothing.
private _nodesCtrl = _display displayCtrl DSC_TABLET_IDC_RADIO_NODES;
if (!isNull _nodesCtrl) then {
    private _hot = [];
    {
        private _n = _y;
        private _alert = _n getOrDefault ["alert", "GREEN"];
        if (_alert != "GREEN") then {
            private _nPos = _n getOrDefault ["position", []];
            // Parens around the whole distance2D call are REQUIRED. Binary
            // operators like distance2D bind LOOSER than arithmetic in SQF, so
            //     (getPosASL player) distance2D _nPos / 100
            // parses as
            //     (getPosASL player) distance2D (_nPos / 100)
            // which divides a position ARRAY by a number and throws
            // "Error /: Type Array, expected Number" every refresh.
            private _dist = if (_nPos isEqualTo []) then { -1 } else {
                round (((getPosASL player) distance2D _nPos) / 100) / 10
            };
            private _cs = _n getOrDefault ["callsign", "?"];
            _hot pushBack format ["%1 %2 (%3km)", _cs, _alert, _dist];
        };
    } forEach _nodes;

    if (_hot isEqualTo []) then {
        _nodesCtrl ctrlSetText "NETWORK STATUS: all quiet";
        _nodesCtrl ctrlSetTextColor [0.45, 0.70, 0.45, 1];
    } else {
        _hot = _hot select [0, 8];
        _nodesCtrl ctrlSetText format ["ALERTED: %1", _hot joinString "   "];
        _nodesCtrl ctrlSetTextColor [0.90, 0.60, 0.25, 1];
    };
};
