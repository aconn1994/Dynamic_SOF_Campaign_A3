#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_sweepConvert
 * Description:
 *     Detection -> convert hook for the SWEEP archetype (Campaign Overhaul
 *     Session 6 §6). Fires exactly once, when fnc_sweepEvaluateTick returns
 *     convertRequested — guarded here by completionState.converted so a
 *     duplicate call is a harmless no-op.
 *
 *     Does NOT regenerate anything. The AO already exists; conversion is a
 *     MUTATION of the live mission. DSC_currentMission is a hashmap
 *     (reference type) and the mission loop's captured local is the SAME
 *     object, so mutating completionState/completion/markers in place here
 *     is observed by the loop at its next debrief — exactly how
 *     fnc_interactionSiteFire's sitesCompleted bump works.
 *
 *     Two convert targets, selected by the archetype's "convertOn" field:
 *       "RAID"  - completionExpr = (original condition already met) OR
 *                 (hvt down/captured). You're blown; finish it the hard
 *                 way or leave with what you banked.
 *       "EXFIL" - completionExpr = (original condition already met) OR
 *                 (every live player beyond exfilDistance of the
 *                 objective). Break contact and keep the partial yield.
 *     Both disjunctions PRESERVE the original success path — a player who
 *     had already banked enough observation is not retroactively failed by
 *     being seen afterward.
 *
 *     The enemy-side reaction is deliberately nothing extra: the unit that
 *     spotted the player is already stamped into the C2 network, and C2
 *     files the contact report / raises the node / dispatches recall-or-QRF
 *     through its own existing ladder. A bespoke chase here would duplicate
 *     fnc_c2Respond and violate the "keep flee/convert coarse" rule (§12.2).
 *
 *     Does NOT call fnc_advanceCampaign (§10's decoupling landmine) — the
 *     series learns about a conversion through the standardized outcome
 *     (fnc_buildMissionOutcome's "converted"/"convertedTo" passthrough
 *     fields), at the normal OUTCOME seam, same as everything else.
 *
 * Arguments:
 *     0: _ctx <HASHMAP> -
 *        "runId"            <STRING>  The sweep run this conversion belongs
 *                                     to (logging only).
 *        "convertOn"        <STRING>  "RAID" | "EXFIL".
 *        "exfilDistance"    <NUMBER>  Break-contact radius for "EXFIL".
 *        "objectivePos"     <ARRAY>   Position the exfil distance is
 *                                     measured from.
 *        "garrisonClusters" <ARRAY>   AO garrison clusters, for redrawing
 *                                     full compound markers on reveal.
 *        "location"         <HASHMAP> Location object, for marker drawing.
 *
 * Return Value:
 *     <BOOL> - true if conversion was applied, false if there was nothing
 *              to convert or it was already converted.
 *
 * Example:
 *     if (_state get "convertRequested") then {
 *         [_convertCtx] call DSC_core_fnc_sweepConvert;
 *     };
 */

params [
    ["_ctx", createHashMap, [createHashMap]]
];

private _runId = _ctx getOrDefault ["runId", ""];
private _convertOn = _ctx getOrDefault ["convertOn", "RAID"];
private _exfilDistance = _ctx getOrDefault ["exfilDistance", 400];
private _objectivePos = _ctx getOrDefault ["objectivePos", [0, 0, 0]];
private _garrisonClusters = _ctx getOrDefault ["garrisonClusters", []];
private _location = _ctx getOrDefault ["location", createHashMap];

private _mission = missionNamespace getVariable ["DSC_currentMission", createHashMap];
if (_mission isEqualTo createHashMap) exitWith {
    WARNING_1("sweepConvert - no active mission to convert (runId=%1)",_runId);
    false
};

private _completionState = _mission get "completionState";

if (_completionState getOrDefault ["converted", false]) exitWith {
    LOG_1("sweepConvert - already converted, ignoring duplicate request (runId=%1)",_runId);
    false
};

// ----------------------------------------------------------------------------
// Swap the completion condition in place.
// ----------------------------------------------------------------------------
private _originalCompletion = _mission get "completion";

private _newCompletion = switch (_convertOn) do {
    case "RAID": {
        createHashMapFromArray [
            ["type", "SWEEP_CONVERTED_RAID"],
            ["completionExpr", {
                params ["_state"];
                private _orig = _state getOrDefault ["sweepOriginalCompletion", "OBSERVED"];
                private _origResult = [_orig, _state] call DSC_core_fnc_evaluateCompletion;
                private _origComplete = _origResult get "complete";
                private _hvt = _state getOrDefault ["hvt", objNull];
                private _hvtDown = (!isNull _hvt) && { !alive _hvt || { captive _hvt } };
                _origComplete || _hvtDown
            }],
            ["successMsg", "Objective compromised - mission completed by force"],
            ["partialMsg", "Objective compromised - target not neutralized"]
        ]
    };
    case "EXFIL": {
        createHashMapFromArray [
            ["type", "SWEEP_CONVERTED_EXFIL"],
            ["completionExpr", {
                params ["_state"];
                private _orig = _state getOrDefault ["sweepOriginalCompletion", "OBSERVED"];
                private _origResult = [_orig, _state] call DSC_core_fnc_evaluateCompletion;
                private _origComplete = _origResult get "complete";
                private _exfilPos = _state getOrDefault ["sweepObjectivePos", [0, 0, 0]];
                private _exfilDist = _state getOrDefault ["sweepExfilDistance", 400];
                private _players = allPlayers select { alive _x };
                private _brokeContact = (_players isNotEqualTo []) && { (_players findIf { (_x distance2D _exfilPos) < _exfilDist }) == -1 };
                _origComplete || _brokeContact
            }],
            ["successMsg", "Broke contact - partial intelligence secured"],
            ["partialMsg", "Compromised and unable to break contact"]
        ]
    };
    default {
        _originalCompletion
    };
};

_completionState set ["sweepOriginalCompletion", _originalCompletion];
_completionState set ["sweepObjectivePos", _objectivePos];
_completionState set ["sweepExfilDistance", _exfilDistance];
_completionState set ["converted", true];
_completionState set ["convertedTo", _convertOn];

_mission set ["completion", _newCompletion];

// ----------------------------------------------------------------------------
// Reveal the markers — once compromised there's no reason to withhold layout.
// ----------------------------------------------------------------------------
{ deleteMarker _x } forEach (_mission getOrDefault ["markers", []]);
private _newMarkers = [_garrisonClusters, _location] call DSC_core_fnc_drawCompoundMarkers;
_mission set ["markers", _newMarkers];

// ----------------------------------------------------------------------------
// Player-facing feedback (unconditional — mission feedback stays ungated).
// ----------------------------------------------------------------------------
systemChat format ["Contact! Position compromised - mission converted to %1", _convertOn];

missionNamespace setVariable ["DSC_currentMission", _mission, true];

INFO_2("sweepConvert - mission converted to %1 (runId=%2)",_convertOn,_runId);

true
