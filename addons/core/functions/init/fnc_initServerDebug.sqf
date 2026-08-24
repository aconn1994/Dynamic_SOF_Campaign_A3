#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_initServerDebug
 * Description:
 *     Server-side debug/admin extension layer. Runs after fnc_initServer.
 *     Initializes globals and registers CBA event handlers used by the
 *     Commander's Tablet to inject mission templates and abort the active
 *     mission.
 *
 *     This is the home for any future server-side debug machinery (state
 *     dumps, scenario probes, AI inspection tooling, etc.) so the production
 *     init path stays clean.
 *
 *     Anyone may currently invoke these events. Add admin gating here later
 *     by checking _uid against an allowlist.
 *
 * Globals set:
 *     DSC_missionQueue            <ARRAY>  FIFO queue of partial templates
 *     DSC_missionAbortRequested   <BOOL>   abort flag honored by mission loop
 *
 * CBA events handled:
 *     "DSC_tablet_queueMission" [_template, _uid, _name]
 *     "DSC_tablet_abortMission" [_uid, _name]
 *
 * Arguments: none
 */

if (!isServer) exitWith {};

INFO("========== Initializing Server Debug Layer ==========");

// ----------------------------------------------------------------------------
// Globals (idempotent — fnc_initServer also defends these)
// ----------------------------------------------------------------------------
if (isNil { missionNamespace getVariable "DSC_missionQueue" }) then {
    missionNamespace setVariable ["DSC_missionQueue", [], true];
};
if (isNil { missionNamespace getVariable "DSC_missionAbortRequested" }) then {
    missionNamespace setVariable ["DSC_missionAbortRequested", false, true];
};

// ----------------------------------------------------------------------------
// CBA event: queue a mission template
// ----------------------------------------------------------------------------
["DSC_tablet_queueMission", {
    params [
        ["_template", createHashMap, [createHashMap]],
        ["_uid", "", [""]],
        ["_name", "", [""]]
    ];

    if (_template isEqualTo createHashMap) exitWith {
        WARNING_2("tablet queue rejected (empty template) from %1 [%2]",_name,_uid);
    };

    private _queue = missionNamespace getVariable ["DSC_missionQueue", []];
    _queue pushBack _template;
    missionNamespace setVariable ["DSC_missionQueue", _queue, true];

    LOG_4("tablet queued mission from %1 [%2] - queue size %3 - template %4",_name,_uid,count _queue,_template);
}] call CBA_fnc_addEventHandler;

// ----------------------------------------------------------------------------
// CBA event: abort current mission
// ----------------------------------------------------------------------------
["DSC_tablet_abortMission", {
    params [
        ["_uid", "", [""]],
        ["_name", "", [""]]
    ];

    if (!(missionNamespace getVariable ["missionInProgress", false])) exitWith {
        WARNING_2("tablet abort ignored (no active mission) from %1 [%2]",_name,_uid);
    };

    missionNamespace setVariable ["DSC_missionAbortRequested", true, true];
    INFO_2("tablet abort requested from %1 [%2]",_name,_uid);
}] call CBA_fnc_addEventHandler;

// ----------------------------------------------------------------------------
// Tier-1 test harness: suite registry + self-test
// ----------------------------------------------------------------------------
// Proves fnc_runTests correctly tallies passes/fails. Later sessions
// register their own suites the same way (DSC_testSuites set [name, code]);
// see fnc_runTests header for the registration contract.
if (isNil "DSC_testSuites") then {
    missionNamespace setVariable ["DSC_testSuites", createHashMap];
};

private _testSuites = missionNamespace getVariable ["DSC_testSuites", createHashMap];

_testSuites set ["harness_selftest", {
    [
        ["trivially true", (1 == 1)],
        ["trivially false (expected FAIL - proves the runner reports failures)", (1 == 2)]
    ]
}];

INFO("Registered test suite: harness_selftest (fnc_runTests self-check)");

