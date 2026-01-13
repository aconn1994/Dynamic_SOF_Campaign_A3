#include "script_component.hpp"

class CfgPatches {
    class ADDON {
        name = COMPONENT_NAME;
        units[] = {};
        weapons[] = {};
        requiredVersion = 2.02;
        requiredAddons[] = {
            "DSC_main"
        };
        author = AUTHOR;
        authorUrl = "";
    };
};

#include "CfgEventHandlers.hpp"
