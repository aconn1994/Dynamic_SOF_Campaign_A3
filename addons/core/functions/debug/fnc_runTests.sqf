#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_runTests
 * Description:
 *     Tier-1 headless test runner. Executes every suite registered in
 *     `DSC_testSuites` and logs a PASS/FAIL line per assertion plus a final
 *     summary. This is the agent's self-verification tier — no playtest
 *     needed (see .crush/agentic-workflow-and-testing.md Part B.2).
 *
 *     REGISTRATION CONTRACT
 *
 *     `DSC_testSuites` is a HASHMAP: suiteName <STRING> -> suiteCode <CODE>.
 *     A suite's CODE takes no arguments and returns an ARRAY of assertion
 *     results, each `[label <STRING>, passed <BOOL>]`:
 *
 *         DSC_testSuites set ["my_suite", {
 *             private _results = [];
 *             _results pushBack ["1 equals 1", (1 == 1)];
 *             _results pushBack ["names match", ("a" == "a")];
 *             _results
 *         }];
 *
 *     Register suites BEFORE calling fnc_runTests (e.g. from
 *     fnc_initServerDebug, or directly in a test mission's initServer.sqf).
 *     If `DSC_testSuites` is nil, an empty registry is created and the run
 *     reports 0 passed / 0 failed.
 *
 *     A suite that returns something other than an ARRAY is skipped with an
 *     ERROR log line naming the offending suite; it does not stop the run.
 *
 * Arguments: None
 *
 * Return Value:
 *     <ARRAY> - [passed <NUMBER>, failed <NUMBER>]
 *
 * Example:
 *     DSC_testSuites set ["harness_selftest", {
 *         [["trivially true", true], ["trivially false", false]]
 *     }];
 *     private _result = [] call DSC_core_fnc_runTests;
 *     _result params ["_passed", "_failed"];
 */

if (isNil "DSC_testSuites") then {
    missionNamespace setVariable ["DSC_testSuites", createHashMap];
};

private _suites = missionNamespace getVariable ["DSC_testSuites", createHashMap];

private _totalPassed = 0;
private _totalFailed = 0;

INFO("=============== runTests: starting ===============");

{
    private _suiteName = _x;
    private _suiteCode = _y;

    private _results = [] call _suiteCode;

    if !(_results isEqualType []) then {
        ERROR_1("runTests - suite '%1' did not return an array, skipping",_suiteName);
    } else {
        {
            _x params ["_label", "_passed"];
            private _fullLabel = format ["%1/%2", _suiteName, _label];

            if (_passed) then {
                _totalPassed = _totalPassed + 1;
                INFO_1("PASS: %1",_fullLabel);
            } else {
                _totalFailed = _totalFailed + 1;
                ERROR_1("FAIL: %1",_fullLabel);
            };
        } forEach _results;
    };
} forEach _suites;

private _summary = format ["runTests: %1 passed, %2 failed", _totalPassed, _totalFailed];
INFO(_summary);

[_totalPassed, _totalFailed]
