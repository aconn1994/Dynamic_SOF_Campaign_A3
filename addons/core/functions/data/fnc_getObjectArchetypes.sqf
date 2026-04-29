#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_getObjectArchetypes
 * Description:
 *     Returns the object archetype registry. Object archetypes describe
 *     mission objects (intel, supplies, equipment) as pure data: which
 *     classnames to draw from, how many to place, where to place them, and
 *     how the player interacts with them.
 *
 *     The raid generator consumes archetypes by name. Adding a new object
 *     type is a content task — append a hashmap entry here.
 *
 *     Archetype Fields:
 *       "classnames"        <ARRAY>    Pool of CfgVehicles classnames; one
 *                                      picked at random per placement.
 *       "count"             <NUMBER|ARRAY> Either a fixed count or a
 *                                          [min, max] range.
 *       "placement"         <STRING>   Placement strategy key:
 *                                      "INTERIOR_FLOOR" | "OUTDOOR_PILE"
 *       "zOffset"           <NUMBER>   Optional vertical offset added on
 *                                      top of the strategy's natural Z
 *                                      (e.g. for laptops sitting on tables).
 *       "destroyable"       <BOOL>     Object is a "destroy" target.
 *       "interactable"      <BOOL>     Object is an "interact" target.
 *       "interactionResult" <STRING>   Result key fed into mission state
 *                                      when interacted (e.g. "GATHER_INTEL").
 *       "briefingDesc"      <STRING>   Description for briefing fragment.
 *
 * Arguments: None
 *
 * Return Value:
 *     <HASHMAP> - Archetype name -> archetype hashmap.
 *
 * Example:
 *     private _archetypes = call DSC_core_fnc_getObjectArchetypes;
 *     private _supply = _archetypes get "SUPPLY_CACHE";
 */

createHashMapFromArray [

    // === Intel ===
    ["INTEL_LAPTOP", createHashMapFromArray [
        ["classnames", ["Land_Laptop_unfolded_F", "Land_Laptop_device_F"]],
        ["count", 1],
        ["placement", "INTERIOR_FLOOR"],
        ["zOffset", 0.9],                    // Approximate table height
        ["destroyable", false],
        ["interactable", true],
        ["interactionResult", "GATHER_INTEL"],
        ["briefingDesc", "Computer terminal — recover for intel"]
    ]],

    ["INTEL_DOCUMENTS", createHashMapFromArray [
        ["classnames", ["Land_File1_F", "Land_File2_F", "Land_FilePhotos_F"]],
        ["count", [2, 5]],
        ["placement", "INTERIOR_FLOOR"],
        ["zOffset", 0.9],
        ["destroyable", false],
        ["interactable", true],
        ["interactionResult", "GATHER_INTEL"],
        ["briefingDesc", "Documents — recover for intel"]
    ]],

    // === Supplies / sabotage targets ===
    ["SUPPLY_CACHE", createHashMapFromArray [
        ["classnames", ["Box_NATO_Ammo_F", "Box_East_AmmoVeh_F", "Box_East_Support_F"]],
        ["count", [3, 8]],
        ["placement", "INTERIOR_FLOOR"],
        ["zOffset", 0],
        ["destroyable", true],
        ["interactable", false],
        ["briefingDesc", "Weapons and ammunition cache"]
    ]],

    ["BOMB_PARTS", createHashMapFromArray [
        ["classnames", ["Land_Workbench_01_F", "Land_ToolTrolley_02_F", "Land_PaperBox_open_full_F"]],
        ["count", [1, 3]],
        ["placement", "INTERIOR_FLOOR"],
        ["zOffset", 0],
        ["destroyable", true],
        ["interactable", false],
        ["briefingDesc", "Bombmaking equipment"]
    ]],

    ["WEAPONS_CRATE", createHashMapFromArray [
        ["classnames", ["Box_East_WpsLaunch_F", "Box_East_Wps_F"]],
        ["count", [1, 3]],
        ["placement", "OUTDOOR_PILE"],
        ["zOffset", 0],
        ["destroyable", true],
        ["interactable", false],
        ["briefingDesc", "Weapons crate"]
    ]]
]
