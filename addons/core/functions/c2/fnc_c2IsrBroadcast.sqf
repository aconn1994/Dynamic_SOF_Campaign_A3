#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_c2IsrBroadcast
 * Description:
 *     Sprint F.4 — decides whether the player earns a given feed line, and if
 *     so delivers it as ambient radio chatter.
 *
 *     WHY THIS LIVES AT fnc_c2FeedAdd
 *
 *     Called from the tail of `fnc_c2FeedAdd`, which is the single choke point
 *     every C2 line already passes through. That means all six existing feed
 *     call sites (`c2Signal` x4, `c2ResponseQrf`, `c2ResponseRecall`) become
 *     player-facing with no changes, and any future signal type is covered
 *     automatically. Same reasoning as stamping C2 provenance at the presence
 *     dispatcher rather than inside each setup function.
 *
 *     COVERAGE GATING HAPPENS AT READ TIME, NOT WRITE TIME
 *
 *     `DSC_c2Feed` deliberately records everything the enemy said, including
 *     lines the player never earned. That single buffer then serves both an
 *     omniscient debug view and the coverage-limited player view. This function
 *     is the read-time filter for the *live* surface; the tablet applies the
 *     same rule to the scrollback.
 *
 *     TWO THINGS ARE SUPPRESSED REGARDLESS OF COVERAGE
 *
 *       1. `LOST` lines. A transmission that never arrived is exactly the
 *          information the player is not supposed to have — the whole point of
 *          the report timer is that a clean wipe leaves the network ignorant.
 *          Showing "(not received)" would tell the player they got away with
 *          it, which is the reward for good play, not a status readout.
 *          They stay in the buffer for debugging.
 *
 *       2. Echo/corroborating lines. Fifteen groups in one firefight produce a
 *          lot of "small arms heard (corroborating)". Useful in the RPT,
 *          spam on screen mid-contact.
 *
 *     THROTTLE
 *
 *     A busy network can emit several lines per second. `systemChat` has no
 *     rate limit and will happily bury the player's own squad reports and
 *     mission feedback. One line per ~2.5 s to the live surface; everything
 *     else is still in the scrollback, which is precisely the problem the
 *     tablet Radio Feed page exists to solve.
 *
 * Arguments:
 *     0: _entry <HASHMAP> - a feed entry as built by fnc_c2FeedAdd
 *
 * Return Value:
 *     <BOOL> - true if delivered to the live surface
 */

params [["_entry", createHashMap, [createHashMap]]];

if (!isServer) exitWith { false };
if (_entry isEqualTo createHashMap) exitWith { false };

private _source = _entry getOrDefault ["source", "INTERCEPT"];
private _text   = _entry getOrDefault ["text", ""];

if (_text isEqualTo "") exitWith { false };

// Never surface a transmission that did not arrive — see header.
if (_source isEqualTo "LOST") exitWith { false };

// Corroborating chatter is buffer-only.
if ("corroborating" in (toLower _text)) exitWith { false };

// ============================================================================
// Coverage check
// ============================================================================
// Delegated to fnc_c2IsrEntryTier so the live surface and the tablet scrollback
// apply exactly the same rule. Coverage is best-of {event position, node LKP,
// node position} — judging it at the node alone silently withheld firefights
// happening next to the player because the reporting node was kilometres away.
([_entry] call DSC_core_fnc_c2IsrEntryTier) params ["_tier", "_requiredRank"];

if (_tier < _requiredRank) exitWith { false };

// ============================================================================
// Throttle
// ============================================================================
private _lastAt = missionNamespace getVariable ["DSC_c2ChatterLastAt", -999];
if ((serverTime - _lastAt) < 2.5) exitWith { false };
missionNamespace setVariable ["DSC_c2ChatterLastAt", serverTime];

// ============================================================================
// Deliver
// ============================================================================
// Formatted here (server) so every client shows an identical line and the
// client handler stays a dumb sink.
private _from  = _entry getOrDefault ["from", ""];
private _to    = _entry getOrDefault ["to", ""];
private _stamp = _entry getOrDefault ["stamp", ""];

private _line = if (_from != "" && {_to != ""}) then {
    format ["[%1] %2 >> %3: %4", _stamp, _from, _to, _text]
} else {
    format ["[%1] %2: %3", _stamp, _source, _text]
};

["DSC_c2_chatter", [_line]] call CBA_fnc_globalEvent;

true
