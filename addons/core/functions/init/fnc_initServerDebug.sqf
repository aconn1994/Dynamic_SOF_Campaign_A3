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

// ----------------------------------------------------------------------------
// Tier-1 test suite: SWEEP archetype (Campaign Overhaul Session 6)
// ----------------------------------------------------------------------------
// fnc_sweepEvaluateTick and fnc_resolveSweepYield are fully PURE (no world
// reads) per docs/campaign_overhaul/session_06_sweep_archetype.md §8. Every
// case below uses hand-built samples/tuning/state hashmaps; the one
// deliberate exception is the intelAdd round-trip, same pattern as the
// intel_ledger/series_arbiter suites' intentional ledger-write assertions.
_testSuites set ["sweep", {
    private _results = [];

    // HashMap has no binary "+" merge operator — only unary +_hashmap (deep
    // copy). This local helper is the override-on-top-of-base idiom used
    // elsewhere in this codebase (fnc_generateMission's own tuning merge,
    // fnc_interactionSiteFire's tokenContext copy): deep-copy the base, then
    // `set` each override key over it.
    private _withOverride = {
        params ["_base", "_overrides"];
        private _r = +_base;
        { _r set [_x, _y] } forEach _overrides;
        _r
    };

    // ================================================================
    // A. Completion conditions (through fnc_evaluateCompletion)
    // ================================================================
    private _observedBelow = createHashMapFromArray [["observedSeconds", 50], ["observeRequired", 120]];
    _results pushBack ["OBSERVED: false below threshold", !((["OBSERVED", _observedBelow] call DSC_core_fnc_evaluateCompletion) get "complete")];

    private _observedAt = createHashMapFromArray [["observedSeconds", 120], ["observeRequired", 120]];
    _results pushBack ["OBSERVED: true at exactly threshold (boundary)", ((["OBSERVED", _observedAt] call DSC_core_fnc_evaluateCompletion) get "complete")];

    private _observedCompromised = createHashMapFromArray [["observedSeconds", 120], ["observeRequired", 120], ["compromised", true]];
    _results pushBack ["OBSERVED: completes even when compromised is true (detection is not a fail)", ((["OBSERVED", _observedCompromised] call DSC_core_fnc_evaluateCompletion) get "complete")];

    private _sweptNMinus1 = createHashMapFromArray [["sweptPoints", 2], ["sweptRequired", 3]];
    _results pushBack ["AREA_SWEPT: false at N-1 of N", !((["AREA_SWEPT", _sweptNMinus1] call DSC_core_fnc_evaluateCompletion) get "complete")];

    private _sweptAtN = createHashMapFromArray [["sweptPoints", 3], ["sweptRequired", 3]];
    private _sweptAboveN = createHashMapFromArray [["sweptPoints", 4], ["sweptRequired", 3]];
    _results pushBack ["AREA_SWEPT: true at N and N+1", ((["AREA_SWEPT", _sweptAtN] call DSC_core_fnc_evaluateCompletion) get "complete") && {((["AREA_SWEPT", _sweptAboveN] call DSC_core_fnc_evaluateCompletion) get "complete")}];

    private _sweptZeroRequired = createHashMapFromArray [["sweptPoints", 0], ["sweptRequired", 0]];
    _results pushBack ["AREA_SWEPT: false when sweptRequired == 0 (no spurious auto-complete)", !((["AREA_SWEPT", _sweptZeroRequired] call DSC_core_fnc_evaluateCompletion) get "complete")];

    _results pushBack ["TARGET_IDENTIFIED: false when the key is absent", !((["TARGET_IDENTIFIED", createHashMap] call DSC_core_fnc_evaluateCompletion) get "complete")];

    private _targetIdSet = createHashMapFromArray [["targetIdentified", true]];
    _results pushBack ["TARGET_IDENTIFIED: true when set", ((["TARGET_IDENTIFIED", _targetIdSet] call DSC_core_fnc_evaluateCompletion) get "complete")];

    _results pushBack ["All three return false against an empty state hashmap (no error)", (
        !((["OBSERVED", createHashMap] call DSC_core_fnc_evaluateCompletion) get "complete") &&
        {!((["AREA_SWEPT", createHashMap] call DSC_core_fnc_evaluateCompletion) get "complete")} &&
        {!((["TARGET_IDENTIFIED", createHashMap] call DSC_core_fnc_evaluateCompletion) get "complete")}
    )];

    // ================================================================
    // B. fnc_sweepEvaluateTick
    // ================================================================
    private _tuningBase = createHashMapFromArray [
        ["observeMax", 600], ["compromiseThreshold", 0.6], ["compromiseTicks", 2], ["pidDwellRequired", 5]
    ];

    private _dwellSample = createHashMapFromArray [
        ["dt", 5], ["observerDistance", 300], ["hasLOS", true], ["maxKnowsAbout", 0], ["newSweptPoints", 0], ["pidInRange", false]
    ];
    private _afterDwell = [_dwellSample, _tuningBase, createHashMap] call DSC_core_fnc_sweepEvaluateTick;
    _results pushBack ["sweepEvaluateTick: dwell accumulates by dt when in band + LOS + not compromised", ((_afterDwell get "observedSeconds") == 5)];

    private _noLosSample = [_dwellSample, createHashMapFromArray [["hasLOS", false]]] call _withOverride;
    private _afterNoLos = [_noLosSample, _tuningBase, createHashMap] call DSC_core_fnc_sweepEvaluateTick;
    _results pushBack ["sweepEvaluateTick: no accumulation without LOS", ((_afterNoLos get "observedSeconds") == 0)];

    private _beyondMaxSample = [_dwellSample, createHashMapFromArray [["observerDistance", 700]]] call _withOverride;
    private _afterBeyondMax = [_beyondMaxSample, _tuningBase, createHashMap] call DSC_core_fnc_sweepEvaluateTick;
    _results pushBack ["sweepEvaluateTick: no accumulation beyond observeMax", ((_afterBeyondMax get "observedSeconds") == 0)];

    private _closeSample = [_dwellSample, createHashMapFromArray [["observerDistance", 5]]] call _withOverride;
    private _afterClose = [_closeSample, _tuningBase, createHashMap] call DSC_core_fnc_sweepEvaluateTick;
    _results pushBack ["sweepEvaluateTick: accumulation DOES occur at very close range (no minimum distance)", ((_afterClose get "observedSeconds") == 5)];

    private _compromisedState = createHashMapFromArray [["compromised", true]];
    private _afterWhileCompromised = [_dwellSample, _tuningBase, _compromisedState] call DSC_core_fnc_sweepEvaluateTick;
    _results pushBack ["sweepEvaluateTick: no accumulation while compromised", ((_afterWhileCompromised get "observedSeconds") == 0)];

    // Latch: two above-threshold ticks (compromiseTicks=2) compromises; a
    // subsequent below-threshold tick leaves it true (never clears).
    private _hotSample = createHashMapFromArray [["dt", 1], ["observerDistance", -1], ["hasLOS", false], ["maxKnowsAbout", 0.8], ["newSweptPoints", 0], ["pidInRange", false]];
    private _coldSample = [_hotSample, createHashMapFromArray [["maxKnowsAbout", 0.1]]] call _withOverride;
    private _latchTick1 = [_hotSample, _tuningBase, createHashMap] call DSC_core_fnc_sweepEvaluateTick;
    private _latchTick2 = [_hotSample, _tuningBase, _latchTick1] call DSC_core_fnc_sweepEvaluateTick;
    private _latchTick3 = [_coldSample, _tuningBase, _latchTick2] call DSC_core_fnc_sweepEvaluateTick;

    _results pushBack ["sweepEvaluateTick: latch sets compromised at compromiseTicks", ((_latchTick1 get "compromised") == false) && {(_latchTick2 get "compromised") == true}];
    _results pushBack ["sweepEvaluateTick: latch never clears on a subsequent below-threshold tick", ((_latchTick3 get "compromised") == true)];

    // Anti-twitch: a single above-threshold tick with compromiseTicks=2 does
    // not compromise; the streak resets on a below-threshold tick.
    _results pushBack ["sweepEvaluateTick: anti-twitch - single above-threshold tick does not compromise", ((_latchTick1 get "compromised") == false)];
    private _resetTick = [_coldSample, _tuningBase, _latchTick1] call DSC_core_fnc_sweepEvaluateTick;
    _results pushBack ["sweepEvaluateTick: anti-twitch - streak resets on a below-threshold tick", ((_resetTick get "compromiseStreak") == 0) && {(_resetTick get "compromised") == false}];

    // bestProximity monotone non-increasing across ticks.
    private _proxTick1 = [_dwellSample, _tuningBase, createHashMap] call DSC_core_fnc_sweepEvaluateTick;
    private _fartherSample = [_dwellSample, createHashMapFromArray [["observerDistance", 500]]] call _withOverride;
    private _proxTick2 = [_fartherSample, _tuningBase, _proxTick1] call DSC_core_fnc_sweepEvaluateTick;
    _results pushBack ["sweepEvaluateTick: bestProximity is monotone non-increasing across ticks", ((_proxTick1 get "bestProximity") == 300) && {(_proxTick2 get "bestProximity") == 300}];

    // Threshold honored from tuning — identical sample, two thresholds, two outcomes.
    private _midSample = [_hotSample, createHashMapFromArray [["maxKnowsAbout", 0.5]]] call _withOverride;
    private _tuningLowThresh = [_tuningBase, createHashMapFromArray [["compromiseThreshold", 0.3], ["compromiseTicks", 1]]] call _withOverride;
    private _tuningHighThresh = [_tuningBase, createHashMapFromArray [["compromiseThreshold", 0.9], ["compromiseTicks", 1]]] call _withOverride;
    private _lowThreshResult = [_midSample, _tuningLowThresh, createHashMap] call DSC_core_fnc_sweepEvaluateTick;
    private _highThreshResult = [_midSample, _tuningHighThresh, createHashMap] call DSC_core_fnc_sweepEvaluateTick;
    _results pushBack ["sweepEvaluateTick: threshold is honored from tuning (same sample, different thresholds, different outcomes)", ((_lowThreshResult get "compromised") == true) && {(_highThreshResult get "compromised") == false}];

    // convertRequested true only on the latching tick.
    _results pushBack ["sweepEvaluateTick: convertRequested is false on a non-latching tick", ((_latchTick1 get "convertRequested") == false)];
    _results pushBack ["sweepEvaluateTick: convertRequested is true only on the latching tick", ((_latchTick2 get "convertRequested") == true) && {(_latchTick3 get "convertRequested") == false}];

    // convertRequested false when an already-compromised state is passed in (idempotent).
    private _alreadyCompromised = createHashMapFromArray [["compromised", true], ["compromiseStreak", 5]];
    private _idempotentTick = [_hotSample, _tuningBase, _alreadyCompromised] call DSC_core_fnc_sweepEvaluateTick;
    _results pushBack ["sweepEvaluateTick: convertRequested is false when an already-compromised state is passed in", ((_idempotentTick get "convertRequested") == false)];

    // ================================================================
    // C. fnc_resolveSweepYield
    // ================================================================
    private _yieldTuningObserve = createHashMapFromArray [
        ["observeRequired", 120], ["observeMax", 600], ["observeIdeal", 250], ["sweptRequired", 0],
        ["patrolObserveSeconds", 180], ["dwellW", 0.5], ["proxW", 0.3], ["covW", 0.2],
        ["baseConfidence", 0.9], ["stealthPenalty", 0.5], ["confMin", 0.05], ["confMax", 0.95]
    ];

    private _noCollectionFacts = createHashMapFromArray [["observedSeconds", 0], ["sweptPoints", 0], ["targetIdentified", false]];
    _results pushBack ["resolveSweepYield: no collection at all returns []", ([_noCollectionFacts, _yieldTuningObserve] call DSC_core_fnc_resolveSweepYield) isEqualTo []];

    private _cleanFacts = createHashMapFromArray [
        ["observedSeconds", 120], ["bestProximity", 250], ["compromised", false],
        ["sweptPoints", 0], ["targetIdentified", false], ["locationId", "loc_test"], ["pidSubjectRef", ""], ["seriesId", ""]
    ];
    private _cleanTokens = [_cleanFacts, _yieldTuningObserve] call DSC_core_fnc_resolveSweepYield;
    private _cleanLayout = _cleanTokens select { (_x get "type") == "AREA_LAYOUT" };
    _results pushBack ["resolveSweepYield: full dwell + ideal proximity + undetected yields AREA_LAYOUT with confidence >= 0.7", (count _cleanLayout == 1) && {((_cleanLayout select 0) get "confidence") >= 0.7}];

    private _compromisedFacts = [_cleanFacts, createHashMapFromArray [["compromised", true]]] call _withOverride;
    private _compromisedTokens = [_compromisedFacts, _yieldTuningObserve] call DSC_core_fnc_resolveSweepYield;
    private _compromisedLayout = _compromisedTokens select { (_x get "type") == "AREA_LAYOUT" };
    private _cleanConfidence = (_cleanLayout select 0) get "confidence";
    private _compromisedConfidence = (_compromisedLayout select 0) get "confidence";
    _results pushBack ["resolveSweepYield: compromised run - AREA_LAYOUT confidence strictly lower and still > 0", (_compromisedConfidence < _cleanConfidence) && {_compromisedConfidence > 0}];

    private _compromisedHasQrf = (_compromisedTokens findIf { (_x get "type") == "QRF_POSTURE" }) != -1;
    private _cleanHasQrf = (_cleanTokens findIf { (_x get "type") == "QRF_POSTURE" }) != -1;
    _results pushBack ["resolveSweepYield: compromised run emits QRF_POSTURE, clean run does not", _compromisedHasQrf && {!_cleanHasQrf}];

    private _closerFacts = [_cleanFacts, createHashMapFromArray [["bestProximity", 250]]] call _withOverride;
    private _fartherFacts = [_cleanFacts, createHashMapFromArray [["bestProximity", 500]]] call _withOverride;
    private _closerConfidence = ((([_closerFacts, _yieldTuningObserve] call DSC_core_fnc_resolveSweepYield) select { (_x get "type") == "AREA_LAYOUT" }) select 0) get "confidence";
    private _fartherConfidence = ((([_fartherFacts, _yieldTuningObserve] call DSC_core_fnc_resolveSweepYield) select { (_x get "type") == "AREA_LAYOUT" }) select 0) get "confidence";
    _results pushBack ["resolveSweepYield: proximity monotonicity - closer bestProximity yields confidence >=", (_closerConfidence >= _fartherConfidence)];

    private _halfDwellFacts = [_cleanFacts, createHashMapFromArray [["observedSeconds", 60]]] call _withOverride;
    private _doubleDwellFacts = [_cleanFacts, createHashMapFromArray [["observedSeconds", 240]]] call _withOverride;
    private _halfDwellConfidence = ((([_halfDwellFacts, _yieldTuningObserve] call DSC_core_fnc_resolveSweepYield) select { (_x get "type") == "AREA_LAYOUT" }) select 0) get "confidence";
    private _doubleDwellConfidence = ((([_doubleDwellFacts, _yieldTuningObserve] call DSC_core_fnc_resolveSweepYield) select { (_x get "type") == "AREA_LAYOUT" }) select 0) get "confidence";
    _results pushBack ["resolveSweepYield: dwell monotonicity + saturation - 2x observeRequired scores same as 1x, both >= half-dwell", (_doubleDwellConfidence == _cleanConfidence) && {_doubleDwellConfidence >= _halfDwellConfidence}];

    private _pidFacts = [_cleanFacts, createHashMapFromArray [["targetIdentified", true], ["pidSubjectRef", "hvt_test_subject"]]] call _withOverride;
    private _pidTokens = [_pidFacts, _yieldTuningObserve] call DSC_core_fnc_resolveSweepYield;
    private _hvtIdentityTokens = _pidTokens select { (_x get "type") == "HVT_IDENTITY" };
    _results pushBack ["resolveSweepYield: targetIdentified emits HVT_IDENTITY with the supplied subjectRef", (count _hvtIdentityTokens == 1) && {((_hvtIdentityTokens select 0) get "subjectRef") == "hvt_test_subject"}];
    _results pushBack ["resolveSweepYield: HVT_IDENTITY absent when targetIdentified is false", (_cleanTokens findIf { (_x get "type") == "HVT_IDENTITY" }) == -1];

    // sweptRequired == 0 -> weights renormalize, no divide-by-zero, strictly
    // greater than the naive un-renormalized value.
    private _dwellFactorNaive = 0 max (1 min (120 / 120));
    private _proxFactorNaive = 0 max (1 min ((600 - 250) / (600 - 250)));
    private _naiveQuality = (0.5 * _dwellFactorNaive + 0.3 * _proxFactorNaive + 0.2 * 0) / 1.0;
    private _naiveConfidence = 0.05 max (0.95 min (0.9 * _naiveQuality * 1.0));
    _results pushBack ["resolveSweepYield: sweptRequired == 0 renormalizes weights (no divide-by-zero, strictly greater than naive)", (_cleanConfidence > _naiveConfidence) && {_cleanConfidence >= 0.05} && {_cleanConfidence <= 0.95}];

    private _allTokensInRange = (_pidTokens findIf { ((_x get "confidence") < 0.05) || ((_x get "confidence") > 0.95) }) == -1;
    _results pushBack ["resolveSweepYield: every emitted confidence within [confMin, confMax]", _allTokensInRange];

    private _seriesFacts = [_cleanFacts, createHashMapFromArray [["seriesId", "series_test"]]] call _withOverride;
    private _seriesTokens = [_seriesFacts, _yieldTuningObserve] call DSC_core_fnc_resolveSweepYield;
    private _allSeriesScope = (_seriesTokens findIf { (_x get "scope") != "SERIES" }) == -1;
    private _allLocationScope = (_cleanTokens findIf { (_x get "scope") != "LOCATION" }) == -1;
    _results pushBack ["resolveSweepYield: seriesId != '' -> all tokens scope SERIES, '' -> LOCATION", _allSeriesScope && _allLocationScope];

    _results pushBack ["resolveSweepYield: AREA_LAYOUT.subjectRef equals the location id passed in", ((_cleanLayout select 0) get "subjectRef") == "loc_test"];

    // Round-trip: one emitted token through fnc_intelAdd then fnc_intelQuery
    // lands in DSC_intelLedger (deliberate impure assertion).
    [] call DSC_core_fnc_intelInit;
    {
        [_x] call DSC_core_fnc_intelAdd;
    } forEach _cleanTokens;
    private _ledgerAfterSweep = missionNamespace getVariable ["DSC_intelLedger", createHashMap];
    private _sweepRoundTrip = [_ledgerAfterSweep, createHashMapFromArray [["subjectRef", "loc_test"], ["type", "AREA_LAYOUT"]]] call DSC_core_fnc_intelQuery;
    _results pushBack ["resolveSweepYield: emitted token round-trips through fnc_intelAdd/fnc_intelQuery into DSC_intelLedger", (count _sweepRoundTrip) > 0];

    // ================================================================
    // D. Builder reuse (fnc_buildIntelTokenFromSite with a synthetic site)
    // ================================================================
    private _syntheticSite = createHashMapFromArray [["pos", [5000, 6000, 0]], ["id", "sweep_run_test_1"]];
    private _syntheticToken = [createHashMapFromArray [["type", "AREA_LAYOUT"], ["confidence", 0.8]], _syntheticSite] call DSC_core_fnc_buildIntelTokenFromSite;
    private _syntheticPayload = _syntheticToken get "payload";
    _results pushBack ["buildIntelTokenFromSite: synthetic site (pos+id only) enriches payload.pos/grid/siteId", (
        ((_syntheticPayload get "pos") isEqualTo [5000, 6000, 0]) &&
        {(_syntheticPayload get "siteId") == "sweep_run_test_1"} &&
        {(_syntheticPayload get "grid") isEqualType ""}
    )];

    _results
}];

