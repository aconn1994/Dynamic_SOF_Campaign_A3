#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_c2IsrEntryTier
 * Description:
 *     Sprint F.4 — resolves the player's ISR coverage tier for one feed entry.
 *
 *     SHARED BY BOTH READ SURFACES ON PURPOSE
 *
 *     `fnc_c2IsrBroadcast` (live systemChat) and `fnc_panelRadio_refresh`
 *     (tablet scrollback) both need this answer, and if they compute it
 *     differently the two surfaces disagree about what the player knows —
 *     a line appears in chat but not in the scrollback, or vice versa. One
 *     function, one rule.
 *
 *     COVERAGE IS BEST-OF, NOT NODE-ONLY
 *
 *     The original implementation judged coverage at the NODE's position only.
 *     That was wrong in the most common case: a node is usually kilometres
 *     from the event it is talking about, so a firefight 200 m from the player
 *     was withheld entirely — they could hear the shooting while the radio
 *     feed stayed silent. Confirmed in playtest: an opFor-vs-AAF engagement
 *     generated a full set of INTERCEPT lines that never reached the player
 *     because the reporting node was 3 km away.
 *
 *     Coverage is therefore the BEST of three positions:
 *
 *       1. `eventPos` on the entry — where the reported thing happened.
 *          Set by signal/response callers. The most accurate source.
 *       2. The node's current LKP — fallback for entries written before
 *          eventPos existed, and for accountability signals that carry no
 *          position of their own.
 *       3. The node's own position — "I am standing in this installation and
 *          can hear its radio."
 *
 *     Taking the maximum is the intuitive reading: the player learns about a
 *     transmission if they are near EITHER end of it, or have a drone over
 *     either end.
 *
 * Arguments:
 *     0: _entry <HASHMAP> - a feed entry from fnc_c2FeedAdd
 *
 * Return Value:
 *     <ARRAY> [_tier, _requiredRank]
 *       _tier         <NUMBER> best coverage tier the player has, 0..3
 *       _requiredRank <NUMBER> tier this entry needs, 1..3
 *     Deliver when _tier >= _requiredRank.
 */

params [["_entry", createHashMap, [createHashMap]]];

if (_entry isEqualTo createHashMap) exitWith { [0, 99] };

// ----------------------------------------------------------------------------
// Required tier
// ----------------------------------------------------------------------------
private _grade = _entry getOrDefault ["grade", "BASIC"];
private _requiredRank = switch (toUpper _grade) do {
    case "BASIC":    { 1 };
    case "ENHANCED": { 2 };
    case "FULL":     { 3 };
    default          { 1 };
};

// ----------------------------------------------------------------------------
// Candidate positions
// ----------------------------------------------------------------------------
private _candidates = [];

private _eventPos = _entry getOrDefault ["eventPos", []];
if (_eventPos isNotEqualTo []) then { _candidates pushBack _eventPos };

private _nodeId = _entry getOrDefault ["nodeId", ""];
if (_nodeId != "") then {
    private _nodes = missionNamespace getVariable ["DSC_c2Nodes", createHashMap];
    private _node  = _nodes getOrDefault [_nodeId, createHashMap];
    if (_node isNotEqualTo createHashMap) then {

        private _lkp = _node getOrDefault ["lkp", createHashMap];
        private _lkpPos = _lkp getOrDefault ["position", []];
        if (_lkpPos isNotEqualTo []) then { _candidates pushBack _lkpPos };

        private _nodePos = _node getOrDefault ["position", []];
        if (_nodePos isNotEqualTo []) then { _candidates pushBack _nodePos };
    };
};

// No resolvable position means the entry cannot be graded, so it stays
// buffer-only rather than being handed over for free.
if (_candidates isEqualTo []) exitWith { [0, _requiredRank] };

// ----------------------------------------------------------------------------
// Best coverage across candidates
// ----------------------------------------------------------------------------
private _best = 0;
{
    private _t = ([_x] call DSC_core_fnc_c2IsrCoverage) select 0;
    if (_t > _best) then { _best = _t };
    // Short-circuit: FULL is the ceiling, no point checking further.
    if (_best >= 3) exitWith {};
} forEach _candidates;

[_best, _requiredRank]
