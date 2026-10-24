#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_getStructureSubtypes
 * Description:
 *     Returns Table 1 of the structure taxonomy (Session 01 — Ambient World
 *     Overhaul, docs/overhauls/ambient_world/session_01_structure_taxonomy.md
 *     "Approved Mini-Spec" §A4). Pure data, hand-authored, 83 rows.
 *
 *     Every row is [subtype <STRING>, category <STRING>, displayName <STRING>,
 *     defaultFlags <ARRAY of STRING>]. Every subtype belongs to exactly one
 *     of the 11 fixed categories (Decision Log B15-B19):
 *         residential, commercial, industrial, agricultural, medical,
 *         religious, infrastructure, port, airport, law_enforcement, military
 *
 *     Authored flag vocabulary (12): occupiable, anchor, satellite, military,
 *     sentry_only, hvt_suitable, hostage_suitable, ruined, landmark,
 *     infrastructure_node, sabotage_target, hackable.
 *
 *     Three more flags (workplace, public_access, civilian_home) are DERIVED
 *     at catalog build time (see fnc_getStructureCatalog, §A3) and must never
 *     appear in this table.
 *
 *     Category `military` is both a category (purpose-built structures with
 *     no civilian analogue) and a flag (affiliation, true for every class in
 *     the category plus crossover classes authored elsewhere via a Table 2
 *     "+military" override). Invariant: category military => flag military.
 *
 *     This function performs no validation — it is pure data. Vocabulary and
 *     cross-reference validation happens once, at catalog build time, in
 *     fnc_getStructureCatalog.
 *
 * Arguments: None
 *
 * Return Value:
 *     <ARRAY> - Array of [subtype, category, displayName, defaultFlags] rows.
 *
 * Example:
 *     private _subtypes = call DSC_core_fnc_getStructureSubtypes;
 */

