#include "script_component.hpp"

/*
 * Faction Group Mapper
 * 
 * Scans CfgGroups for a faction and categorizes groups into infantry, motorized, and mechanized.
 * Uses the group's vehicles to determine category - infantry have no vehicles, motorized have
 * unarmored/light vehicles, mechanized have armored vehicles.
 * 
 * Arguments:
 *   0: Faction class name <STRING>
 * 
 * Returns:
 *   Hashmap with keys:
 *     - "infantry": Array of group config paths (foot infantry, no vehicles)
 *     - "motorized": Array of group config paths (unarmored/light armor vehicles)
 *     - "mechanized": Array of group config paths (armored vehicles)
 *     - "factionClass": The input faction class name
 *     - "factionDisplayName": Display name of the faction
 *     - "side": Side number (0=OPFOR, 1=BLUFOR, 2=INDEP, 3=CIV)
 * 
 * Example:
 *   ["rhs_faction_usarmy_d"] call DSC_core_fnc_factionGroupMapper
 */

params ["_factionClass"];

private _result = createHashMap;
_result set ["factionClass", _factionClass];
_result set ["infantry", []];
_result set ["motorized", []];
_result set ["mechanized", []];

// Get faction info
private _factionCfg = configFile >> "CfgFactionClasses" >> _factionClass;
if (!isClass _factionCfg) exitWith {
    diag_log format ["DSC: fnc_factionGroupMapper - Faction class '%1' not found in CfgFactionClasses", _factionClass];
    _result
};

private _factionDisplayName = getText (_factionCfg >> "displayName");
private _side = getNumber (_factionCfg >> "side");
_result set ["factionDisplayName", _factionDisplayName];
_result set ["side", _side];

// Map side number to CfgGroups side class name
private _sideClass = switch (_side) do {
    case 0: { "East" };
    case 1: { "West" };
    case 2: { "Indep" };
    case 3: { "Civilian" };
    default { "" };
};

if (_sideClass == "") exitWith {
    diag_log format ["DSC: fnc_factionGroupMapper - Unknown side %1 for faction '%2'", _side, _factionClass];
    _result
};

// Check if faction exists in CfgGroups
private _groupsFactionCfg = configFile >> "CfgGroups" >> _sideClass >> _factionClass;
if (!isClass _groupsFactionCfg) exitWith {
    diag_log format ["DSC: fnc_factionGroupMapper - No CfgGroups entry for faction '%1' under %2", _factionClass, _sideClass];
    _result
};

// Armored vehicle categories for classification
// These vehicleClass values indicate armored/mechanized vehicles
private _armoredCategories = ["armored", "armor", "tank", "tanks", "apc", "ifv", "mrap"];

// Motorized vehicle categories (unarmored wheeled/tracked)
private _motorizedCategories = ["car", "cars", "truck", "trucks", "support"];

// Function to check if a vehicle classname is armored
private _fnc_isArmoredVehicle = {
    params ["_vehicleClassName", "_armoredCats"];
    
    private _vehCfg = configFile >> "CfgVehicles" >> _vehicleClassName;
    if (!isClass _vehCfg) exitWith { false };
    
    // Skip if it's a man
    if (getNumber (_vehCfg >> "isMan") == 1) exitWith { false };
    
    private _vehicleClass = toLower getText (_vehCfg >> "vehicleClass");
    private _armor = getNumber (_vehCfg >> "armor");
    
    // DEBUG: Log vehicle info
    // diag_log format ["DSC DEBUG: Vehicle %1 - vehicleClass='%2', armor=%3", _vehicleClassName, _vehicleClass, _armor];
    
    // Check armor categories
    private _isArmored = false;
    {
        if (_vehicleClass find _x >= 0) exitWith { _isArmored = true };
    } forEach _armoredCats;
    
    // Also check if it has significant armor value as backup
    if (!_isArmored) then {
        if (_armor > 201) then { _isArmored = true }; // Vanilla MRAPs are 200 armor
    };
    
    _isArmored
};

// Function to check if a vehicle classname is motorized (unarmored vehicle)
private _fnc_isMotorizedVehicle = {
    params ["_vehicleClassName", "_motorizedCats"];
    
    private _vehCfg = configFile >> "CfgVehicles" >> _vehicleClassName;
    if (!isClass _vehCfg) exitWith { false };
    
    // Skip if it's a man
    if (getNumber (_vehCfg >> "isMan") == 1) exitWith { false };
    
    private _vehicleClass = toLower getText (_vehCfg >> "vehicleClass");
    
    // Check motorized categories
    private _isMotorized = false;
    {
        if (_vehicleClass find _x >= 0) exitWith { _isMotorized = true };
    } forEach _motorizedCats;
    
    _isMotorized
};

// Iterate through all group categories (Infantry, SpecOps, Motorized, etc.)
{
    private _categoryCfg = _x;
    
    // Iterate through all groups in this category
    {
        private _groupCfg = _x;
        private _groupPath = configName _groupCfg;
        private _groupConfigPath = [_sideClass, _factionClass, configName _categoryCfg, _groupPath] joinString "/";
        
        // Analyze units in the group to determine category
        private _hasArmoredVehicle = false;
        private _hasMotorizedVehicle = false;
        private _hasAnyVehicle = false;
        
        // Check each unit entry in the group
        {
            private _unitCfg = _x;
            private _vehicle = getText (_unitCfg >> "vehicle");
            
            // DEBUG: Log all unit entries to understand structure
            // diag_log format ["DSC DEBUG: Group unit - vehicle='%1', configName='%2'", _vehicle, configName _unitCfg];
            
            // Check if this unit has an associated vehicle (not the unit class itself) CHECK THIS SPOT TOMORROWWWWWWWWWWWWWWWWWWWWWWWWWWWW
            private _vehCfg = configFile >> "CfgVehicles" >> _vehicle;
            if (isClass _vehCfg) then {
                private _isMan = getNumber (_vehCfg >> "isMan") == 1;
                
                // DEBUG
                // diag_log format ["DSC DEBUG: %1 isMan=%2", _vehicle, _isMan];
                
                if (!_isMan) then {
                    _hasAnyVehicle = true;
                    
                    if ([_vehicle, _armoredCategories] call _fnc_isArmoredVehicle) then {
                        _hasArmoredVehicle = true;
                    };
                    
                    if ([_vehicle, _motorizedCategories] call _fnc_isMotorizedVehicle) then {
                        _hasMotorizedVehicle = true;
                    };
                };
            };
        } forEach ("true" configClasses _groupCfg);
        
        // Categorize the group
        // Priority: Mechanized > Motorized > Infantry
        private _category = if (_hasArmoredVehicle) then {
            "mechanized"
        } else {
            ["infantry", "motorized"] select (_hasMotorizedVehicle || _hasAnyVehicle)
        };
        
        private _arr = _result get _category;
        _arr pushBack _groupConfigPath;
        
    } forEach ("true" configClasses _categoryCfg);
    
} forEach ("true" configClasses _groupsFactionCfg);

// Log summary
private _infantryCount = count (_result get "infantry");
private _motorizedCount = count (_result get "motorized");
private _mechanizedCount = count (_result get "mechanized");

diag_log format [
    "DSC: fnc_factionGroupMapper - %1 (%2): Infantry=%3, Motorized=%4, Mechanized=%5",
    _factionDisplayName,
    _factionClass,
    _infantryCount,
    _motorizedCount,
    _mechanizedCount
];

_result
