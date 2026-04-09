#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_getStructureTypes
 * Description:
 *     Returns curated lists of structure class names categorized as main or side.
 *     Uses base classes (isKindOf) where possible, with exact class names for edge cases.
 *     Physically separated by civilian and military for easier management.
 *
 * Arguments:
 *     None
 *
 * Return Value:
 *     <HASHMAP> - Keys:
 *       "main" - Array of class names for main/anchor structures
 *       "side" - Array of class names for side/satellite structures
 *
 * Example:
 *     private _types = call DSC_core_fnc_getStructureTypes;
 *     private _mainTypes = _types get "main";
 */

// ============================================================================
// MAIN STRUCTURES (Anchor buildings - multi-story, barracks, HQs, large buildings)
// ============================================================================

// --- Military Main ---
private _mainMilitary = [
    // Barracks
    "Land_i_Barracks_V1_F",
    "Land_i_Barracks_V2_F",
    "Land_u_Barracks_V2_F",
    "Land_Barracks_01_camo_F",
    "Land_Barracks_01_grey_F",
    "Land_Barracks_01_dilapidated_F",
    "Land_Barracks_02_F",
    "Land_Barracks_03_F",
    "Land_Barracks_04_F",
    "Land_Barracks_05_F",
    "Land_Barracks_06_F",

    // Cargo HQ
    "Cargo_HQ_base_F",

    // Military Offices
    "Land_MilOffices_V1_F",
    "Land_Offices_01_V1_F",

    // Research/Command
    "Land_Research_house_V1_F",
    "Land_Research_HQ_F",

    // Bunkers
    "Land_Bunker_01_big_F",

    // Medevac
    "Land_Medevac_HQ_V1_F",

    // Airport
    "Land_Airport_Tower_F"
];

// --- Civilian Main ---
private _mainCivilian = [
    // Mediterranean Big Houses (base classes cover V1/V2/V3 variants)
    "Land_i_House_Big_01_V1_F",
    "Land_i_House_Big_01_V2_F",
    "Land_i_House_Big_01_V3_F",
    "Land_i_House_Big_02_V1_F",
    "Land_i_House_Big_02_V2_F",
    "Land_i_House_Big_02_V3_F",

    // Urban Big Houses
    "Land_u_House_Big_01_V1_F",
    "Land_u_House_Big_02_V1_F",

    // Stone Houses (Big)
    "Land_i_Stone_HouseBig_V1_F",
    "Land_i_Stone_HouseBig_V2_F",
    "Land_i_Stone_HouseBig_V3_F",

    // Damaged Big Houses
    "Land_i_House_Big_01_V1_dam_F",
    "Land_i_House_Big_02_V1_dam_F",
    "Land_d_House_Big_01_V1_F",
    "Land_d_House_Big_02_V1_F",
    "Land_i_Stone_HouseBig_V1_dam_F",
    "Land_d_Stone_HouseBig_V1_F",

    // Tanoa Big Houses
    "Land_House_Big_01_F",
    "Land_House_Big_02_F",
    "Land_House_Big_03_F",
    "Land_House_Big_04_F",

    // Livonia Houses (2-wide)
    "Land_House_2W01_F",
    "Land_House_2W02_F",
    "Land_House_2W03_F",
    "Land_House_2W04_F",
    "Land_House_2B01_F",
    "Land_House_2B02_F",
    "Land_House_2B03_F",
    "Land_House_2B04_F",

    // House Ruins (Big)
    "Land_HouseRuin_Big_01_F",
    "Land_HouseRuin_Big_01_half_F",
    "Land_HouseRuin_Big_02_F",
    "Land_HouseRuin_Big_02_half_F",
    "Land_HouseRuin_Big_03_half_F",

    // Garage Complexes (Livonia)
    "Land_GarageRow_01_large_F",
    "Land_GarageOffice_01_F",

    // Shops (multi-room)
    "Land_i_Shop_01_V1_F",
    "Land_i_Shop_01_V2_F",
    "Land_i_Shop_01_V3_F",
    "Land_i_Shop_02_V1_F",
    "Land_i_Shop_02_V2_F",
    "Land_i_Shop_02_V3_F",
    "Land_u_Shop_01_V1_F",
    "Land_u_Shop_02_V1_F",
    "Land_Shop_City_01_F",
    "Land_Shop_City_02_F",
    "Land_Shop_City_05_F",
    "Land_Shop_Town_01_F",
    "Land_Shop_Town_03_F",
    "Land_Shop_Town_05_F",
    "Land_i_Shop_01_V1_dam_F",
    "Land_i_Shop_02_V1_dam_F",

    // Hotels / Schools / Supermarkets
    "Land_Hotel_01_F",
    "Land_Hotel_02_F",
    "Land_School_01_F",
    "Land_Supermarket_01_F",

    // Hospitals
    "Land_Hospital_main_F",
    "Land_Hospital_side1_F",
    "Land_Hospital_side2_F",
    "Land_HealthCenter_01_F",

    // Industrial (Large)
    "Land_dp_mainFactory_F",
    "Land_dp_smallFactory_F",
    "Land_DPP_01_mainFactory_F",
    "Land_Warehouse_01_F",
    "Land_Warehouse_02_F",
    "Land_Warehouse_03_F",
    "Land_CarService_F",

    // Multi-story / Office
    "Land_MultistoryBuilding_01_F",
    "Land_MultistoryBuilding_04_F",

    // Churches / Public
    "Land_Church_01_F",
    "Land_Church_02_F",
    "Land_Church_03_F",
    "Land_Cathedral_01_F",

    // Airports
    "Land_Airport_01_terminal_F",
    "Land_Airport_02_terminal_F"
];

