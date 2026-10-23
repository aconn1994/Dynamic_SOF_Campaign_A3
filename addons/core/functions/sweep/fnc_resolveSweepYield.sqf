#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_resolveSweepYield
 * Description:
 *     PURE. The SWEEP intel-yield formula (Campaign Overhaul Session 6,
 *     docs/campaign_overhaul/session_06_sweep_archetype.md §4). Facts +
 *     tuning -> an ARRAY of schema-valid PARTIAL intel tokens (no ledger
 *     write, no position enrichment — the caller runs each token through
 *     fnc_buildIntelTokenFromSite then fnc_intelAdd, exactly the Session 5
 *     interaction-site pattern).
 *
 *     Three normalized factors, each clamped to [0,1]:
 *         dwellFactor     = clamp01(observedSeconds / observeRequired)
 *         proximityFactor = clamp01((observeMax - bestProximity) / (observeMax - observeIdeal))
 *         coverageFactor  = clamp01(sweptPoints / sweptRequired)   -- only if sweptRequired > 0
 *         stealthFactor   = compromised ? stealthPenalty : 1.0    -- default 0.5
 *
 *     Combined as a WEIGHTED SUM scaled by a stealth multiplier (not a
 *     triple product — a product collapses: ideal dwell with mediocre
 *     proximity would score like a punishment for a safe standoff):
 *         quality    = (dwellW*dwellFactor + proxW*proximityFactor + covW*coverageFactor)
 *                      / (sum of APPLICABLE weights)
 *         confidence = clamp(baseConfidence * quality * stealthFactor, confMin, confMax)
 *
 *     Weights RENORMALIZE over the applicable factors: if sweptRequired==0
 *     (a pure observe sweep), covW is dropped and the remaining weights are
 *     rescaled — no divide-by-zero, and a pure-observe mission isn't
 *     permanently capped below 100% quality.
 *
 *     confMin is never 0 (a completed objective always yields something);
 *     confMax is never 1.0 (total certainty is reserved for HQ-granted
 *     intel).
 *
 *     Token set emitted (scope is "SERIES" when the caller passed a
 *     non-empty seriesId, else "LOCATION" — every token shares this rule,
 *     unlike the interaction-site registry's per-archetype AREA/LOCATION
 *     defaults):
 *         AREA_LAYOUT          - always, if ANY collection happened. This
 *                                 is the token that unlocks compound
 *                                 markers (§5) — subjectRef MUST be the
 *                                 location id on both the write side here
 *                                 and the marker-gate read side.
 *         ENEMY_STRENGTH       - sweptRequired > 0 and sweep complete.
 *         PATROL_PATTERN       - observedSeconds >= patrolObserveSeconds
 *                                 (default 180) — you watched long enough
 *                                 to see the rotation.
 *         HVT_IDENTITY +
 *         HVT_LOCATION         - targetIdentified (subjectRef = pidSubjectRef).
 *         QRF_POSTURE          - compromised. Deliberately NOT just "less"
 *                                 intel — it changes the mix: you lose
 *                                 layout fidelity but learn their reaction
 *                                 posture.
 *
 *     Returns [] when nothing was collected at all (observedSeconds==0 &&
 *     sweptPoints==0 && !targetIdentified) — a sweep that never collected
 *     anything yields nothing. The "a dryhole always yields" rule applies
 *     to a COMPLETED objective, not a no-show.
 *
 * Arguments:
 *     0: _facts <HASHMAP> - "observedSeconds", "bestProximity",
 *        "compromised", "sweptPoints", "targetIdentified", "locationId",
 *        "pidSubjectRef", "seriesId".
 *     1: _tuning <HASHMAP> - "observeRequired", "observeMax", "observeIdeal",
 *        "sweptRequired", "patrolObserveSeconds", "dwellW", "proxW", "covW",
 *        "baseConfidence", "stealthPenalty", "confMin", "confMax".
 *
 * Return Value:
 *     <ARRAY> - Partial intel tokens (HASHMAPs), not yet written to the
 *               ledger.
 *
 * Example:
 *     private _tokens = [_facts, _tuning] call DSC_core_fnc_resolveSweepYield;
 *     {
 *         private _enriched = [_x, _syntheticSite] call DSC_core_fnc_buildIntelTokenFromSite;
 *         [_enriched] call DSC_core_fnc_intelAdd;
 *     } forEach _tokens;
 */

params [
    ["_facts", createHashMap, [createHashMap]],
    ["_tuning", createHashMap, [createHashMap]]
];

