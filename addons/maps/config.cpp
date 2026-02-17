#include "script_component.hpp"

class CfgPatches {
    class ADDON {
        name = COMPONENT_NAME;
        units[] = {};
        weapons[] = {};
        requiredVersion = 2.02;
        requiredAddons[] = {
            "DSC_core",
            "DSC_main"
        };
        author = AUTHOR;
        authorUrl = "";
    };
};

class CfgMissions {
    class Missions {
        class DSC_Altis {
            briefingName = "Dynamic SOF Campaign - Altis";
            directory = "z\DSC\addons\maps\DSC_Altis.Altis";
        };
    };
    class MPMissions {
        class DSC_Altis {
            briefingName = "Dynamic SOF Campaign - Altis";
            directory = "z\DSC\addons\maps\DSC_Altis.Altis";
        };
    };
};
