#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_intelDecay
 * Description:
 *     Pure(-ish) expiry pass over a passed-in ledger: drops every token
 *     whose `expiresAt <= _now`, mutating `_ledger` in place (HashMap is a
 *     reference type, same convention as `fnc_c2RaiseAlert`'s node mutation —
 *     no re-`setVariable` needed for the mutation to be visible; production
 *     callers only re-publish for network-broadcast hygiene, not correctness).
 *
 *     Intel decay is a SEPARATE clock from C2 alert decay — do not overload
 *     C2 node state as intel confidence (`.crush/campaign-overhaul.md` §10).
 *     A future tick calls this on `DSC_intelLedger`; for now it is a function
 *     the tests drive directly.
 *
 * Arguments:
 *     0: _ledger <HASHMAP> - id -> token (see fnc_intelAdd header for schema).
 *                            Mutated in place.
 *     1: _now    <NUMBER>  - reference time for expiry (default: serverTime).
 *                            Exposed so tests can pin a deterministic clock.
 *
 * Return Value:
 *     <NUMBER> - count of tokens dropped
 *
 * Example:
 *     private _ledger = missionNamespace getVariable ["DSC_intelLedger", createHashMap];
 *     private _dropped = [_ledger] call DSC_core_fnc_intelDecay;
 */

params [
    ["_ledger", createHashMap, [createHashMap]],
    ["_now", serverTime, [0]]
];

private _expiredIds = [];

{
    private _token = _y;
    if ((_token get "expiresAt") <= _now) then {
        _expiredIds pushBack _x;
    };
} forEach _ledger;

{ _ledger deleteAt _x } forEach _expiredIds;

private _droppedCount = count _expiredIds;
if (_droppedCount > 0) then {
    LOG_1("intelDecay - dropped %1 expired token(s)",_droppedCount);
};

_droppedCount
