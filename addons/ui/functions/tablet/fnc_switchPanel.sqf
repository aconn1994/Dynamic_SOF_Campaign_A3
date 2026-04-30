#include "..\..\script_component.hpp"
/*
 * Function: DSC_ui_fnc_switchPanel
 * Description:
 *     Stub for future tab switching. Phase A only ships the Mission Gen panel,
 *     so non-mission tabs simply hint "coming soon" and return.
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

switch (_panelKey) do {
    case "mission": {
        // Already shown — just refresh state.
        [_display] call DSC_ui_fnc_panelMissionGen_refreshState;
    };
    default {
        hint format ["'%1' panel not implemented yet.", _panelKey];
    };
};
