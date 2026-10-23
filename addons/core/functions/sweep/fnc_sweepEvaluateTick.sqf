#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_sweepEvaluateTick
 * Description:
 *     PURE. Per-tick accumulator math for the SWEEP archetype (Campaign
 *     Overhaul Session 6, docs/campaign_overhaul/session_06_sweep_archetype.md
 *     §3). Takes one tick's world sample plus tuning plus the previous
 *     state, returns the next state. No world reads of any kind — the
 *     caller (fnc_sweepMonitor) does all sampling.
 *
 *     Rules, evaluated in this order (see §3 of the mini-spec):
 *       1. Dwell accumulates `dt` iff observerDistance is in [0, observeMax],
 *          hasLOS is true, and the INCOMING compromised flag is false.
 *          Deliberately no minimum distance — closer is better yield AND
 *          higher detection risk; let that tension be emergent.
 *       2. bestProximity is monotone non-increasing: min(bestProximity,
 *          observerDistance), updated alongside dwell.
 *       3. Compromise latches: maxKnowsAbout >= compromiseThreshold
 *          increments compromiseStreak; otherwise the streak resets to 0
 *          (the LATCH itself never resets). When the streak reaches
 *          compromiseTicks and the incoming state was not yet compromised,
 *          compromised flips true and convertRequested is true for THIS
 *          TICK ONLY. This two-stage design (streak-then-latch) is the
 *          direct answer to knowsAbout being binary-ish and twitchy — a
 *          single spurious spike cannot convert the mission, and a real
 *          detection cannot un-convert it two seconds later.
 *       4. PID: pidSeconds accumulates `dt` while pidInRange; latches
 *          targetIdentified at pidDwellRequired cumulative seconds.
 *       5. Swept: sweptPoints += newSweptPoints (sub-points are plain
 *          positions, consumed by the monitor's own distance check).
 *
 *     None of the three new completion conditions (OBSERVED/AREA_SWEPT/
 *     TARGET_IDENTIFIED) read AI state — getting spotted is a complication,
 *     not a fail (§3/§12.2). Compromise here only ever gates/degrades
 *     accumulation and (downstream, in fnc_resolveSweepYield) yield
 *     quality; it never appears in a completion check.
 *
 * Arguments:
 *     0: _sample <HASHMAP> - This tick's world sample:
 *        "dt"               <NUMBER> Measured serverTime delta (NOT the
 *                                    sleep constant).
 *        "observerDistance" <NUMBER> Min 2D distance from any live player
 *                                    to the objective; -1 = no live players.
 *        "hasLOS"           <BOOL>   Best observer has line of sight.
 *        "maxKnowsAbout"    <NUMBER> Max knowsAbout any alive nearby enemy
 *                                    holds on any player.
 *        "newSweptPoints"   <NUMBER> Sub-points newly entered this tick.
 *        "pidInRange"       <BOOL>   A player is within pidRange of a live
 *                                    pidTarget with LOS.
 *     1: _tuning <HASHMAP> - "observeMax", "compromiseThreshold",
 *        "compromiseTicks", "pidDwellRequired". Every number is read from
 *        here, never literal in the body.
 *     2: _state <HASHMAP> - Previous state: "observedSeconds",
 *        "bestProximity", "compromised", "compromiseStreak", "sweptPoints",
 *        "pidSeconds", "targetIdentified", "converted". Missing keys
 *        default safely (empty state is a valid first call).
 *
 * Return Value:
 *     <HASHMAP> - Next state, same keys as _state plus output-only
 *                 "convertRequested" <BOOL> (true only on the tick the
 *                 compromise latch flips).
 *
 * Example:
 *     _state = [_sample, _tuning, _state] call DSC_core_fnc_sweepEvaluateTick;
 *     if (_state get "convertRequested") then { [_ctx] call DSC_core_fnc_sweepConvert };
 */

params [
    ["_sample", createHashMap, [createHashMap]],
    ["_tuning", createHashMap, [createHashMap]],
    ["_state", createHashMap, [createHashMap]]
];

private _dt = _sample getOrDefault ["dt", 0];
private _observerDistance = _sample getOrDefault ["observerDistance", -1];
private _hasLOS = _sample getOrDefault ["hasLOS", false];
private _maxKnowsAbout = _sample getOrDefault ["maxKnowsAbout", 0];
private _newSweptPoints = _sample getOrDefault ["newSweptPoints", 0];
private _pidInRange = _sample getOrDefault ["pidInRange", false];

private _observeMax = _tuning getOrDefault ["observeMax", 600];
private _compromiseThreshold = _tuning getOrDefault ["compromiseThreshold", 0.6];
private _compromiseTicks = _tuning getOrDefault ["compromiseTicks", 2];
private _pidDwellRequired = _tuning getOrDefault ["pidDwellRequired", 5];

private _observedSecondsIn = _state getOrDefault ["observedSeconds", 0];
private _bestProximityIn = _state getOrDefault ["bestProximity", 999999];
private _compromisedIn = _state getOrDefault ["compromised", false];
private _compromiseStreakIn = _state getOrDefault ["compromiseStreak", 0];
private _sweptPointsIn = _state getOrDefault ["sweptPoints", 0];
private _pidSecondsIn = _state getOrDefault ["pidSeconds", 0];
private _targetIdentifiedIn = _state getOrDefault ["targetIdentified", false];
private _convertedIn = _state getOrDefault ["converted", false];

// ----------------------------------------------------------------------------
// 1 + 2: Dwell + bestProximity, gated on the INCOMING compromised flag.
// ----------------------------------------------------------------------------
private _inBand = (_observerDistance >= 0) && { _observerDistance <= _observeMax } && _hasLOS && !_compromisedIn;

private _observedSeconds = _observedSecondsIn;
private _bestProximity = _bestProximityIn;
if (_inBand) then {
    _observedSeconds = _observedSecondsIn + _dt;
    _bestProximity = _bestProximityIn min _observerDistance;
};

// ----------------------------------------------------------------------------
// 3: Compromise latch — streak-then-latch, never clears once true.
// ----------------------------------------------------------------------------
private _compromiseStreak = if (_maxKnowsAbout >= _compromiseThreshold) then {
    _compromiseStreakIn + 1
} else {
    0
};

private _compromised = _compromisedIn;
private _convertRequested = false;
if (!_compromisedIn && { _compromiseStreak >= _compromiseTicks }) then {
    _compromised = true;
    _convertRequested = true;
};

// ----------------------------------------------------------------------------
// 4: PID dwell.
// ----------------------------------------------------------------------------
private _pidSeconds = _pidSecondsIn + ([0, _dt] select _pidInRange);
private _targetIdentified = _targetIdentifiedIn || { _pidSeconds >= _pidDwellRequired };

// ----------------------------------------------------------------------------
// 5: Swept sub-points.
// ----------------------------------------------------------------------------
private _sweptPoints = _sweptPointsIn + _newSweptPoints;

createHashMapFromArray [
    ["observedSeconds", _observedSeconds],
    ["bestProximity", _bestProximity],
    ["compromised", _compromised],
    ["compromiseStreak", _compromiseStreak],
    ["sweptPoints", _sweptPoints],
    ["pidSeconds", _pidSeconds],
    ["targetIdentified", _targetIdentified],
    ["converted", _convertedIn],
    ["convertRequested", _convertRequested]
]