// ----------------------------------------------------------------------------
// Tier-1 test suite: Intel Ledger (Campaign Overhaul Session 2)
// ----------------------------------------------------------------------------
// intelQuery/intelBest/intelDecay are exercised against hand-built local
// ledgers (never DSC_intelLedger) so this suite is fully deterministic and
// touches no global state except for the intelAdd assertions, which are the
// one function whose contract IS "write to DSC_intelLedger".
_testSuites set ["intel_ledger", {
    private _results = [];

    // ---- intelAdd: fills defaults, clamps confidence, returns id ----
    [] call DSC_core_fnc_intelInit;

    private _addedId = [createHashMapFromArray [
        ["type", "HVT_LOCATION"],
        ["subjectRef", "hvt_test"],
        ["confidence", 1.5],
        ["source", "SSE"]
    ]] call DSC_core_fnc_intelAdd;

    _results pushBack ["intelAdd returns a non-empty id", (_addedId isEqualType "" && {_addedId != ""})];

    private _ledgerGlobal = missionNamespace getVariable ["DSC_intelLedger", createHashMap];
    private _addedToken = _ledgerGlobal getOrDefault [_addedId, createHashMap];

    _results pushBack ["intelAdd stores the token under its id", (_addedToken isNotEqualTo createHashMap)];
    _results pushBack ["intelAdd fills subjectKind default", ((_addedToken getOrDefault ["subjectKind", ""]) == "AREA")];
    _results pushBack ["intelAdd fills scope default", ((_addedToken getOrDefault ["scope", ""]) == "AREA")];
    _results pushBack ["intelAdd clamps confidence to 1.0", ((_addedToken getOrDefault ["confidence", -1]) == 1)];
    _results pushBack ["intelAdd sets expiresAt after discoveredAt", ((_addedToken get "expiresAt") > (_addedToken get "discoveredAt"))];

    // ---- Hand-built ledger for query/best/decay (pure, no global touch) ----
    private _now = 100000;

    private _tokenA = createHashMapFromArray [
        ["id", "tokA"], ["type", "HVT_LOCATION"], ["subjectKind", "ENTITY"],
        ["subjectRef", "subjX"], ["confidence", 0.4], ["source", "SSE"],
        ["scope", "AREA"], ["discoveredAt", _now - 10], ["expiresAt", _now + 1000],
        ["payload", createHashMap]
    ];
    private _tokenB = createHashMapFromArray [
        ["id", "tokB"], ["type", "ENEMY_STRENGTH"], ["subjectKind", "LOCATION"],
        ["subjectRef", "subjX"], ["confidence", 0.9], ["source", "RECON"],
        ["scope", "LOCATION"], ["discoveredAt", _now - 10], ["expiresAt", _now + 1000],
        ["payload", createHashMap]
    ];
    private _tokenC = createHashMapFromArray [
        ["id", "tokC"], ["type", "HVT_LOCATION"], ["subjectKind", "ENTITY"],
        ["subjectRef", "subjY"], ["confidence", 0.7], ["source", "HQ"],
        ["scope", "SERIES"], ["discoveredAt", _now - 10], ["expiresAt", _now + 1000],
        ["payload", createHashMap]
    ];
    // Already-expired — must never surface from query/best.
    private _tokenExpired = createHashMapFromArray [
        ["id", "tokExpired"], ["type", "HVT_LOCATION"], ["subjectKind", "ENTITY"],
        ["subjectRef", "subjX"], ["confidence", 0.99], ["source", "SIGINT"],
        ["scope", "AREA"], ["discoveredAt", _now - 2000], ["expiresAt", _now - 1000],
        ["payload", createHashMap]
    ];

    private _testLedger = createHashMapFromArray [
        ["tokA", _tokenA], ["tokB", _tokenB], ["tokC", _tokenC], ["tokExpired", _tokenExpired]
    ];

    // ---- intelQuery: filter by type / subjectRef / scope ----
    private _byType = [_testLedger, createHashMapFromArray [["type", "HVT_LOCATION"]], _now] call DSC_core_fnc_intelQuery;
    _results pushBack ["intelQuery filters by type", ((count _byType) == 2)];

    private _bySubject = [_testLedger, createHashMapFromArray [["subjectRef", "subjX"]], _now] call DSC_core_fnc_intelQuery;
    _results pushBack ["intelQuery filters by subjectRef", ((count _bySubject) == 2)];

    private _byScope = [_testLedger, createHashMapFromArray [["scope", "SERIES"]], _now] call DSC_core_fnc_intelQuery;
    _results pushBack ["intelQuery filters by scope", ((count _byScope) == 1 && {(_byScope select 0) get "id" == "tokC"})];

    private _byExpiredSubject = [_testLedger, createHashMapFromArray [["subjectRef", "subjX"], ["type", "HVT_LOCATION"]], _now] call DSC_core_fnc_intelQuery;
    _results pushBack ["intelQuery excludes an expired token even when criteria match", ((count _byExpiredSubject) == 1 && {(_byExpiredSubject findIf { (_x get "id") == "tokExpired" }) == -1})];

    // ---- intelBest: highest-confidence LIVE token ----
    private _best = [_testLedger, "subjX", "HVT_LOCATION", _now] call DSC_core_fnc_intelBest;
    _results pushBack ["intelBest returns the highest-confidence live token (ignores expired higher one)", ((_best get "id") == "tokA")];

    private _bestNone = [_testLedger, "subjZZZ", "NOTHING", _now] call DSC_core_fnc_intelBest;
    _results pushBack ["intelBest returns empty sentinel when nothing matches", (_bestNone isEqualTo createHashMap)];

    // ---- intelDecay: drops expired, keeps live ----
    private _decayLedger = createHashMapFromArray [
        ["tokA", _tokenA], ["tokB", _tokenB], ["tokC", _tokenC], ["tokExpired", _tokenExpired]
    ];
    private _dropped = [_decayLedger, _now] call DSC_core_fnc_intelDecay;

    _results pushBack ["intelDecay drops exactly the expired token", (_dropped == 1)];
    _results pushBack ["intelDecay keeps live tokens", ((count _decayLedger) == 3)];
    _results pushBack ["intelDecay actually removed the expired id", !("tokExpired" in (keys _decayLedger))];

    _results
}];

INFO("Registered test suite: intel_ledger (Intel Ledger add/query/best/decay)");

INFO("Server debug layer initialized (tablet events registered)");