[
    // ========================================================================
    // residential (12)
    // ========================================================================
    ["house_small",          "residential", "a small house",                ["occupiable", "anchor"]],
    ["house_small_damaged",  "residential", "a damaged house",               ["occupiable", "anchor"]],
    ["house_big",            "residential", "a large house",                 ["occupiable", "anchor", "hostage_suitable"]],
    ["house_big_damaged",    "residential", "a damaged two-storey house",    ["occupiable", "anchor", "hostage_suitable"]],
    ["apartment_block",      "residential", "an apartment block",            ["occupiable", "anchor", "hostage_suitable", "hvt_suitable"]],
    ["estate",               "residential", "an estate",                     ["occupiable", "anchor", "hostage_suitable", "hvt_suitable", "landmark"]],
    ["castle",               "residential", "a castle",                      ["occupiable", "anchor", "sentry_only", "landmark"]],
    ["slum",                 "residential", "a shanty",                      ["occupiable", "satellite", "hostage_suitable"]],
    ["house_annex",          "residential", "an outbuilding",                ["occupiable", "satellite"]],
    ["garage_private",       "residential", "a garage",                      ["occupiable", "satellite", "hostage_suitable"]],
    ["shed_domestic",        "residential", "a shed",                        ["occupiable", "satellite", "hostage_suitable"]],
    ["ruin_residential",     "residential", "a ruined building",             ["occupiable", "satellite", "ruined"]],

    // ========================================================================
    // commercial (11)
    // ========================================================================
    ["shop",                 "commercial", "a shop",                         ["occupiable", "anchor"]],
    ["shop_damaged",         "commercial", "a derelict shop",                ["occupiable", "anchor"]],
    ["office",               "commercial", "an office building",            ["occupiable", "anchor", "hostage_suitable", "hvt_suitable", "landmark"]],
    ["hotel",                "commercial", "a hotel",                        ["occupiable", "anchor", "hostage_suitable", "hvt_suitable", "landmark"]],
    ["school",               "commercial", "a school",                       ["occupiable", "anchor", "hostage_suitable", "hvt_suitable", "landmark"]],
    ["supermarket",          "commercial", "a supermarket",                  ["occupiable", "anchor", "hostage_suitable", "landmark"]],
    ["kiosk",                "commercial", "a kiosk",                        ["occupiable", "satellite"]],
    ["village_store",        "commercial", "a village store",                ["occupiable", "satellite"]],
    ["garage_complex",       "commercial", "a garage complex",               ["occupiable", "anchor", "hostage_suitable"]],
    ["fuel_station",         "commercial", "a petrol station",               ["occupiable", "satellite", "landmark"]],
    ["stadium",              "commercial", "a stadium",                      ["occupiable", "satellite", "landmark"]],

    // ========================================================================
    // industrial (12)
    // ========================================================================
    ["factory",              "industrial", "a factory",                      ["occupiable", "anchor", "hostage_suitable", "landmark"]],
    ["warehouse_big",        "industrial", "a large warehouse",              ["occupiable", "anchor", "hostage_suitable"]],
    ["warehouse_small",      "industrial", "a storage shed",                 ["occupiable", "anchor", "hostage_suitable"]],
    ["workshop",             "industrial", "a workshop",                     ["occupiable", "satellite", "hostage_suitable"]],
    ["autoshop",             "industrial", "an auto repair shop",            ["occupiable", "anchor", "hostage_suitable"]],
    ["shed_industrial",      "industrial", "an industrial shed",             ["occupiable", "satellite", "hostage_suitable"]],
    ["storage_tank",         "industrial", "a storage tank",                 ["occupiable", "satellite", "sentry_only"]],
    ["chimney",              "industrial", "a smokestack",                   ["occupiable", "anchor", "sentry_only", "landmark"]],
    ["processing_plant",     "industrial", "a processing plant",             ["occupiable", "anchor", "hostage_suitable", "landmark"]],
    ["mine_site",            "industrial", "a mine",                         ["occupiable", "satellite", "landmark"]],
    ["pipeline",             "industrial", "a pipeline run",                 []],
    ["construction_site",    "industrial", "an unfinished building",         ["occupiable", "anchor", "sentry_only"]],

    // ========================================================================
    // agricultural (8)
    // ========================================================================
    ["barn_large",           "agricultural", "a large barn",                 ["occupiable", "anchor", "hostage_suitable"]],
    ["barn_small",           "agricultural", "a barn",                       ["occupiable", "satellite", "hostage_suitable"]],
    ["livestock_shed",       "agricultural", "a livestock shed",             ["occupiable", "satellite", "hostage_suitable"]],
    ["sawmill",              "agricultural", "a sawmill",                    ["occupiable", "satellite", "landmark"]],
    ["windmill",             "agricultural", "a windmill",                   ["occupiable", "satellite", "sentry_only", "landmark"]],
    ["greenhouse",           "agricultural", "a greenhouse",                 []],
    ["grain_silo",           "agricultural", "a grain silo",                 ["sentry_only"]],
    ["hunting_stand",        "agricultural", "a hunting stand",              ["occupiable", "satellite", "sentry_only"]],

    // ========================================================================
    // medical (4)
    // ========================================================================
    ["hospital",             "medical", "a hospital",                        ["occupiable", "anchor", "hostage_suitable", "hvt_suitable", "landmark"]],
    ["clinic",               "medical", "a health centre",                   ["occupiable", "anchor", "hostage_suitable", "landmark"]],
    ["field_hospital",       "medical", "a field hospital",                  ["occupiable", "anchor", "military", "hostage_suitable"]],
    ["decon_facility",       "medical", "a decontamination facility",        ["occupiable", "anchor", "military"]],

    // ========================================================================
    // religious (5)
    // ========================================================================
    ["church",               "religious", "a church",                       ["occupiable", "anchor", "hostage_suitable", "landmark"]],
    ["chapel",               "religious", "a chapel",                       ["occupiable", "satellite", "hostage_suitable", "landmark"]],
    ["ruin_church",          "religious", "a ruined church",                ["occupiable", "satellite", "ruined", "landmark"]],
    ["mausoleum",            "religious", "a mausoleum",                    ["occupiable", "satellite", "landmark"]],
    ["temple",               "religious", "a temple",                       ["occupiable", "anchor", "hostage_suitable", "landmark"]],

    // ========================================================================
    // infrastructure (12)
    // ========================================================================
    ["power_station",        "infrastructure", "a power station",            ["occupiable", "anchor", "infrastructure_node", "sabotage_target", "hackable", "landmark"]],
    ["power_substation",     "infrastructure", "an electrical substation",   ["occupiable", "satellite", "infrastructure_node", "sabotage_target", "landmark"]],
    ["power_distribution",   "infrastructure", "a power line",               ["infrastructure_node", "sabotage_target"]],
    ["solar_array",          "infrastructure", "a solar array",              ["occupiable", "anchor", "infrastructure_node", "sabotage_target", "landmark"]],
    ["comms_tower",          "infrastructure", "a communications tower",     ["infrastructure_node", "sabotage_target", "hackable", "landmark"]],
    ["comms_relay",          "infrastructure", "a relay mast",               ["infrastructure_node", "sabotage_target", "hackable"]],
    ["water_facility",       "infrastructure", "a water facility",           ["occupiable", "satellite", "infrastructure_node", "sabotage_target", "landmark"]],
    ["fuel_infrastructure",  "infrastructure", "a fuel depot",               ["infrastructure_node", "sabotage_target", "sentry_only"]],
    ["rail_station",         "infrastructure", "a railway station",         ["occupiable", "anchor", "hostage_suitable", "landmark"]],
    ["lighthouse",           "infrastructure", "a lighthouse",               ["occupiable", "anchor", "sentry_only", "landmark"]],
    ["radar_site",           "infrastructure", "a radar site",               ["occupiable", "anchor", "military", "infrastructure_node", "sabotage_target", "hackable", "landmark"]],
    ["bridge",               "infrastructure", "a bridge",                   ["occupiable", "satellite", "infrastructure_node", "sabotage_target", "landmark"]],

    // ========================================================================
    // port (5)
    // ========================================================================
    ["shipyard",             "port", "a shipyard",                          ["occupiable", "anchor", "landmark"]],
    ["container_terminal",   "port", "a container terminal",                ["occupiable", "anchor", "landmark"]],
    ["pier",                 "port", "a pier",                              ["occupiable", "satellite"]],
    ["crane",                "port", "a dockside crane",                    ["occupiable", "satellite", "sentry_only", "landmark"]],
    ["navigation_aid",       "port", "a navigation light",                  []],

    // ========================================================================
    // airport (3)
    // ========================================================================
    ["terminal",             "airport", "an airport terminal",              ["occupiable", "anchor", "hostage_suitable", "hvt_suitable", "landmark"]],
    ["hangar",               "airport", "a hangar",                        ["occupiable", "anchor", "hostage_suitable", "landmark"]],
    ["control_tower",        "airport", "a control tower",                  ["occupiable", "anchor", "sentry_only", "landmark"]],

    // ========================================================================
    // law_enforcement (1)
    // ========================================================================
    ["police_station",       "law_enforcement", "a police station",         ["occupiable", "anchor", "hostage_suitable", "hvt_suitable", "landmark"]],

    // ========================================================================
    // military (10) — every row carries "military" by the B23 invariant
    // ========================================================================
    ["barracks",             "military", "a barracks",                      ["occupiable", "anchor", "military", "hostage_suitable", "hvt_suitable", "landmark"]],
    ["bunker",               "military", "a bunker",                        ["occupiable", "satellite", "military", "sentry_only"]],
    ["guard_post",           "military", "a guard post",                    ["occupiable", "satellite", "military", "sentry_only"]],
    ["cargo_structure",      "military", "a prefab logistics building",     ["occupiable", "satellite", "military", "hostage_suitable"]],
    ["command_post",         "military", "a command post",                  ["occupiable", "anchor", "military", "hostage_suitable", "hvt_suitable", "landmark"]],
    ["camp_tent",            "military", "a camp tent",                     ["occupiable", "satellite", "military", "hostage_suitable"]],
    ["camp_house",           "military", "a camp hut",                      ["occupiable", "satellite", "military", "hostage_suitable"]],
    ["helipad",              "military", "a helipad",                       ["military"]],
    ["fortification",        "military", "a barrier emplacement",           ["military", "sentry_only"]],
    ["dome",                 "military", "a radome",                        ["occupiable", "satellite", "military", "sentry_only"]]
]