// ============================================================================
// SIDE STRUCTURES (Satellite buildings - sheds, small huts, guard posts, garages)
// ============================================================================

// --- Military Side ---
private _sideMilitary = [
    // Cargo Patrol Towers
    "Cargo_Patrol_base_F",
    "Cargo_Tower_base_F",

    // Small Cargo Buildings
    "Land_Cargo_House_V1_F",
    "Land_Cargo_House_V2_F",
    "Land_Cargo_House_V3_F",
    "Land_Cargo_House_V4_F",
    "Land_cargo_house_slum_F",

    // Small Bunkers / Guard Houses
    "Land_Bunker_01_small_F",
    "Land_GuardHouse_01_F",

    // Guard Towers (Livonia)
    "Land_GuardTower_01_F",
    "Land_GuardTower_02_F",

    // Guard Boxes
    "Land_GuardBox_01_smooth_F",

    // Radar
    "Land_MobileRadar_01_radar_F",

    // Medevac Small
    "Land_Medevac_house_V1_F"
];

// --- Civilian Side ---
private _sideCivilian = [
    // Mediterranean Small Houses
    "Land_i_House_Small_01_V1_F",
    "Land_i_House_Small_01_V2_F",
    "Land_i_House_Small_01_V3_F",
    "Land_i_House_Small_02_V1_F",
    "Land_i_House_Small_02_V2_F",
    "Land_i_House_Small_02_V3_F",
    "Land_i_House_Small_03_V1_F",

    // Urban Small Houses
    "Land_u_House_Small_01_V1_F",
    "Land_u_House_Small_02_V1_F",

    // Stone Houses (Small)
    "Land_i_Stone_HouseSmall_V1_F",
    "Land_i_Stone_HouseSmall_V2_F",
    "Land_i_Stone_HouseSmall_V3_F",

    // Damaged Small Houses
    "Land_i_House_Small_01_V1_dam_F",
    "Land_i_House_Small_01_V2_dam_F",
    "Land_i_House_Small_02_V1_dam_F",
    "Land_d_House_Small_01_V1_F",
    "Land_d_House_Small_02_V1_F",
    "Land_i_Stone_HouseSmall_V1_dam_F",
    "Land_d_Stone_HouseSmall_V1_F",
    "Land_u_House_Small_01_V1_dam_F",
    "Land_u_House_Small_02_V1_dam_F",

    // Tanoa Small Houses
    "Land_House_Small_01_F",
    "Land_House_Small_02_F",
    "Land_House_Small_03_F",
    "Land_House_Small_04_F",
    "Land_House_Small_05_F",
    "Land_House_Small_06_F",
    "Land_House_Native_01_F",
    "Land_House_Native_02_F",

    // Livonia Houses (1-wide)
    "Land_House_1W01_F",
    "Land_House_1W02_F",
    "Land_House_1W03_F",
    "Land_House_1W04_F",
    "Land_House_1W05_F",
    "Land_House_1W06_F",
    "Land_House_1W07_F",
    "Land_House_1W08_F",
    "Land_House_1W09_F",
    "Land_House_1W10_F",
    "Land_House_1W11_F",
    "Land_House_1W13_F",

    // House Ruins (Small)
    "Land_HouseRuin_Small_01_half_F",

    // Slums
    "Land_Slum_House01_F",
    "Land_Slum_House02_F",
    "Land_Slum_House03_F",
    "Land_Slum_01_F",
    "Land_Slum_02_F",
    "Land_Slum_03_F",
    "Land_Slum_04_F",
    "Land_Slum_05_F",

    // Sheds
    "Land_i_Shed_Ind_F",
    "Land_i_Shed_Ind_old_F",
    "Land_u_Shed_Ind_F",
    "Land_i_Stone_Shed_V1_F",
    "Land_i_Stone_Shed_V2_F",
    "Land_i_Stone_Shed_V3_F",
    "Land_i_Stone_Shed_V1_dam_F",
    "Land_d_Stone_Shed_V1_F",
    "Land_Metal_Shed_F",
    "Land_Shed_01_F",
    "Land_Shed_02_F",
    "Land_Shed_03_F",
    "Land_Shed_04_F",
    "Land_Shed_05_F",
    "Land_Shed_06_F",
    "Land_Shed_07_F",
    "Land_Shed_09_F",
    "Land_Shed_10_F",
    "Land_Shed_11_F",
    "Land_Shed_12_F",
    "Land_Shed_14_F",

    // Workshops (Livonia)
    "Land_Workshop_01_F",
    "Land_Workshop_02_F",
    "Land_Workshop_03_F",
    "Land_Workshop_04_F",
    "Land_Workshop_05_F",

    // Garages
    "Land_i_Garage_V1_F",
    "Land_i_Garage_V2_F",
    "Land_GarageShelter_01_F",
    "Land_GarageRow_01_small_F",

    // Utility
    "Land_WaterStation_01_F",

    // Addons (attached rooms)
    "Land_i_Addon_02_V1_F",
    "Land_i_Addon_03_V1_F",
    "Land_i_Addon_03mid_V1_F",
    "Land_i_Addon_04_V1_F",
    "Land_u_Addon_01_V1_F",
    "Land_u_Addon_02_V1_F",
    "Land_Addon_04_F",
    "Land_d_Addon_02_V1_F",

    // Chapels
    "Land_Chapel_Small_V1_F",
    "Land_Chapel_Small_V2_F",
    "Land_Chapel_V1_F",
    "Land_Chapel_V2_F",

    // Small Commercial
    "Land_VillageStore_01_F",
    "Land_FuelStation_Build_F",
    "Land_FuelStation_Shed_F",
    "Land_FuelStation_01_shop_F",
    "Land_FuelStation_01_workshop_F",
    "Land_FuelStation_02_workshop_F",

    // Unfinished / WIP
    "Land_Unfinished_Building_01_F",
    "Land_Unfinished_Building_02_F"
];

