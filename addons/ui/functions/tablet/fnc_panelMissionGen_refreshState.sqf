#include "..\..\script_component.hpp"
#include "..\..\dialog\idc.hpp"
/*
 * Function: DSC_ui_fnc_panelMissionGen_refreshState
 * Description:
 *     Reads public mission state globals and renders a multi-line summary
 *     into the panel status text + footer.
 *
 *     Globals consulted:
 *       missionState, missionInProgress, DSC_currentMission,
 *       DSC_missionQueue, DSC_lastMissionOutcome
 *
 * Arguments:
 *     0: _display <DISPLAY> - tablet display
 */

params [["_display", displayNull, [displayNull]]];
if (isNull _display) exitWith {};

private _state         = missionNamespace getVariable ["missionState", "IDLE"];
private _inProgress    = missionNamespace getVariable ["missionInProgress", false];
private _current       = missionNamespace getVariable ["DSC_currentMission", createHashMap];
private _queue         = missionNamespace getVariable ["DSC_missionQueue", []];
private _lastOutcome   = missionNamespace getVariable ["DSC_lastMissionOutcome", createHashMap];

private _currentDesc = "(none)";
if ((_current isNotEqualTo createHashMap) && _inProgress) then {
    private _type = _current getOrDefault ["type", "?"];
    private _loc  = _current getOrDefault ["locationName", _current getOrDefault ["location", "?"]];
    if (_loc isEqualType createHashMap) then { _loc = _loc getOrDefault ["name", "?"]; };
    _currentDesc = format ["%1 @ %2", _type, _loc];
};

private _lastDesc = "(none)";
if (_lastOutcome isNotEqualTo createHashMap) then {
    private _success = _lastOutcome getOrDefault ["success", false];
    private _msg = _lastOutcome getOrDefault ["message", ""];
    _lastDesc = format ["%1 - %2", ["FAIL", "SUCCESS"] select _success, _msg];
};

private _summary = format [
    "STATE: %1   |   IN PROGRESS: %2   |   QUEUED: %3\nCURRENT: %4\nLAST: %5",
    _state, _inProgress, count _queue, _currentDesc, _lastDesc
];

private _statusCtrl = _display displayCtrl DSC_TABLET_IDC_MGEN_STATUS;
_statusCtrl ctrlSetText _summary;

private _footerCtrl = _display displayCtrl DSC_TABLET_IDC_FOOTER_STATE;
_footerCtrl ctrlSetText format ["DSC %1  |  %2  |  Queue: %3", _state, _currentDesc, count _queue];
