#include "..\script_component.hpp"

// =======================================================
// GOING TO COME BACK TO THIS FUNCTION LATER
// =======================================================
params ["_displayName", "_factionSources"];
    
private _factionMap = createHashMap;
_factionMap set ["displayName", _displayName];

// Initialize all branches as empty hashmaps
private _infantry = createHashMap;
private _specops = createHashMap;
private _motorized = createHashMap;
private _mechanized = createHashMap;
private _airFixedWing = createHashMap;
private _airRotaryWing = createHashMap;
private _navy = createHashMap;

// Track which faction classes contribute to this composite faction
private _sourceClasses = [];
private _side = -1;


// Helper function to get infantry units from a faction class, categorized by role
_getInfantryUnits = {
    params ["_factionClass"];
    
    private _units = createHashMap;
    _units set ["rifleman", []];
    _units set ["autorifleman", []];
    _units set ["grenadier", []];
    _units set ["marksman", []];
    _units set ["medic", []];
    _units set ["engineer", []];
    _units set ["at", []];
    _units set ["aa", []];
    _units set ["sniper", []];
    _units set ["officer", []];
    
    {
        private _unitCfg = _x;
        private _unitFaction = getText (_unitCfg >> "faction");
        private _scope = getNumber (_unitCfg >> "scope");
        
        if (_unitFaction == _factionClass && {getNumber (_unitCfg >> "isMan") == 1} && {_scope >= 2}) then {
            private _unitClass = configName _unitCfg;
            private _unitName = toLower getText (_unitCfg >> "displayName");
            
            private _role = switch (true) do {
                case ("medic" in _unitName || "corpsman" in _unitName): { "medic" };
                case ("engineer" in _unitName || "sapper" in _unitName || "pioneer" in _unitName): { "engineer" };
                case ("sniper" in _unitName): { "sniper" };
                case ("marksman" in _unitName || "designated" in _unitName): { "marksman" };
                case ("autorifle" in _unitName || "machinegun" in _unitName || "mg" in _unitName || "automatic" in _unitName): { "autorifleman" };
                case ("grenadier" in _unitName): { "grenadier" };
                case ("aa" in _unitName || "anti-air" in _unitName || "manpad" in _unitName): { "aa" };
                case ("at" in _unitName || "anti-tank" in _unitName || "launcher" in _unitName || "missile" in _unitName): { "at" };
                case ("officer" in _unitName || "commander" in _unitName || "leader" in _unitName || "sergeant" in _unitName): { "officer" };
                default { "rifleman" };
            };
            
            (_units get _role) pushBack _unitClass;
        };
    } forEach ("true" configClasses (configFile >> "CfgVehicles"));
    
    _units;
};

// Helper function to get armor assets (crew + armored vehicles) from a faction class
_getArmorAssets = {
    params ["_factionClass"];
    
    private _assets = createHashMap;
    _assets set ["crew", []];
    _assets set ["tanks", []];
    _assets set ["apcs", []];
    
    {
        private _vehCfg = _x;
        private _vehFaction = getText (_vehCfg >> "faction");
        private _scope = getNumber (_vehCfg >> "scope");
        
        if (_vehFaction == _factionClass && {_scope >= 2}) then {
            private _vehClass = configName _vehCfg;
            private _isMan = getNumber (_vehCfg >> "isMan") == 1;
            
            if (_isMan) then {
                private _unitName = toLower getText (_vehCfg >> "displayName");
                if ("crew" in _unitName || "crewman" in _unitName || "tanker" in _unitName) then {
                    (_assets get "crew") pushBack _vehClass;
                };
            } else {
                private _vehName = toLower getText (_vehCfg >> "displayName");
                private _parents = [];
                private _parentCfg = inheritsFrom _vehCfg;
                while {!isNull _parentCfg} do {
                    _parents pushBack (toLower configName _parentCfg);
                    _parentCfg = inheritsFrom _parentCfg;
                };
                
                private _isTank = false;
                private _isAPC = false;
                
                {
                    if (_x in ["tank", "tank_f", "mbt_01_base_f", "mbt_02_base_f", "mbt_03_base_f", 
                               "rhs_t72_base", "rhs_t80_base", "rhs_t90_base", "rhsusf_m1a1_base", "rhsusf_m1a2_base"]) then {
                        _isTank = true;
                    };
                    if (_x in ["apc_tracked_01_base_f", "apc_tracked_02_base_f", "apc_tracked_03_base_f",
                               "apc_wheeled_01_base_f", "apc_wheeled_02_base_f", "apc_wheeled_03_base_f",
                               "mrap_01_base_f", "mrap_02_base_f", "mrap_03_base_f",
                               "wheeled_apc_f", "tracked_apc_f", "apc_f",
                               "rhs_btr_base", "rhs_bmd_base", "rhs_bmp_base",
                               "rhsusf_m113_base", "rhsusf_stryker_base", "rhsusf_m1117_base"]) then {
                        _isAPC = true;
                    };
                } forEach _parents;
                
                if (!_isTank && !_isAPC) then {
                    if ("mbt" in _vehName || "tank" in _vehName || "t-72" in _vehName || "t-80" in _vehName || 
                        "t-90" in _vehName || "m1a1" in _vehName || "m1a2" in _vehName || "abrams" in _vehName ||
                        "leopard" in _vehName || "merkava" in _vehName || "challenger" in _vehName) then {
                        _isTank = true;
                    };
                    if ("apc" in _vehName || "ifv" in _vehName || "mrap" in _vehName || "btr" in _vehName || 
                        "bmp" in _vehName || "bmd" in _vehName || "stryker" in _vehName || "bradley" in _vehName ||
                        "warrior" in _vehName || "marder" in _vehName || "m113" in _vehName || "lav" in _vehName) then {
                        _isAPC = true;
                    };
                };
                
                if (_isTank) then {
                    (_assets get "tanks") pushBack _vehClass;
                };
                if (_isAPC) then {
                    (_assets get "apcs") pushBack _vehClass;
                };
            };
        };
    } forEach ("true" configClasses (configFile >> "CfgVehicles"));
    
    _assets;
};

