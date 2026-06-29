#include "script_component.hpp"

/*
 * Extract all group definitions for a faction from CfgGroups.
 * 
 * Pure extraction layer - collects raw config data without any classification
 * or interpretation. Returns structured data for downstream processing.
 * 
 * Arguments:
 *   0: Faction class name <STRING>
 * 
 * Returns:
 *   Array of hashmaps, each containing:
 *     - "side": Side number (0=OPFOR, 1=BLUFOR, 2=INDEP, 3=CIV)
 *     - "sideName": Side class name ("East", "West", "Indep", "Civilian")
 *     - "factionClass": The input faction class name
 *     - "category": Group category from CfgGroups (e.g., "Infantry", "SpecOps")
 *     - "groupName": The group classname
 *     - "path": Full config path string "Side/Faction/Category/GroupName"
 *     - "units": Array of unit config path strings
 *     - "vehicles": Array of vehicle/unit classnames from 'vehicle' property
 *     - "unitCount": Number of units in the group
 * 
 * Example:
 *   ["rhs_faction_msv"] call DSC_core_fnc_extractGroups
 */

params ["_factionClass"];

private _result = [];

// Get faction info from CfgFactionClasses
private _factionCfg = configFile >> "CfgFactionClasses" >> _factionClass;
if (!isClass _factionCfg) exitWith {
    TRACE_1("Faction Config not found: ",_factionClass);
    ERROR("Faction class not found in CfgFactionClasses.");
    _result
};

private _side = getNumber (_factionCfg >> "side");

// Map side number to CfgGroups side class name
private _sideName = switch (_side) do {
    case 0: { "East" };
    case 1: { "West" };
    case 2: { "Indep" };
    case 3: { "Civilian" };
    default { "" };
};

if (_sideName == "") exitWith {
    TRACE_2("Unknown side for faction: ",_side,_factionClass);
    _result
};

// Workaround for Faction Class Name and 3Den Category name desync (Seriously Arma?)
// Vanilla
if (_factionClass isEqualTo "BLU_G_F") then { _factionClass = "Guerilla" }; // FIA
if (_factionClass isEqualTo "BLU_GEN_F") then { _factionClass = "Gendarmerie" }; // Gendarmerie

// RHSUSAF
if (_factionClass isEqualTo "rhs_faction_socom") then { _factionClass = "rhs_faction_socom_marsoc" }; // US Socom

// Check if faction exists in CfgGroups
private _groupsFactionCfg = configFile >> "CfgGroups" >> _sideName >> _factionClass;
if (!isClass _groupsFactionCfg) exitWith {
    TRACE_2("No CfgGroups entry for faction.",_factionClass,_sideName);
    ERROR("No CfgGroups entry for faction.");
    _result
};

// Iterate through all group categories (Infantry, SpecOps, Motorized, etc.)
{
    private _categoryCfg = _x;
    private _categoryName = configName _categoryCfg;
    
    // Iterate through all groups in this category
    {
        private _groupCfg = _x;
        private _groupName = configName _groupCfg;
        private _groupPath = [_sideName, _factionClass, _categoryName, _groupName] joinString "/";
        
        // Extract unit data from group
        private _units = [];
        private _vehicles = [];
        
        {
            private _unitCfg = _x;
            private _unitPath = format ["CfgGroups/%1/%2", _groupPath, configName _unitCfg];
            private _vehicleClass = getText (_unitCfg >> "vehicle");
            
            _units pushBack _unitPath;
            
            if (_vehicleClass != "") then {
                _vehicles pushBack _vehicleClass;
            };
        } forEach ("true" configClasses _groupCfg);
        
        // Build group data hashmap
        private _groupData = createHashMap;
        _groupData set ["side", _side];
        _groupData set ["sideName", _sideName];
        _groupData set ["factionClass", _factionClass];
        _groupData set ["category", _categoryName];
        _groupData set ["groupName", _groupName];
        _groupData set ["path", _groupPath];
        _groupData set ["units", _units];
        _groupData set ["vehicles", _vehicles];
        _groupData set ["unitCount", count _units];
        
        _result pushBack _groupData;
        
    } forEach ("true" configClasses _categoryCfg);
    
} forEach ("true" configClasses _groupsFactionCfg);

// Log extraction summary
TRACE_2("Extracted groups from faction",count _result,_factionClass);

_result
