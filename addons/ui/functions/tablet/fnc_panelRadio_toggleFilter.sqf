#include "..\..\script_component.hpp"
#include "..\..\dialog\idc.hpp"
/*
 * Function: DSC_ui_fnc_panelRadio_toggleFilter
 * Description:
 *     C2 Sprint F.4 — toggles the Radio Feed between EARNED and ALL.
 *
 *     EARNED is the honest player view: coverage-gated, and LOST transmissions
 *     hidden. ALL is a development affordance that shows the complete buffer —
 *     every line the enemy network produced, including the reports that never
 *     went out.
 *
 *     ALL is deliberately NOT the default and is deliberately colored as a
 *     warning. It reveals whether a group transmitted before dying, which is
 *     the exact question the report timer exists to make uncertain. Useful for
 *     verifying the network; corrosive to play with on.
 *
 * Arguments:
 *     0: _display <DISPLAY> - tablet display
 */

params [["_display", displayNull, [displayNull]]];
if (isNull _display) exitWith {};

private _showAll = !(_display getVariable ["DSC_radioShowAll", false]);
_display setVariable ["DSC_radioShowAll", _showAll];

private _btn = _display displayCtrl DSC_TABLET_IDC_RADIO_FILTER;
if (!isNull _btn) then {
    if (_showAll) then {
        _btn ctrlSetText "ALL (DEBUG)";
        _btn ctrlSetBackgroundColor [0.45, 0.28, 0.12, 0.90];
    } else {
        _btn ctrlSetText "EARNED";
        _btn ctrlSetBackgroundColor [0.20, 0.30, 0.35, 0.85];
    };
};

[_display] call DSC_ui_fnc_panelRadio_refresh;
