#include "..\..\script_component.hpp"
#include "..\..\dialog\idc.hpp"
/*
 * Function: DSC_ui_fnc_panelMissionGen_submit
 * Description:
 *     Builds a template via fnc_panelMissionGen_readTemplate and fires the
 *     server-side CBA events:
 *       - "DSC_tablet_abortMission" (if Replace current is checked + active)
 *       - "DSC_tablet_queueMission" (always)
 *
 *     Logs a one-line summary to systemChat + the panel status text.
 *
 * Arguments:
 *     0: _display <DISPLAY>
 */

params [["_display", displayNull, [displayNull]]];
if (isNull _display) exitWith {};

([_display] call DSC_ui_fnc_panelMissionGen_readTemplate) params ["_template", "_replace"];

if (_replace && (missionNamespace getVariable ["missionInProgress", false])) then {
    ["DSC_tablet_abortMission", [getPlayerUID player, name player]] call CBA_fnc_serverEvent;
};

["DSC_tablet_queueMission", [_template, getPlayerUID player, name player]] call CBA_fnc_serverEvent;

// Status feedback — show the keys actually set
private _keys = keys _template;
private _summary = format ["QUEUED with %1 fields: %2%3",
    count _keys,
    _keys joinString ", ",
    [" ", " -- replacing current"] select _replace
];

private _statusCtrl = _display displayCtrl DSC_TABLET_IDC_MGEN_STATUS;
_statusCtrl ctrlSetText _summary;

systemChat format ["Tablet: %1", _summary];

// Refresh after a brief delay so the server has time to log the queued mission.
[{
    [_this select 0] call DSC_ui_fnc_panelMissionGen_refreshState;
}, [_display], 1] call CBA_fnc_waitAndExecute;
