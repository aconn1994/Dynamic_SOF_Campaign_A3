#include "..\..\script_component.hpp"
/*
 * Function: DSC_ui_fnc_openTablet
 * Description:
 *     Opens the Commander's Tablet dialog. Bound to Ctrl+Y by initPlayerLocalDebug.
 *
 *     Refuses to open if the world isn't initialized yet (the panel needs
 *     DSC_factionData / DSC_influenceData / DSC_locations).
 *
 * Arguments: none
 * Return: BOOL — whether the dialog was successfully opened
 *
 * Example:
 *     [] call DSC_ui_fnc_openTablet;
 */

if (!hasInterface) exitWith { false };

if (!isNull (uiNamespace getVariable ["DSC_TabletDisplay", displayNull])) exitWith {
    closeDialog 0;
    false
};

if (!(missionNamespace getVariable ["initGlobalsComplete", false])) exitWith {
    hint "Commander's Tablet:\nWorld initialization not complete yet.";
    false
};

private _classRegistered = isClass (configFile >> "DSC_Tablet");
diag_log format ["DSC_ui: openTablet - DSC_Tablet registered at configFile root: %1", _classRegistered];

if (!_classRegistered) exitWith {
    hint "Commander's Tablet:\nDSC_Tablet class not found in CfgDialogs.\nCheck that the DSC_ui PBO is loaded.";
    diag_log "DSC_ui: DSC_Tablet missing from CfgDialogs - PBO not loaded or config malformed";
    false
};

private _ok = createDialog "DSC_Tablet";
if (!_ok) exitWith {
    diag_log "DSC_ui: Failed to create DSC_Tablet dialog";
    false
};

true