// ============================================================================
// PER-MAP EXCLUSIONS
// ============================================================================
// These are checked at RUNTIME against actual map objects (not against the type lists).
// Use exact class names for surgical control, or base classes to exclude entire families.
// Maps not listed here default to no exclusions.

private _mapExclusions = createHashMapFromArray [

    // Altis - Exclude rusty/abandoned military structures (one-off ruins, not active bases)
    ["Altis", [
        "Land_Cargo_Patrol_V2_F",
        "Land_Cargo_Tower_V2_F",
        "Land_Cargo_HQ_V2_F",
        "Land_Cargo_House_V2_F"
    ]],

    // Stratis - No exclusions (rusty structures form complete bases here)
    ["Stratis", []],

    // Tanoa - No exclusions
    ["Tanoa", []],

    // Malden - No exclusions (rusty structures form complete bases here)
    ["Malden", []],

    // Livonia
    ["Enoch", []]
];

private _currentMap = worldName;
private _exclusions = _mapExclusions getOrDefault [_currentMap, []];

if (_exclusions isNotEqualTo []) then {
    diag_log format ["DSC: fnc_getStructureTypes - Map %1: %2 exclusion rules active", _currentMap, count _exclusions];
};

// ============================================================================
// COMBINE AND RETURN
// ============================================================================
private _result = createHashMapFromArray [
    ["main", _mainMilitary + _mainCivilian],
    ["side", _sideMilitary + _sideCivilian],
    ["mainMilitary", _mainMilitary],
    ["mainCivilian", _mainCivilian],
    ["sideMilitary", _sideMilitary],
    ["sideCivilian", _sideCivilian],
    ["exclusions", _exclusions]
];

_result
