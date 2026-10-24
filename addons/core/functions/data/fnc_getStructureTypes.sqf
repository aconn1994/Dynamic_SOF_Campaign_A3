#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_getStructureTypes
 * Description:
 *     @deprecated — use DSC_core_fnc_getStructureCatalog instead.
 *
 *     Thin shim kept for zero-call-site-edit compatibility (Session 01,
 *     docs/overhauls/ambient_world/session_01_structure_taxonomy.md
 *     "Approved Mini-Spec" §A2). Returns exactly the 11 legacy keys this
 *     function always returned, now derived from the structure taxonomy
 *     catalog rather than hand-duplicated arrays.
 *
 *     Every consumer (fnc_scanLocations and anyone else) keeps working
 *     unmodified. This shim will be deleted in a later session once call
 *     sites migrate to fnc_getStructureCatalog directly.
 *
 * Arguments:
 *     None
 *
 * Return Value:
 *     <HASHMAP> - Keys:
 *       "main"                 - Array of main structure class names
 *       "side"                 - Array of side structure class names
 *       "mainMilitary"         - Military main structures
 *       "mainCivilian"         - Civilian main structures
 *       "sideMilitary"         - Military side structures
 *       "sideCivilian"         - Civilian side structures
 *       "exclusions"           - Per-map exclusion list
 *       "functionalCategories" - Hashmap of category -> class name array
 *       "functionalLookup"     - Hashmap of class name -> category (reverse lookup)
 *       "nonOccupiable"        - Hashmap of category -> non-enterable class arrays
 *       "nonOccupiableLookup"  - Hashmap of class name -> category (reverse lookup)
 *
 * Example:
 *     private _types = call DSC_core_fnc_getStructureTypes;
 *     private _mainTypes = _types get "main";
 *     private _funcLookup = _types get "functionalLookup";
 */

private _catalog = [] call DSC_core_fnc_getStructureCatalog;

createHashMapFromArray [
    ["main", _catalog get "main"],
    ["side", _catalog get "side"],
    ["mainMilitary", _catalog get "mainMilitary"],
    ["mainCivilian", _catalog get "mainCivilian"],
    ["sideMilitary", _catalog get "sideMilitary"],
    ["sideCivilian", _catalog get "sideCivilian"],
    ["exclusions", _catalog get "exclusions"],
    ["functionalCategories", _catalog get "functionalCategories"],
    ["functionalLookup", _catalog get "functionalLookup"],
    ["nonOccupiable", _catalog get "nonOccupiable"],
    ["nonOccupiableLookup", _catalog get "nonOccupiableLookup"]
]
