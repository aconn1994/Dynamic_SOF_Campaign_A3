#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_addInteractionHandler
 * Description:
 *     Attaches an interaction action menu to a placed mission object
 *     (laptop, document, intel source). When a player triggers the action,
 *     the configured result key is appended to the mission's intel array
 *     and the mission's intelGathered flag is set on completionState. The
 *     completion monitor (fnc_evaluateCompletion + ANY_INTERACTED) then
 *     fires the next tick.
 *
 *     The action is added to the local player by remote-execing addAction
 *     globally; per-client filter ensures the action only appears for
 *     active players.
 *
 *     Result keys are stored as hashmap tokens:
 *       { "type": "GATHER_INTEL", "object": <classname>, "pos": <world pos> }
 *
 *     Series and follow-on missions can read the tokens to seed the next
 *     mission template.
 *
 * Arguments:
 *     0: _object <OBJECT>      Object to make interactable
 *     1: _config <HASHMAP>:
 *        "result"      <STRING>  Result key (e.g. "GATHER_INTEL")
 *        "actionText"  <STRING>  Menu text (default "Recover Intel")
 *        "removeOnUse" <BOOL>    Remove the action after first use (default true)
 *
 * Return Value:
 *     <NUMBER> - addAction id, or -1 on failure.
 */

params [
    ["_object", objNull, [objNull]],
    ["_config", createHashMap, [createHashMap]]
];

if (isNull _object) exitWith {
    diag_log "DSC: addInteractionHandler - null object";
    -1
};

private _result = _config getOrDefault ["result", "GATHER_INTEL"];
private _actionText = _config getOrDefault ["actionText", "Recover Intel"];
private _removeOnUse = _config getOrDefault ["removeOnUse", true];

_object setVariable ["DSC_interactable", true, true];
_object setVariable ["DSC_interactionResult", _result, true];

private _id = _object addAction [
    _actionText,
    {
        params ["_target", "_caller", "_actionId", "_args"];
        _args params ["_resultKey", "_remove"];

        // Don't double-fire
        if (_target getVariable ["DSC_interacted", false]) exitWith {};
        _target setVariable ["DSC_interacted", true, true];

        // Build intel token
        private _token = createHashMapFromArray [
            ["type", _resultKey],
            ["object", typeOf _target],
            ["pos", getPos _target],
            ["time", serverTime]
        ];

        // Update mission state — read, mutate, write back
        private _mission = missionNamespace getVariable ["DSC_currentMission", createHashMap];
        if (_mission isNotEqualTo createHashMap) then {
            private _state = _mission getOrDefault ["completionState", createHashMap];
            _state set ["intelGathered", true];

            private _existing = _mission getOrDefault ["intelTokens", []];
            _existing pushBack _token;
            _mission set ["intelTokens", _existing];
            _mission set ["completionState", _state];
            missionNamespace setVariable ["DSC_currentMission", _mission, true];
        };

        systemChat format ["Intel recovered: %1", _resultKey];
        diag_log format ["DSC: Interaction fired - %1 on %2", _resultKey, typeOf _target];

        if (_remove) then {
            _target removeAction _actionId;
        };
    },
    [_result, _removeOnUse],
    1.5,
    true,
    true,
    "",
    "alive _target && {_this distance _target < 3}"
];

_id
