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

// ----------------------------------------------------------------------------
// Tier-1 test suite: Series Arbiter (Campaign Overhaul Session 3)
// ----------------------------------------------------------------------------
// fnc_startSeries / fnc_advanceCampaign are fully pure (no global reads other
// than fnc_intelAdd's ledger write, which the "intelReward lands in the
// ledger" assertions exercise deliberately, same pattern as intel_ledger's
// intelAdd checks above). Mock series/outcomes are hand-built locals.
_testSuites set ["series_arbiter", {
    private _results = [];

    // ---- startSeries: ONE_OFF factory equals today's random template ----
    private _oneOffSeries = [] call DSC_core_fnc_startSeries;
    private _oneOffStages = _oneOffSeries get "stages";

    _results pushBack ["startSeries ONE_OFF produces exactly one stage", (count _oneOffStages == 1)];

    private _oneOffTemplate = (_oneOffStages select 0) get "missionTemplate";
    private _todaysRandomTemplate = createHashMapFromArray [
        ["type", "KILL_CAPTURE"],
        ["missionProfile", "AFO_rural"]
    ];

    _results pushBack ["startSeries ONE_OFF template matches today's random template", (_oneOffTemplate isEqualTo _todaysRandomTemplate)];
    _results pushBack ["startSeries ONE_OFF has no branch targets (always terminal)", (((_oneOffStages select 0) get "onSuccess") == "" && {((_oneOffStages select 0) get "onFailure") == ""})];

    // ---- advanceCampaign SELECT: no thread -> one-off template ----
    private _selectNoThread = ["SELECT", createHashMap, createHashMap] call DSC_core_fnc_advanceCampaign;
    _selectNoThread params ["_selNoThreadTemplate", "_selNoThreadSeries"];

    _results pushBack ["advanceCampaign(SELECT) with no thread returns today's random template", (_selNoThreadTemplate isEqualTo _todaysRandomTemplate)];
    _results pushBack ["advanceCampaign(SELECT) with no thread starts a ONE_OFF series", ((_selNoThreadSeries get "threadType") == "ONE_OFF")];

    // ---- advanceCampaign SELECT: tablet queue outranks series ----
    private _queuedTemplate = createHashMapFromArray [["type", "QUEUED_TEMPLATE"]];
    private _mockActiveSeries = createHashMapFromArray [
        ["threadType", "TEST_THREAD"],
        ["stages", [createHashMapFromArray [["id", "irrelevant"], ["missionTemplate", createHashMapFromArray [["type", "SERIES_TEMPLATE"]]]]]],
        ["stageIndex", 0],
        ["branchState", createHashMap],
        ["subjectRefs", createHashMap],
        ["narrative", createHashMap],
        ["intelRequirements", []]
    ];
    private _selectWithQueue = ["SELECT", _queuedTemplate, _mockActiveSeries] call DSC_core_fnc_advanceCampaign;
    _selectWithQueue params ["_selQueueTemplate", "_selQueueSeries"];

    _results pushBack ["advanceCampaign(SELECT) tablet queue outranks active series", (_selQueueTemplate isEqualTo _queuedTemplate)];
    _results pushBack ["advanceCampaign(SELECT) leaves the active series untouched when queue wins", (_selQueueSeries isEqualTo _mockActiveSeries)];

    // ---- Mock 2-branch series for OUTCOME tests ----
    // stageA -> onSuccess: stageB (terminal) / onFailure: stageA_fail (terminal)
    private _stageA = createHashMapFromArray [
        ["id", "stageA"],
        ["entryConditions", []],
        ["missionTemplate", createHashMapFromArray [["type", "STAGE_A"]]],
        ["onSuccess", "stageB"],
        ["onFailure", "stageA_fail"],
        ["intelReward", [createHashMapFromArray [["type", "HVT_LOCATION"], ["subjectRef", "arbiter_test_subject"], ["confidence", 0.8], ["source", "HQ"]]]],
        ["narrativeBeat", ""]
    ];
    private _stageB = createHashMapFromArray [
        ["id", "stageB"],
        ["entryConditions", []],
        ["missionTemplate", createHashMapFromArray [["type", "STAGE_B"]]],
        ["onSuccess", ""],
        ["onFailure", ""],
        ["intelReward", []],
        ["narrativeBeat", ""]
    ];
    private _stageAFail = createHashMapFromArray [
        ["id", "stageA_fail"],
        ["entryConditions", []],
        ["missionTemplate", createHashMapFromArray [["type", "STAGE_A_FAIL"]]],
        ["onSuccess", ""],
        ["onFailure", ""],
        ["intelReward", []],
        ["narrativeBeat", ""]
    ];

    private _twoStageSeries = createHashMapFromArray [
        ["threadType", "TEST_THREAD"],
        ["stages", [_stageA, _stageB, _stageAFail]],
        ["stageIndex", 0],
        ["branchState", createHashMap],
        ["subjectRefs", createHashMap],
        ["narrative", createHashMap],
        ["intelRequirements", []]
    ];

    // ---- OUTCOME: success advances to onSuccess target ----
    private _successOutcome = createHashMapFromArray [["success", true]];
    private _outcomeSuccessResult = ["OUTCOME", _successOutcome, +_twoStageSeries, createHashMap] call DSC_core_fnc_advanceCampaign;
    _outcomeSuccessResult params ["_seriesAfterSuccess", "_rewardAfterSuccess"];

    _results pushBack ["advanceCampaign(OUTCOME) success advances stageIndex to onSuccess target", ((_seriesAfterSuccess get "stageIndex") == 1)];
    _results pushBack ["advanceCampaign(OUTCOME) success records branchState", (((_seriesAfterSuccess get "branchState") getOrDefault ["stageA", ""]) == "success")];
    _results pushBack ["advanceCampaign(OUTCOME) success returns the completed stage's intelReward", ((count _rewardAfterSuccess) == 1 && {(_rewardAfterSuccess select 0) get "subjectRef" == "arbiter_test_subject"})];

    // ---- OUTCOME: failure takes onFailure target ----
    private _failureOutcome = createHashMapFromArray [["success", false]];
    private _outcomeFailureResult = ["OUTCOME", _failureOutcome, +_twoStageSeries, createHashMap] call DSC_core_fnc_advanceCampaign;
    _outcomeFailureResult params ["_seriesAfterFailure", "_rewardAfterFailure"];

    _results pushBack ["advanceCampaign(OUTCOME) failure advances stageIndex to onFailure target", ((_seriesAfterFailure get "stageIndex") == 2)];
    _results pushBack ["advanceCampaign(OUTCOME) failure records branchState", (((_seriesAfterFailure get "branchState") getOrDefault ["stageA", ""]) == "failure")];

    // ---- intelReward tokens actually land in the ledger on stage completion ----
    [] call DSC_core_fnc_intelInit;
    {
        [_x] call DSC_core_fnc_intelAdd;
    } forEach _rewardAfterSuccess;
    private _ledgerAfterReward = missionNamespace getVariable ["DSC_intelLedger", createHashMap];
    private _rewardQuery = [_ledgerAfterReward, createHashMapFromArray [["subjectRef", "arbiter_test_subject"]]] call DSC_core_fnc_intelQuery;
    private _rewardLanded = (count _rewardQuery) > 0;

    _results pushBack ["OUTCOME intelReward tokens land in DSC_intelLedger via fnc_intelAdd", _rewardLanded];

    // ---- series clears when exhausted (terminal stage, e.g. ONE_OFF or stageB) ----
    private _terminalSeries = createHashMapFromArray [
        ["threadType", "TEST_THREAD"],
        ["stages", [_stageB]],
        ["stageIndex", 0],
        ["branchState", createHashMap],
        ["subjectRefs", createHashMap],
        ["narrative", createHashMap],
        ["intelRequirements", []]
    ];
    private _outcomeTerminalResult = ["OUTCOME", _successOutcome, _terminalSeries, createHashMap] call DSC_core_fnc_advanceCampaign;
    _outcomeTerminalResult params ["_seriesAfterTerminal", "_rewardAfterTerminal"];

    _results pushBack ["advanceCampaign(OUTCOME) clears the series when its stages are exhausted", (_seriesAfterTerminal isEqualTo createHashMap)];

    // ---- one-off wrapper (real fnc_startSeries output) clears after one stage ----
    private _outcomeOneOffResult = ["OUTCOME", _successOutcome, _oneOffSeries, createHashMap] call DSC_core_fnc_advanceCampaign;
    _outcomeOneOffResult params ["_seriesAfterOneOff", "_rewardAfterOneOff"];

    _results pushBack ["advanceCampaign(OUTCOME) clears a ONE_OFF thread after its single stage", (_seriesAfterOneOff isEqualTo createHashMap)];

    _results
}];

