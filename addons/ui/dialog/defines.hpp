// Commander's Tablet — UI defines
//
// Strategy: inherit from BIS base classes (RscText, RscButton, RscCombo,
// RscEdit, RscCheckBox, RscControlsGroup, RscPicture). They define every
// required property the engine looks for. We forward-declare them, then
// inherit and override only the colors/fonts/styles we want.
//
// SAFE FOR CONFIG ONLY. SQF files should include `idc.hpp` instead.

#include "idc.hpp"

// --- Common fonts ---
#define FONT_M             "PuristaMedium"
#define FONT_B             "PuristaBold"
#define FONT_L             "PuristaLight"

// --- Static / control style flags we still reference directly ---
#define ST_LEFT             0
#define ST_CENTER           1
#define ST_RIGHT            2
#define ST_PICTURE         48
#define ST_FRAME           64
#define ST_BACKGROUND     128

// --- Colors ---
#define COLOR_BG_PANEL    { 0.08, 0.10, 0.12, 0.95 }
#define COLOR_BG_BTN      { 0.20, 0.30, 0.35, 0.85 }
#define COLOR_BG_BTN_HL   { 0.30, 0.45, 0.55, 0.95 }
#define COLOR_TEXT        { 0.85, 0.92, 0.95, 1.0 }
#define COLOR_TEXT_DIM    { 0.55, 0.62, 0.65, 1.0 }
#define COLOR_ACCENT      { 0.30, 0.75, 0.95, 1.0 }
#define COLOR_DANGER      { 0.85, 0.30, 0.25, 1.0 }
#define COLOR_TRANSPARENT { 0, 0, 0, 0 }

// ============================================================================
// Forward-declare BIS base classes (engine provides full definitions)
// ============================================================================
class RscText;
class RscPicture;
class RscButton;
class RscEdit;
class RscCombo;
class RscCheckBox;
class RscControlsGroupNoScrollbars;
class RscXSliderH;
class RscListBox;

// ============================================================================
// DSC base classes — inherit BIS, override style only
// ============================================================================

class DSC_RscText : RscText {
    idc = -1;
    style = ST_LEFT;
    colorBackground[] = COLOR_TRANSPARENT;
    colorText[]       = COLOR_TEXT;
    font = FONT_M;
    sizeEx = 0.030;
    text = "";
    x = 0; y = 0; w = 0.1; h = 0.04;
};

class DSC_RscTextDim : DSC_RscText {
    colorText[] = COLOR_TEXT_DIM;
    sizeEx = 0.025;
};

class DSC_RscPicture : RscPicture {
    idc = -1;
    style = ST_PICTURE;
    colorText[] = { 1, 1, 1, 1 };
    colorBackground[] = COLOR_TRANSPARENT;
    text = "";
    x = 0; y = 0; w = 0.1; h = 0.04;
};

class DSC_RscBackground : DSC_RscText {
    style = ST_BACKGROUND;
    colorBackground[] = COLOR_BG_PANEL;
};

class DSC_RscFrame : DSC_RscText {
    style = ST_FRAME;
    colorText[] = COLOR_TEXT_DIM;
    sizeEx = 0.022;
};

class DSC_RscButton : RscButton {
    idc = -1;
    style = ST_CENTER;
    text = "";
    action = "";
    font = FONT_B;
    sizeEx = 0.028;
    colorText[]               = COLOR_TEXT;
    colorFocused[]            = COLOR_TEXT;
    colorDisabled[]           = COLOR_TEXT_DIM;
    colorBackground[]         = COLOR_BG_BTN;
    colorBackgroundDisabled[] = { 0.1, 0.1, 0.1, 0.5 };
    colorBackgroundActive[]   = COLOR_BG_BTN_HL;
    x = 0; y = 0; w = 0.1; h = 0.04;
};

class DSC_RscTabButton : DSC_RscButton {
    sizeEx = 0.030;
    colorBackground[]       = { 0.10, 0.13, 0.16, 0.75 };
    colorBackgroundActive[] = COLOR_ACCENT;
};

class DSC_RscDangerButton : DSC_RscButton {
    colorBackground[]       = { 0.45, 0.18, 0.15, 0.85 };
    colorBackgroundActive[] = { 0.65, 0.25, 0.20, 0.95 };
};

class DSC_RscCombo : RscCombo {
    idc = -1;
    style = ST_LEFT;
    font = FONT_M;
    sizeEx = 0.028;
    colorText[]             = COLOR_TEXT;
    colorBackground[]       = { 0.10, 0.13, 0.16, 0.95 };
    colorSelect[]           = COLOR_ACCENT;
    colorSelectBackground[] = { 0.20, 0.30, 0.35, 0.85 };
    x = 0; y = 0; w = 0.1; h = 0.04;
};

class DSC_RscEdit : RscEdit {
    idc = -1;
    style = ST_LEFT;
    font = FONT_M;
    sizeEx = 0.028;
    colorText[]       = COLOR_TEXT;
    colorBackground[] = { 0.10, 0.13, 0.16, 0.95 };
    text = "";
    x = 0; y = 0; w = 0.1; h = 0.04;
};

class DSC_RscCheckbox : RscCheckBox {
    idc = -1;
    color[]         = COLOR_TEXT;
    colorText[]     = COLOR_TEXT;
    colorBackground[] = { 0, 0, 0, 0.4 };
    colorSelectedBg[] = COLOR_ACCENT;
    checked = 0;
    x = 0; y = 0; w = 0.04; h = 0.04;
};

class DSC_RscControlsGroup : RscControlsGroupNoScrollbars {
    idc = -1;
    x = 0; y = 0; w = 1; h = 1;
    class Controls {};
};

class DSC_RscSlider : RscXSliderH {
    idc = -1;
    color[] = COLOR_TEXT;
    colorActive[] = COLOR_ACCENT;
    x = 0; y = 0; w = 0.2; h = 0.04;
};

class DSC_RscListBox : RscListBox {
    idc = -1;
    style = ST_LEFT;
    font = FONT_M;
    sizeEx = 0.024;
    rowHeight = 0.030;
    colorText[]       = COLOR_TEXT;
    colorBackground[] = { 0.10, 0.13, 0.16, 0.95 };
    colorSelect[]     = COLOR_ACCENT;
    colorSelectBackground[] = { 0.20, 0.30, 0.35, 0.85 };
    x = 0; y = 0; w = 0.3; h = 0.2;
};
