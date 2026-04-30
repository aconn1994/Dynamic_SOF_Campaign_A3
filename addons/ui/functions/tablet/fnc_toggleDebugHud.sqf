#include "..\..\script_component.hpp"
#include "..\..\dialog\idc.hpp"
/*
 * Function: DSC_ui_fnc_toggleDebugHud
 * Description:
 *     Toggles the always-on debug HUD overlay (top-left corner). Spawns a
 *     CBA per-frame handler that updates FPS / frame time / mission state /
 *     entity counts / a custom diag slot.
 *
 *     The HUD is local-only and lives in RscTitles, so it doesn't grab input
 *     or block the player from playing.
 *
 *     Toggle keybind: Ctrl+Shift+F (registered by initPlayerLocalDebug).
 *
 *     Other code can write to the bottom "custom" line by storing a string
 *     into missionNamespace var DSC_debugHudCustom.
 *
 * Arguments: none
 */

private _isShown = missionNamespace getVariable ["DSC_debugHudShown", false];

if (_isShown) then {
    // Hide
    private _handlerId = missionNamespace getVariable ["DSC_debugHudHandlerId", -1];
    if (_handlerId >= 0) then {
        [_handlerId] call CBA_fnc_removePerFrameHandler;
    };
    missionNamespace setVariable ["DSC_debugHudHandlerId", -1];
    missionNamespace setVariable ["DSC_debugHudShown", false];

    "DSC_DebugHud" cutText ["", "PLAIN"];
    systemChat "DSC: Debug HUD off";
} else {
    // Show
    "DSC_DebugHud" cutRsc ["DSC_DebugHud", "PLAIN", 0, false];
    missionNamespace setVariable ["DSC_debugHudShown", true];

    private _id = [{
        params ["_args"];

        private _display = uiNamespace getVariable ["DSC_DebugHudDisplay", displayNull];
        if (isNull _display) exitWith {
            // Display not yet created — wait
        };

        // FPS + frame time
        private _fps = round diag_fps;
        private _ft = round (1000 / (diag_fps max 1));
        private _fpsCtrl = _display displayCtrl DSC_DEBUG_HUD_IDC_FPS;
        _fpsCtrl ctrlSetText format ["FPS %1   FT %2ms", _fps, _ft];

        // Color FPS by health
        private _fpsColor = switch (true) do {
            case (_fps >= 50): { [0.30, 0.85, 0.40, 1] };
            case (_fps >= 30): { [0.95, 0.80, 0.30, 1] };
            default            { [0.95, 0.30, 0.25, 1] };
        };
        _fpsCtrl ctrlSetTextColor _fpsColor;

        // Mission state
        private _state = missionNamespace getVariable ["missionState", "?"];
        private _inProg = missionNamespace getVariable ["missionInProgress", false];
        private _queueLen = count (missionNamespace getVariable ["DSC_missionQueue", []]);
        private _stateCtrl = _display displayCtrl DSC_DEBUG_HUD_IDC_STATE;
        _stateCtrl ctrlSetText format ["state: %1  inProg: %2  q: %3", _state, _inProg, _queueLen];

        // Entity counts
        private _allUnits = allUnits;
        private _allVeh = vehicles;
        private _allGrps = allGroups;
        private _countsCtrl = _display displayCtrl DSC_DEBUG_HUD_IDC_COUNTS;
        _countsCtrl ctrlSetText format ["units %1  groups %2  veh %3",
            count _allUnits, count _allGrps, count _allVeh];

        // Custom slot — anyone can write a diag string into this var
        private _custom = missionNamespace getVariable ["DSC_debugHudCustom", ""];
        private _customCtrl = _display displayCtrl DSC_DEBUG_HUD_IDC_CUSTOM;
        _customCtrl ctrlSetText _custom;
    }, 0.5, []] call CBA_fnc_addPerFrameHandler;

    missionNamespace setVariable ["DSC_debugHudHandlerId", _id];
    systemChat "DSC: Debug HUD on (Ctrl+Shift+F to toggle)";
};