INFO("Registered test suite: series_arbiter (startSeries ONE_OFF factory + advanceCampaign SELECT/OUTCOME)");

// ----------------------------------------------------------------------------
// Tier-1 test suite: Briefing Composer (Campaign Overhaul Session 4)
// ----------------------------------------------------------------------------
// fnc_composeBriefing is pure (context -> string, no global/world reads), so
// every case here uses a hand-built mock context. The parity case captures
// fnc_createMissionBriefing's pre-refactor output for a fixed KILL_CAPTURE
// context and asserts the refactored composer reproduces it byte-for-byte.
_testSuites set ["briefing_composer", {
    private _results = [];

    // ---- getBriefingBanks: all five sections exist per (missionType, GENERIC) ----
    private _banks = call DSC_core_fnc_getBriefingBanks;
    private _kcEntry = _banks getOrDefault ["raid_kill_capture", createHashMap];
    private _kcVoices = _kcEntry getOrDefault ["voices", createHashMap];
    private _kcGeneric = _kcVoices getOrDefault ["GENERIC", createHashMap];
    private _sectionKeys = keys _kcGeneric;

    _results pushBack ["getBriefingBanks seeds all five sections (situation/mission/execution/intel/support)", (
        ("situation" in _sectionKeys) &&
        {"mission" in _sectionKeys} &&
        {"execution" in _sectionKeys} &&
        {"intel" in _sectionKeys} &&
        {"support" in _sectionKeys}
    )];

    _results pushBack ["getBriefingBanks carries titlePrefix/taskIcon through from the existing fragments", (
        ((_kcEntry getOrDefault ["titlePrefix", ""]) == "Eliminate HVT") &&
        {(_kcEntry getOrDefault ["taskIcon", ""]) == "kill"}
    )];

    // ---- composeBriefing: named slot interpolation ----
    private _slotContext = createHashMapFromArray [
        ["missionType", "raid_kill_capture"],
        ["unitVoice", "GENERIC"],
        ["slots", createHashMapFromArray [
            ["locationName", "Kavala"],
            ["relativeDesc", "in Kavala"],
            ["areaDesc", "urban area"],
            ["strengthEstimate", "estimated light resistance"],
            ["targetBlock", ""],
            ["garrisonEstimate", "Light garrison presence (fireteam-sized)"],
            ["patrolEstimate", "No patrol activity reported"],
            ["threatText", "No special threats identified."]
        ]]
    ];
    private _slotBody = [_slotContext] call DSC_core_fnc_composeBriefing;

    _results pushBack ["composeBriefing interpolates %locationName", ("Kavala" in _slotBody)];

    private _hasUnfilledSlot = (
        ("%locationName" in _slotBody) ||
        {"%relativeDesc" in _slotBody} ||
        {"%areaDesc" in _slotBody} ||
        {"%strengthEstimate" in _slotBody} ||
        {"%targetBlock" in _slotBody} ||
        {"%garrisonEstimate" in _slotBody} ||
        {"%patrolEstimate" in _slotBody} ||
        {"%threatText" in _slotBody}
    );
    _results pushBack ["composeBriefing leaves no unfilled %slot placeholders", !_hasUnfilledSlot];

    // ---- composeBriefing: emits recognizable content for all five sections ----
    _results pushBack ["composeBriefing body contains the MISSION section (OBJECTIVE)", ("OBJECTIVE:" in _slotBody)];
    _results pushBack ["composeBriefing body contains the SITUATION section (LOCATION/AREA)", ("LOCATION:" in _slotBody && {"AREA:" in _slotBody})];
    _results pushBack ["composeBriefing body contains the INTEL section (INTEL/THREATS)", ("INTEL:" in _slotBody && {"THREATS:" in _slotBody})];
    _results pushBack ["composeBriefing body contains the EXECUTION section (RULES OF ENGAGEMENT)", ("RULES OF ENGAGEMENT:" in _slotBody)];

    // ---- Parity: fixed KILL_CAPTURE context reproduces pre-refactor output ----
    private _parityContext = createHashMapFromArray [
        ["missionType", "raid_kill_capture"],
        ["unitVoice", "GENERIC"],
        ["slots", createHashMapFromArray [
            ["locationName", "Kavala"],
            ["relativeDesc", "in Kavala"],
            ["areaDesc", "urban area"],
            ["strengthEstimate", "estimated light resistance"],
            ["targetBlock", "<t font='PuristaBold'>TARGETS:</t><br/>- Officer: A high ranking officer<br/><br/>"],
            ["garrisonEstimate", "Light garrison presence (fireteam-sized)"],
            ["patrolEstimate", "No patrol activity reported"],
            ["threatText", "No special threats identified."]
        ]]
    ];

    private _expectedBody =
        "<t size='1.2'>MISSION BRIEFING</t><br/><br/>" +
        "<t font='PuristaBold'>OBJECTIVE:</t> Locate and eliminate or capture a high-value target.<br/><br/>" +
        "<t font='PuristaBold'>LOCATION:</t> Kavala, in Kavala.<br/><br/>" +
        "<t font='PuristaBold'>AREA:</t> Operating from a urban area, estimated light resistance.<br/><br/>" +
        "<t font='PuristaBold'>TARGETS:</t><br/>- Officer: A high ranking officer<br/><br/>" +
        "<t font='PuristaBold'>INTEL:</t><br/>" +
        "- Light garrison presence (fireteam-sized)<br/>" +
        "- No patrol activity reported<br/><br/>" +
        "<t font='PuristaBold'>THREATS:</t><br/>No special threats identified.<br/><br/>" +
        "<t font='PuristaBold'>RULES OF ENGAGEMENT:</t> Weapons free. Eliminate or capture the HVT and RTB for debrief.";

    private _actualBody = [_parityContext] call DSC_core_fnc_composeBriefing;

    _results pushBack ["composeBriefing parity: fixed KILL_CAPTURE context matches pre-refactor byte-for-byte output", (_actualBody == _expectedBody)];

    _results
}];

