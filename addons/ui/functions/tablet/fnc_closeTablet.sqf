#include "..\..\script_component.hpp"
/*
 * Function: DSC_ui_fnc_closeTablet
 * Description: Closes the tablet dialog if open.
 */

if (!isNull (uiNamespace getVariable ["DSC_TabletDisplay", displayNull])) then {
    closeDialog 0;
};
