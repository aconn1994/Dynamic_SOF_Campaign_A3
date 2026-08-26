#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_startSeries
 * Description:
 *     Constructs a `DSC_activeSeries` state hashmap (`.crush/campaign-overhaul.md`
 *     §2 shape: threadType, stages[], stageIndex, branchState, subjectRefs,
 *     narrative, intelRequirements).
 *
 *     Called with no arguments (or `_threadType == "ONE_OFF"` and no explicit
 *     `_stages`), this builds the **ONE_OFF thread factory** (§11 decision 3):
 *     a single stage whose `missionTemplate` is byte-for-byte identical to
 *     `fnc_selectMission`'s existing random-template fallback (KILL_CAPTURE /
 *     AFO_rural). There is no pure-random fallback path in the final design —
 *     when no narrative thread is active, the arbiter starts this lightweight
 *     one-off instead, so a deployment with no series configured produces
 *     exactly today's missions. A one-off has empty `onSuccess`/`onFailure`,
 *     so `fnc_advanceCampaign` clears it after its single stage completes.
 *
 *     Real narrative threads (Session 5+) call this with an explicit
 *     `_threadType` and `_stages` DAG (§5.1 stage schema) to skip the
 *     one-off factory.
 *
 * Arguments:
 *     0: _threadType <STRING> - (Optional, default "ONE_OFF")
 *     1: _stages <ARRAY> - (Optional) DAG of stage hashmaps (§5.1 schema).
 *        Default [] triggers the ONE_OFF factory when _threadType is
 *        "ONE_OFF"; for any other _threadType, an empty array is used as-is
 *        (caller is expected to supply real stages).
 *     2: _subjectRefs <HASHMAP> - (Optional) the faction/location/entity this
 *        thread is about. Default createHashMap.
 *     3: _narrative <HASHMAP> - (Optional) overarching briefing thread data.
 *        Default createHashMap.
 *     4: _intelRequirements <ARRAY> - (Optional) ledger tokens gating the
 *        next stage. Default [].
 *
 * Return Value:
 *     <HASHMAP> - the new DSC_activeSeries state object (NOT published to
 *        missionNamespace — callers own that write, same convention as
 *        fnc_intelInit/fnc_intelAdd).
 *
 * Example:
 *     // Default: a fresh ONE_OFF thread emitting today's random template
 *     private _series = [] call DSC_core_fnc_startSeries;
 *
 *     // A real 2-stage narrative thread
 *     private _series = ["DISMANTLE_CELL", [_stageFind, _stageCapture]]
 *         call DSC_core_fnc_startSeries;
 */

params [
    ["_threadType", "ONE_OFF", [""]],
    ["_stages", [], [[]]],
    ["_subjectRefs", createHashMap, [createHashMap]],
    ["_narrative", createHashMap, [createHashMap]],
    ["_intelRequirements", [], [[]]]
];

// ============================================================================
// ONE_OFF thread factory (§11 decision 3)
// ============================================================================
// Must stay in lockstep with fnc_selectMission's random-template fallback
// (type=KILL_CAPTURE, missionProfile=AFO_rural) — that parity is the whole
// invisibility guarantee for this session.
if (_threadType == "ONE_OFF" && {_stages isEqualTo []}) then {
    private _oneOffTemplate = createHashMapFromArray [
        ["type", "KILL_CAPTURE"],
        ["missionProfile", "AFO_rural"]
    ];

    _stages = [createHashMapFromArray [
        ["id", "one_off"],
        ["entryConditions", []],
        ["missionTemplate", _oneOffTemplate],
        ["onSuccess", ""],
        ["onFailure", ""],
        ["intelReward", []],
        ["narrativeBeat", ""]
    ]];

    INFO("startSeries - no narrative thread queued, started ONE_OFF (today's random template)");
};

createHashMapFromArray [
    ["threadType", _threadType],
    ["stages", _stages],
    ["stageIndex", 0],
    ["branchState", createHashMap],
    ["subjectRefs", _subjectRefs],
    ["narrative", _narrative],
    ["intelRequirements", _intelRequirements]
]
