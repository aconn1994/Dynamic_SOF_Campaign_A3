#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_intelBest
 * Description:
 *     Pure lookup over a passed-in ledger (built on `fnc_intelQuery`, same
 *     testability contract): the highest-`confidence` LIVE token matching
 *     both `subjectRef` and `type`. This is what the resolver and series
 *     gates call to ask "what's our best intel on X?".
 *
 * Arguments:
 *     0: _ledger     <HASHMAP> - id -> token (see fnc_intelAdd header for schema)
 *     1: _subjectRef <STRING>  - subject to match
 *     2: _type       <STRING>  - token type to match
 *     3: _now        <NUMBER>  - reference time for liveness (default: serverTime)
 *
 * Return Value:
 *     <HASHMAP> - the best matching live token, or an empty HASHMAP (the
 *                 null/empty sentinel) if none exists.
 *
 * Example:
 *     private _best = [_ledger, "hvt_bombmaker", "HVT_LOCATION"] call DSC_core_fnc_intelBest;
 *     if (_best isNotEqualTo createHashMap) then { ... };
 */

params [
    ["_ledger", createHashMap, [createHashMap]],
    ["_subjectRef", "", [""]],
    ["_type", "", [""]],
    ["_now", serverTime, [0]]
];

private _criteria = createHashMapFromArray [
    ["subjectRef", _subjectRef],
    ["type", _type]
];

private _matches = [_ledger, _criteria, _now] call DSC_core_fnc_intelQuery;

private _best = createHashMap;
private _bestConfidence = -1;

{
    private _confidence = _x get "confidence";
    if (_confidence > _bestConfidence) then {
        _bestConfidence = _confidence;
        _best = _x;
    };
} forEach _matches;

_best
