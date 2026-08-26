#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_advanceCampaign
 * Description:
 *     Pure series arbiter (`.crush/campaign-overhaul.md` §5.2). The mission
 *     loop calls this at two points, distinguished by `_mode`:
 *
 *     "SELECT" (top of loop, between queue-consume and fnc_selectMission) —
 *         decide the mission template for the upcoming mission. Precedence:
 *           1. Tablet queue (`_payload` already holds the dequeued template;
 *              the queue-consume code itself is untouched — this function
 *              never reads DSC_missionQueue directly).
 *           2. The CURRENT stage of `_activeSeries` (already advanced by a
 *              prior "OUTCOME" call — this mode does NOT re-advance state).
 *           3. A freshly started ONE_OFF thread (§11 decision 3) when no
 *              series exists yet (or one just cleared).
 *         Returns `[_template, _activeSeries]` — `_activeSeries` is only
 *         different from the input when a fresh ONE_OFF had to be started.
 *
 *     "OUTCOME" (after fnc_buildMissionOutcome, only when the mission was
 *         NOT aborted — an aborted mission has no outcome to consume) —
 *         evaluate the current stage against `_payload` (the mission
 *         outcome), branch onSuccess/onFailure, and clear the series when
 *         its stages are exhausted (a ONE_OFF's onSuccess/onFailure are both
 *         "", so it always clears after its single stage — §11 decision 3).
 *         Returns `[_activeSeries, _intelRewardTokens]` — the caller feeds
 *         each token in `_intelRewardTokens` to fnc_intelAdd (this function
 *         never touches the ledger itself, matching the "real callers own
 *         the read/write of the global" convention from fnc_intelAdd).
 *
 *     Fully pure: no global reads, no spawning, no side effects. `_intelLedger`
 *     is threaded through for future entryConditions-gated branching (§5.1);
 *     it is not evaluated by this session's ONE_OFF-only slice, but the
 *     parameter exists now so later stage DAGs don't require a signature
 *     change (§11 decision 1: the onFailure branch must exist even before a
 *     real thread uses it).
 *
 * Arguments:
 *     0: _mode <STRING> - "SELECT" or "OUTCOME"
 *     1: _payload <HASHMAP> - mode-dependent:
 *        SELECT:  the template already produced by the queue-consume step
 *                 (createHashMap sentinel means "queue was empty")
 *        OUTCOME: DSC_lastMissionOutcome (must contain "success" <BOOL>)
 *     2: _activeSeries <HASHMAP> - DSC_activeSeries snapshot (createHashMap
 *        sentinel means "no series active")
 *     3: _intelLedger <HASHMAP> - (Optional) DSC_intelLedger snapshot,
 *        read-only. Default createHashMap.
 *
 * Return Value:
 *     <ARRAY> - mode-dependent:
 *        SELECT:  [_template <HASHMAP>, _activeSeries <HASHMAP>]
 *        OUTCOME: [_activeSeries <HASHMAP>, _intelRewardTokens <ARRAY>]
 *
 * Example:
 *     // Loop top: queue was empty, no series active yet
 *     private _r = ["SELECT", createHashMap, createHashMap] call DSC_core_fnc_advanceCampaign;
 *     _r params ["_template", "_series"];
 *
 *     // After buildMissionOutcome (only when !_aborted)
 *     private _r = ["OUTCOME", _outcome, _series, _ledger] call DSC_core_fnc_advanceCampaign;
 *     _r params ["_series", "_rewardTokens"];
 *     { [_x] call DSC_core_fnc_intelAdd } forEach _rewardTokens;
 */

params [
    ["_mode", "SELECT", [""]],
    ["_payload", createHashMap, [createHashMap]],
    ["_activeSeries", createHashMap, [createHashMap]],
    ["_intelLedger", createHashMap, [createHashMap]]
];

// ============================================================================
// SELECT — decide the template for the upcoming mission.
// ============================================================================
if (_mode == "SELECT") exitWith {
    // 1. Tablet queue outranks series selection unconditionally.
    if (_payload isNotEqualTo createHashMap) exitWith {
        [_payload, _activeSeries]
    };

    // 2. No series active (first run, or previous one just cleared) — start
    //    a fresh ONE_OFF thread.
    if (_activeSeries isEqualTo createHashMap) then {
        _activeSeries = [] call DSC_core_fnc_startSeries;
    };

    private _stages = _activeSeries getOrDefault ["stages", []];
    private _stageIndex = _activeSeries getOrDefault ["stageIndex", 0];

    private _template = createHashMap;
    if (_stageIndex >= 0 && {_stageIndex < count _stages}) then {
        private _stage = _stages select _stageIndex;
        _template = _stage getOrDefault ["missionTemplate", createHashMap];
    };

    // Defensive: a malformed/exhausted series (shouldn't normally reach
    // SELECT — OUTCOME clears exhausted series to createHashMap) degrades to
    // a fresh ONE_OFF rather than handing fnc_selectMission an empty template.
    if (_template isEqualTo createHashMap) then {
        WARNING("advanceCampaign(SELECT) - active series had no usable stage template, starting fresh ONE_OFF");
        _activeSeries = [] call DSC_core_fnc_startSeries;
        _template = ((_activeSeries get "stages") select 0) get "missionTemplate";
    };

    [_template, _activeSeries]
};

// ============================================================================
// OUTCOME — consume a completed mission's outcome, advance/clear the series.
// ============================================================================
if (_mode == "OUTCOME") exitWith {
    // Nothing to advance (e.g. no series was ever started — shouldn't happen
    // once SELECT has run at least once, but stay defensive).
    if (_activeSeries isEqualTo createHashMap) exitWith {
        [createHashMap, []]
    };

    private _stages = _activeSeries getOrDefault ["stages", []];
    private _stageIndex = _activeSeries getOrDefault ["stageIndex", 0];

    if (_stageIndex < 0 || {_stageIndex >= count _stages}) exitWith {
        WARNING("advanceCampaign(OUTCOME) - stageIndex out of range, clearing series");
        [createHashMap, []]
    };

    private _stage = _stages select _stageIndex;
    private _intelReward = _stage getOrDefault ["intelReward", []];
    private _success = _payload getOrDefault ["success", false];

    // §11 decision 1: failure diverts the branch (onFailure), it does not
    // soft-retry the same stage.
    private _nextStageId = ["onFailure", "onSuccess"] select _success;
    _nextStageId = _stage getOrDefault [_nextStageId, ""];

    // No branch target — series complete (always true for a ONE_OFF).
    if (_nextStageId == "") exitWith {
        LOG("advanceCampaign(OUTCOME) - stage exhausted (no branch target), series cleared");
        [createHashMap, _intelReward]
    };

    private _nextIndex = _stages findIf { (_x getOrDefault ["id", ""]) == _nextStageId };

    // Dangling stage reference — degrade to exhausted rather than crash.
    if (_nextIndex == -1) exitWith {
        WARNING_1("advanceCampaign(OUTCOME) - branch target stage id '%1' not found, clearing series",_nextStageId);
        [createHashMap, _intelReward]
    };

    private _branchState = _activeSeries getOrDefault ["branchState", createHashMap];
    private _stageId = _stage getOrDefault ["id", ""];
    private _branchResult = ["failure", "success"] select _success;
    _branchState set [_stageId, _branchResult];

    _activeSeries set ["stageIndex", _nextIndex];
    _activeSeries set ["branchState", _branchState];

    LOG_2("advanceCampaign(OUTCOME) - stage '%1' -> '%2'",_stageId,_nextStageId);

    [_activeSeries, _intelReward]
};

ERROR_1("advanceCampaign - unknown mode '%1'",_mode);
[createHashMap, []]
