#include "script_component.hpp"

/*
 * Get all structure classnames that inherit from a base class.
 * 
 * Scans CfgVehicles for all classes that inherit from the specified
 * base structure class. Useful for finding all variants of a structure
 * type (different camos, damaged versions, etc.)
 * 
 * Arguments:
 *   0: Base class name(s) <STRING or ARRAY> - Parent class(es) to search for
 *   1: (Optional) Log results <BOOL> - Output to RPT log (default: true)
 * 
 * Returns:
 *   Hashmap with base class as key, array of variant classnames as value
 * 
 * Examples:
 *   // Single base class
 *   ["Cargo_Tower_base_F"] call DSC_core_fnc_getStructureVariants
 *   
 *   // Multiple base classes
 *   [["Cargo_Tower_base_F", "Cargo_Patrol_base_F", "Cargo_HQ_base_F"]] call DSC_core_fnc_getStructureVariants
 *   
 *   // Without logging
 *   ["Cargo_Tower_base_F", false] call DSC_core_fnc_getStructureVariants
 */

params [
    ["_baseClasses", [], ["", []]],
    ["_logResults", true, [true]]
];

// Normalize to array
if (_baseClasses isEqualType "") then {
    _baseClasses = [_baseClasses];
};

if (count _baseClasses == 0) exitWith {
    diag_log "DSC: fnc_getStructureVariants - No base classes provided";
    createHashMap
};

private _result = createHashMap;

// Initialize result hashmap with empty arrays
{
    _result set [_x, []];
} forEach _baseClasses;

// Scan all CfgVehicles classes
private _allVehicles = "true" configClasses (configFile >> "CfgVehicles");

{
    private _cfg = _x;
    private _classname = configName _cfg;
    
    // Skip if scope < 1 (hidden classes)
    private _scope = getNumber (_cfg >> "scope");
    if (_scope < 1) then { continue };
    
    // Check against each base class
    {
        private _baseClass = _x;
        
        // Skip if this IS the base class itself
        if (_classname == _baseClass) then { continue };
        
        // Check inheritance
        if (_classname isKindOf _baseClass) then {
            (_result get _baseClass) pushBack _classname;
        };
    } forEach _baseClasses;
} forEach _allVehicles;

// Log results if requested
if (_logResults) then {
    diag_log "DSC: ============ Structure Variants Found ============";
    {
        private _baseClass = _x;
        private _variants = _result get _baseClass;
        diag_log format ["DSC: Base class: %1", _baseClass];
        diag_log format ["DSC:   Variants found: %1", count _variants];
        {
            diag_log format ["DSC:     - %1", _x];
        } forEach _variants;
    } forEach _baseClasses;
    diag_log "DSC: ==================================================";
};

_result
