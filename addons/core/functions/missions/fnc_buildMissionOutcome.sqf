#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_buildMissionOutcome
 * Description:
 *     Builds a standardized mission outcome hashmap. Every mission ends by
 *     producing this shape so downstream consumers — influence updates,
 *     campaign series, next-mission briefings, intel-as-currency — can read
 *     results without per-mission-type branching.
 *
 *     Outcome is composed from:
 *       - The mission hashmap (entities, objects, completion config)
 *       - The completion evaluation result (from fnc_evaluateCompletion)
 *       - Caller-supplied extras (intelGathered overrides, casualty counts)
 *
 *     Fields with no direct source default sensibly:
 *       - casualties: 0 (player squad death tracking is a future hook)
 *       - evasionRatio: 0 (combat-start tracking is a future hook)
 *
 * Arguments:
 *     0: _mission <HASHMAP> - Mission data from the raid generator
 *     1: _completionResult <HASHMAP> - Result from fnc_evaluateCompletion:
 *        "complete"  <BOOL>   Condition currently satisfied
 *        "success"   <BOOL>   Same as complete (kept for compound symmetry)
 *        "message"   <STRING> Outcome message
 *        "type"      <STRING> Resolved condition type
 *     2: _extras <HASHMAP> - Optional extras (caller may pass empty hashmap):
 *        "partialResult" <BOOL>   Mission ended on timeout/abort
 *        "casualties"    <NUMBER> Player squad casualties
 *        "intelGathered" <ARRAY>  Override intel data
 *        "seriesId"      <STRING> Mission series id (if part of a series)
 *        "seriesIndex"   <NUMBER> Index in the series
 *
 * Return Value:
 *     <HASHMAP> - Standardized outcome:
 *        "success"             <BOOL>
 *        "completionType"      <STRING>  Which condition was evaluated
 *        "partialResult"       <BOOL>    Mission ended on timeout/abort
 *        "message"             <STRING>  Success or partial message
 *        "entitiesEliminated"  <ARRAY>   Entities not alive at end
 *        "entitiesEscaped"     <ARRAY>   Entities still alive (HVTs that fled)
 *        "entitiesCaptured"    <ARRAY>   Entities alive AND captive
 *        "objectsDestroyed"    <ARRAY>   Objects not alive at end
 *        "objectsInteracted"   <ARRAY>   Objects flagged interacted
 *        "intelGathered"       <ARRAY>   Intel data tokens for next mission
 *        "casualties"          <NUMBER>  Player squad casualties
 *        "enemiesKilled"       <NUMBER>  Mission units not alive at end
 *        "duration"            <NUMBER>  Seconds since startTime
 *        "evasionRatio"        <NUMBER>  Combat-free time / total time
 *        "seriesId"            <STRING>
 *        "seriesIndex"         <NUMBER>
 *        "locationId"          <STRING>  Pulled from completionState if set
 *        "locationName"        <STRING>
 *
 * Example:
 *     private _result = [_mission get "completion", _mission get "completionState"]
 *         call DSC_core_fnc_evaluateCompletion;
 *     private _outcome = [_mission, _result, createHashMap]
 *         call DSC_core_fnc_buildMissionOutcome;
 */

params [
    ["_mission", createHashMap, [createHashMap]],
    ["_completionResult", createHashMap, [createHashMap]],
    ["_extras", createHashMap, [createHashMap]]
];

private _state = _mission getOrDefault ["completionState", createHashMap];
private _entities = _mission getOrDefault ["entities", []];
private _objects = _mission getOrDefault ["objects", []];
private _allUnits = _mission getOrDefault ["units", []];
private _startTime = _mission getOrDefault ["startTime", serverTime];

// ----------------------------------------------------------------------------
// Categorize entities
// ----------------------------------------------------------------------------
private _eliminated = _entities select { !alive _x };
private _alive = _entities select { alive _x };
private _captured = _alive select { captive _x };
// "Escaped" only meaningful for non-captive alive entities (i.e. they fled)
private _escaped = _alive select { !captive _x };

// ----------------------------------------------------------------------------
// Categorize objects
// ----------------------------------------------------------------------------
private _objectsDestroyed = _objects select { !alive _x };
// Interacted-with objects flagged via DSC_interacted setVariable when an
// interaction handler fires. Empty until interaction system is wired (future).
private _objectsInteracted = _objects select { _x getVariable ["DSC_interacted", false] };

// ----------------------------------------------------------------------------
// Intel
// ----------------------------------------------------------------------------
private _intelGathered = _extras getOrDefault ["intelGathered", []];
if (_intelGathered isEqualTo []) then {
    private _flag = _state getOrDefault ["intelGathered", false];
    if (_flag isEqualType true) then {
        if (_flag) then {
            // Boolean flag with no payload — emit a sentinel token so series
            // can still detect intel was gathered.
            _intelGathered = [createHashMapFromArray [["type", "generic"]]];
        };
    } else {
        if (_flag isEqualType []) then { _intelGathered = _flag };
    };
};

// ----------------------------------------------------------------------------
// Combat metrics
// ----------------------------------------------------------------------------
private _enemiesKilled = ({ !alive _x } count _allUnits);
private _duration = serverTime - _startTime;

// ----------------------------------------------------------------------------
// Compose outcome
// ----------------------------------------------------------------------------
createHashMapFromArray [
    ["success", _completionResult getOrDefault ["success", false]],
    ["completionType", _completionResult getOrDefault ["type", _mission getOrDefault ["type", "UNKNOWN"]]],
    ["partialResult", _extras getOrDefault ["partialResult", false]],
    ["message", _completionResult getOrDefault ["message", ""]],
    ["entitiesEliminated", _eliminated],
    ["entitiesEscaped", _escaped],
    ["entitiesCaptured", _captured],
    ["objectsDestroyed", _objectsDestroyed],
    ["objectsInteracted", _objectsInteracted],
    ["intelGathered", _intelGathered],
    ["casualties", _extras getOrDefault ["casualties", 0]],
    ["enemiesKilled", _enemiesKilled],
    ["duration", _duration],
    ["evasionRatio", 0],                                          // TODO: requires combat-start tracking
    ["seriesId", _extras getOrDefault ["seriesId", ""]],
    ["seriesIndex", _extras getOrDefault ["seriesIndex", -1]],
    ["locationName", _mission getOrDefault ["locationName", ""]]
]
