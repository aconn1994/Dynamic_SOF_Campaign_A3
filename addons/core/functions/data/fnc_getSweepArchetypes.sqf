#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_getSweepArchetypes
 * Description:
 *     Returns the SWEEP archetype registry (Campaign Overhaul Session 6,
 *     docs/campaign_overhaul/session_06_sweep_archetype.md §7). Same shape
 *     family as fnc_getEntityArchetypes/fnc_getInteractionSiteArchetypes —
 *     fnc_generateMission's "SWEEP" case resolves a mission config's
 *     "sweepConfig.archetype" name here to fill in tuning/yield-weight
 *     defaults, which the template's sweepConfig may still override
 *     field-by-field (template overrides always win, same priority order
 *     as everywhere else in the mission config system).
 *
 *     Field reference:
 *       "completion"   <STRING>   OBSERVED | AREA_SWEPT | TARGET_IDENTIFIED.
 *       "convertOn"    <STRING>   "RAID" | "EXFIL" — detection->convert target.
 *       "tuning"       <HASHMAP>  fnc_sweepEvaluateTick inputs plus
 *                                 "patrolObserveSeconds" and "exfilDistance":
 *                                   observeRequired, observeMax, observeIdeal,
 *                                   compromiseThreshold, compromiseTicks,
 *                                   pidDwellRequired, patrolObserveSeconds,
 *                                   exfilDistance.
 *       "yieldWeights" <HASHMAP>  fnc_resolveSweepYield weight inputs:
 *                                   dwellW, proxW, covW, baseConfidence,
 *                                   stealthPenalty, confMin, confMax.
 *       "sweptRequired" <NUMBER|ARRAY> Sub-point count (or [min,max]) for
 *                                 AREA_SWEPT; 0 for archetypes that don't
 *                                 use coverage.
 *       "sweptRadius"  <NUMBER>   Distance to count a sub-point as entered.
 *       "pidRange"     <NUMBER>   LOS+distance radius for TARGET_IDENTIFIED.
 *
 * Arguments: None
 *
 * Return Value:
 *     <HASHMAP> - Archetype name -> archetype hashmap.
 *
 * Example:
 *     private _archetypes = call DSC_core_fnc_getSweepArchetypes;
 *     private _observe = _archetypes get "SR_OBSERVE";
 */

private _defaultTuning = createHashMapFromArray [
    ["observeRequired", 120],
    ["observeMax", 600],
    ["observeIdeal", 250],
    ["compromiseThreshold", 0.6],
    ["compromiseTicks", 2],
    ["pidDwellRequired", 5],
    ["patrolObserveSeconds", 180],
    ["exfilDistance", 400]
];

private _defaultYieldWeights = createHashMapFromArray [
    ["dwellW", 0.5],
    ["proxW", 0.3],
    ["covW", 0.2],
    ["baseConfidence", 0.9],
    ["stealthPenalty", 0.5],
    ["confMin", 0.05],
    ["confMax", 0.95]
];

createHashMapFromArray [

    ["SR_OBSERVE", createHashMapFromArray [
        ["completion", "OBSERVED"],
        ["convertOn", "EXFIL"],
        ["tuning", +_defaultTuning],
        ["yieldWeights", +_defaultYieldWeights],
        ["sweptRequired", 0],
        ["sweptRadius", 40],
        ["pidRange", 300]
    ]],

    ["SR_AREA_SWEEP", createHashMapFromArray [
        ["completion", "AREA_SWEPT"],
        ["convertOn", "RAID"],
        ["tuning", +_defaultTuning],
        ["yieldWeights", +_defaultYieldWeights],
        ["sweptRequired", [3, 5]],
        ["sweptRadius", 40],
        ["pidRange", 300]
    ]],

    ["SR_PID", createHashMapFromArray [
        ["completion", "TARGET_IDENTIFIED"],
        ["convertOn", "RAID"],
        ["tuning", +_defaultTuning],
        ["yieldWeights", +_defaultYieldWeights],
        ["sweptRequired", 0],
        ["sweptRadius", 40],
        ["pidRange", 300]
    ]]
]