private _observedSeconds = _facts getOrDefault ["observedSeconds", 0];
private _bestProximity = _facts getOrDefault ["bestProximity", 999999];
private _compromised = _facts getOrDefault ["compromised", false];
private _sweptPoints = _facts getOrDefault ["sweptPoints", 0];
private _targetIdentified = _facts getOrDefault ["targetIdentified", false];
private _locationId = _facts getOrDefault ["locationId", ""];
private _pidSubjectRef = _facts getOrDefault ["pidSubjectRef", ""];
private _seriesId = _facts getOrDefault ["seriesId", ""];

if (_observedSeconds == 0 && { _sweptPoints == 0 } && { !_targetIdentified }) exitWith { [] };

private _observeRequired = _tuning getOrDefault ["observeRequired", 120];
private _observeMax = _tuning getOrDefault ["observeMax", 600];
private _observeIdeal = _tuning getOrDefault ["observeIdeal", 250];
private _sweptRequired = _tuning getOrDefault ["sweptRequired", 0];
private _patrolObserveSeconds = _tuning getOrDefault ["patrolObserveSeconds", 180];

private _dwellW = _tuning getOrDefault ["dwellW", 0.5];
private _proxW = _tuning getOrDefault ["proxW", 0.3];
private _covW = _tuning getOrDefault ["covW", 0.2];
private _baseConfidence = _tuning getOrDefault ["baseConfidence", 0.9];
private _stealthPenalty = _tuning getOrDefault ["stealthPenalty", 0.5];
private _confMin = _tuning getOrDefault ["confMin", 0.05];
private _confMax = _tuning getOrDefault ["confMax", 0.95];

private _clamp01 = { 0 max (1 min _this) };

private _dwellFactor = (_observedSeconds / _observeRequired) call _clamp01;

private _proxDenom = _observeMax - _observeIdeal;
private _proximityFactor = if (_proxDenom > 0) then {
    ((_observeMax - _bestProximity) / _proxDenom) call _clamp01
} else {
    0
};

private _hasCoverage = _sweptRequired > 0;
private _coverageFactor = if (_hasCoverage) then {
    (_sweptPoints / _sweptRequired) call _clamp01
} else {
    0
};

private _stealthFactor = [_stealthPenalty, 1.0] select !_compromised;

private _weightSum = _dwellW + _proxW + ([0, _covW] select _hasCoverage);
private _weightedSum = (_dwellW * _dwellFactor) + (_proxW * _proximityFactor) + ([0, _covW * _coverageFactor] select _hasCoverage);
private _quality = if (_weightSum > 0) then { _weightedSum / _weightSum } else { 0 };

private _confidence = _confMin max (_confMax min (_baseConfidence * _quality * _stealthFactor));

private _scope = ["LOCATION", "SERIES"] select (_seriesId != "");

private _tokens = [];

// AREA_LAYOUT — always, since the zero-collection case already exited above.
_tokens pushBack createHashMapFromArray [
    ["type", "AREA_LAYOUT"],
    ["subjectKind", "LOCATION"],
    ["subjectRef", _locationId],
    ["confidence", _confidence],
    ["source", "RECON"],
    ["scope", _scope]
];

if (_hasCoverage && { _sweptPoints >= _sweptRequired }) then {
    _tokens pushBack createHashMapFromArray [
        ["type", "ENEMY_STRENGTH"],
        ["subjectKind", "LOCATION"],
        ["subjectRef", _locationId],
        ["confidence", _confidence],
        ["source", "RECON"],
        ["scope", _scope]
    ];
};

if (_observedSeconds >= _patrolObserveSeconds) then {
    _tokens pushBack createHashMapFromArray [
        ["type", "PATROL_PATTERN"],
        ["subjectKind", "LOCATION"],
        ["subjectRef", _locationId],
        ["confidence", _confidence],
        ["source", "RECON"],
        ["scope", _scope]
    ];
};

if (_targetIdentified) then {
    _tokens pushBack createHashMapFromArray [
        ["type", "HVT_IDENTITY"],
        ["subjectKind", "ENTITY"],
        ["subjectRef", _pidSubjectRef],
        ["confidence", _confidence],
        ["source", "RECON"],
        ["scope", _scope]
    ];
    _tokens pushBack createHashMapFromArray [
        ["type", "HVT_LOCATION"],
        ["subjectKind", "ENTITY"],
        ["subjectRef", _pidSubjectRef],
        ["confidence", _confidence],
        ["source", "RECON"],
        ["scope", _scope]
    ];
};

if (_compromised) then {
    _tokens pushBack createHashMapFromArray [
        ["type", "QRF_POSTURE"],
        ["subjectKind", "LOCATION"],
        ["subjectRef", _locationId],
        ["confidence", _confidence],
        ["source", "RECON"],
        ["scope", _scope]
    ];
};

_tokens
