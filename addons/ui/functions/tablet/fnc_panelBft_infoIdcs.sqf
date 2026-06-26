#include "..\..\script_component.hpp"
#include "..\..\dialog\idc.hpp"
/*
 * Function: DSC_ui_fnc_panelBft_infoIdcs
 * Description:
 *     Returns the canonical list of every IDC that makes up the BFT info
 *     card chrome (background, title, X button, all key labels, all value
 *     labels). switchPanel, panelBft_clearSelection, and panelBft_populateInfo
 *     all need to show/hide these as a unit, so the list lives in one place.
 *
 * Return Value:
 *     <ARRAY of NUMBER> — IDCs in declaration order
 */

[
    DSC_TABLET_IDC_BFT_INFO_BG,
    DSC_TABLET_IDC_BFT_INFO_TITLE,
    DSC_TABLET_IDC_BFT_INFO_CLEAR,
    DSC_TABLET_IDC_BFT_INFO_KEY_CATEGORY,  DSC_TABLET_IDC_BFT_INFO_VAL_CATEGORY,
    DSC_TABLET_IDC_BFT_INFO_KEY_SIDE,      DSC_TABLET_IDC_BFT_INFO_VAL_SIDE,
    DSC_TABLET_IDC_BFT_INFO_KEY_FACTION,   DSC_TABLET_IDC_BFT_INFO_VAL_FACTION,
    DSC_TABLET_IDC_BFT_INFO_KEY_STRENGTH,  DSC_TABLET_IDC_BFT_INFO_VAL_STRENGTH,
    DSC_TABLET_IDC_BFT_INFO_KEY_VEHICLE,   DSC_TABLET_IDC_BFT_INFO_VAL_VEHICLE,
    DSC_TABLET_IDC_BFT_INFO_KEY_DIST,      DSC_TABLET_IDC_BFT_INFO_VAL_DIST,
    DSC_TABLET_IDC_BFT_INFO_KEY_DIST_OBJ,  DSC_TABLET_IDC_BFT_INFO_VAL_DIST_OBJ,
    DSC_TABLET_IDC_BFT_CMD_HEADER,
    DSC_TABLET_IDC_BFT_CMD_TAKE,
    DSC_TABLET_IDC_BFT_CMD_MOVE_HERE,
    DSC_TABLET_IDC_BFT_CMD_MOVE_OBJ,
    DSC_TABLET_IDC_BFT_CMD_QRF,
    DSC_TABLET_IDC_BFT_CMD_RELEASE
]
