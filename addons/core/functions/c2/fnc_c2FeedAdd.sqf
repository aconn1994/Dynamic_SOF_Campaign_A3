#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_c2FeedAdd
 * Description:
 *     Sprint F.2 — writes one line into the radio feed ring buffer.
 *
 *     The feed is the raw material for the Commander's Tablet Radio Feed
 *     page (F.4). It is populated now, during F.2, because propagation is
 *     what actually generates chatter — building the data in the same pass
 *     that generates it means F.4 is a pure presentation task with nothing
 *     left to reverse-engineer.
 *
 *     Populating it early also makes F.2 verifiable by hand: dumping the
 *     feed after an engagement shows the whole conversation the enemy had
 *     about you, including the parts that never arrived.
 *
 *     Entries are NOT filtered by player ISR coverage here. Coverage gating
 *     happens at read time in F.4 so the same buffer can serve an omniscient
 *     debug view and a coverage-limited player view without being written
 *     twice. `grade` carries the fidelity tier the line would be earned at.
 *
 * Arguments:
 *     0: _source   <STRING> - "INTERCEPT" | "ISR" | "PARTNER" | "COMMAND" | "LOST"
 *     1: _from     <STRING> - originating callsign ("" if unknown)
 *     2: _to       <STRING> - receiving callsign
 *     3: _text     <STRING> - the message
 *     4: _nodeId   <STRING> - node for map cross-reference
 *     5: _grade    <STRING> - ISR fidelity tier required (default "BASIC")
 *     6: _eventPos <ARRAY>  - world position the message is ABOUT (default [])
 *
 *        _eventPos exists because ISR coverage is positional and the node is
 *        usually NOT where the interesting thing happened. A firefight 200 m
 *        from the player reported to a node 3 km away was being withheld from
 *        the player entirely — they could hear the shooting but the radio feed
 *        said nothing, because coverage was evaluated at the node. Passing the
 *        signal position lets coverage be judged on the EVENT the player might
 *        plausibly perceive.
 *
 * Return Value:
 *     <BOOL> - true if written
 */

params [
    ["_source",   "INTERCEPT", [""]],
    ["_from",     "", [""]],
    ["_to",       "", [""]],
    ["_text",     "", [""]],
    ["_nodeId",   "", [""]],
    ["_grade",    "BASIC", [""]],
    ["_eventPos", [], [[]]]
];

if (_text isEqualTo "") exitWith { false };

private _feed = missionNamespace getVariable ["DSC_c2Feed", []];

// Wall-clock in-game time reads better in a scrollback than serverTime.
private _h = floor dayTime;
private _m = floor ((dayTime - _h) * 60);
private _s = floor ((((dayTime - _h) * 60) - _m) * 60);
private _stamp = format ["%1:%2:%3",
    [_h, 2] call CBA_fnc_formatNumber,
    [_m, 2] call CBA_fnc_formatNumber,
    [_s, 2] call CBA_fnc_formatNumber
];

private _entry = createHashMapFromArray [
    ["time",     serverTime],
    ["stamp",    _stamp],
    ["source",   _source],
    ["from",     _from],
    ["to",       _to],
    ["text",     _text],
    ["nodeId",   _nodeId],
    ["grade",    _grade],
    ["eventPos", _eventPos]
];

_feed pushBack _entry;

// Ring buffer — trim oldest. 200 entries is deep enough to scroll back
// through a long engagement without letting a multi-hour session grow the
// array without bound.
private _maxEntries = 200;
if ((count _feed) > _maxEntries) then {
    _feed deleteRange [0, (count _feed) - _maxEntries];
};

missionNamespace setVariable ["DSC_c2Feed", _feed, true];

// ============================================================================
// F.4 — live delivery
// ============================================================================
// Every C2 line already flows through this function, so hooking the ISR
// broadcast here makes all six existing call sites player-facing with no
// changes, and covers any future signal type automatically. The broadcast
// applies its own coverage gate, suppression rules and throttle — this call is
// deliberately unconditional.
[_entry] call DSC_core_fnc_c2IsrBroadcast;

#ifdef DEBUG_MODE_FULL
private _line = if (_from != "" && {_to != ""}) then {
    format ["[%1] (%2) %3 -> %4  ""%5""", _stamp, _source, _from, _to, _text]
} else {
    format ["[%1] (%2) %3", _stamp, _source, _text]
};
LOG(_line);
#endif

true
