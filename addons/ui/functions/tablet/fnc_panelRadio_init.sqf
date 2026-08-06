#include "..\..\script_component.hpp"
#include "..\..\dialog\idc.hpp"
/*
 * Function: DSC_ui_fnc_panelRadio_init
 * Description:
 *     C2 Sprint F.4 — initializes the Radio Feed panel.
 *
 *     Sets the filter to a known state, attaches the auto-refresh loop once,
 *     and paints the first frame. Called on tab switch.
 *
 *     WHY AUTO-REFRESH
 *
 *     The feed is live data. A player who opens the tablet mid-response and
 *     sits on this page expects to see new intercepts arrive — a static
 *     snapshot would make the page feel broken precisely when it matters most.
 *     The loop is attached to the display via `DSC_radioRefreshAdded` so
 *     re-entering the tab does not stack multiple loops (the same guard pattern
 *     the BFT panel uses for its Draw/click handlers).
 *
 * Arguments:
 *     0: _display <DISPLAY> - tablet display
 */

params [["_display", displayNull, [displayNull]]];
if (isNull _display) exitWith {};

// ----------------------------------------------------------------------------
// Default filter: EARNED
// ----------------------------------------------------------------------------
// The player-honest view is the default. ALL is a debug affordance that shows
// lines the player's coverage never earned, including LOST transmissions —
// useful for verifying the network, misleading as a default because it reveals
// exactly the information the report timer is designed to withhold.
_display setVariable ["DSC_radioShowAll", false];

private _filterBtn = _display displayCtrl DSC_TABLET_IDC_RADIO_FILTER;
if (!isNull _filterBtn) then {
    _filterBtn ctrlSetText "EARNED";
    _filterBtn ctrlSetBackgroundColor [0.20, 0.30, 0.35, 0.85];
};

// ----------------------------------------------------------------------------
// Auto-refresh loop (attached once per display)
// ----------------------------------------------------------------------------
if (isNil { _display getVariable "DSC_radioRefreshAdded" }) then {
    _display setVariable ["DSC_radioRefreshAdded", true];

    [{
        params ["_args", "_handle"];
        _args params ["_disp"];

        // Stop when the dialog closes or the player leaves the tab. Checking
        // the list control's visibility is the cheapest reliable proxy for
        // "this panel is on screen" and avoids a second piece of tab state.
        private _list = _disp displayCtrl DSC_TABLET_IDC_RADIO_LIST;
        if (isNull _disp || {isNull _list} || {!ctrlShown _list}) exitWith {
            [_handle] call CBA_fnc_removePerFrameHandler;
            if (!isNull _disp) then { _disp setVariable ["DSC_radioRefreshAdded", nil] };
        };

        [_disp] call DSC_ui_fnc_panelRadio_refresh;
    }, 2, [_display]] call CBA_fnc_addPerFrameHandler;
};

[_display] call DSC_ui_fnc_panelRadio_refresh;