// Helper function to get air assets from a faction class
_getAirAssets = {
    params ["_factionClass"];
    
    private _assets = createHashMap;
    _assets set ["pilot", []];
    _assets set ["aircraft", []];  // TODO: Add aircraft detection
    
    {
        private _unitCfg = _x;
        private _unitFaction = getText (_unitCfg >> "faction");
        private _scope = getNumber (_unitCfg >> "scope");
        
        if (_unitFaction == _factionClass && {getNumber (_unitCfg >> "isMan") == 1} && {_scope >= 2}) then {
            private _unitClass = configName _unitCfg;
            private _unitName = toLower getText (_unitCfg >> "displayName");
            
            if ("pilot" in _unitName) then {
                (_assets get "pilot") pushBack _unitClass;
            };
        };
    } forEach ("true" configClasses (configFile >> "CfgVehicles"));
    
    _assets;
};

// Helper function to get motorized assets (light/unarmored vehicles) from a faction class
_getMotorizedAssets = {
    params ["_factionClass"];
    
    private _assets = createHashMap;
    _assets set ["crew", []];
    _assets set ["vehicles", []];  // TODO: Add light vehicle detection
    
    {
        private _unitCfg = _x;
        private _unitFaction = getText (_unitCfg >> "faction");
        private _scope = getNumber (_unitCfg >> "scope");
        
        if (_unitFaction == _factionClass && {getNumber (_unitCfg >> "isMan") == 1} && {_scope >= 2}) then {
            private _unitClass = configName _unitCfg;
            private _unitName = toLower getText (_unitCfg >> "displayName");
            
            if ("driver" in _unitName) then {
                (_assets get "crew") pushBack _unitClass;
            };
        };
    } forEach ("true" configClasses (configFile >> "CfgVehicles"));
    
    _assets;
};

// Helper function to get naval assets from a faction class
_getNavalAssets = {
    params ["_factionClass"];
    
    private _assets = createHashMap;
    _assets set ["crew", []];
    _assets set ["diver", []];
    _assets set ["boats", []];  // TODO: Add boat detection
    
    {
        private _unitCfg = _x;
        private _unitFaction = getText (_unitCfg >> "faction");
        private _scope = getNumber (_unitCfg >> "scope");
        
        if (_unitFaction == _factionClass && {getNumber (_unitCfg >> "isMan") == 1} && {_scope >= 2}) then {
            private _unitClass = configName _unitCfg;
            private _unitName = toLower getText (_unitCfg >> "displayName");
            
            if ("diver" in _unitName || "frogman" in _unitName || "seal" in _unitName) then {
                (_assets get "diver") pushBack _unitClass;
            };
        };
    } forEach ("true" configClasses (configFile >> "CfgVehicles"));
    
    _assets;
};


// Process each faction source
{
    _x params ["_factionClass", "_branches"];
    _sourceClasses pushBack _factionClass;
    
    // Get side from first faction (assume all sources are same side)
    if (_side == -1) then {
        private _factionCfg = configFile >> "CfgFactionClasses" >> _factionClass;
        _side = getNumber (_factionCfg >> "side");
    };
    
    // Process each branch this faction provides
    {
        switch (_x) do {
            case "infantry": {
                private _units = [_factionClass] call _getInfantryUnits;
                {
                    private _existing = _infantry getOrDefault [_x, []];
                    _infantry set [_x, _existing + (_units get _x)];
                } forEach (keys _units);
            };
            case "specops": {
                private _units = [_factionClass] call _getInfantryUnits;
                {
                    private _existing = _specops getOrDefault [_x, []];
                    _specops set [_x, _existing + (_units get _x)];
                } forEach (keys _units);
            };
            case "motorized": {
                private _assets = [_factionClass] call _getMotorizedAssets;
                {
                    private _existing = _motorized getOrDefault [_x, []];
                    _motorized set [_x, _existing + (_assets get _x)];
                } forEach (keys _assets);
            };
            case "mechanized": {
                private _assets = [_factionClass] call _getArmorAssets;
                {
                    private _existing = _mechanized getOrDefault [_x, []];
                    _mechanized set [_x, _existing + (_assets get _x)];
                } forEach (keys _assets);
            };
            case "airFixedWing": {
                private _assets = [_factionClass] call _getAirAssets;
                {
                    private _existing = _airFixedWing getOrDefault [_x, []];
                    _airFixedWing set [_x, _existing + (_assets get _x)];
                } forEach (keys _assets);
            };
            case "airRotaryWing": {
                private _assets = [_factionClass] call _getAirAssets;
                {
                    private _existing = _airRotaryWing getOrDefault [_x, []];
                    _airRotaryWing set [_x, _existing + (_assets get _x)];
                } forEach (keys _assets);
            };
            case "navy": {
                private _assets = [_factionClass] call _getNavalAssets;
                {
                    private _existing = _navy getOrDefault [_x, []];
                    _navy set [_x, _existing + (_assets get _x)];
                } forEach (keys _assets);
            };
        };
    } forEach _branches;
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
