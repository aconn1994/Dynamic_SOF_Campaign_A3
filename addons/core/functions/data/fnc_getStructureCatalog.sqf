#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_getStructureCatalog
 * Description:
 *     Builds (once) and returns the structure taxonomy catalog — Session 01,
 *     Ambient World Overhaul, docs/overhauls/ambient_world/
 *     session_01_structure_taxonomy.md "Approved Mini-Spec" §A2/§A3/§A5.
 *
 *     Two authored tables, everything else derived:
 *       Table 1 (fnc_getStructureSubtypes) — 83 subtypes, each with a
 *         category, a display name, and default flags.
 *       Table 2 (inlined below, §A5)      — ~575 classnames, each pointed
 *         at a subtype, with an optional "+flag"/"-flag" override array.
 *
 *     Legacy keys (main/side/mainMilitary/mainCivilian/sideMilitary/
 *     sideCivilian/exclusions/functionalCategories/functionalLookup/
 *     nonOccupiable/nonOccupiableLookup) are derived mechanically from the
 *     anchor/satellite/military/occupiable flags so they stay byte-identical
 *     to the pre-Session-01 fnc_getStructureTypes.sqf output (§A3). Only
 *     functionalLookup/functionalCategories/nonOccupiable* can shift, and
 *     only in the ways listed in §A9 of the session doc.
 *
 *     Invariant (structural, not hopeful): occupiable <=> exactly one of
 *     anchor/satellite. A non-occupiable class carries neither and cannot
 *     appear in main or side.
 *
 *     Unknown subtype / unknown flag is loud (ERROR), never a silent no-op —
 *     the fnc_resolveEntityClass / unitClassResolver precedent (AGENTS.md).
 *
 * Arguments:
 *     0: _rebuild <BOOL> - Discard the cache and recompute (default false).
 *
 * Return Value:
 *     <HASHMAP> - Keys:
 *       "byClass"              - class -> {subtype, category, displayName, flags}
 *       "bySubtype"            - subtype -> [classnames]
 *       "byCategory"           - category -> [subtypes]
 *       "subtypeInfo"          - subtype -> {category, displayName, flags}
 *       "byFlag"               - flag -> [classnames] (authored + derived flags)
 *       "main", "side", "mainMilitary", "mainCivilian",
 *       "sideMilitary", "sideCivilian"                - legacy, ARRAY
 *       "exclusions"           - legacy, ARRAY (per-map, hand-authored)
 *       "functionalCategories", "functionalLookup"    - legacy, HASHMAP
 *       "nonOccupiable", "nonOccupiableLookup"         - legacy, HASHMAP
 *       "tableRowCount"        - raw Table 2 row count (Tier-1 introspection)
 *       "duplicateClassCount"  - duplicate classnames encountered in Table 2
 *
 * Example:
 *     private _catalog = [] call DSC_core_fnc_getStructureCatalog;
 *     private _byClass = _catalog get "byClass";
 *     private _record = _byClass getOrDefault ["Land_School_01_F", createHashMap];
 */

params [["_rebuild", false, [false]]];

if (!_rebuild && {!(isNil { missionNamespace getVariable "DSC_structureCatalogCache" })}) exitWith {
    missionNamespace getVariable "DSC_structureCatalogCache"
};

// ============================================================================
// Known vocabulary (Decision Log B15-B26) — used for loud validation, never
// a silent no-op on a typo'd category or flag.
// ============================================================================
private _knownCategories = [
    "residential", "commercial", "industrial", "agricultural", "medical",
    "religious", "infrastructure", "port", "airport", "law_enforcement", "military"
];

private _knownFlags = [
    // Authored (12)
    "occupiable", "anchor", "satellite", "military", "sentry_only",
    "hvt_suitable", "hostage_suitable", "ruined", "landmark",
    "infrastructure_node", "sabotage_target", "hackable",
    // Derived, never authored (3) — §A3
    "workplace", "public_access", "civilian_home"
];

private _civilianHomeExcludedSubtypes = ["shed_domestic", "garage_private", "house_annex", "castle"];
private _workplaceCategories = ["commercial", "industrial", "agricultural", "medical", "infrastructure", "port", "airport", "law_enforcement", "military"];
private _publicAccessCategories = ["commercial", "medical", "religious", "law_enforcement", "airport", "port"];

// ============================================================================
// Table 1 — subtype registry
// ============================================================================
private _subtypeTable = call DSC_core_fnc_getStructureSubtypes;

private _subtypeInfo = createHashMap;
private _byCategory = createHashMap;

{
    _x params [["_subtype", "", [""]], ["_category", "", [""]], ["_displayName", "", [""]], ["_defaultFlags", [], [[]]]];

    if !(_category in _knownCategories) then {
        ERROR_2("getStructureCatalog - subtype '%1' has unknown category '%2'",_subtype,_category);
    };

    {
        if !(_x in _knownFlags) then {
            ERROR_2("getStructureCatalog - subtype '%1' has unknown flag '%2'",_subtype,_x);
        };
    } forEach _defaultFlags;

    if (_subtype in _subtypeInfo) then {
        ERROR_1("getStructureCatalog - duplicate subtype '%1' in Table 1",_subtype);
    };

    _subtypeInfo set [_subtype, createHashMapFromArray [
        ["category", _category],
        ["displayName", _displayName],
        ["flags", _defaultFlags]
    ]];

    private _catSubtypes = _byCategory getOrDefault [_category, []];
    _catSubtypes pushBackUnique _subtype;
    _byCategory set [_category, _catSubtypes];
} forEach _subtypeTable;