INFO("Registered test suite: briefing_composer (fnc_composeBriefing sections + slot interpolation + parity)");

// ----------------------------------------------------------------------------
// Tier-1 test suite: Interaction Sites (Campaign Overhaul Session 5)
// ----------------------------------------------------------------------------
// Pure-function tests only — no world objects, no addAction, no network, per
// docs/campaign_overhaul/session_05_interaction_site.md's Tier-1 test plan.
_testSuites set ["interaction_site", {
    private _results = [];

    // ---- buildInteractionSiteConfig: defaults on empty input ----
    private _emptySite = [createHashMap] call DSC_core_fnc_buildInteractionSiteConfig;

    _results pushBack ["buildInteractionSiteConfig fills a non-empty id", ((_emptySite get "id") isEqualType "" && {(_emptySite get "id") != ""})];
    _results pushBack ["buildInteractionSiteConfig defaults radius > 0", ((_emptySite get "radius") > 0)];

    private _emptyDuration = _emptySite get "duration";
    _results pushBack ["buildInteractionSiteConfig duration is a 2-element ascending pair", (_emptyDuration isEqualType [] && {count _emptyDuration == 2} && {(_emptyDuration select 0) <= (_emptyDuration select 1)})];

    _results pushBack ["buildInteractionSiteConfig defaults tangibility to abstract", ((_emptySite get "tangibility") == "abstract")];
    _results pushBack ["buildInteractionSiteConfig defaults requireCount to [1,1]", ((_emptySite get "requireCount") isEqualTo [1, 1])];
    _results pushBack ["buildInteractionSiteConfig defaults state to ARMED", ((_emptySite get "state") == "ARMED")];

    // ---- buildInteractionSiteConfig: caller-supplied fields preserved verbatim ----
    private _customRaw = createHashMapFromArray [
        ["id", "my_custom_id"],
        ["action", "Custom Action"],
        ["radius", 25],
        ["tangibility", "focalProp"]
    ];
    private _customSite = [_customRaw] call DSC_core_fnc_buildInteractionSiteConfig;

    _results pushBack ["buildInteractionSiteConfig preserves caller id", ((_customSite get "id") == "my_custom_id")];
    _results pushBack ["buildInteractionSiteConfig preserves caller action", ((_customSite get "action") == "Custom Action")];
    _results pushBack ["buildInteractionSiteConfig preserves caller radius", ((_customSite get "radius") == 25)];
    _results pushBack ["buildInteractionSiteConfig preserves caller tangibility", ((_customSite get "tangibility") == "focalProp")];

    // ---- SITES_INTERACTED completion logic (via fnc_evaluateCompletion, same as other named types) ----
    private _stateIncomplete = createHashMapFromArray [["sitesCompleted", 0], ["sitesRequired", 1]];
    private _resultIncomplete = ["SITES_INTERACTED", _stateIncomplete] call DSC_core_fnc_evaluateCompletion;
    _results pushBack ["SITES_INTERACTED: 0/1 is incomplete", !(_resultIncomplete get "complete")];

    private _stateComplete = createHashMapFromArray [["sitesCompleted", 1], ["sitesRequired", 1]];
    private _resultComplete = ["SITES_INTERACTED", _stateComplete] call DSC_core_fnc_evaluateCompletion;
    _results pushBack ["SITES_INTERACTED: 1/1 is complete", (_resultComplete get "complete")];

    private _stateNofM1 = createHashMapFromArray [["sitesCompleted", 2], ["sitesRequired", 3]];
    private _resultNofM1 = ["SITES_INTERACTED", _stateNofM1] call DSC_core_fnc_evaluateCompletion;
    _results pushBack ["SITES_INTERACTED: 2/3 is incomplete (N-of-M not yet met)", !(_resultNofM1 get "complete")];

    private _stateNofM2 = createHashMapFromArray [["sitesCompleted", 3], ["sitesRequired", 3]];
    private _resultNofM2 = ["SITES_INTERACTED", _stateNofM2] call DSC_core_fnc_evaluateCompletion;
    _results pushBack ["SITES_INTERACTED: 3/3 is complete", (_resultNofM2 get "complete")];

    private _resultMissingKeys = ["SITES_INTERACTED", createHashMap] call DSC_core_fnc_evaluateCompletion;
    _results pushBack ["SITES_INTERACTED: missing keys default to incomplete, no error", !(_resultMissingKeys get "complete")];

    // ---- buildIntelTokenFromSite ----
    private _mockSite = createHashMapFromArray [["id", "site_test_1"], ["pos", [1000, 2000, 0]]];
    private _mockContext = createHashMapFromArray [
        ["type", "HVT_LOCATION"],
        ["source", "SSE"],
        ["confidence", 0.6]
    ];
    private _builtToken = [_mockContext, _mockSite] call DSC_core_fnc_buildIntelTokenFromSite;

    _results pushBack ["buildIntelTokenFromSite preserves type/source/confidence", ((_builtToken get "type") == "HVT_LOCATION" && {(_builtToken get "source") == "SSE"} && {(_builtToken get "confidence") == 0.6})];

    private _builtPayload = _builtToken get "payload";
    _results pushBack ["buildIntelTokenFromSite seeds payload from site pos", ((_builtPayload get "pos") isEqualTo [1000, 2000, 0])];
    _results pushBack ["buildIntelTokenFromSite seeds payload with site id", ((_builtPayload get "siteId") == "site_test_1")];

    // Confidence clamping is intelAdd's job, not the builder's — an
    // out-of-range value must pass through unclamped here.
    private _outOfRangeContext = createHashMapFromArray [["type", "generic"], ["confidence", 1.5]];
    private _outOfRangeToken = [_outOfRangeContext, _mockSite] call DSC_core_fnc_buildIntelTokenFromSite;
    _results pushBack ["buildIntelTokenFromSite does not clamp confidence (that's intelAdd's job)", ((_outOfRangeToken get "confidence") == 1.5)];

    // ---- resolveSearchYield ----
    private _yieldMatch = ["opFor", "opFor"] call DSC_core_fnc_resolveSearchYield;
    private _yieldBaseline = ["opFor", ""] call DSC_core_fnc_resolveSearchYield;
    _results pushBack ["resolveSearchYield: matching roles yield SERIES", ((_yieldMatch get "scope") == "SERIES")];
    _results pushBack ["resolveSearchYield: matching roles yield confidence above the AREA baseline", ((_yieldMatch get "confidence") > (_yieldBaseline get "confidence"))];

    private _yieldMismatch = ["opFor", "irregulars"] call DSC_core_fnc_resolveSearchYield;
    _results pushBack ["resolveSearchYield: mismatched roles yield AREA", ((_yieldMismatch get "scope") == "AREA")];

    private _yieldNoSeries = ["opFor", ""] call DSC_core_fnc_resolveSearchYield;
    _results pushBack ["resolveSearchYield: no active series always yields AREA regardless of victim role", ((_yieldNoSeries get "scope") == "AREA")];

    _results
}];

INFO("Registered test suite: interaction_site (site config defaults + SITES_INTERACTED + token builder + search yield)");

INFO("Server debug layer initialized (tablet events registered)");

