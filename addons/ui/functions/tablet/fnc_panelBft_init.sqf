#include "..\..\script_component.hpp"
#include "..\..\dialog\idc.hpp"
/*
 * Function: DSC_ui_fnc_panelBft_init
 * Description:
 *     Initializes (and re-centers) the Blue Force Tracker map. Called on tab
 *     switch and by the RECENTER button.
 *
 *     The Draw EH, the click EH, and the wheel-zoom EH are all attached
 *     once on first init and persist for the life of the dialog. The wheel
 *     handler is the important one for usability: Arma's default map zoom
 *     centers on the cursor, which drifts the map off the player after a
 *     few scrolls and made selection feel broken. Our override calls
 *     ctrlMapAnimAdd with a recomputed scale but ALWAYS re-centers on the
 *     player, so the player marker stays fixed under the cursor's screen
 *     position regardless of zoom.
 *
 *     Re-running just re-centers the map, refreshes the status line, and
 *     clears any stale selection from the previous tab visit.
 *
 * Arguments:
 *     0: _display <DISPLAY> - tablet display
 */

params [["_display", displayNull, [displayNull]]];
if (isNull _display) exitWith {};

private _map = _display displayCtrl DSC_TABLET_IDC_BFT_MAP;
if (isNull _map) exitWith {
    diag_log "DSC: panelBft_init - BFT map control not found";
};

// ----------------------------------------------------------------------------
// Center on player + zoom to a tactical scale (~1.5 km half-width)
// ----------------------------------------------------------------------------
private _playerPos = getPosWorld player;
ctrlMapAnimClear _map;
_map ctrlMapAnimAdd [0, 0.10, _playerPos];
ctrlMapAnimCommit _map;

// ----------------------------------------------------------------------------
// Attach Draw EH once
// ----------------------------------------------------------------------------
if (isNil { _map getVariable "DSC_bftDrawAdded" }) then {
    _map ctrlAddEventHandler ["Draw", {
        _this call DSC_ui_fnc_panelBft_draw;
    }];
    _map setVariable ["DSC_bftDrawAdded", true];
};

// ----------------------------------------------------------------------------
// Attach click EH once
// ----------------------------------------------------------------------------
if (isNil { _map getVariable "DSC_bftClickAdded" }) then {
    _map ctrlAddEventHandler ["MouseButtonClick", {
        _this call DSC_ui_fnc_panelBft_select;
    }];
    _map setVariable ["DSC_bftClickAdded", true];
};

// ----------------------------------------------------------------------------
// Reset filter to ALL on every tab open so re-entry starts in a known state
// ----------------------------------------------------------------------------
_display setVariable ["DSC_bftFilterMine", false];
private _filterBtn = _display displayCtrl DSC_TABLET_IDC_BFT_FILTER;
if (!isNull _filterBtn) then {
    _filterBtn ctrlSetText "ALL";
    _filterBtn ctrlSetBackgroundColor [0.20, 0.30, 0.35, 0.85];
};

// ----------------------------------------------------------------------------
// Reset any stale selection from a prior tab visit
// ----------------------------------------------------------------------------
[_display] call DSC_ui_fnc_panelBft_clearSelection;

// ----------------------------------------------------------------------------
// Status line — count tracks
// ----------------------------------------------------------------------------
private _tracks = missionNamespace getVariable ["DSC_bftTracks", []];
private _squadAlive = (units group player) select { alive _x };

private _statusCtrl = _display displayCtrl DSC_TABLET_IDC_BFT_STATUS;
if (!isNull _statusCtrl) then {
    _statusCtrl ctrlSetText format [
        "%1 tracks  |  squad: %2  |  filter: ALL",
        count _tracks,
        count _squadAlive
    ];
};

diag_log format ["DSC: panelBft_init - %1 tracks, squad=%2", count _tracks, count _squadAlive];
