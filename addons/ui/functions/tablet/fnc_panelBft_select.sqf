#include "..\..\script_component.hpp"
#include "..\..\dialog\idc.hpp"
/*
 * Function: DSC_ui_fnc_panelBft_select
 * Description:
 *     MouseButtonClick handler for the BFT map control.
 *
 *     Diagnosed engine behaviour for map controls hosted inside a controls
 *     group: `ctrlMapWorldToScreen` returns coordinates as if the map were
 *     positioned at safezone origin (0,0), while `drawIcon` paints icons
 *     relative to the host group's actual safezone position. The constant
 *     offset between the two equals the host group's origin
 *     (`ctrlPosition` of BftPanel). Subtracting that origin from each
 *     track's projected position aligns it with where the icon is actually
 *     drawn, so we can hit-test the raw click event coordinates against
 *     the compensated position.
 *
 *     A small one-line diag_log per click captures click/playerScreen/hit
 *     so any future drift on a different aspect ratio or UI scale is easy
 *     to spot in the RPT.
 *
 * Arguments (MouseButtonClick event):
 *     0: _ctrl   <CONTROL>  - map control
 *     1: _button <NUMBER>   - 0 left, 1 right
 *     2: _xPos   <NUMBER>   - click X in safezone units
 *     3: _yPos   <NUMBER>   - click Y in safezone units
 */

// Pick radius in safezone units. ~0.045 = roughly an icon-radius worth of
// forgiveness on a 1080p screen; clicks slightly off an icon still register.
#define DSC_BFT_PICK_RADIUS 0.045

params [
    ["_ctrl",   controlNull, [controlNull]],
    ["_button", 0,           [0]],
    ["_xPos",   0,           [0]],
    ["_yPos",   0,           [0]]
];

if (isNull _ctrl) exitWith {};
if (_button != 0) exitWith {};        // left-click only

private _display = ctrlParent _ctrl;
if (isNull _display) exitWith {};

// ----------------------------------------------------------------------------
// Host group origin — used to compensate the WorldToScreen/drawIcon mismatch
// ----------------------------------------------------------------------------
private _grpCtrl = _display displayCtrl DSC_TABLET_IDC_BFT_PANEL;
private _grpPos  = if (!isNull _grpCtrl) then { ctrlPosition _grpCtrl } else { [0,0,1,1] };
_grpPos params ["_gx", "_gy", "_gw", "_gh"];

private _click = [_xPos, _yPos];

// ----------------------------------------------------------------------------
// Hit-test: project each track, compensate by group origin, compare in
// safezone-distance space against the raw click event.
// ----------------------------------------------------------------------------
private _tracks   = [] call DSC_ui_fnc_panelBft_buildTracks;
private _best     = createHashMap;
private _bestDist = DSC_BFT_PICK_RADIUS;

{
    private _t    = _x;
    private _wpos = _t getOrDefault ["position", [0,0,0]];
    private _spos = _ctrl ctrlMapWorldToScreen _wpos;
    if (count _spos >= 2) then {
        private _sposActual = [(_spos select 0) - _gx, (_spos select 1) - _gy];
        private _d = _click distance _sposActual;
        if (_d < _bestDist) then {
            _bestDist = _d;
            _best     = _t;
        };
    };
} forEach _tracks;

// ----------------------------------------------------------------------------
// Diagnostic log
// ----------------------------------------------------------------------------
private _playerScreen = _ctrl ctrlMapWorldToScreen (getPosATL player);
private _playerActual = if (count _playerScreen >= 2) then {
    [(_playerScreen select 0) - _gx, (_playerScreen select 1) - _gy]
} else { [] };

diag_log format [
    "DSC: bftSelect click=(%1,%2) grpOrigin=(%3,%4) playerActual=%5 playerDist=%6 hit=%7 hitDist=%8 (pickRadius=%9)",
    _xPos toFixed 4, _yPos toFixed 4,
    _gx toFixed 4, _gy toFixed 4,
    _playerActual,
    (if (_playerActual isEqualTo []) then { -1 } else { _click distance _playerActual }) toFixed 4,
    _best getOrDefault ["id", "<none>"],
    _bestDist toFixed 4,
    DSC_BFT_PICK_RADIUS
];

// ----------------------------------------------------------------------------
// Apply selection
// ----------------------------------------------------------------------------
if (_best isEqualTo createHashMap) exitWith {
    [_display] call DSC_ui_fnc_panelBft_clearSelection;
};

private _id = _best getOrDefault ["id", ""];
_display setVariable ["DSC_bftSelectedId", _id];

[_display, _best] call DSC_ui_fnc_panelBft_populateInfo;