// ============================================================================
// Table 2 — class scaffold (§A5). Transcribed verbatim from the approved
// mini-spec. Do NOT re-derive this from the pre-Session-01 file.
//
// Row shape: [classname, subtype] or [classname, subtype, overrideTokens].
// overrideTokens are "+flag" / "-flag" strings applied on top of the
// subtype's default flags, in order.
//
// "// REVIEW" rows are the agent's low-confidence transcription guesses —
// see docs/overhauls/ambient_world/session_01_ambiguities.md (§A6).
// ============================================================================
private _table2 = [

    // ========================================================================
    // residential
    // ========================================================================

    // -- house_small --
    ["Land_i_House_Small_01_V1_F", "house_small"], ["Land_i_House_Small_01_V2_F", "house_small"], ["Land_i_House_Small_01_V3_F", "house_small"],
    ["Land_i_House_Small_02_V1_F", "house_small"], ["Land_i_House_Small_02_V2_F", "house_small"], ["Land_i_House_Small_02_V3_F", "house_small"],
    ["Land_i_House_Small_03_V1_F", "house_small"],
    ["Land_i_House_Small_01_b_yellow_F", "house_small"], ["Land_i_House_Small_01_b_pink_F", "house_small"], ["Land_i_House_Small_01_b_whiteblue_F", "house_small"],
    ["Land_i_House_Small_01_b_blue_F", "house_small"], ["Land_i_House_Small_01_b_white_F", "house_small"], ["Land_i_House_Small_01_b_brown_F", "house_small"],
    ["Land_i_House_Small_02_b_whiteblue_F", "house_small"], ["Land_i_House_Small_02_b_blue_F", "house_small"], ["Land_i_House_Small_02_b_white_F", "house_small"],
    ["Land_i_House_Small_02_b_pink_F", "house_small"], ["Land_i_House_Small_02_b_brown_F", "house_small"], ["Land_i_House_Small_02_b_yellow_F", "house_small"],
    ["Land_i_House_Small_02_c_pink_F", "house_small"], ["Land_i_House_Small_02_c_whiteblue_F", "house_small"], ["Land_i_House_Small_02_c_blue_F", "house_small"],
    ["Land_u_House_Small_01_V1_F", "house_small"], ["Land_u_House_Small_02_V1_F", "house_small"],
    ["Land_i_Stone_HouseSmall_V1_F", "house_small"], ["Land_i_Stone_HouseSmall_V2_F", "house_small"], ["Land_i_Stone_HouseSmall_V3_F", "house_small"],
    ["Land_House_Small_01_F", "house_small"], ["Land_House_Small_02_F", "house_small"], ["Land_House_Small_03_F", "house_small"],
    ["Land_House_Small_04_F", "house_small"], ["Land_House_Small_05_F", "house_small"], ["Land_House_Small_06_F", "house_small"],
    ["Land_House_Native_01_F", "house_small"], ["Land_House_Native_02_F", "house_small"],
    ["Land_House_1W01_F", "house_small", ["+satellite", "-anchor"]], ["Land_House_1W02_F", "house_small", ["+satellite", "-anchor"]],
    ["Land_House_1W03_F", "house_small", ["+satellite", "-anchor"]], ["Land_House_1W04_F", "house_small", ["+satellite", "-anchor"]],
    ["Land_House_1W05_F", "house_small", ["+satellite", "-anchor"]], ["Land_House_1W06_F", "house_small", ["+satellite", "-anchor"]],
    ["Land_House_1W07_F", "house_small", ["+satellite", "-anchor"]], ["Land_House_1W08_F", "house_small", ["+satellite", "-anchor"]],
    ["Land_House_1W09_F", "house_small", ["+satellite", "-anchor"]], ["Land_House_1W10_F", "house_small", ["+satellite", "-anchor"]],
    ["Land_House_1W11_F", "house_small", ["+satellite", "-anchor"]], ["Land_House_1W12_F", "house_small", ["+satellite", "-anchor"]],
    ["Land_House_1W13_F", "house_small", ["+satellite", "-anchor"]],

    // -- house_small_damaged --
    ["Land_i_House_Small_01_V1_dam_F", "house_small_damaged"], ["Land_i_House_Small_01_V2_dam_F", "house_small_damaged"], ["Land_i_House_Small_01_V3_dam_F", "house_small_damaged"],
    ["Land_i_House_Small_02_V1_dam_F", "house_small_damaged"], ["Land_i_House_Small_02_V2_dam_F", "house_small_damaged"], ["Land_i_House_Small_02_V3_dam_F", "house_small_damaged"],
    ["Land_i_House_Small_03_V1_dam_F", "house_small_damaged"],
    ["Land_d_House_Small_01_V1_F", "house_small_damaged"], ["Land_d_House_Small_02_V1_F", "house_small_damaged"],
    ["Land_u_House_Small_01_V1_dam_F", "house_small_damaged"], ["Land_u_House_Small_02_V1_dam_F", "house_small_damaged"],
    ["Land_i_Stone_HouseSmall_V1_dam_F", "house_small_damaged"], ["Land_i_Stone_HouseSmall_V2_dam_F", "house_small_damaged"], ["Land_i_Stone_HouseSmall_V3_dam_F", "house_small_damaged"],
    ["Land_d_Stone_HouseSmall_V1_F", "house_small_damaged"],

    // -- house_big --
    ["Land_i_House_Big_01_V1_F", "house_big"], ["Land_i_House_Big_01_V2_F", "house_big"], ["Land_i_House_Big_01_V3_F", "house_big"],
    ["Land_i_House_Big_02_V1_F", "house_big"], ["Land_i_House_Big_02_V2_F", "house_big"], ["Land_i_House_Big_02_V3_F", "house_big"],
    ["Land_i_House_Big_01_b_yellow_F", "house_big"], ["Land_i_House_Big_01_b_blue_F", "house_big"], ["Land_i_House_Big_01_b_pink_F", "house_big"],
    ["Land_i_House_Big_01_b_white_F", "house_big"], ["Land_i_House_Big_01_b_whiteblue_F", "house_big"], ["Land_i_House_Big_01_b_brown_F", "house_big"],
    ["Land_i_House_Big_02_b_pink_F", "house_big"], ["Land_i_House_Big_02_b_brown_F", "house_big"], ["Land_i_House_Big_02_b_whiteblue_F", "house_big"],
    ["Land_i_House_Big_02_b_blue_F", "house_big"], ["Land_i_House_Big_02_b_yellow_F", "house_big"], ["Land_i_House_Big_02_b_white_F", "house_big"],
    ["Land_u_House_Big_01_V1_F", "house_big"], ["Land_u_House_Big_02_V1_F", "house_big"],
    ["Land_i_Stone_HouseBig_V1_F", "house_big"], ["Land_i_Stone_HouseBig_V2_F", "house_big"], ["Land_i_Stone_HouseBig_V3_F", "house_big"],
    ["Land_i_Stone_House_Big_01_b_clay_F", "house_big"],
    ["Land_House_Big_01_F", "house_big"], ["Land_House_Big_02_F", "house_big"], ["Land_House_Big_03_F", "house_big"], ["Land_House_Big_04_F", "house_big"], ["Land_House_Big_05_F", "house_big"],
    ["Land_House_2W01_F", "house_big"], ["Land_House_2W02_F", "house_big"], ["Land_House_2W03_F", "house_big"], ["Land_House_2W04_F", "house_big"], ["Land_House_2W05_F", "house_big"],
    ["Land_House_2B01_F", "house_big"], ["Land_House_2B02_F", "house_big"], ["Land_House_2B03_F", "house_big"], ["Land_House_2B04_F", "house_big"],
    ["Land_House_1B01_F", "house_big"],

    // -- house_big_damaged --
    ["Land_i_House_Big_01_V1_dam_F", "house_big_damaged"], ["Land_i_House_Big_01_V2_dam_F", "house_big_damaged"], ["Land_i_House_Big_01_V3_dam_F", "house_big_damaged"],
    ["Land_i_House_Big_02_V1_dam_F", "house_big_damaged"], ["Land_i_House_Big_02_V2_dam_F", "house_big_damaged"], ["Land_i_House_Big_02_V3_dam_F", "house_big_damaged"],
    ["Land_u_House_Big_01_V1_dam_F", "house_big_damaged"], ["Land_u_House_Big_02_V1_dam_F", "house_big_damaged"],
    ["Land_d_House_Big_01_V1_F", "house_big_damaged"], ["Land_d_House_Big_02_V1_F", "house_big_damaged"],
    ["Land_i_Stone_HouseBig_V1_dam_F", "house_big_damaged"], ["Land_i_Stone_HouseBig_V2_dam_F", "house_big_damaged"], ["Land_i_Stone_HouseBig_V3_dam_F", "house_big_damaged"],
    ["Land_d_Stone_HouseBig_V1_F", "house_big_damaged"],

    // -- apartment_block --
    ["Land_MultistoryBuilding_01_F", "apartment_block"], ["Land_MultistoryBuilding_03_F", "apartment_block"], ["Land_MultistoryBuilding_04_F", "apartment_block"],

    // -- estate --
    ["Land_GH_MainBuilding_left_F", "estate"], ["Land_GH_MainBuilding_middle_F", "estate"], ["Land_GH_MainBuilding_right_F", "estate"], ["Land_GH_House_1_F", "estate"],
    ["Land_GH_House_2_F", "estate"],
    ["Land_GH_Gazebo_F", "estate"],

    // -- castle --
    ["Land_Castle_01_tower_F", "castle"],
    ["Land_CastleRuins_01_bastion_F", "castle", ["+satellite", "-anchor", "+ruined"]],

    // -- slum --
    ["Land_Slum_House01_F", "slum"], ["Land_Slum_House02_F", "slum"], ["Land_Slum_House03_F", "slum"],
    ["Land_Slum_01_F", "slum"], ["Land_Slum_02_F", "slum"], ["Land_Slum_03_F", "slum"], ["Land_Slum_04_F", "slum"], ["Land_Slum_05_F", "slum"],

    // -- house_annex --
    ["Land_i_Addon_02_V1_F", "house_annex"], ["Land_i_Addon_03_V1_F", "house_annex"], ["Land_i_Addon_03mid_V1_F", "house_annex"], ["Land_i_Addon_04_V1_F", "house_annex"],
    ["Land_u_Addon_01_V1_F", "house_annex"], ["Land_u_Addon_02_V1_F", "house_annex"],
    ["Land_Addon_04_F", "house_annex"], ["Land_d_Addon_02_V1_F", "house_annex"], ["Land_u_Addon_01_V1_dam_F", "house_annex"],
    ["Land_FireEscape_01_tall_F", "house_annex", ["+sentry_only"]],
    ["Land_FireEscape_01_short_F", "house_annex", ["+sentry_only"]],

    // -- garage_private --
    ["Land_i_Garage_V1_F", "garage_private"], ["Land_i_Garage_V2_F", "garage_private"],
    ["Land_i_Garage_V1_dam_F", "garage_private"], ["Land_i_Garage_V2_dam_F", "garage_private"],
    ["Land_Highway_Pillar_01_garage_F", "garage_private"],
    ["Land_GarageShelter_01_F", "garage_private", ["+anchor", "-satellite"]],

    // -- shed_domestic --
    ["Land_i_Stone_Shed_V1_F", "shed_domestic"], ["Land_i_Stone_Shed_V2_F", "shed_domestic"], ["Land_i_Stone_Shed_V3_F", "shed_domestic"],
    ["Land_i_Stone_Shed_V1_dam_F", "shed_domestic", ["+ruined"]],
    ["Land_i_Stone_Shed_V2_dam_F", "shed_domestic"],
    ["Land_i_Stone_Shed_V3_dam_F", "shed_domestic"],
    ["Land_d_Stone_Shed_V1_F", "shed_domestic", ["+ruined"]],
    ["Land_i_Stone_Shed_01_b_raw_F", "shed_domestic"], ["Land_i_Stone_Shed_01_b_clay_F", "shed_domestic"], ["Land_i_Stone_Shed_01_b_white_F", "shed_domestic"],
    ["Land_i_Stone_Shed_01_c_white_F", "shed_domestic"], ["Land_i_Stone_Shed_01_c_clay_F", "shed_domestic"], ["Land_i_Stone_Shed_01_c_raw_F", "shed_domestic"],
    ["Land_Shed_01_F", "shed_domestic"], ["Land_Shed_02_F", "shed_domestic"], ["Land_Shed_03_F", "shed_domestic"], ["Land_Shed_04_F", "shed_domestic"],
    ["Land_Shed_05_F", "shed_domestic"], ["Land_Shed_06_F", "shed_domestic"], ["Land_Shed_07_F", "shed_domestic"], ["Land_Shed_09_F", "shed_domestic"],
    ["Land_Shed_10_F", "shed_domestic"], ["Land_Shed_11_F", "shed_domestic"], ["Land_Shed_12_F", "shed_domestic"], ["Land_Shed_14_F", "shed_domestic"],
    ["Land_Shed_08_brown_F", "shed_domestic"], ["Land_Shed_08_grey_F", "shed_domestic"],
    ["Land_Caravan_01_rust_F", "shed_domestic"],
    ["Land_Shed_05_ruins_F", "shed_domestic", ["+ruined"]],

    // -- ruin_residential --
    ["Land_HouseRuin_Small_01_half_F", "ruin_residential"],
    ["Land_House_Small_01_V1_ruins_F", "ruin_residential"], ["Land_House_Small_02_V1_ruins_F", "ruin_residential"],
    ["Land_Stone_HouseBig_V1_ruins_F", "ruin_residential"], ["Land_Stone_Shed_V1_ruins_F", "ruin_residential"],
    ["Land_Garage_V1_ruins_F", "ruin_residential"], ["Land_Addon_02_V1_ruins_F", "ruin_residential"], ["Land_Addon_04_V1_ruins_F", "ruin_residential"],
    ["Land_HouseRuin_Big_01_F", "ruin_residential", ["+anchor", "-satellite"]], ["Land_HouseRuin_Big_01_half_F", "ruin_residential", ["+anchor", "-satellite"]],
    ["Land_HouseRuin_Big_02_F", "ruin_residential", ["+anchor", "-satellite"]], ["Land_HouseRuin_Big_02_half_F", "ruin_residential", ["+anchor", "-satellite"]],
    ["Land_HouseRuin_Big_03_half_F", "ruin_residential", ["+anchor", "-satellite"]],
    ["Land_House_Big_01_V1_ruins_F", "ruin_residential", ["+anchor", "-satellite"]], ["Land_House_Big_02_V1_ruins_F", "ruin_residential", ["+anchor", "-satellite"]],

    // ========================================================================
    // commercial
    // ========================================================================

    // -- shop --
    ["Land_i_Shop_01_V1_F", "shop"], ["Land_i_Shop_01_V2_F", "shop"], ["Land_i_Shop_01_V3_F", "shop"],
    ["Land_i_Shop_02_V1_F", "shop"], ["Land_i_Shop_02_V2_F", "shop"], ["Land_i_Shop_02_V3_F", "shop"],
    ["Land_u_Shop_01_V1_F", "shop"], ["Land_u_Shop_02_V1_F", "shop"],
    ["Land_Shop_City_01_F", "shop"], ["Land_Shop_City_02_F", "shop"], ["Land_Shop_City_04_F", "shop"],
    ["Land_Shop_City_05_F", "shop"], ["Land_Shop_City_06_F", "shop"], ["Land_Shop_City_07_F", "shop"],
    ["Land_Shop_Town_01_F", "shop"], ["Land_Shop_Town_03_F", "shop"], ["Land_Shop_Town_05_F", "shop"],
    ["Land_i_Shop_02_b_whiteblue_F", "shop"], ["Land_i_Shop_02_b_brown_F", "shop"], ["Land_i_Shop_02_b_white_F", "shop"],
    ["Land_i_Shop_02_b_yellow_F", "shop"], ["Land_i_Shop_02_b_pink_F", "shop"], ["Land_i_Shop_02_b_blue_F", "shop"],
    ["Land_Shop_Town_02_F", "shop", ["-occupiable", "-anchor"]],

    // -- shop_damaged --
    ["Land_i_Shop_01_V1_dam_F", "shop_damaged"], ["Land_i_Shop_01_V2_dam_F", "shop_damaged"], ["Land_i_Shop_01_V3_dam_F", "shop_damaged"],
    ["Land_i_Shop_02_V1_dam_F", "shop_damaged"], ["Land_i_Shop_02_V2_dam_F", "shop_damaged"], ["Land_i_Shop_02_V3_dam_F", "shop_damaged"],
    ["Land_u_Shop_01_V1_dam_F", "shop_damaged"], ["Land_u_Shop_02_V1_dam_F", "shop_damaged"],
    ["Land_d_Shop_01_V1_F", "shop_damaged"],
    ["Land_d_Shop_02_V1_F", "shop_damaged", ["+satellite", "-anchor"]],
    ["Land_Shop_01_V1_ruins_F", "shop_damaged", ["+ruined"]], ["Land_Shop_02_V1_ruins_F", "shop_damaged", ["+ruined"]],

    // -- office / hotel / school / supermarket / kiosk / village_store --
    ["Land_Offices_01_V1_F", "office"],
    ["Land_Hotel_01_F", "hotel"], ["Land_Hotel_02_F", "hotel"],
    ["Land_School_01_F", "school"],
    ["Land_Supermarket_01_F", "supermarket"], ["Land_Supermarket_01_malden_F", "supermarket"],
    ["Land_Kiosk_blueking_F", "kiosk"], ["Land_Kiosk_gyros_F", "kiosk"], ["Land_Kiosk_papers_F", "kiosk"], ["Land_Kiosk_redburger_F", "kiosk"],
    ["Land_VillageStore_01_F", "village_store"],

    // -- garage_complex --
    ["Land_GarageRow_01_large_F", "garage_complex"], ["Land_GarageOffice_01_F", "garage_complex"],
    ["Land_GarageRow_01_small_F", "garage_complex", ["+satellite", "-anchor"]],

    // -- fuel_station --
    ["Land_FuelStation_Build_F", "fuel_station"], ["Land_FuelStation_Shed_F", "fuel_station"],
    ["Land_FuelStation_01_shop_F", "fuel_station"], ["Land_FuelStation_01_workshop_F", "fuel_station"],
    ["Land_FuelStation_02_workshop_F", "fuel_station"], ["Land_FuelStation_03_shop_F", "fuel_station"],

    // -- stadium --
    ["Land_Stadium_p4_F", "stadium"],
    ["Land_Stadium_p5_F", "stadium"],
    ["Land_Stadium_p9_F", "stadium"],

    // ========================================================================
    // industrial
    // ========================================================================

    // -- factory --
    ["Land_dp_mainFactory_F", "factory"], ["Land_dp_smallFactory_F", "factory"],
    ["Land_DPP_01_mainFactory_F", "factory"], ["Land_Factory_Main_F", "factory"], ["Land_Factory_02_F", "factory"],

    // -- warehouse_big --
    ["Land_Warehouse_01_F", "warehouse_big"], ["Land_Warehouse_02_F", "warehouse_big"], ["Land_Warehouse_03_F", "warehouse_big"],
    ["Land_IndustrialShed_01_F", "warehouse_big"],
    ["Land_SM_01_shed_F", "warehouse_big"],
    ["Land_SM_01_shed_unfinished_F", "warehouse_big"],

    // -- warehouse_small --
    ["Land_Rail_Warehouse_Small_F", "warehouse_small", ["+satellite", "-anchor"]],

    // -- workshop --
    ["Land_Workshop_01_F", "workshop"], ["Land_Workshop_02_F", "workshop"], ["Land_Workshop_03_F", "workshop"],
    ["Land_Workshop_04_F", "workshop"], ["Land_Workshop_05_F", "workshop"],

    // -- autoshop --
    ["Land_CarService_F", "autoshop"],

    // -- shed_industrial --
    ["Land_i_Shed_Ind_F", "shed_industrial"], ["Land_i_Shed_Ind_old_F", "shed_industrial"],
    ["Land_u_Shed_Ind_F", "shed_industrial"], ["Land_Metal_Shed_F", "shed_industrial"],
    ["Land_Shed_Ind_old_ruins_F", "shed_industrial", ["+ruined"]],

    // -- storage_tank --
    ["Land_dp_bigTank_old_F", "storage_tank"], ["Land_StorageTank_01_small_F", "storage_tank"],
    ["Land_dp_bigTank_F", "storage_tank", ["+anchor", "-satellite"]], ["Land_StorageTank_01_large_F", "storage_tank", ["+anchor", "-satellite"]],
    ["Land_dp_tankSmall_F", "storage_tank", ["-occupiable", "-satellite"]], ["Land_dp_tankRound_F", "storage_tank", ["-occupiable", "-satellite"]],
    ["Land_Tank_rust_F", "storage_tank", ["-occupiable", "-satellite"]], ["Land_Ind_TankSmall_F", "storage_tank", ["-occupiable", "-satellite"]],
    ["Land_Ind_TankSmall2_EP1_F", "storage_tank", ["-occupiable", "-satellite"]], ["Land_Ind_SiloVelke_F", "storage_tank", ["-occupiable", "-satellite"]],

    // -- chimney --
    ["Land_Smokestack_01_F", "chimney"], ["Land_Smokestack_01_factory_F", "chimney"], ["Land_SCF_01_chimney_F", "chimney"],

    // -- processing_plant --
    ["Land_SCF_01_boilerBuilding_F", "processing_plant"], ["Land_SCF_01_generalBuilding_F", "processing_plant"],
    ["Land_SCF_01_condenser_F", "processing_plant"], ["Land_SCF_01_diffuser_F", "processing_plant"],
    ["Land_SCF_01_clarifier_F", "processing_plant"], ["Land_SCF_01_washer_F", "processing_plant"],
    ["Land_SCF_01_crystallizer_F", "processing_plant"], ["Land_SCF_01_crystallizerTowers_F", "processing_plant"],
    ["Land_CementWorks_01_grey_F", "processing_plant"], ["Land_CementWorks_01_brick_F", "processing_plant"],
    ["Land_SCF_01_feeder_F", "processing_plant", ["+satellite", "-anchor"]],
    ["Land_SCF_01_storageBin_big_F", "processing_plant", ["+satellite", "-anchor"]],
    ["Land_SCF_01_storageBin_medium_F", "processing_plant", ["+satellite", "-anchor"]],
    ["Land_SCF_01_storageBin_small_F", "processing_plant", ["+satellite", "-anchor"]],

    // -- mine_site --
    ["Land_HaulTruck_01_abandoned_F", "mine_site", ["-occupiable"]],
    ["Land_MiningShovel_01_abandoned_F", "mine_site", ["-occupiable"]],
    ["Land_Mine_01_warehouse_F", "mine_site", ["+anchor", "-satellite"]],

    // -- pipeline --
    ["Land_IndPipe1_ground_F", "pipeline"], ["Land_IndPipe1_20m_F", "pipeline"],
    ["Land_Pipes_large_F", "pipeline", ["-occupiable"]],

    // -- construction_site --
    ["Land_Unfinished_Building_01_F", "construction_site"], ["Land_Unfinished_Building_02_F", "construction_site"],
    ["Land_Unfinished_Building_01_noLadder_F", "construction_site"], ["Land_WIP_F", "construction_site"],
    ["Land_Unfinished_Building_01_ruins_F", "construction_site", ["+ruined"]], ["Land_Unfinished_Building_02_ruins_F", "construction_site", ["+ruined"]],

    // ========================================================================
    // agricultural
    // ========================================================================

    ["Land_Barn_01_grey_F", "barn_large"], ["Land_Barn_01_brown_F", "barn_large"], ["Land_Barn_03_large_F", "barn_large"], ["Land_Barn_04_F", "barn_large"],
    ["Land_Barn_02_F", "barn_small"], ["Land_Barn_03_small_F", "barn_small"],
    ["Land_Cowshed_01_B_F", "livestock_shed"], ["Land_Cowshed_01_C_F", "livestock_shed"], ["Land_FeedShack_01_F", "livestock_shed"],
    ["Land_Cowshed_01_A_F", "livestock_shed", ["+anchor", "-satellite"]],
    ["Land_Sawmill_01_F", "sawmill"],
    ["Land_Sawmill_01_illuminati_tower_F", "sawmill", ["+sentry_only"]],
    ["Land_i_Windmill01_F", "windmill"], ["Land_d_Windmill01_F", "windmill"],
    ["Land_Greenhouse_01_F", "greenhouse"],
    ["Land_Silo_01_F", "grain_silo"], ["Land_Silo_Wheat_F", "grain_silo"],
    ["Land_DeerStand_02_F", "hunting_stand"],

    // ========================================================================
    // medical
    // ========================================================================

    ["Land_Hospital_main_F", "hospital"], ["Land_Hospital_side1_F", "hospital"], ["Land_Hospital_side2_F", "hospital"],
    ["Land_HealthCenter_01_F", "clinic"],

    // -- field_hospital (33 MedicalTent classes + Medevac_HQ; Medevac_house overridden to satellite) --
    ["Land_MedicalTent_01_tropic_closed_F", "field_hospital"],
    ["Land_MedicalTent_01_MTP_closed_F", "field_hospital"],
    ["Land_MedicalTent_01_greenhex_closed_F", "field_hospital"],
    ["Land_MedicalTent_01_brownhex_closed_F", "field_hospital"],
    ["Land_MedicalTent_01_digital_closed_F", "field_hospital"],
    ["Land_MedicalTent_01_white_IDAP_med_closed_F", "field_hospital"],
    ["Land_MedicalTent_01_white_generic_closed_F", "field_hospital"],
    ["Land_MedicalTent_01_white_generic_open_F", "field_hospital"],
    ["Land_MedicalTent_01_white_generic_outer_F", "field_hospital"],
    ["Land_MedicalTent_01_white_generic_inner_F", "field_hospital"],
    ["Land_MedicalTent_01_white_IDAP_closed_F", "field_hospital"],
    ["Land_MedicalTent_01_white_IDAP_open_F", "field_hospital"],
    ["Land_MedicalTent_01_white_IDAP_outer_F", "field_hospital"],
    ["Land_MedicalTent_01_aaf_generic_inner_F", "field_hospital"],
    ["Land_MedicalTent_01_aaf_generic_closed_F", "field_hospital"],
    ["Land_MedicalTent_01_aaf_generic_open_F", "field_hospital"],
    ["Land_MedicalTent_01_aaf_generic_outer_F", "field_hospital"],
    ["Land_MedicalTent_01_NATO_generic_inner_F", "field_hospital"],
    ["Land_MedicalTent_01_NATO_generic_closed_F", "field_hospital"],
    ["Land_MedicalTent_01_NATO_generic_open_F", "field_hospital"],
    ["Land_MedicalTent_01_NATO_generic_outer_F", "field_hospital"],
    ["Land_MedicalTent_01_NATO_tropic_generic_inner_F", "field_hospital"],
    ["Land_MedicalTent_01_NATO_tropic_generic_closed_F", "field_hospital"],
    ["Land_MedicalTent_01_NATO_tropic_generic_open_F", "field_hospital"],
    ["Land_MedicalTent_01_NATO_tropic_generic_outer_F", "field_hospital"],
    ["Land_MedicalTent_01_CSAT_brownhex_generic_inner_F", "field_hospital"],
    ["Land_MedicalTent_01_CSAT_brownhex_generic_closed_F", "field_hospital"],
    ["Land_MedicalTent_01_CSAT_brownhex_generic_open_F", "field_hospital"],
    ["Land_MedicalTent_01_CSAT_brownhex_generic_outer_F", "field_hospital"],
    ["Land_MedicalTent_01_CSAT_greenhex_generic_inner_F", "field_hospital"],
    ["Land_MedicalTent_01_CSAT_greenhex_generic_closed_F", "field_hospital"],
    ["Land_MedicalTent_01_CSAT_greenhex_generic_open_F", "field_hospital"],
    ["Land_MedicalTent_01_CSAT_greenhex_generic_outer_F", "field_hospital"],
    ["Land_Medevac_HQ_V1_F", "field_hospital"],
    ["Land_Medevac_house_V1_F", "field_hospital", ["+satellite", "-anchor"]],

    // -- decon_facility --
    ["Land_DeconTent_01_white_F", "decon_facility"], ["Land_DeconTent_01_yellow_F", "decon_facility"], ["Land_DeconTent_01_IDAP_F", "decon_facility"],
    ["Land_DeconTent_01_CSAT_brownhex_F", "decon_facility"], ["Land_DeconTent_01_CSAT_greenhex_F", "decon_facility"],
    ["Land_DeconTent_01_NATO_F", "decon_facility"], ["Land_DeconTent_01_NATO_tropic_F", "decon_facility"], ["Land_DeconTent_01_AAF_F", "decon_facility"],

    // ========================================================================
    // religious
    // ========================================================================

    ["Land_Church_01_F", "church"], ["Land_Church_02_F", "church"], ["Land_Church_03_F", "church"],
    ["Land_Cathedral_01_F", "church"], ["Land_Church_01_V1_F", "church"],
    ["Land_Church_04_lightblue_F", "church"], ["Land_Church_04_yellow_F", "church"], ["Land_Church_04_white_red_F", "church"],
    ["Land_Church_04_red_F", "church"], ["Land_Church_04_damaged_F", "church"], ["Land_Church_04_yellow_damaged_F", "church"],
    ["Land_Church_05_F", "church", ["+satellite", "-anchor"]],
    ["Land_Chapel_Small_V1_F", "chapel"], ["Land_Chapel_Small_V2_F", "chapel"], ["Land_Chapel_V1_F", "chapel"], ["Land_Chapel_V2_F", "chapel"],
    ["Land_Chapel_02_white_F", "chapel"], ["Land_Chapel_02_yellow_F", "chapel"],
    ["Land_Chapel_02_white_damaged_F", "chapel"], ["Land_Chapel_02_yellow_damaged_F", "chapel"],
    ["Land_Chapel_02_white_ruins_F", "ruin_church"], ["Land_Chapel_02_yellow_ruins_F", "ruin_church"],
    ["Land_ChurchRuin_01_F", "ruin_church", ["+anchor", "-satellite"]],
    ["Land_Mausoleum_01_F", "mausoleum"],
    ["Land_Temple_Native_01_F", "temple"],

    // ========================================================================
    // infrastructure
    // ========================================================================
    
    ["Land_CoalPlant_01_MainBuilding_F", "power_station"],
    ["Land_PowerStation_01_F", "power_station", ["+satellite", "-anchor"]],
    ["Land_PowerGenerator_F", "power_station", ["-occupiable", "-anchor"]],
    ["Land_Substation_01_F", "power_substation"],
    ["Land_spp_Transformer_F", "power_substation", ["-occupiable", "-satellite"]],
    ["Land_PowerLine_01_pole_transformer_F", "power_substation", ["-occupiable", "-satellite"]],
    ["Land_PowerLine_distributor_F", "power_distribution"],
    ["Land_spp_Tower_F", "solar_array"],
    ["Land_spp_Panel_F", "solar_array", ["-occupiable", "-anchor"]],
    ["Land_Communication_F", "comms_tower"], ["Land_TTowerBig_1_F", "comms_tower"], ["Land_TTowerBig_2_F", "comms_tower"],
    ["Land_TTowerSmall_1_F", "comms_relay"],
    ["Land_TTowerSmall_2_F", "comms_relay"],
    ["Land_Communication_anchor_F", "comms_relay"],
    ["Land_WaterStation_01_F", "water_facility"],
    ["Land_ReservoirTank_V1_F", "water_facility", ["-occupiable", "-satellite"]],
    ["Land_WaterTower_01_F", "water_facility", ["-occupiable", "-satellite"]],
    ["Land_WaterTank_F", "water_facility", ["-occupiable", "-satellite"]],
    ["Land_FuelStation_Feed_F", "fuel_infrastructure"],
    ["Land_Rail_Station_Big_F", "rail_station"],
    ["Land_LightHouse_F", "lighthouse"], ["Land_Lighthouse_03_red_F", "lighthouse"], ["Land_Lighthouse_03_green_F", "lighthouse"],
    ["Land_Lighthouse_small_F", "lighthouse", ["+satellite", "-anchor"]],
    ["Land_Radar_F", "radar_site"], ["Land_Radar_01_HQ_F", "radar_site"], ["Land_Radar_01_antenna_base_F", "radar_site"],
    ["Land_Radar_01_kitchen_F", "radar_site"],
    ["Land_Radar_01_antenna_F", "radar_site", ["+satellite", "-anchor"]], ["Land_Radar_01_cooler_F", "radar_site", ["+satellite", "-anchor"]],
    ["Land_MobileRadar_01_radar_F", "radar_site", ["+satellite", "-anchor"]],
    ["Land_Radar_Small_F", "radar_site", ["-occupiable", "-anchor"]],
    ["Land_Bridge_HighWay_PathLod_F", "bridge"],
    ["Land_Bridge_01_PathLod_F", "bridge"],
    ["Land_Bridge_Asphalt_PathLod_F", "bridge"],
    ["Land_Bridge_Concrete_PathLod_F", "bridge"],
    ["Land_Canal_Wall_Stairs_F", "bridge", ["+sentry_only"]],

    // ========================================================================
    // port
    // ========================================================================

    ["Land_SY_01_crusher_F", "shipyard"], ["Land_SY_01_shiploader_F", "shipyard"], ["Land_SY_01_shiploader_arm_F", "shipyard"],
    ["Land_DryDock_01_end_F", "shipyard"], ["Land_DryDock_01_middle_F", "shipyard"],
    ["Land_SY_01_reclaimer_F", "shipyard", ["+satellite", "-anchor"]], ["Land_SY_01_conveyor_end_F", "shipyard", ["+satellite", "-anchor"]],
    ["Land_ContainerLine_01_F", "container_terminal"], ["Land_ContainerLine_02_F", "container_terminal"], ["Land_ContainerLine_03_F", "container_terminal"],
    ["Land_Pier_F", "pier"], ["Land_Pier_small_F", "pier"], ["Land_nav_pier_m_F", "pier"],
    ["Land_PierWooden_01_dock_F", "pier"], ["Land_PierWooden_01_hut_F", "pier"], ["Land_PierWooden_01_platform_F", "pier"],
    ["Land_PierWooden_01_16m_F", "pier"], ["Land_PierWooden_01_10m_noRails_F", "pier"],
    ["Land_PierWooden_02_16m_F", "pier"], ["Land_PierWooden_02_30deg_F", "pier"], ["Land_PierWooden_02_ladder_F", "pier"],
    ["Land_PierWooden_02_barrel_F", "pier"], ["Land_PierWooden_02_hut_F", "pier"],
    ["Land_Crane_F", "crane"], ["Land_ContainerCrane_01_F", "crane"], ["Land_MobileCrane_01_F", "crane"], ["Land_MobileCrane_01_hook_F", "crane"],
    ["Land_NavigLight_F", "navigation_aid"], ["Land_Bollard_01_F", "navigation_aid"],

    // ========================================================================
    // airport
    // ========================================================================

    ["Land_Airport_01_terminal_F", "terminal"], ["Land_Airport_02_terminal_F", "terminal"],
    ["Land_Airport_left_F", "terminal"], ["Land_Airport_right_F", "terminal"],
    ["Land_Airport_01_hangar_F", "hangar"], ["Land_Airport_02_hangar_left_F", "hangar"], ["Land_Airport_02_hangar_right_F", "hangar"],
    ["Land_ServiceHangar_01_L_F", "hangar"], ["Land_ServiceHangar_01_R_F", "hangar"],
    ["Land_Hangar_F", "hangar", ["+military"]],
    ["Land_Airport_01_controlTower_F", "control_tower"], ["Land_Airport_02_controlTower_F", "control_tower"],
    ["Land_ControlTower_01_F", "control_tower"], ["Land_ControlTower_02_F", "control_tower"],
    ["Land_Airport_Tower_F", "control_tower", ["+military"]], ["Land_Airport_Tower_dam_F", "control_tower", ["+military"]],

    // ========================================================================
    // law_enforcement
    // ========================================================================

    ["Land_PoliceStation_01_F", "police_station"],

    // ========================================================================
    // military
    // ========================================================================

    // -- barracks (13) --
    ["Land_i_Barracks_V1_F", "barracks"], ["Land_i_Barracks_V2_F", "barracks"], ["Land_u_Barracks_V2_F", "barracks"],
    ["Land_Barracks_01_camo_F", "barracks"], ["Land_Barracks_01_grey_F", "barracks"], ["Land_Barracks_01_dilapidated_F", "barracks"],
    ["Land_Barracks_02_F", "barracks"], ["Land_Barracks_03_F", "barracks"], ["Land_Barracks_04_F", "barracks"],
    ["Land_Barracks_05_F", "barracks"], ["Land_Barracks_06_F", "barracks"],
    ["Land_i_Barracks_V1_dam_F", "barracks"], ["Land_i_Barracks_V2_dam_F", "barracks"],

    // -- bunker (13) --
    ["Land_Bunker_01_small_F", "bunker"],
    ["Land_Bunker_02_right_F", "bunker"], ["Land_Bunker_02_left_F", "bunker"], ["Land_Bunker_02_double_F", "bunker"],
    ["Land_Bunker_02_light_double_F", "bunker"], ["Land_Bunker_02_light_left_F", "bunker"], ["Land_Bunker_02_light_right_F", "bunker"],
    ["Land_Bunker_01_big_F", "bunker", ["+anchor", "-satellite"]], ["Land_Bunker_01_HQ_F", "bunker", ["+anchor", "-satellite"]],
    ["Land_Bunker_01_tall_F", "bunker", ["+anchor", "-satellite"]], ["Land_PillboxBunker_01_big_F", "bunker", ["+anchor", "-satellite"]],
    ["Land_PillboxBunker_01_rectangle_F", "bunker", ["+anchor", "-satellite"]], ["Land_PillboxBunker_01_hex_F", "bunker", ["+anchor", "-satellite"]],

    // -- guard_post (9) --
    ["Land_GuardHouse_01_F", "guard_post"], ["Land_GuardHouse_02_F", "guard_post"], ["Land_GuardHouse_02_grey_F", "guard_post"],
    ["Land_GuardHouse_03_F", "guard_post"], ["Land_GuardBox_01_green_F", "guard_post"], ["Land_GuardBox_01_brown_F", "guard_post"],
    ["Land_GuardBox_01_smooth_F", "guard_post"], ["Land_GuardTower_01_F", "guard_post"], ["Land_GuardTower_02_F", "guard_post"],

    // -- cargo_structure (10) --
    ["Cargo_Patrol_base_F", "cargo_structure"], ["Cargo_Tower_base_F", "cargo_structure"],
    ["Land_Cargo_House_V1_F", "cargo_structure"], ["Land_Cargo_House_V2_F", "cargo_structure"],
    ["Land_Cargo_House_V3_F", "cargo_structure"], ["Land_Cargo_House_V4_F", "cargo_structure"],
    ["Land_Cargo_House_V3_derelict_F", "cargo_structure"], ["Land_Cargo_Tower_V3_derelict_F", "cargo_structure"],
    ["Land_Cargo_Patrol_V2_ruins_F", "cargo_structure", ["+ruined"]], ["Land_Cargo_Patrol_V3_ruins_F", "cargo_structure", ["+ruined"]],

    // -- command_post (5) --
    ["Cargo_HQ_base_F", "command_post"], ["Land_MilOffices_V1_F", "command_post"],
    ["Land_Research_house_V1_F", "command_post"],
    ["Land_Research_HQ_F", "command_post"],
    ["Land_Cargo_HQ_V3_derelict_F", "command_post"],

    // -- camp_tent (18) --
    ["Land_ConnectorTent_01_white_open_F", "camp_tent"], ["Land_ConnectorTent_01_white_closed_F", "camp_tent"], ["Land_ConnectorTent_01_white_cross_F", "camp_tent"],
    ["Land_ConnectorTent_01_CSAT_brownhex_open_F", "camp_tent"], ["Land_ConnectorTent_01_CSAT_brownhex_closed_F", "camp_tent"], ["Land_ConnectorTent_01_CSAT_brownhex_cross_F", "camp_tent"],
    ["Land_ConnectorTent_01_CSAT_greenhex_open_F", "camp_tent"], ["Land_ConnectorTent_01_CSAT_greenhex_closed_F", "camp_tent"], ["Land_ConnectorTent_01_CSAT_greenhex_cross_F", "camp_tent"],
    ["Land_ConnectorTent_01_NATO_open_F", "camp_tent"], ["Land_ConnectorTent_01_NATO_closed_F", "camp_tent"], ["Land_ConnectorTent_01_NATO_cross_F", "camp_tent"],
    ["Land_ConnectorTent_01_NATO_tropic_open_F", "camp_tent"], ["Land_ConnectorTent_01_NATO_tropic_closed_F", "camp_tent"], ["Land_ConnectorTent_01_NATO_tropic_cross_F", "camp_tent"],
    ["Land_ConnectorTent_01_AAF_open_F", "camp_tent"], ["Land_ConnectorTent_01_AAF_closed_F", "camp_tent"], ["Land_ConnectorTent_01_AAF_cross_F", "camp_tent"],

    // -- camp_house / helipad / fortification / dome --
    ["Land_Camp_House_01_brown_F", "camp_house"],
    ["Land_HelipadCircle_F", "helipad"], ["Land_HelipadSquare_F", "helipad"], ["Land_HelipadRescue_F", "helipad"],
    ["Land_HBarrier_Big_F", "fortification"], ["Land_HBarrier_1_F", "fortification"],
    ["Land_Dome_Small_WIP_F", "dome"],
    ["Land_Dome_Small_WIP2_F", "dome"],
    ["Land_Dome_Big_F", "dome", ["-occupiable", "-satellite"]], ["Land_Dome_Small_F", "dome", ["-occupiable", "-satellite"]]
];

