#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_intelQuery
 * Description:
 *     Pure filter over a passed-in ledger — reads no globals, so it is
 *     directly Tier-1 testable with a hand-built ledger + criteria and no
 *     dependency on `DSC_intelLedger` existing.
 *
 *     Returns every LIVE (non-expired, `expiresAt > _now`) token matching
 *     every criteria key the caller supplied. An omitted criteria key is a
 *     wildcard (matches any value on that field).
 *
 *     Real callers read `DSC_intelLedger` themselves and pass it in:
 *         private _ledger = missionNamespace getVariable ["DSC_intelLedger", createHashMap];
 *         private _hits = [_ledger, createHashMapFromArray [["type","HVT_LOCATION"]]]
 *             call DSC_core_fnc_intelQuery;
 *
 * Arguments:
 *     0: _ledger   <HASHMAP> - id -> token (see fnc_intelAdd header for schema)
 *     1: _criteria <HASHMAP> - any subset of "subjectRef" / "type" / "scope" /
 *                              "source" -> the value to match
 *     2: _now      <NUMBER>  - reference time for liveness (default: serverTime).
 *                              Exposed so tests can pin a deterministic clock
 *                              instead of racing real elapsed serverTime.
 *
 * Return Value:
 *     <ARRAY> - matching live token <HASHMAP>s, unordered (HashMap iteration
 *               order is not deterministic).
 *
 * Example:
 *     private _hits = [_ledger, createHashMapFromArray [["subjectRef", "hvt_bombmaker"]]]
 *         call DSC_core_fnc_intelQuery;
 */

params [
    ["_ledger", createHashMap, [createHashMap]],
    ["_criteria", createHashMap, [createHashMap]],
    ["_now", serverTime, [0]]
];

private _matches = [];

{
    private _token = _y;

    if ((_token get "expiresAt") > _now) then {
        private _ok = true;

        {
            private _key = _x;
            private _want = _y;
            if (_ok && {(_token getOrDefault [_key, ""]) != _want}) then {
                _ok = false;
            };
        } forEach _criteria;

        if (_ok) then { _matches pushBack _token };
    };
} forEach _ledger;

_matches
