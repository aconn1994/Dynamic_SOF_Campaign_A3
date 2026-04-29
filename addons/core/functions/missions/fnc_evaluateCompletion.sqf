#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_evaluateCompletion
 * Description:
 *     Evaluates a mission's completion condition against its state hashmap.
 *     Drives the raid monitor loop:
 *
 *         while { _missionActive } do {
 *             private _result = [_completion, _state] call DSC_core_fnc_evaluateCompletion;
 *             if (_result get "complete") exitWith { ... };
 *             sleep 2;
 *         };
 *
 *     Three dispatch paths:
 *
 *       1. Inline expr - if _completion contains "completionExpr" code, run
 *          it directly. Use for compound conditions ("HVT dead AND intel
 *          gathered").
 *
 *       2. Named type - if _completion contains "type" string, look up the
 *          named condition in fnc_getCompletionTypes and run its check.
 *
 *       3. Bare string - if _completion is itself a string, treat it as a
 *          named type. Convenience for simple cases.
 *
 *     Returns a result hashmap rather than a bare bool so callers can
 *     surface success/partial messages without re-querying the registry.
 *
 * Arguments:
 *     0: _completion <HASHMAP|STRING> - Either:
 *        - String: condition type name (e.g. "KILL_CAPTURE")
 *        - Hashmap with "type" <STRING>      : named condition
 *        - Hashmap with "completionExpr" <CODE>: inline check
 *        Optional hashmap fields:
 *        - "successMsg" / "partialMsg" - override registry messages
 *     1: _state <HASHMAP> - Mission state. Keys depend on the condition.
 *        Common keys:
 *          "hvt"            <OBJECT>
 *          "objects"        <ARRAY>
 *          "hostages"       <ARRAY>
 *          "defenders"      <ARRAY>
 *          "intelGathered"  <BOOL>
 *          "extractPos"     <ARRAY>
 *
 * Return Value:
 *     <HASHMAP>:
 *       "complete"   <BOOL>    Condition currently satisfied
 *       "success"    <BOOL>    Same as complete (kept distinct for
 *                              compound conditions where partial
 *                              completion may differ from success)
 *       "message"    <STRING>  Success message if complete, partial
 *                              message if not
 *       "type"       <STRING>  Resolved type name ("CUSTOM" for inline)
 *
 * Example:
 *     private _state = createHashMapFromArray [["hvt", _hvtUnit]];
 *     private _result = ["KILL_CAPTURE", _state] call DSC_core_fnc_evaluateCompletion;
 *     if (_result get "complete") then { hint (_result get "message") };
 */

params [
    ["_completion", "", ["", createHashMap]],
    ["_state", createHashMap, [createHashMap]]
];

private _typeName = "CUSTOM";
private _checkBlock = {};
private _successMsg = "Mission complete";
private _partialMsg = "Mission incomplete";

// ----------------------------------------------------------------------------
// Resolve dispatch path
// ----------------------------------------------------------------------------
if (_completion isEqualType "") then {
    _typeName = _completion;
} else {
    if ("completionExpr" in _completion) then {
        _checkBlock = _completion get "completionExpr";
        _typeName = _completion getOrDefault ["type", "CUSTOM"];
        _successMsg = _completion getOrDefault ["successMsg", _successMsg];
        _partialMsg = _completion getOrDefault ["partialMsg", _partialMsg];
    } else {
        _typeName = _completion getOrDefault ["type", ""];
        _successMsg = _completion getOrDefault ["successMsg", _successMsg];
        _partialMsg = _completion getOrDefault ["partialMsg", _partialMsg];
    };
};

// Fetch named condition if we don't already have an inline expr
if (_checkBlock isEqualTo {}) then {
    if (_typeName isEqualTo "") exitWith {
        diag_log "DSC: evaluateCompletion - no completion type specified";
    };
    private _registry = call DSC_core_fnc_getCompletionTypes;
    private _entry = _registry getOrDefault [_typeName, createHashMap];
    if (_entry isEqualTo createHashMap) exitWith {
        diag_log format ["DSC: evaluateCompletion - unknown completion type '%1'", _typeName];
    };
    _checkBlock = _entry get "check";
    // Only fall back to registry messages if caller didn't override
    if (_completion isEqualType "" || { !("successMsg" in _completion) }) then {
        _successMsg = _entry getOrDefault ["successMsg", _successMsg];
    };
    if (_completion isEqualType "" || { !("partialMsg" in _completion) }) then {
        _partialMsg = _entry getOrDefault ["partialMsg", _partialMsg];
    };
};

// ----------------------------------------------------------------------------
// Run check
// ----------------------------------------------------------------------------
private _complete = false;
if (_checkBlock isNotEqualTo {}) then {
    _complete = [_state] call _checkBlock;
};

createHashMapFromArray [
    ["complete", _complete],
    ["success", _complete],
    ["message", [_partialMsg, _successMsg] select _complete],
    ["type", _typeName]
]
