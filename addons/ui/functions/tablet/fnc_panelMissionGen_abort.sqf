#include "..\..\script_component.hpp"
#include "..\..\dialog\idc.hpp"
/*
 * Function: DSC_ui_fnc_panelMissionGen_abort
 * Description: Fires the server abort event for the active mission.
 *
 * Arguments:
 *     0: _display <DISPLAY> - tablet display
 */

params [["_display", displayNull, [displayNull]]];

if (!(missionNamespace getVariable ["missionInProgress", false])) exitWith {
    if (!isNull _display) then {
        (_display displayCtrl DSC_TABLET_IDC_MGEN_STATUS) ctrlSetText "No active mission to abort.";
    };
    hint "No active mission to abort.";
};

["DSC_tablet_abortMission", [getPlayerUID player, name player]] call CBA_fnc_serverEvent;

if (!isNull _display) then {
    (_display displayCtrl DSC_TABLET_IDC_MGEN_STATUS) ctrlSetText "Abort requested. Waiting for server cleanup...";
};

systemChat "Tablet: abort requested";

// Refresh after a moment.
[{
    [_this select 0] call DSC_ui_fnc_panelMissionGen_refreshState;
}, [_display], 2] call CBA_fnc_waitAndExecute;
