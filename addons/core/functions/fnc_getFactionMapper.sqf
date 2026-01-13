#include "..\script_component.hpp"

/*
 * Faction Mapper using Editor Categories (vehicleClass)
 * 
 * Maps units/vehicles based on CfgVehicleClasses categories instead of name matching.
 * This is more reliable as it uses the same classification the Eden editor uses.
 * 
 * Arguments:
 *   0: Display name for this composite faction <STRING>
 *   1: Array of [factionClass, [branches]] pairs <ARRAY>
 *      Branches: "infantry", "specops", "motorized", "mechanized", "airFixedWing", "airRotaryWing", "navy"
 * 
 * Returns:
 *   Hashmap with faction data organized by branch
 */

params ["_displayName", "_factionSources"];

private _factionMap = createHashMap;
_factionMap set ["displayName", _displayName];

// Initialize branches - each will contain "units" and/or "vehicles" arrays
private _infantry = createHashMap;
private _specops = createHashMap;
private _motorized = createHashMap;
private _mechanized = createHashMap;
private _airFixedWing = createHashMap;
private _airRotaryWing = createHashMap;
private _navy = createHashMap;

// Track source factions
private _sourceClasses = [];
private _side = -1;

// Category mapping - maps vehicleClass values to our branches
// Infantry categories (men on foot)
private _infantryCategories = ["men", "menurban", "mensnow", "menarctic", "mentropical", "mensupport"];
private _specopsCategories = ["menrecon", "mensniper", "mendiver", "menspecops"];

// Vehicle categories
private _armorCategories = ["armored", "armor"];
private _carCategories = ["car", "cars", "support"];
private _heliCategories = ["helicopter", "helicopters", "air"];
private _planeCategories = ["plane", "planes", "jet", "jets"];
private _navalCategories = ["ship", "ships", "boat", "boats", "naval"];

// Process each faction source
{
    _x params ["_factionClass", "_branches"];
    _sourceClasses pushBack _factionClass;
    
    // Get side from first faction
    if (_side == -1) then {
        private _factionCfg = configFile >> "CfgFactionClasses" >> _factionClass;
        _side = getNumber (_factionCfg >> "side");
    };
    
    // Scan all CfgVehicles entries for this faction
    {
        private _cfg = _x;
        private _cfgFaction = getText (_cfg >> "faction");
        private _scope = getNumber (_cfg >> "scope");
        
        if (_cfgFaction == _factionClass && {_scope >= 2}) then {
            private _class = configName _cfg;
            private _vehicleClass = toLower getText (_cfg >> "vehicleClass");
            private _isMan = getNumber (_cfg >> "isMan") == 1;
            
            // Determine which branch this belongs to based on vehicleClass
            private _targetBranch = "";
            private _isUnit = _isMan;
            
            if (_isMan) then {
                // Check infantry categories
                {
                    if (_vehicleClass find _x >= 0) exitWith { _targetBranch = "infantry"; };
                } forEach _infantryCategories;
                
                // Check specops categories (overrides infantry if matched)
                {
                    if (_vehicleClass find _x >= 0) exitWith { _targetBranch = "specops"; };
                } forEach _specopsCategories;
            } else {
                // Vehicle classification
                {
                    if (_vehicleClass find _x >= 0) exitWith { _targetBranch = "mechanized"; };
                } forEach _armorCategories;
                
                if (_targetBranch == "") then {
                    {
                        if (_vehicleClass find _x >= 0) exitWith { _targetBranch = "motorized"; };
                    } forEach _carCategories;
                };
                
                if (_targetBranch == "") then {
                    {
                        if (_vehicleClass find _x >= 0) exitWith { _targetBranch = "airRotaryWing"; };
                    } forEach _heliCategories;
                };
                
                if (_targetBranch == "") then {
                    {
                        if (_vehicleClass find _x >= 0) exitWith { _targetBranch = "airFixedWing"; };
                    } forEach _planeCategories;
                };
                
                if (_targetBranch == "") then {
                    {
                        if (_vehicleClass find _x >= 0) exitWith { _targetBranch = "navy"; };
                    } forEach _navalCategories;
                };
            };
            
            // Add to branch if it was requested
            if (_targetBranch != "" && {_targetBranch in _branches}) then {
                private _branchMap = switch (_targetBranch) do {
                    case "infantry": { _infantry };
                    case "specops": { _specops };
                    case "mechanized": { _mechanized };
                    case "motorized": { _motorized };
                    case "airRotaryWing": { _airRotaryWing };
                    case "airFixedWing": { _airFixedWing };
                    case "navy": { _navy };
                    default { createHashMap };
                };
                
                // Add to units or vehicles array
                private _key = ["vehicles", "units"] select (_isUnit);
                private _arr = _branchMap getOrDefault [_key, []];
                _arr pushBack _class;
                _branchMap set [_key, _arr];
            };
        };
    } forEach ("true" configClasses (configFile >> "CfgVehicles"));
    
} forEach _factionSources;

_factionMap set ["side", _side];
_factionMap set ["sourceClasses", _sourceClasses];
_factionMap set ["infantry", _infantry];
_factionMap set ["specops", _specops];
_factionMap set ["motorized", _motorized];
_factionMap set ["mechanized", _mechanized];
_factionMap set ["airFixedWing", _airFixedWing];
_factionMap set ["airRotaryWing", _airRotaryWing];
_factionMap set ["navy", _navy];

_factionMap;
