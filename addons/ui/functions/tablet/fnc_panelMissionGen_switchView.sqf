#include "..\..\script_component.hpp"
#include "..\..\dialog\idc.hpp"
/*
 * Function: DSC_ui_fnc_panelMissionGen_switchView
 * Description:
 *     Toggles between Standard and Advanced views by showing/hiding the
 *     Advanced overlay group. Updates the view-toggle button colors so the
 *     active mode is visually obvious.
 *
 * Arguments:
 *     0: _display <DISPLAY> - tablet display
 *     1: _view <STRING>     - "standard" or "advanced"
 */

params [
    ["_display", displayNull, [displayNull]],
    ["_view", "standard", [""]]
];
if (isNull _display) exitWith {};

private _advCtrl = _display displayCtrl DSC_TABLET_IDC_MGEN_ADV_PANEL;
private _stdBtn  = _display displayCtrl DSC_TABLET_IDC_MGEN_VIEW_STD;
private _advBtn  = _display displayCtrl DSC_TABLET_IDC_MGEN_VIEW_ADV;

private _accent = [0.30, 0.75, 0.95, 1.0];
private _idle   = [0.10, 0.13, 0.16, 0.75];

if (_view == "advanced") then {
    _advCtrl ctrlShow true;
    _stdBtn ctrlSetBackgroundColor _idle;
    _advBtn ctrlSetBackgroundColor _accent;
} else {
    _advCtrl ctrlShow false;
    _stdBtn ctrlSetBackgroundColor _accent;
    _advBtn ctrlSetBackgroundColor _idle;
};

// Remember active view on the display so submit can read it
_display setVariable ["DSC_mgenView", _view];
