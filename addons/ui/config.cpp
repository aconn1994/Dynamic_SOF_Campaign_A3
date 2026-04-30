#include "script_component.hpp"

class CfgPatches {
    class ADDON {
        name = COMPONENT_NAME;
        units[] = {};
        weapons[] = {};
        requiredVersion = 2.02;
        requiredAddons[] = {
            "DSC_main",
            "DSC_core"
        };
        author = AUTHOR;
        authorUrl = "";
    };
};

#include "CfgEventHandlers.hpp"

#include "dialog\defines.hpp"
#include "dialog\tablet.hpp"
#include "dialog\debug_hud.hpp"
