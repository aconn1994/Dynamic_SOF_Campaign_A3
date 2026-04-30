#include "..\..\script_component.hpp"
#include "..\..\dialog\idc.hpp"
/*
 * Function: DSC_ui_fnc_panelMissionGen_sliderLabel
 * Description:
 *     onSliderPosChanged handler — writes the slider's current rounded value
 *     into its companion label. Maps slider IDC -> label IDC. Snaps the
 *     position to the nearest 10% step.
 *
 * Arguments (from engine):
 *     0: _slider <CONTROL>
 *     1: _value  <NUMBER> 0-100
 */

params [["_slider", controlNull], ["_value", 0]];
if (isNull _slider) exitWith {};

private _idc = ctrlIDC _slider;
private _labelIdc = switch (_idc) do {
    case DSC_TABLET_IDC_MGEN_ADV_VEH_ARMED:  { DSC_TABLET_IDC_MGEN_ADV_VEH_ARMED_LBL };
    case DSC_TABLET_IDC_MGEN_ADV_AREA_PRES:  { DSC_TABLET_IDC_MGEN_ADV_AREA_PRES_LBL };
    case DSC_TABLET_IDC_MGEN_ADV_GUARD_COV:  { DSC_TABLET_IDC_MGEN_ADV_GUARD_COV_LBL };
    default { -1 };
};

if (_labelIdc < 0) exitWith {};

// Snap to nearest 10
private _snapped = round (_value / 10) * 10;
if (_snapped != _value) then {
    _slider sliderSetPosition _snapped;
};

private _display = ctrlParent _slider;
private _label = _display displayCtrl _labelIdc;
_label ctrlSetText format ["%1%2", _snapped, "%"];
