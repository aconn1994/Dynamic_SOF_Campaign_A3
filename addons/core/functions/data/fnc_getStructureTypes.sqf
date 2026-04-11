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
    "Land_Bunker_01_HQ_F",
    "Land_Bunker_01_tall_F",
    "Land_PillboxBunker_01_big_F",
    "Land_PillboxBunker_01_rectangle_F",
    "Land_PillboxBunker_01_hex_F",

    // Medevac
    "Land_Medevac_HQ_V1_F",

    // Airport
    "Land_Airport_Tower_F",
    "Land_Airport_01_controlTower_F",
    "Land_Airport_02_controlTower_F",

    // Radar
    "Land_Radar_F",
    "Land_Radar_01_HQ_F",
    "Land_Radar_01_antenna_base_F",
    "Land_Radar_01_kitchen_F",

    // Derelict Cargo (Malden)
    "Land_Cargo_HQ_V3_derelict_F",

    // Control Towers
    "Land_ControlTower_01_F",
    "Land_ControlTower_02_F",

    // Hangars
    "Land_Hangar_F"
];

// --- Civilian Main ---
private _mainCivilian = [
    // Mediterranean Big Houses
    "Land_i_House_Big_01_V1_F",
    "Land_i_House_Big_01_V2_F",
    "Land_i_House_Big_01_V3_F",
    "Land_i_House_Big_02_V1_F",
    "Land_i_House_Big_02_V2_F",
    "Land_i_House_Big_02_V3_F",

    // Malden Big Houses (color variants)
    "Land_i_House_Big_01_b_yellow_F",
    "Land_i_House_Big_01_b_blue_F",
    "Land_i_House_Big_01_b_pink_F",
    "Land_i_House_Big_01_b_white_F",
    "Land_i_House_Big_01_b_whiteblue_F",
    "Land_i_House_Big_01_b_brown_F",
    "Land_i_House_Big_02_b_pink_F",
    "Land_i_House_Big_02_b_brown_F",
    "Land_i_House_Big_02_b_whiteblue_F",
    "Land_i_House_Big_02_b_blue_F",
    "Land_i_House_Big_02_b_yellow_F",
    "Land_i_House_Big_02_b_white_F",

    // Urban Big Houses
    "Land_u_House_Big_01_V1_F",
    "Land_u_House_Big_02_V1_F",

    // Stone Houses (Big)
    "Land_i_Stone_HouseBig_V1_F",
    "Land_i_Stone_HouseBig_V2_F",
    "Land_i_Stone_HouseBig_V3_F",
    "Land_i_Stone_House_Big_01_b_clay_F",

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
    "Land_Shop_City_06_F",
    "Land_Shop_City_07_F",
    "Land_Shop_Town_01_F",
    "Land_Shop_Town_03_F",
    "Land_Shop_Town_05_F",
    "Land_i_Shop_01_V1_dam_F",
    "Land_i_Shop_02_V1_dam_F",

    // Malden Shops (color variants)
    "Land_i_Shop_02_b_whiteblue_F",
    "Land_i_Shop_02_b_brown_F",
    "Land_i_Shop_02_b_white_F",
    "Land_i_Shop_02_b_yellow_F",
    "Land_i_Shop_02_b_pink_F",
    "Land_i_Shop_02_b_blue_F",

    // Hotels / Schools / Supermarkets
    "Land_Hotel_01_F",
    "Land_Hotel_02_F",
    "Land_School_01_F",
    "Land_Supermarket_01_F",
    "Land_Supermarket_01_malden_F",

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
    "Land_MultistoryBuilding_03_F",
    "Land_MultistoryBuilding_04_F",

    // Churches / Public
    "Land_Church_01_F",
    "Land_Church_02_F",
    "Land_Church_03_F",
    "Land_Cathedral_01_F",

    // Airports
    "Land_Airport_01_terminal_F",
    "Land_Airport_02_terminal_F",
    "Land_Airport_left_F",
    "Land_Airport_right_F",
    "Land_Airport_01_hangar_F",
    "Land_Airport_02_hangar_left_F",
    "Land_Airport_02_hangar_right_F",

    // Industrial (Altis)
    "Land_Factory_Main_F",
    "Land_dp_bigTank_F",
    "Land_spp_Tower_F",

    // Sugar Cane Factory (Tanoa)
    "Land_SCF_01_boilerBuilding_F",
    "Land_SCF_01_generalBuilding_F",
    "Land_SCF_01_condenser_F",
    "Land_SCF_01_diffuser_F",
    "Land_SCF_01_clarifier_F",
    "Land_SCF_01_washer_F",
    "Land_SCF_01_crystallizer_F",
    "Land_SCF_01_crystallizerTowers_F",
    "Land_SCF_01_heap_bagasse_F",
    "Land_SCF_01_chimney_F",

    // Shipyard / Port (Tanoa)
    "Land_SY_01_crusher_F",
    "Land_SY_01_shiploader_F",
    "Land_SY_01_shiploader_arm_F",
    "Land_ContainerLine_01_F",
    "Land_ContainerLine_02_F",
    "Land_DryDock_01_end_F",
    "Land_DryDock_01_middle_F",
    "Land_StorageTank_01_large_F",

    // Temple
    "Land_Temple_Native_01_F",

    // Shop (Tanoa)
    "Land_Shop_City_04_F",

    // Lighthouses
    "Land_LightHouse_F",
    "Land_Lighthouse_03_red_F",
    "Land_Lighthouse_03_green_F",

    // Damaged Shops (Big)
    "Land_d_Shop_01_V1_F",

    // Ruins (Big)
    "Land_House_Big_01_V1_ruins_F",
    "Land_House_Big_02_V1_ruins_F",

    // Estate / Manor (GH)
    "Land_GH_MainBuilding_left_F",
    "Land_GH_MainBuilding_middle_F",
    "Land_GH_MainBuilding_right_F",
    "Land_GH_House_1_F",

    // Castle
    "Land_Castle_01_tower_F",

    // Police Station
    "Land_PoliceStation_01_F",

    // Barns (Large)
    "Land_Barn_04_F",
    "Land_Barn_03_large_F",
    "Land_Barn_01_grey_F",
    "Land_Barn_01_brown_F",

    // Unfinished (Large)
    "Land_Unfinished_Building_01_noLadder_F",

    // Livonia Houses
    "Land_House_1B01_F",
    "Land_House_2W05_F",

    // Service Hangars
    "Land_ServiceHangar_01_L_F",
    "Land_ServiceHangar_01_R_F",

    // Industrial (Livonia)
    "Land_Factory_02_F",
    "Land_CementWorks_01_grey_F",
    "Land_CementWorks_01_brick_F",
    "Land_ContainerLine_03_F",
    "Land_IndustrialShed_01_F",
    "Land_Smokestack_01_factory_F",
    "Land_Smokestack_01_F",
    "Land_CoalPlant_01_MainBuilding_F",
    "Land_Mine_01_warehouse_F",

    // Rail
    "Land_Rail_Station_Big_F",

    // Farming (Large)
    "Land_Cowshed_01_A_F",

    // Churches (Livonia)
    "Land_Church_04_lightblue_F",
    "Land_Church_04_yellow_F",
    "Land_Church_04_white_red_F",
    "Land_Church_04_red_F",
    "Land_Church_04_damaged_F",
    "Land_Church_04_yellow_damaged_F",
    "Land_ChurchRuin_01_F",

    // Construction
    "Land_WIP_F"
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
    "Land_Cargo_House_V3_derelict_F",

    // Derelict Cargo (Malden Side)
    "Land_Cargo_Patrol_V2_ruins_F",
    "Land_Cargo_Tower_V3_derelict_F",

    // Small Bunkers / Guard Houses
    "Land_Bunker_01_small_F",
    "Land_GuardHouse_01_F",

    // Ruined Military
    "Land_Cargo_Patrol_V3_ruins_F",

    // Bunkers (Livonia)
    "Land_Bunker_02_right_F",
    "Land_Bunker_02_left_F",
    "Land_Bunker_02_double_F",
    "Land_Bunker_02_light_double_F",
    "Land_Bunker_02_light_left_F",
    "Land_Bunker_02_light_right_F",

    // Guard Houses (Livonia)
    "Land_GuardHouse_02_F",
    "Land_GuardHouse_02_grey_F",
    "Land_GuardHouse_03_F",
    "Land_GuardBox_01_green_F",
    "Land_GuardBox_01_brown_F",

    // Radar Components
    "Land_Radar_01_antenna_F",
    "Land_Radar_01_cooler_F",

    // Camp
    "Land_Camp_House_01_brown_F",

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

    // Malden Small Houses (color variants)
    "Land_i_House_Small_01_b_yellow_F",
    "Land_i_House_Small_01_b_pink_F",
    "Land_i_House_Small_01_b_whiteblue_F",
    "Land_i_House_Small_01_b_blue_F",
    "Land_i_House_Small_01_b_white_F",
    "Land_i_House_Small_01_b_brown_F",
    "Land_i_House_Small_02_b_whiteblue_F",
    "Land_i_House_Small_02_c_pink_F",
    "Land_i_House_Small_02_b_blue_F",
    "Land_i_House_Small_02_b_white_F",
    "Land_i_House_Small_02_b_pink_F",
    "Land_i_House_Small_02_b_brown_F",
    "Land_i_House_Small_02_b_yellow_F",
    "Land_i_House_Small_02_c_whiteblue_F",
    "Land_i_House_Small_02_c_blue_F",

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

    // Livonia Houses (1-wide additional)
    "Land_House_1W12_F",

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
    "Land_Shed_Ind_old_ruins_F",
    "Land_u_Shed_Ind_F",
    "Land_i_Stone_Shed_V1_F",
    "Land_i_Stone_Shed_V2_F",
    "Land_i_Stone_Shed_V3_F",
    "Land_i_Stone_Shed_V1_dam_F",
    "Land_d_Stone_Shed_V1_F",

    // Malden Stone Sheds (color variants)
    "Land_i_Stone_Shed_01_b_raw_F",
    "Land_i_Stone_Shed_01_b_clay_F",
    "Land_i_Stone_Shed_01_b_white_F",
    "Land_i_Stone_Shed_01_c_white_F",
    "Land_i_Stone_Shed_01_c_clay_F",
    "Land_i_Stone_Shed_01_c_raw_F",

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
    "Land_Shed_05_ruins_F",
    "Land_Shed_08_brown_F",
    "Land_Shed_08_grey_F",

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
    "Land_PowerStation_01_F",
    "Land_Substation_01_F",

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
    "Land_Chapel_02_white_F",
    "Land_Chapel_02_yellow_F",
    "Land_Chapel_02_white_damaged_F",
    "Land_Chapel_02_yellow_damaged_F",
    "Land_Chapel_02_white_ruins_F",
    "Land_Chapel_02_yellow_ruins_F",
    "Land_Church_05_F",

    // Small Commercial
    "Land_VillageStore_01_F",
    "Land_FuelStation_Build_F",
    "Land_FuelStation_Shed_F",
    "Land_FuelStation_01_shop_F",
    "Land_FuelStation_01_workshop_F",
    "Land_FuelStation_02_workshop_F",
    "Land_FuelStation_03_shop_F",

    // Unfinished / WIP
    "Land_Unfinished_Building_01_F",
    "Land_Unfinished_Building_02_F",
    "Land_Unfinished_Building_01_ruins_F",
    "Land_Unfinished_Building_02_ruins_F",

    // Damaged Shops (Small)
    "Land_d_Shop_02_V1_F",
    "Land_Shop_01_V1_ruins_F",
    "Land_Shop_02_V1_ruins_F",

    // Ruins (Small/Side)
    "Land_House_Small_01_V1_ruins_F",
    "Land_House_Small_02_V1_ruins_F",
    "Land_Stone_HouseBig_V1_ruins_F",
    "Land_Stone_Shed_V1_ruins_F",
    "Land_Garage_V1_ruins_F",
    "Land_Addon_02_V1_ruins_F",
    "Land_Addon_04_V1_ruins_F",

    // Windmills
    "Land_i_Windmill01_F",
    "Land_d_Windmill01_F",

    // Small Lighthouse / Crane
    "Land_Lighthouse_small_F",
    "Land_Crane_F",
    "Land_ContainerCrane_01_F",
    "Land_MobileCrane_01_F",
    "Land_MobileCrane_01_hook_F",

    // Estate / Manor (GH) Side
    "Land_GH_Gazebo_F",
    "Land_GH_House_2_F",

    // Piers / Bridges
    "Land_Pier_F",
    "Land_Pier_small_F",
    "Land_nav_pier_m_F",
    "Land_PierWooden_01_dock_F",
    "Land_PierWooden_01_hut_F",
    "Land_PierWooden_01_platform_F",
    "Land_PierWooden_01_16m_F",
    "Land_PierWooden_01_10m_noRails_F",
    "Land_PierWooden_02_16m_F",
    "Land_PierWooden_02_30deg_F",
    "Land_PierWooden_02_ladder_F",
    "Land_PierWooden_02_barrel_F",
    "Land_PierWooden_02_hut_F",
    "Land_Bridge_HighWay_PathLod_F",
    "Land_Bridge_01_PathLod_F",
    "Land_Bridge_Asphalt_PathLod_F",
    "Land_Bridge_Concrete_PathLod_F",
    "Land_Canal_Wall_Stairs_F",
    "Land_Track_01_bridge_F",

    // Stadium
    "Land_Stadium_p4_F",
    "Land_Stadium_p5_F",
    "Land_Stadium_p9_F",

    // Barns (Small) / Farming
    "Land_Barn_02_F",
    "Land_Barn_03_small_F",
    "Land_Cowshed_01_B_F",
    "Land_Cowshed_01_C_F",
    "Land_FeedShack_01_F",

    // Sawmill
    "Land_Sawmill_01_F",
    "Land_Sawmill_01_illuminati_tower_F",

    // Deer Stands
    // "Land_DeerStand_01_F",
    "Land_DeerStand_02_F",

    // Industrial (Small)
    "Land_dp_bigTank_old_F",
    "Land_Rail_Warehouse_Small_F",
    "Land_StorageTank_01_small_F",

    // Sugar Cane Factory Side (Tanoa)
    "Land_SCF_01_feeder_F",
    "Land_SCF_01_storageBin_big_F",
    "Land_SCF_01_storageBin_medium_F",
    "Land_SCF_01_storageBin_small_F",

    // Shipyard Side (Tanoa)
    "Land_SY_01_reclaimer_F",
    "Land_SY_01_conveyor_end_F",

    // Tanoa Shops (Small)
    "Land_Shop_Town_02_F",

    // Mausoleum
    "Land_Mausoleum_01_F",

    // Fire Escapes
    "Land_FireEscape_01_tall_F",
    "Land_FireEscape_01_short_F",

    // Mining / Abandoned
    "Land_HaulTruck_01_abandoned_F",
    "Land_MiningShovel_01_abandoned_F",

    // Ruins (Livonia)
    "Land_CastleRuins_01_bastion_F",

    // Walls / Gates
    "Land_WoodenWall_04_s_d_5m_F",
    "Land_BrickWall_03_l_gate_F",
    "Land_Highway_Pillar_01_garage_F",

    // Caravan
    "Land_Caravan_01_rust_F"
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
    ["Enoch", [
        "Land_DeerStand_02_F"
    ]]
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
