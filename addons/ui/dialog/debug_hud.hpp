// Commander's Tablet — Debug HUD overlay
//
// A small always-on overlay rendered via cutRsc. Toggled by Ctrl+Shift+F.
// Pulled from a per-frame CBA handler that updates the labels with FPS,
// frame time, mission state, entity counts, and any custom diag string.
//
// Use DSC_ui_fnc_toggleDebugHud to show/hide.
// Use DSC_ui_fnc_setDebugHudCustom to write a string into the bottom slot.
//
// Lives in RscTitles so it doesn't grab input or block the player.

#define HUD_X "safezoneX + safezoneW * 0.005"
#define HUD_Y "safezoneY + safezoneH * 0.30"
#define HUD_W "safezoneW * 0.16"
#define HUD_H "safezoneH * 0.040"

class RscTitles {
    class DSC_DebugHud {
        idd = DSC_DEBUG_HUD_IDD;
        movingEnable = 0;
        enableSimulation = 1;
        duration = 1e10;
        fadeIn = 0;
        fadeOut = 0.2;
        onLoad = "uiNamespace setVariable ['DSC_DebugHudDisplay', _this select 0];";
        onUnload = "uiNamespace setVariable ['DSC_DebugHudDisplay', displayNull];";

        class controls {

            class HudBg : DSC_RscBackground {
                idc = -1;
                x = HUD_X;
                y = HUD_Y;
                w = HUD_W;
                h = "safezoneH * 0.18";
                colorBackground[] = { 0, 0, 0, 0.55 };
            };

            class FpsLine : DSC_RscText {
                idc = DSC_DEBUG_HUD_IDC_FPS;
                font = FONT_B;
                sizeEx = 0.024;
                text = "FPS --";
                x = HUD_X;
                y = HUD_Y;
                w = HUD_W;
                h = HUD_H;
                colorText[] = COLOR_ACCENT;
            };

            class StateLine : DSC_RscTextDim {
                idc = DSC_DEBUG_HUD_IDC_STATE;
                sizeEx = 0.020;
                text = "state --";
                x = HUD_X;
                y = "safezoneY + safezoneH * 0.34";
                w = HUD_W;
                h = HUD_H;
            };

            class CountsLine : DSC_RscTextDim {
                idc = DSC_DEBUG_HUD_IDC_COUNTS;
                sizeEx = 0.020;
                text = "u/g/v --";
                x = HUD_X;
                y = "safezoneY + safezoneH * 0.38";
                w = HUD_W;
                h = HUD_H;
            };

            class CustomLine : DSC_RscTextDim {
                idc = DSC_DEBUG_HUD_IDC_CUSTOM;
                sizeEx = 0.020;
                text = "";
                x = HUD_X;
                y = "safezoneY + safezoneH * 0.42";
                w = HUD_W;
                h = HUD_H;
            };
        };
    };
};
