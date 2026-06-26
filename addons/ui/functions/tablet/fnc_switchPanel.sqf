#include "..\..\script_component.hpp"
#include "..\..\dialog\idc.hpp"
/*
 * Function: DSC_ui_fnc_switchPanel
 * Description:
 *     Tab dispatcher for the tablet. Toggles ctrlShow on each panel's
 *     controls and repaints the tab button highlights.
 *
 *     Mission Gen is hosted in a single controls group, so its panel
 *     entry holds one IDC. The Blue Force Tracker is composed of several
 *     top-level controls (map + chrome labels + buttons) — its entry holds
 *     the full set so they show/hide as one.
 *
 * Arguments:
 *     0: _display <DISPLAY> - tablet display
 *     1: _panelKey <STRING> - panel identifier ("mission","supports","bft","squad","intel")
 */

params [
    ["_display", displayNull, [displayNull]],
    ["_panelKey", "mission", [""]]
];

if (isNull _display) exitWith {};

// ----------------------------------------------------------------------------
// Panel → controls IDCs. Each panel is shown/hidden as a unit.
// ----------------------------------------------------------------------------
private _bftBase = [
    DSC_TABLET_IDC_BFT_TITLE,
    DSC_TABLET_IDC_BFT_STATUS,
    DSC_TABLET_IDC_BFT_FILTER,
    DSC_TABLET_IDC_BFT_RECENTER,
    DSC_TABLET_IDC_BFT_PANEL,
    DSC_TABLET_IDC_BFT_LEGEND
];

private _panelControls = createHashMapFromArray [
    ["mission", [DSC_TABLET_IDC_MGEN_PANEL]],
    ["bft",     _bftBase + ([] call DSC_ui_fnc_panelBft_infoIdcs)]
];

{
    private _show = (_x == _panelKey);
    {
        private _ctrl = _display displayCtrl _x;
        if (!isNull _ctrl) then { _ctrl ctrlShow _show };
    } forEach _y;
} forEach _panelControls;

// ----------------------------------------------------------------------------
// Tab button highlight (selected = accent, others = dim)
// ----------------------------------------------------------------------------
private _accent = [0.30, 0.75, 0.95, 1.0];
private _dim    = [0.10, 0.13, 0.16, 0.75];

private _tabIdcs = createHashMapFromArray [
    ["mission",  DSC_TABLET_IDC_TAB_MISSION],
    ["supports", DSC_TABLET_IDC_TAB_SUPPORTS],
    ["bft",      DSC_TABLET_IDC_TAB_BFT],
    ["squad",    DSC_TABLET_IDC_TAB_SQUAD],
    ["intel",    DSC_TABLET_IDC_TAB_INTEL]
];

{
    private _ctrl = _display displayCtrl _y;
    if (!isNull _ctrl) then {
        _ctrl ctrlSetBackgroundColor ([_dim, _accent] select (_x == _panelKey));
    };
} forEach _tabIdcs;

// ----------------------------------------------------------------------------
// Per-panel init / refresh
// ----------------------------------------------------------------------------
switch (_panelKey) do {
    case "mission": {
        [_display] call DSC_ui_fnc_panelMissionGen_refreshState;
    };
    case "bft": {
        [_display] call DSC_ui_fnc_panelBft_init;
    };
    default {
        hint format ["'%1' panel not implemented yet.", _panelKey];
    };
};
