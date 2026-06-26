#include "..\..\script_component.hpp"
#include "..\..\dialog\idc.hpp"
/*
 * Function: DSC_ui_fnc_panelBft_toggleFilter
 * Description:
 *     Toggles the BFT clutter filter between two states:
 *
 *       ALL  (default) — every track from panelBft_buildTracks is drawn
 *                        and selectable.
 *       MINE           — drop ambient garrisons, roving patrols, mission
 *                        attachments, ISR, and unknown categories. Keeps
 *                        the player, the squad, the objective, and any
 *                        track under (or formerly under) player command.
 *
 *     State lives on the tablet display via DSC_bftFilterMine; the draw EH
 *     and click handler both call panelBft_buildTracks which honors it.
 *     Repaints the button label so the player can see the current state.
 *
 * Arguments:
 *     0: _display <DISPLAY> - tablet display
 */

params [["_display", displayNull, [displayNull]]];
if (isNull _display) exitWith {};

private _current = _display getVariable ["DSC_bftFilterMine", false];
private _next    = !_current;
_display setVariable ["DSC_bftFilterMine", _next];

private _btn = _display displayCtrl DSC_TABLET_IDC_BFT_FILTER;
if (!isNull _btn) then {
    _btn ctrlSetText (["ALL", "MINE"] select _next);
    _btn ctrlSetBackgroundColor (
        [[0.20, 0.30, 0.35, 0.85], [0.30, 0.45, 0.20, 0.90]] select _next
    );
};

private _statusCtrl = _display displayCtrl DSC_TABLET_IDC_BFT_STATUS;
if (!isNull _statusCtrl) then {
    private _tracks = [] call DSC_ui_fnc_panelBft_buildTracks;
    private _squadAlive = (units group player) select { alive _x };
    _statusCtrl ctrlSetText format [
        "%1 tracks  |  squad: %2  |  filter: %3",
        count _tracks,
        count _squadAlive,
        ["ALL", "MINE"] select _next
    ];
};

diag_log format ["DSC: panelBft_toggleFilter -> %1", ["ALL", "MINE"] select _next];
