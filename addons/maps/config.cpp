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
    class MPMissions {
        class DSC_Altis {
            briefingName = "Dynamic SOF Campaign - Altis";
            directory = "z\DSC\addons\maps\DSC_Altis.Altis";
        };
        class DSC_Livonia {
            briefingName = "Dynamic SOF Campaign - Livonia";
            directory = "z\DSC\addons\maps\DSC_Livonia.enoch";
        };
        class DSC_Malden {
            briefingName = "Dynamic SOF Campaign - Malden";
            directory = "z\DSC\addons\maps\DSC_Malden.Malden";
        };
        class DSC_Stratis {
            briefingName = "Dynamic SOF Campaign - Stratis";
            directory = "z\DSC\addons\maps\DSC_Stratis.Stratis";
        };
        class DSC_Tanoa {
            briefingName = "Dynamic SOF Campaign - Tanoa";
            directory = "z\DSC\addons\maps\DSC_Tanoa.Tanoa";
        };
    };
};