// ============================================================================
// Derive everything else (§A3)
// ============================================================================
private _byClass = createHashMap;
private _bySubtype = createHashMap;
private _byFlag = createHashMap;

private _mainMilitary = [];
private _mainCivilian = [];
private _sideMilitary = [];
private _sideCivilian = [];

private _functionalCategories = createHashMap;
private _functionalLookup = createHashMap;
private _nonOccupiable = createHashMap;
private _nonOccupiableLookup = createHashMap;

private _duplicateClassCount = 0;

{
    _x params [["_class", "", [""]], ["_subtype", "", [""]], ["_overrides", [], [[]]]];

    if !(_subtype in _subtypeInfo) then {
        ERROR_2("getStructureCatalog - class '%1' references unknown subtype '%2', skipping",_class,_subtype);
        continue;
    };

    if (_class in _byClass) then {
        _duplicateClassCount = _duplicateClassCount + 1;
        ERROR_1("getStructureCatalog - duplicate class '%1' in Table 2, keeping first occurrence",_class);
        continue;
    };

    private _subInfo = _subtypeInfo get _subtype;
    private _category = _subInfo get "category";
    private _displayName = _subInfo get "displayName";
    private _flags = +(_subInfo get "flags");

    {
        private _token = _x;
        private _sign = _token select [0, 1];
        private _flagName = _token select [1, (count _token) - 1];

        if !(_flagName in _knownFlags) then {
            ERROR_2("getStructureCatalog - class '%1' has unknown override flag '%2'",_class,_flagName);
        } else {
            if (_sign == "+") then {
                _flags pushBackUnique _flagName;
            } else {
                _flags = _flags - [_flagName];
            };
        };
    } forEach _overrides;

    private _isOccupiable = "occupiable" in _flags;
    private _isRuined = "ruined" in _flags;
    private _isMilitary = "military" in _flags;
    private _isAnchor = "anchor" in _flags;
    private _isSatellite = "satellite" in _flags;

    // Derived flags (computed, never authored) — §A3
    if (_isOccupiable && {!_isRuined} && {!_isMilitary} && {_category == "residential"} && {!(_subtype in _civilianHomeExcludedSubtypes)}) then {
        _flags pushBackUnique "civilian_home";
    };
    if (_isOccupiable && {!_isRuined} && {_category in _workplaceCategories}) then {
        _flags pushBackUnique "workplace";
    };
    if (_isOccupiable && {!_isRuined} && {!_isMilitary} && {_category in _publicAccessCategories}) then {
        _flags pushBackUnique "public_access";
    };

    _byClass set [_class, createHashMapFromArray [
        ["subtype", _subtype],
        ["category", _category],
        ["displayName", _displayName],
        ["flags", _flags]
    ]];

    private _subtypeClasses = _bySubtype getOrDefault [_subtype, []];
    _subtypeClasses pushBack _class;
    _bySubtype set [_subtype, _subtypeClasses];

    {
        private _flagClasses = _byFlag getOrDefault [_x, []];
        _flagClasses pushBackUnique _class;
        _byFlag set [_x, _flagClasses];
    } forEach _flags;

    if (_isAnchor) then {
        if (_isMilitary) then { _mainMilitary pushBack _class } else { _mainCivilian pushBack _class };
    };
    if (_isSatellite) then {
        if (_isMilitary) then { _sideMilitary pushBack _class } else { _sideCivilian pushBack _class };
    };

    if (_isOccupiable) then {
        private _catClasses = _functionalCategories getOrDefault [_category, []];
        _catClasses pushBack _class;
        _functionalCategories set [_category, _catClasses];
        _functionalLookup set [_class, _category];
    } else {
        private _catClasses = _nonOccupiable getOrDefault [_category, []];
        _catClasses pushBack _class;
        _nonOccupiable set [_category, _catClasses];
        _nonOccupiableLookup set [_class, _category];
    };
} forEach _table2;

