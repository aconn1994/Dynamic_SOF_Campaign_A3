#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_initPlayerLocalDebug
 * Description:
 *     Client-side debug/admin extension layer. Runs after fnc_initPlayerLocal.
 *     Currently registers the CBA keybind that opens the Commander's Tablet
 *     and is the home for any future client-side debug tooling (overlays,
 *     diagnostic huds, dev shortcuts).
 *
 *     Default keybind: Ctrl+Shift+T (DIK_T = 0x14). User-rebindable from
 *     CBA Settings -> Addon Options -> "DSC Debug".
 *     (Avoid Ctrl+Y -- conflicts with Zeus.)
 *
 * Arguments: none
 */

if (!hasInterface) exitWith {};

waitUntil { !isNull (findDisplay 46) };

[
    "DSC Debug",
    "openTablet",
    ["Open Commander's Tablet", "Toggle the DSC Commander's Tablet UI"],
    {
        private _ready = missionNamespace getVariable ["initGlobalsComplete", false];
        private _hasFaction = !isNil { missionNamespace getVariable "DSC_factionData" };
        private _hasInfluence = !isNil { missionNamespace getVariable "DSC_influenceData" };
        private _hasLocations = !isNil { missionNamespace getVariable "DSC_locations" };

        diag_log format [
            "DSC: tablet keybind pressed - initGlobalsComplete=%1 factionData=%2 influenceData=%3 locations=%4 missionState=%5",
            _ready, _hasFaction, _hasInfluence, _hasLocations,
            missionNamespace getVariable ["missionState", "<unset>"]
        ];

        if (!_ready) exitWith {
            hint format [
                "DSC: world still initializing.\n\ninitGlobalsComplete=%1\nfactionData=%2\ninfluenceData=%3\nlocations=%4",
                _ready, _hasFaction, _hasInfluence, _hasLocations
            ];
        };
        [] call DSC_ui_fnc_openTablet;
    },
    {false},
    [0x14, [true, true, false]] // Ctrl + Shift + T
] call CBA_fnc_addKeybind;

[
    "DSC Debug",
    "toggleHud",
    ["Toggle Debug HUD", "Show/hide an FPS + state overlay in the top-left corner"],
    { [] call DSC_ui_fnc_toggleDebugHud; },
    {false},
    [0x21, [true, true, false]] // Ctrl + Shift + F
] call CBA_fnc_addKeybind;

diag_log "DSC: Client debug layer initialized (tablet keybind registered)";
