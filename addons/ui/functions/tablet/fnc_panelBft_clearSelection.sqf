#include "..\..\script_component.hpp"
#include "..\..\dialog\idc.hpp"
/*
 * Function: DSC_ui_fnc_panelBft_clearSelection
 * Description:
 *     Drops the active BFT track selection and resets every value label on
 *     the sidebar to the "—" placeholder. The sidebar stays visible — it's
 *     a permanent right-side panel on the BFT tab — only its contents are
 *     reset. Called by the X button on the sidebar and by panelBft_select
 *     when the click lands on empty terrain.
 *
 * Arguments:
 *     0: _display <DISPLAY> - tablet display
 */

params [["_display", displayNull, [displayNull]]];
if (isNull _display) exitWith {};

_display setVariable ["DSC_bftSelectedId", ""];

private _setText = {
    params ["_idc", "_text"];
    private _c = _display displayCtrl _idc;
    if (!isNull _c) then { _c ctrlSetText _text };
};

[DSC_TABLET_IDC_BFT_INFO_TITLE,        "TRACK INFO"] call _setText;
[DSC_TABLET_IDC_BFT_INFO_VAL_CATEGORY, "—"]          call _setText;
[DSC_TABLET_IDC_BFT_INFO_VAL_SIDE,     "—"]          call _setText;
[DSC_TABLET_IDC_BFT_INFO_VAL_FACTION,  "—"]          call _setText;
[DSC_TABLET_IDC_BFT_INFO_VAL_STRENGTH, "—"]          call _setText;
[DSC_TABLET_IDC_BFT_INFO_VAL_VEHICLE,  "—"]          call _setText;
[DSC_TABLET_IDC_BFT_INFO_VAL_DIST,     "—"]          call _setText;
[DSC_TABLET_IDC_BFT_INFO_VAL_DIST_OBJ, "—"]          call _setText;

// Disable BFT-3 command buttons until a commandable track is selected
{
    private _c = _display displayCtrl _x;
    if (!isNull _c) then { _c ctrlEnable false };
} forEach [
    DSC_TABLET_IDC_BFT_CMD_TAKE,
    DSC_TABLET_IDC_BFT_CMD_MOVE_HERE,
    DSC_TABLET_IDC_BFT_CMD_MOVE_OBJ,
    DSC_TABLET_IDC_BFT_CMD_QRF,
    DSC_TABLET_IDC_BFT_CMD_RELEASE
];