// ============================================================================
// Per-map exclusions — moved verbatim from fnc_getStructureTypes.sqf.
// Not derivable from category/subtype; stays hand-authored per map.
// ============================================================================
private _mapExclusions = createHashMapFromArray [
    ["Altis", [
        "Land_Cargo_Patrol_V2_F",
        "Land_Cargo_Tower_V2_F",
        "Land_Cargo_HQ_V2_F",
        "Land_Cargo_House_V2_F"
    ]],
    ["Stratis", []],
    ["Tanoa", []],
    ["Malden", []],
    ["Enoch", [
        "Land_DeerStand_02_F"
    ]]
];

private _currentMap = worldName;
private _exclusions = _mapExclusions getOrDefault [_currentMap, []];

if (_exclusions isNotEqualTo []) then {
    private _exclCount = count _exclusions;
    INFO_2("getStructureCatalog - Map %1: %2 exclusion rules active",_currentMap,_exclCount);
};

// ============================================================================
// Combine and cache
// ============================================================================
private _tableRowCount = count _table2;
private _classCount = count _byClass;

INFO_2("getStructureCatalog - built catalog: %1 classes, %2 subtypes",_classCount,count _subtypeInfo);

private _result = createHashMapFromArray [
    ["byClass", _byClass],
    ["bySubtype", _bySubtype],
    ["byCategory", _byCategory],
    ["subtypeInfo", _subtypeInfo],
    ["byFlag", _byFlag],
    ["main", _mainMilitary + _mainCivilian],
    ["side", _sideMilitary + _sideCivilian],
    ["mainMilitary", _mainMilitary],
    ["mainCivilian", _mainCivilian],
    ["sideMilitary", _sideMilitary],
    ["sideCivilian", _sideCivilian],
    ["exclusions", _exclusions],
    ["functionalCategories", _functionalCategories],
    ["functionalLookup", _functionalLookup],
    ["nonOccupiable", _nonOccupiable],
    ["nonOccupiableLookup", _nonOccupiableLookup],
    ["tableRowCount", _tableRowCount],
    ["duplicateClassCount", _duplicateClassCount]
];

missionNamespace setVariable ["DSC_structureCatalogCache", _result];

_result
