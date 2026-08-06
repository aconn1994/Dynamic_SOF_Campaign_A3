#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_c2RaiseAlert
 * Description:
 *     Sprint F.1 — the single entry point for raising a node's alert state.
 *
 *     F.1 does not call this on its own; the network is log-only until F.2
 *     wires up signals. It exists now for two reasons: it is the contract
 *     F.2 will build against, and it lets the alert ladder + decay be
 *     exercised and validated by hand from the debug console before any
 *     signal source is trusted to drive it.
 *
 *     Alerts only ever RATCHET UP. A node already at RED is not calmed by
 *     a fresh AMBER-grade signal; the lower signal is absorbed and the
 *     decay clock is left alone. Alerts come down exclusively through the
 *     decay ladder on the tick, so a hot area cools on its own schedule
 *     rather than being reset by unrelated noise.
 *
 *     Same-level re-raise refreshes the decay clock. Sustained contact
 *     therefore holds a node at its current level indefinitely, which is
 *     what makes a long firefight keep an area angry.
 *
 *     Records last-known-position when supplied. This is deliberately NOT
 *     the player's live position — it is where the REPORT came from. F.3
 *     responses move to the LKP and search outward from there, and the
 *     confidence value decays so a stale report produces a wider, lazier,
 *     less accurate search.
 *
 * Arguments:
 *     0: _nodeId     <STRING> - target node id
 *     1: _level      <STRING> - "AMBER" | "RED" | "BLACK"
 *     2: _source     <STRING> - what raised it (for feed/debug provenance)
 *     3: _lkpPos     <ARRAY>  - optional last-known-position
 *     4: _confidence <NUMBER> - 0..1 LKP confidence (default 1.0)
 *
 * Return Value:
 *     <BOOL> - true if the node's state actually changed
 *
 * Example:
 *     ["Kavala", "RED", "CONTACT_REPORT", _pos, 0.9] call DSC_core_fnc_c2RaiseAlert;
 */

params [
    ["_nodeId",     "",  [""]],
    ["_level",      "AMBER", [""]],
    ["_source",     "manual", [""]],
    ["_lkpPos",     [], [[]]],
    ["_confidence", 1.0, [0]],
    ["_allowRefresh", true, [true]]
];

if (_nodeId isEqualTo "") exitWith { false };

private _nodes = missionNamespace getVariable ["DSC_c2Nodes", createHashMap];
private _node = _nodes getOrDefault [_nodeId, createHashMap];
if (_node isEqualTo createHashMap) exitWith {
    LOG_1("c2RaiseAlert - unknown node '%1'",_nodeId);
    false
};

private _arch = [] call DSC_core_fnc_getC2Archetypes;
private _rank = _arch get "alertRank";

private _current = _node get "alert";
private _curRank = _rank getOrDefault [_current, 0];
private _newRank = _rank getOrDefault [_level, 0];

// Record LKP regardless of whether the level changes — even an absorbed
// lower-grade signal still tells the node roughly where the trouble is.
if (_lkpPos isNotEqualTo []) then {
    _node set ["lkp", createHashMapFromArray [
        ["position",   _lkpPos],
        ["time",       serverTime],
        ["confidence", _confidence],
        ["source",     _source]
    ]];
};

private _cs = _node get "callsign";

if (_newRank < _curRank) exitWith {
    LOG_3("c2 alert absorbed [%1] %2 signal below current %3",_cs,_level,_current);
    false
};

private _changed = _newRank > _curRank;

// A same-level repeat only restarts the decay clock when the caller says it
// represents a fresh live event. Accountability signals pass false: a wave of
// overdue patrols must not keep re-arming the timer, or the node stays alerted
// forever and the alert state stops meaning anything.
// A same-level repeat only restarts the decay clock when the caller says it
// represents a fresh live event. Accountability signals pass false: a wave of
// overdue patrols must not keep re-arming the timer, or the node stays alerted
// forever and the alert state stops meaning anything.
if (_changed || _allowRefresh) then {
    _node set ["alertSince", serverTime];
};

// Decision timer is cleared ONLY on a real escalation, never on refresh.
//
// Originally this was cleared alongside alertSince, which meant sustained
// contact re-rolled the delay on every incoming report and the node could
// never finish deciding — a playtest showed a node sitting at RED for four
// and a half minutes, logging "still deciding (5s of 119s)" then
// "(3s of 90s)" then "(1s of 74s)" as each fresh report reset it. The whole
// point of latency is that it elapses; it must be immune to the events that
// keep the node hot.
if (_changed) then {
    _node set ["responseDueAt", -1];
};

_node set ["alert", _level];
_node set ["alertSource", _source];

// Campaign memory. Written now, deliberately unread in v1 — turning it on
// later interacts with fnc_updateInfluence, since both model "this region
// has been fought over," and they must not double-count.
private _heat = _node getOrDefault ["heat", 0];
_node set ["heat", (_heat + (_newRank * 0.05)) min 1];

private _stats = missionNamespace getVariable ["DSC_c2Stats", createHashMap];
_stats set ["alertsRaised", (_stats getOrDefault ["alertsRaised", 0]) + 1];

if (_changed) then {
    INFO_4("c2 ALERT [%1] %2 -> %3 (source: %4)",_cs,_current,_level,_source);

    // F.4 telegraph — a node reaching RED means it has CONFIRMED contact, which
    // is the moment the player most needs to know it. Fires an illum flare over
    // the position at night, so "they know I'm here" is legible with no ISR
    // assets and no UI. Only on the transition, never on a refresh: a node
    // holding RED through a long firefight must not keep launching flares.
    if (_level isEqualTo "RED") then {
        private _telePos = _node getOrDefault ["position", []];
        ["ALERT_RED", _telePos] call DSC_core_fnc_c2Telegraph;
    };

    #ifdef DEBUG_MODE_FULL
    private _stateColor = createHashMapFromArray [
        ["GREEN", "ColorGrey"],
        ["AMBER", "ColorYellow"],
        ["RED",   "ColorRed"],
        ["BLACK", "ColorBlack"]
    ];
    private _mName = format ["dsc_c2_%1", _nodeId];
    private _col = _stateColor getOrDefault [_level, "ColorGrey"];
    _mName setMarkerColorLocal _col;
    #endif
} else {
    private _held = ["absorbed (clock untouched)", "refreshed"] select _allowRefresh;
    LOG_3("c2 alert %1 [%2] holding %3",_held,_cs,_level);
};

_changed
