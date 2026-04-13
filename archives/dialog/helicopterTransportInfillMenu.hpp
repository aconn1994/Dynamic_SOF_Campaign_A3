class RscText {
    access = 0;
    type = 0;
    idc = -1;
    style = 0;
    linespacing = 1;
    colorBackground[] = {0, 0, 0, 0};
    colorText[] = {1, 1, 1, 1};
    text = "";
    shadow = 1;
    font = "PuristaMedium";
    sizeEx = 0.04;
};

class RscButton {
    access = 0;
    type = 1;
    text = "";
    colorText[] = {1, 1, 1, 1};
    colorDisabled[] = {0.5, 0.5, 0.5, 1};
    colorBackground[] = {0.2, 0.2, 0.2, 1};
    colorBackgroundDisabled[] = {0.1, 0.1, 0.1, 1};
    colorBackgroundActive[] = {0.3, 0.3, 0.3, 1};
    colorFocused[] = {0.4, 0.4, 0.4, 1};
    colorShadow[] = {0, 0, 0, 0.5};
    colorBorder[] = {0, 0, 0, 1};
    soundEnter[] = {"", 0.09, 1};
    soundPush[] = {"", 0.09, 1};
    soundClick[] = {"", 0.09, 1};
    soundEscape[] = {"", 0.09, 1};
    style = 2;
    shadow = 1;
    font = "PuristaMedium";
    sizeEx = 0.035;
    borderSize = 0;
    offsetX = 0.003;
    offsetY = 0.003;
    offsetPressedX = 0.002;
    offsetPressedY = 0.002;
};

class RscFrame {
    type = 0;
    idc = -1;
    style = 64;
    shadow = 2;
    colorBackground[] = {0, 0, 0, 0.8};
    colorText[] = {1, 1, 1, 1};
    font = "PuristaMedium";
    sizeEx = 0.03;
    text = "";
};

class HelicopterTransportPopupMenu {
    idd = 12345;
    movingEnable = false;
    enableSimulation = true;

    class controlsBackground {
        class Background: RscFrame {
            x = 0.35; y = 0.2;
            w = 0.3; h = 0.5;
        };
    };

    class controls {
        class Title: RscText {
            text = "Select an Option:";
            x = 0.36; y = 0.21;
            w = 0.28; h = 0.04;
        };

        class Option1: RscButton {
            idc = 201;
            text = "Option 1";
            x = 0.36; y = 0.27;
            w = 0.28; h = 0.04;
            action = "closeDialog 0; uiNamespace setVariable ['transportHeloToSpawn', (lightTransportHelo select 1)]; uiNamespace setVariable ['transportHeloSeatPosition', (lightTransportHelo select 2)]; [] execVM 'acorns_modules\insertions\heloInsertion.sqf';";
        };
        class Option2: RscButton {
            idc = 202;
            text = "Option 2";
            x = 0.36; y = 0.32;
            w = 0.28; h = 0.04;
            action = "closeDialog 0; uiNamespace setVariable ['transportHeloToSpawn', (mediumTransportHelo select 1)]; uiNamespace setVariable ['transportHeloSeatPosition', (mediumTransportHelo select 2)]; [] execVM 'acorns_modules\insertions\heloInsertion.sqf';";
        };
        class Option3: RscButton {
            idc = 203;
            text = "Option 3";
            x = 0.36; y = 0.37;
            w = 0.28; h = 0.04;
            action = "closeDialog 0; uiNamespace setVariable ['transportHeloToSpawn', (heavyTransportHelo select 1)]; uiNamespace setVariable ['transportHeloSeatPosition', (heavyTransportHelo select 2)]; [] execVM 'acorns_modules\insertions\heloInsertion.sqf';";
        };

        class CancelButton: RscButton {
            idc = 211;
            text = "Cancel";
            x = 0.51; y = 0.53;
            w = 0.13; h = 0.05;
            action = "closeDialog 0; ['Cancelled'] execVM 'acorns_modules\insertions\heloInsertion.sqf';";
        };
    };
};