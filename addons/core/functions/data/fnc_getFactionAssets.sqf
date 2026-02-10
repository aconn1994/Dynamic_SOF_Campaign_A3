#include "script_component.hpp"

/*
 * Get asset classnames for a faction by category.
 * 
 * Centralized storage for faction-specific asset classnames.
 * Designed to be extended with new categories (aircraft, vehicles, etc.)
 * 
 * Arguments:
 *   0: Faction class name <STRING>
 *   1: Asset category <STRING> - "staticWeapons", "aircraft", "vehicles", etc.
 *   2: (Optional) Subcategory <STRING> - "HMG", "AT", "fixedWing", etc.
 *      If omitted, returns entire category hashmap
 * 
 * Returns:
 *   Array of classnames if subcategory specified
 *   Hashmap of subcategories if only category specified
 *   Empty array/hashmap if faction or category not found
 * 
 * Examples:
 *   ["OPF_F", "staticWeapons", "HMG"] call DSC_core_fnc_getFactionAssets
 *   // Returns: ["O_HMG_01_high_F"]
 *   
 *   ["OPF_F", "staticWeapons"] call DSC_core_fnc_getFactionAssets
 *   // Returns: hashmap with HMG, AT, AA keys
 *   
 *   ["BLU_F", "aircraft", "rotaryWing"] call DSC_core_fnc_getFactionAssets
 *   // Returns: ["B_Heli_Light_01_F", ...]
 */

params ["_factionClass", "_category", ["_subcategory", ""]];

// ============================================================================
// FACTION ASSET DEFINITIONS
// ============================================================================
// Structure: faction -> category -> subcategory -> [classnames]
// 
// Categories:
//   - staticWeapons: HMG, GMG, AT, AA, MORTAR
//   - aircraft: fixedWing, rotaryWing
//   - vehicles: light, heavy, armor, transport
//   - boats: assault, transport
// ============================================================================

private _factionAssets = createHashMapFromArray [
    // ========================================
    // OPFOR - CSAT
    // ========================================
    ["OPF_F", createHashMapFromArray [
        ["staticWeapons", createHashMapFromArray [
            ["HMG", ["O_HMG_01_high_F"]],
            ["GMG", ["O_GMG_01_high_F"]],
            ["AT", ["O_static_AT_F"]],
            ["AA", ["O_static_AA_F"]],
            ["MORTAR", ["O_Mortar_01_F"]]
        ]],
        ["aircraft", createHashMapFromArray [
            ["fixedWingAttack", []],
            ["fixedWingTransport", []],
            ["rotaryWingAttack", []],
            ["rotaryWingTransport", []]
        ]],
        ["vehicles", createHashMapFromArray [
            ["light", []],
            ["heavy", []],
            ["armor", []],
            ["transport", []]
        ]]
    ]],
    
    // ========================================
    // BLUFOR - NATO
    // ========================================
    ["BLU_F", createHashMapFromArray [
        ["staticWeapons", createHashMapFromArray [
            ["HMG", ["B_HMG_01_high_F"]],
            ["GMG", ["B_GMG_01_high_F"]],
            ["AT", ["B_static_AT_F"]],
            ["AA", ["B_static_AA_F"]],
            ["MORTAR", ["B_Mortar_01_F"]]
        ]],
        ["aircraft", createHashMapFromArray [
            ["fixedWingAttack", []],
            ["fixedWingTransport", []],
            ["rotaryWingAttack", []],
            ["rotaryWingTransport", []]
        ]],
        ["vehicles", createHashMapFromArray [
            ["light", []],
            ["heavy", []],
            ["armor", []],
            ["transport", []]
        ]]
    ]],
    
    // ========================================
    // INDEPENDENT - AAF
    // ========================================
    ["IND_F", createHashMapFromArray [
        ["staticWeapons", createHashMapFromArray [
            ["HMG", ["I_HMG_01_high_F"]],
            ["GMG", ["I_GMG_01_high_F"]],
            ["AT", ["I_static_AT_F"]],
            ["AA", ["I_static_AA_F"]],
            ["MORTAR", ["I_Mortar_01_F"]]
        ]],
        ["aircraft", createHashMapFromArray [
            ["fixedWingAttack", []],
            ["fixedWingTransport", []],
            ["rotaryWingAttack", []],
            ["rotaryWingTransport", []]
        ]],
        ["vehicles", createHashMapFromArray [
            ["light", []],
            ["heavy", []],
            ["armor", []],
            ["transport", []]
        ]]
    ]]
    
    // ========================================
    // Add more factions here as needed:
    // RHS, CUP, 3CB, etc.
    // ========================================
];

// ============================================================================
// LOOKUP LOGIC
// ============================================================================

// Check if faction exists
private _factionData = _factionAssets getOrDefault [_factionClass, createHashMap];
if (count _factionData == 0) exitWith {
    diag_log format ["DSC: fnc_getFactionAssets - Faction '%1' not found", _factionClass];
    if (_subcategory != "") then { [] } else { createHashMap }
};

// Check if category exists
private _categoryData = _factionData getOrDefault [_category, createHashMap];
if (count _categoryData == 0) exitWith {
    diag_log format ["DSC: fnc_getFactionAssets - Category '%1' not found for faction '%2'", _category, _factionClass];
    if (_subcategory != "") then { [] } else { createHashMap }
};

// Return category hashmap or specific subcategory array
if (_subcategory == "") exitWith {
    _categoryData
};

// Return subcategory array
_categoryData getOrDefault [_subcategory, []]