INFO("Registered test suite: sweep (completion conditions + evaluateTick + resolveSweepYield + builder reuse)");

// ----------------------------------------------------------------------------
// Tier-1 test suite: Structure Taxonomy (Ambient World Overhaul, Session 01)
// ----------------------------------------------------------------------------
// docs/overhauls/ambient_world/session_01_structure_taxonomy.md "Approved
// Mini-Spec" §A7 — 25 assertions. The catalog is forcibly rebuilt once at the
// top (deterministic baseline for this run) and then re-fetched uncached to
// exercise the cache probe (assertion 12).
_testSuites set ["structure_catalog", {
    private _results = [];

    private _knownCategories = [
        "residential", "commercial", "industrial", "agricultural", "medical",
        "religious", "infrastructure", "port", "airport", "law_enforcement", "military"
    ];
    private _knownFlags = [
        "occupiable", "anchor", "satellite", "military", "sentry_only",
        "hvt_suitable", "hostage_suitable", "ruined", "landmark",
        "infrastructure_node", "sabotage_target", "hackable",
        "workplace", "public_access", "civilian_home"
    ];

    private _subtypes = call DSC_core_fnc_getStructureSubtypes;
    private _catalog = [true] call DSC_core_fnc_getStructureCatalog;

    private _byClass = _catalog get "byClass";
    private _bySubtype = _catalog get "bySubtype";
    private _byCategory = _catalog get "byCategory";
    private _byFlag = _catalog get "byFlag";
    private _main = _catalog get "main";
    private _side = _catalog get "side";
    private _functionalCategories = _catalog get "functionalCategories";
    private _functionalLookup = _catalog get "functionalLookup";
    private _nonOccupiable = _catalog get "nonOccupiable";
    private _nonOccupiableLookup = _catalog get "nonOccupiableLookup";
    private _classKeys = keys _byClass;

    // ================================================================
    // Vocabulary & table integrity
    // ================================================================

    // 1. Every Table 2 class maps to a subtype that exists in Table 1.
    private _subtypeInfoKeys = _catalog get "subtypeInfo";
    private _badSubtypeRef = _classKeys findIf { !(((_byClass get _x) get "subtype") in _subtypeInfoKeys) };
    _results pushBack ["every Table 2 class maps to a subtype that exists in Table 1", (_badSubtypeRef == -1)];

    // 2. Every Table 1 category is in the fixed 11-category vocabulary.
    private _badCategory = _subtypes findIf { !((_x select 1) in _knownCategories) };
    _results pushBack ["every Table 1 subtype's category is in the known 11-category vocabulary", (_badCategory == -1)];

    // 3. Every flag in Table 1, and every override token applied in Table 2, is in the known flag vocabulary.
    private _badTable1Flag = -1;
    {
        private _rowFlags = _x select 3;
        private _hit = _rowFlags findIf { !(_x in _knownFlags) };
        if (_hit != -1) exitWith { _badTable1Flag = _hit };
    } forEach _subtypes;
    private _badByFlagKey = (keys _byFlag) findIf { !(_x in _knownFlags) };
    _results pushBack ["every flag in Table 1 and every byFlag key is in the known flag vocabulary", (_badTable1Flag == -1 && {_badByFlagKey == -1})];

    // 4. No classname appears twice in Table 2.
    _results pushBack ["no classname appears twice in Table 2", ((_catalog get "duplicateClassCount") == 0)];

    // 5. Every subtype has a non-empty displayName.
    private _badDisplayName = _subtypes findIf { (_x select 2) == "" };
    _results pushBack ["every subtype has a non-empty displayName", (_badDisplayName == -1)];

    // 6. Every category has >=1 subtype and >=1 class.
    private _categoryCoverageOk = true;
    {
        private _cat = _x;
        private _subtypeCount = count (_byCategory getOrDefault [_cat, []]);
        private _classCount = (count (_functionalCategories getOrDefault [_cat, []])) + (count (_nonOccupiable getOrDefault [_cat, []]));
        if (_subtypeCount == 0 || {_classCount == 0}) exitWith { _categoryCoverageOk = false };
    } forEach _knownCategories;
    _results pushBack ["every category has >=1 subtype and >=1 class", _categoryCoverageOk];

    // 21. Every Table 1 subtype is used by >=1 Table 2 class.
    private _unusedSubtype = _subtypes findIf {
        private _subtypeName = _x select 0;
        !(_subtypeName in _bySubtype) || { (count (_bySubtype get _subtypeName)) == 0 }
    };
    _results pushBack ["every Table 1 subtype is used by >=1 Table 2 class (no dead subtype)", (_unusedSubtype == -1)];

    // 23. Table 2 class count >= 560.
    private _tableRowCount = _catalog get "tableRowCount";
    _results pushBack ["Table 2 class count >= 560", (_tableRowCount >= 560)];

    // ================================================================
    // Derivation correctness
    // ================================================================

    // 7. main UNION side covers every occupiable class.
    private _occupiableClasses = _classKeys select { "occupiable" in ((_byClass get _x) get "flags") };
    private _uncoveredOccupiable = _occupiableClasses findIf { !(_x in _main) && {!(_x in _side)} };
    _results pushBack ["main UNION side covers every occupiable class", (_uncoveredOccupiable == -1)];

    // 8. main INTERSECT side is empty.
    private _mainSideOverlap = _main findIf { _x in _side };
    _results pushBack ["main INTERSECT side is empty", (_mainSideOverlap == -1)];

    // 9. functionalLookup UNION nonOccupiableLookup is total over Table 2.
    private _functionallyInvisible = _classKeys findIf { !(_x in _functionalLookup) && {!(_x in _nonOccupiableLookup)} };
    _results pushBack ["functionalLookup/nonOccupiableLookup together cover every class (no functionally invisible class)", (_functionallyInvisible == -1)];

    // 10. nonOccupiableLookup and functionalLookup are disjoint.
    private _lookupOverlap = (keys _nonOccupiableLookup) findIf { _x in _functionalLookup };
    _results pushBack ["nonOccupiableLookup and functionalLookup are disjoint", (_lookupOverlap == -1)];

    // 20. Zero classes resolve to category "" or "unknown".
    private _badResolvedCategory = _classKeys findIf {
        private _cat = (_byClass get _x) get "category";
        (_cat == "") || (_cat == "unknown")
    };
    _results pushBack ['zero classes resolve to category "" or "unknown"', (_badResolvedCategory == -1)];

    // 22. The shim returns all 11 legacy keys, correct types, main/side parity.
    private _shim = call DSC_core_fnc_getStructureTypes;
    private _shimKeys = keys _shim;
    private _expectedShimKeys = [
        "main", "side", "mainMilitary", "mainCivilian", "sideMilitary", "sideCivilian",
        "exclusions", "functionalCategories", "functionalLookup", "nonOccupiable", "nonOccupiableLookup"
    ];
    private _missingShimKey = _expectedShimKeys findIf { !(_x in _shimKeys) };
    private _shimArrayTypesOk = (
        (_shim get "main") isEqualType [] && {(_shim get "side") isEqualType []} &&
        {(_shim get "mainMilitary") isEqualType []} && {(_shim get "mainCivilian") isEqualType []} &&
        {(_shim get "sideMilitary") isEqualType []} && {(_shim get "sideCivilian") isEqualType []} &&
        {(_shim get "exclusions") isEqualType []}
    );
    private _shimHashTypesOk = (
        (_shim get "functionalCategories") isEqualType createHashMap && {(_shim get "functionalLookup") isEqualType createHashMap} &&
        {(_shim get "nonOccupiable") isEqualType createHashMap} && {(_shim get "nonOccupiableLookup") isEqualType createHashMap}
    );
    _results pushBack ["shim returns all 11 legacy keys with correct types", ((count _shimKeys) == 11 && {_missingShimKey == -1} && _shimArrayTypesOk && _shimHashTypesOk)];
    _results pushBack ["shim main isEqualTo (mainMilitary + mainCivilian)", ((_shim get "main") isEqualTo ((_shim get "mainMilitary") + (_shim get "mainCivilian")))];
    _results pushBack ["shim side isEqualTo (sideMilitary + sideCivilian)", ((_shim get "side") isEqualTo ((_shim get "sideMilitary") + (_shim get "sideCivilian")))];

    // ================================================================
    // Flag semantics
    // ================================================================

    // 13. Every hvt_suitable class is also occupiable.
    private _hvtNotOccupiable = _classKeys findIf {
        private _f = (_byClass get _x) get "flags";
        ("hvt_suitable" in _f) && {!("occupiable" in _f)}
    };
    _results pushBack ["every hvt_suitable class is also occupiable", (_hvtNotOccupiable == -1)];

    // 14. No class is both hvt_suitable and sentry_only.
    private _hvtAndSentry = _classKeys findIf {
        private _f = (_byClass get _x) get "flags";
        ("hvt_suitable" in _f) && {"sentry_only" in _f}
    };
    _results pushBack ["no class is both hvt_suitable and sentry_only", (_hvtAndSentry == -1)];

    // 15. hvt_suitable SUBSET hostage_suitable.
    private _hvtNotHostage = _classKeys findIf {
        private _f = (_byClass get _x) get "flags";
        ("hvt_suitable" in _f) && {!("hostage_suitable" in _f)}
    };
    _results pushBack ["hvt_suitable is a subset of hostage_suitable", (_hvtNotHostage == -1)];

    // 16. Every sabotage_target/hackable class is also infrastructure_node.
    private _affordanceNotInfraNode = _classKeys findIf {
        private _f = (_byClass get _x) get "flags";
        (("sabotage_target" in _f) || {"hackable" in _f}) && {!("infrastructure_node" in _f)}
    };
    _results pushBack ["every sabotage_target/hackable class is also infrastructure_node", (_affordanceNotInfraNode == -1)];

    // 17. Every class in category military carries flag military (B23 invariant).
    private _militaryCategoryNotFlagged = _classKeys findIf {
        private _rec = _byClass get _x;
        ((_rec get "category") == "military") && {!("military" in (_rec get "flags"))}
    };
    _results pushBack ["every class in category military carries flag military (B23)", (_militaryCategoryNotFlagged == -1)];

    // 18. >=1 class outside category military carries flag military (crossover proof).
    private _crossoverCount = {
        private _rec = _byClass get _x;
        ((_rec get "category") != "military") && {"military" in (_rec get "flags")}
    } count _classKeys;
    _results pushBack [">=1 class outside category military carries flag military (crossover)", (_crossoverCount > 0)];

    // 19. No affiliation flag exists in the vocabulary (B25).
    _results pushBack ["no affiliation flag (law_enforcement/police/insurgent) exists in the vocabulary (B25)", (
        !("law_enforcement" in _knownFlags) && {!("police" in _knownFlags)} && {!("insurgent" in _knownFlags)}
    )];

    // 25. Derived-flag sanity.
    private _civilianHomeCount = count (_byFlag getOrDefault ["civilian_home", []]);
    private _workplaceCount = count (_byFlag getOrDefault ["workplace", []]);
    private _publicAccessCount = count (_byFlag getOrDefault ["public_access", []]);
    private _ruinedWithCivilianHome = (_byFlag getOrDefault ["ruined", []]) findIf { _x in (_byFlag getOrDefault ["civilian_home", []]) };
    _results pushBack ["derived-flag sanity: civilian_home/workplace/public_access each have >=1 class, no ruined class has civilian_home", (
        _civilianHomeCount > 0 && {_workplaceCount > 0} && {_publicAccessCount > 0} && {_ruinedWithCivilianHome == -1}
    )];

    // ================================================================
    // Behavior
    // ================================================================

    // 11. fnc_resolveStructureInfo on an unknown class returns a well-formed record and does not throw.
    private _unknownInfo = ["Land_DSC_TestHarness_NotARealClassname_F"] call DSC_core_fnc_resolveStructureInfo;
    _results pushBack ["resolveStructureInfo on an unknown class returns a well-formed record", (
        ((_unknownInfo get "subtype") == "unknown") &&
        {(_unknownInfo get "category") == "unknown"} &&
        {(_unknownInfo get "displayName") != ""} &&
        {(_unknownInfo get "flags") isEqualTo []}
    )];

    // 12. Catalog build is idempotent and cached - a second call returns the same reference.
    private _handleA = [] call DSC_core_fnc_getStructureCatalog;
    _handleA set ["__dscTestSentinel", "probe"];
    private _handleB = [] call DSC_core_fnc_getStructureCatalog;
    private _cacheIsSameRef = ((_handleB getOrDefault ["__dscTestSentinel", ""]) == "probe");
    _handleA deleteAt "__dscTestSentinel";
    _results pushBack ["catalog build is idempotent and cached (second call returns the same reference)", _cacheIsSameRef];

    // 24. Canary set - fixed classes resolve exactly as stated.
    private _canaries = [
        ["Land_School_01_F", "school", "commercial", []],
        ["Land_CoalPlant_01_MainBuilding_F", "power_station", "infrastructure", ["sabotage_target"]],
        ["Land_FuelStation_Build_F", "fuel_station", "commercial", []],
        ["Land_ReservoirTank_V1_F", "water_facility", "infrastructure", ["!occupiable"]],
        ["Land_spp_Tower_F", "solar_array", "infrastructure", []],
        ["Land_Hangar_F", "hangar", "airport", ["military"]],
        ["Land_i_Barracks_V1_F", "barracks", "military", ["military", "hvt_suitable"]],
        ["Land_dp_bigTank_old_F", "storage_tank", "industrial", ["sentry_only", "!hvt_suitable"]],
        ["Land_PoliceStation_01_F", "police_station", "law_enforcement", []],
        ["Land_MedicalTent_01_MTP_closed_F", "field_hospital", "medical", ["military"]],
        ["Land_Communication_F", "comms_tower", "infrastructure", ["hackable", "!occupiable"]],
        ["Land_Slum_House01_F", "slum", "residential", ["civilian_home"]]
    ];
    {
        _x params ["_canaryClass", "_expSubtype", "_expCategory", "_expFlagChecks"];
        private _rec = _byClass getOrDefault [_canaryClass, createHashMap];
        private _recFlags = _rec getOrDefault ["flags", []];
        private _flagChecksOk = (_expFlagChecks findIf {
            if ((_x select [0, 1]) == "!") then {
                (_x select [1, (count _x) - 1]) in _recFlags
            } else {
                !(_x in _recFlags)
            }
        }) == -1;
        private _canaryOk = (
            ((_rec getOrDefault ["subtype", ""]) == _expSubtype) &&
            {(_rec getOrDefault ["category", ""]) == _expCategory} &&
            _flagChecksOk
        );
        _results pushBack [format ["canary: %1 resolves to subtype=%2 category=%3 with expected flags", _canaryClass, _expSubtype, _expCategory], _canaryOk];
    } forEach _canaries;

    // ================================================================
    // Coverage report (printed, not asserted)
    // ================================================================
    private _coverageLines = [];
    {
        private _cat = _x;
        private _catClassCount = (count (_functionalCategories getOrDefault [_cat, []])) + (count (_nonOccupiable getOrDefault [_cat, []]));
        private _catSubtypeCount = count (_byCategory getOrDefault [_cat, []]);
        _coverageLines pushBack format ["%1: %2 classes / %3 subtypes", _cat, _catClassCount, _catSubtypeCount];
    } forEach _knownCategories;
    private _coverageMsg = format [
        "structure_catalog coverage - total classes: %1, total subtypes: %2 (pre-session baseline: 565) | %3",
        (count _byClass), (count _subtypes), (_coverageLines joinString " | ")
    ];
    INFO(_coverageMsg);

    // NOTE: hand count of "// REVIEW" rows in fnc_getStructureCatalog.sqf's
    // Table 2 at authoring time. Update if REVIEW rows are added/resolved by
    // hand-editing — this is a reporting aid, not an assertion.
    private _reviewRowCount = 41;
    INFO_1("structure_catalog coverage - rows still carrying // REVIEW: %1",_reviewRowCount);

    _results
}];

INFO("Registered test suite: structure_catalog (Ambient World Overhaul Session 01 - structure taxonomy)");

INFO("Server debug layer initialized (tablet events registered)");

