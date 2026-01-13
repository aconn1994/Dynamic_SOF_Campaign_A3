// DSC - Dynamic SOF Campaign - Altis
// Using Aegis and RHS for now, eventually vanilla will be default and code will check for Aegis/RHS mods

// diag_log "========== DSC: Faction Discovery Starting ==========";

// // ============================================================================
// // STEP 1: Get all available factions from CfgFactionClasses
// // ============================================================================
// private _factions = [];
// {
//     private _factionClass = configName _x;
//     private _displayName = getText (_x >> "displayName");
//     private _side = getNumber (_x >> "side");
    
//     // Side mapping: 0=OPFOR, 1=BLUFOR, 2=INDFOR, 3=CIV
//     private _sideName = ["OPFOR", "BLUFOR", "INDFOR", "CIVILIAN"] select (_side min 3);
    
//     _factions pushBack [_factionClass, _displayName, _side, _sideName];
    
//     diag_log format ["DSC: Faction found - %1 (%2) [%3]", _displayName, _factionClass, _sideName];
// } forEach ("true" configClasses (configFile >> "CfgFactionClasses"));

// Pretty-print hashmap to RPT logs with indentation
DSC_logHashmap = {
    params ["_name", "_hashmap", ["_indent", 0]];
    
    private _prefix = "";
    for "_i" from 1 to _indent do { _prefix = _prefix + "  "; };
    
    if (_indent == 0) then {
        diag_log format ["DSC: ========== %1 ==========", _name];
    };
    
    {
        private _key = _x;
        private _value = _y;
        
        if (_value isEqualType createHashMap) then {
            diag_log format ["DSC: %1%2:", _prefix, _key];
            [_key, _value, _indent + 1] call DSC_logHashmap;
        } else {
            if (_value isEqualType []) then {
                if (count _value == 0) then {
                    diag_log format ["DSC: %1%2: []", _prefix, _key];
                } else {
                    diag_log format ["DSC: %1%2: [%3 items]", _prefix, _key, count _value];
                    {
                        diag_log format ["DSC: %1  - %2", _prefix, _x];
                    } forEach _value;
                };
            } else {
                diag_log format ["DSC: %1%2: %3", _prefix, _key, _value];
            };
        };
    } forEach _hashmap;
    
    if (_indent == 0) then {
        diag_log "DSC: ================================";
    };
};

// Helper function to get infantry units from a faction class, categorized by role
// DSC_getInfantryUnits = {
//     params ["_factionClass"];
    
//     private _units = createHashMap;
//     _units set ["rifleman", []];
//     _units set ["autorifleman", []];
//     _units set ["grenadier", []];
//     _units set ["marksman", []];
//     _units set ["medic", []];
//     _units set ["engineer", []];
//     _units set ["at", []];
//     _units set ["aa", []];
//     _units set ["sniper", []];
//     _units set ["officer", []];
    
//     {
//         private _unitCfg = _x;
//         private _unitFaction = getText (_unitCfg >> "faction");
//         private _scope = getNumber (_unitCfg >> "scope");
        
//         if (_unitFaction == _factionClass && {getNumber (_unitCfg >> "isMan") == 1} && {_scope >= 2}) then {
//             private _unitClass = configName _unitCfg;
//             private _unitName = toLower getText (_unitCfg >> "displayName");
            
//             private _role = switch (true) do {
//                 case ("medic" in _unitName || "corpsman" in _unitName): { "medic" };
//                 case ("engineer" in _unitName || "sapper" in _unitName || "pioneer" in _unitName): { "engineer" };
//                 case ("sniper" in _unitName): { "sniper" };
//                 case ("marksman" in _unitName || "designated" in _unitName): { "marksman" };
//                 case ("autorifle" in _unitName || "machinegun" in _unitName || "mg" in _unitName || "automatic" in _unitName): { "autorifleman" };
//                 case ("grenadier" in _unitName): { "grenadier" };
//                 case ("aa" in _unitName || "anti-air" in _unitName || "manpad" in _unitName): { "aa" };
//                 case ("at" in _unitName || "anti-tank" in _unitName || "launcher" in _unitName || "missile" in _unitName): { "at" };
//                 case ("officer" in _unitName || "commander" in _unitName || "leader" in _unitName || "sergeant" in _unitName): { "officer" };
//                 default { "rifleman" };
//             };
            
//             (_units get _role) pushBack _unitClass;
//         };
//     } forEach ("true" configClasses (configFile >> "CfgVehicles"));
    
//     _units;
// };

// // Helper function to get armor crews from a faction class
// DSC_getArmorAssets = {
//     params ["_factionClass"];
    
//     private _assets = createHashMap;
//     _assets set ["crew", []];
//     _assets set ["vehicles", []];  // TODO: Add vehicle detection
    
//     {
//         private _unitCfg = _x;
//         private _unitFaction = getText (_unitCfg >> "faction");
//         private _scope = getNumber (_unitCfg >> "scope");
        
//         if (_unitFaction == _factionClass && {getNumber (_unitCfg >> "isMan") == 1} && {_scope >= 2}) then {
//             private _unitClass = configName _unitCfg;
//             private _unitName = toLower getText (_unitCfg >> "displayName");
            
//             if ("crew" in _unitName || "crewman" in _unitName || "tanker" in _unitName) then {
//                 (_assets get "crew") pushBack _unitClass;
//             };
//         };
//     } forEach ("true" configClasses (configFile >> "CfgVehicles"));
    
//     _assets;
// };

// // Helper function to get air assets from a faction class
// DSC_getAirAssets = {
//     params ["_factionClass"];
    
//     private _assets = createHashMap;
//     _assets set ["pilot", []];
//     _assets set ["aircraft", []];  // TODO: Add aircraft detection
    
//     {
//         private _unitCfg = _x;
//         private _unitFaction = getText (_unitCfg >> "faction");
//         private _scope = getNumber (_unitCfg >> "scope");
        
//         if (_unitFaction == _factionClass && {getNumber (_unitCfg >> "isMan") == 1} && {_scope >= 2}) then {
//             private _unitClass = configName _unitCfg;
//             private _unitName = toLower getText (_unitCfg >> "displayName");
            
//             if ("pilot" in _unitName) then {
//                 (_assets get "pilot") pushBack _unitClass;
//             };
//         };
//     } forEach ("true" configClasses (configFile >> "CfgVehicles"));
    
//     _assets;
// };

// // Helper function to get motorized assets (light/unarmored vehicles) from a faction class
// DSC_getMotorizedAssets = {
//     params ["_factionClass"];
    
//     private _assets = createHashMap;
//     _assets set ["crew", []];
//     _assets set ["vehicles", []];  // TODO: Add light vehicle detection
    
//     {
//         private _unitCfg = _x;
//         private _unitFaction = getText (_unitCfg >> "faction");
//         private _scope = getNumber (_unitCfg >> "scope");
        
//         if (_unitFaction == _factionClass && {getNumber (_unitCfg >> "isMan") == 1} && {_scope >= 2}) then {
//             private _unitClass = configName _unitCfg;
//             private _unitName = toLower getText (_unitCfg >> "displayName");
            
//             if ("driver" in _unitName) then {
//                 (_assets get "crew") pushBack _unitClass;
//             };
//         };
//     } forEach ("true" configClasses (configFile >> "CfgVehicles"));
    
//     _assets;
// };

// // Helper function to get naval assets from a faction class
// DSC_getNavalAssets = {
//     params ["_factionClass"];
    
//     private _assets = createHashMap;
//     _assets set ["crew", []];
//     _assets set ["diver", []];
//     _assets set ["boats", []];  // TODO: Add boat detection
    
//     {
//         private _unitCfg = _x;
//         private _unitFaction = getText (_unitCfg >> "faction");
//         private _scope = getNumber (_unitCfg >> "scope");
        
//         if (_unitFaction == _factionClass && {getNumber (_unitCfg >> "isMan") == 1} && {_scope >= 2}) then {
//             private _unitClass = configName _unitCfg;
//             private _unitName = toLower getText (_unitCfg >> "displayName");
            
//             if ("diver" in _unitName || "frogman" in _unitName || "seal" in _unitName) then {
//                 (_assets get "diver") pushBack _unitClass;
//             };
//         };
//     } forEach ("true" configClasses (configFile >> "CfgVehicles"));
    
//     _assets;
// };

// Main composite faction mapper
// Takes a display name and array of [factionClass, [branches]] pairs
// Branches: "infantry", "specops", "motorized", "mechanized", "airFixedWing", "airRotaryWing", "navy"
// DSC_getFactionMapper = {
//     params ["_displayName", "_factionSources"];
    
//     private _factionMap = createHashMap;
//     _factionMap set ["displayName", _displayName];
    
//     // Initialize all branches as empty hashmaps
//     private _infantry = createHashMap;
//     private _specops = createHashMap;
//     private _motorized = createHashMap;
//     private _mechanized = createHashMap;
//     private _airFixedWing = createHashMap;
//     private _airRotaryWing = createHashMap;
//     private _navy = createHashMap;
    
//     // Track which faction classes contribute to this composite faction
//     private _sourceClasses = [];
//     private _side = -1;
    
//     // Process each faction source
//     {
//         _x params ["_factionClass", "_branches"];
//         _sourceClasses pushBack _factionClass;
        
//         // Get side from first faction (assume all sources are same side)
//         if (_side == -1) then {
//             private _factionCfg = configFile >> "CfgFactionClasses" >> _factionClass;
//             _side = getNumber (_factionCfg >> "side");
//         };
        
//         // Process each branch this faction provides
//         {
//             switch (_x) do {
//                 case "infantry": {
//                     private _units = [_factionClass] call DSC_getInfantryUnits;
//                     {
//                         private _existing = _infantry getOrDefault [_x, []];
//                         _infantry set [_x, _existing + (_units get _x)];
//                     } forEach (keys _units);
//                 };
//                 case "specops": {
//                     private _units = [_factionClass] call DSC_getInfantryUnits;
//                     {
//                         private _existing = _specops getOrDefault [_x, []];
//                         _specops set [_x, _existing + (_units get _x)];
//                     } forEach (keys _units);
//                 };
//                 case "motorized": {
//                     private _assets = [_factionClass] call DSC_getMotorizedAssets;
//                     {
//                         private _existing = _motorized getOrDefault [_x, []];
//                         _motorized set [_x, _existing + (_assets get _x)];
//                     } forEach (keys _assets);
//                 };
//                 case "mechanized": {
//                     private _assets = [_factionClass] call DSC_getArmorAssets;
//                     {
//                         private _existing = _mechanized getOrDefault [_x, []];
//                         _mechanized set [_x, _existing + (_assets get _x)];
//                     } forEach (keys _assets);
//                 };
//                 case "airFixedWing": {
//                     private _assets = [_factionClass] call DSC_getAirAssets;
//                     {
//                         private _existing = _airFixedWing getOrDefault [_x, []];
//                         _airFixedWing set [_x, _existing + (_assets get _x)];
//                     } forEach (keys _assets);
//                 };
//                 case "airRotaryWing": {
//                     private _assets = [_factionClass] call DSC_getAirAssets;
//                     {
//                         private _existing = _airRotaryWing getOrDefault [_x, []];
//                         _airRotaryWing set [_x, _existing + (_assets get _x)];
//                     } forEach (keys _assets);
//                 };
//                 case "navy": {
//                     private _assets = [_factionClass] call DSC_getNavalAssets;
//                     {
//                         private _existing = _navy getOrDefault [_x, []];
//                         _navy set [_x, _existing + (_assets get _x)];
//                     } forEach (keys _assets);
//                 };
//             };
//         } forEach _branches;
//     } forEach _factionSources;
    
//     _factionMap set ["side", _side];
//     _factionMap set ["sourceClasses", _sourceClasses];
//     _factionMap set ["infantry", _infantry];
//     _factionMap set ["specops", _specops];
//     _factionMap set ["motorized", _motorized];
//     _factionMap set ["mechanized", _mechanized];
//     _factionMap set ["airFixedWing", _airFixedWing];
//     _factionMap set ["airRotaryWing", _airRotaryWing];
//     _factionMap set ["navy", _navy];
    
//     _factionMap;
// };


// Build Aegis Mod BluFor
missionNamespace setVariable ["aegisBluForHashmap", 
    ["US BluFor", [
        ["BLU_F", ["infantry", "specops", "motorized", "mechanized", "airFixedWing", "airRotaryWing", "navy"]]
    ]] call DSC_core_fnc_getFactionMapper, 
true];

// Build US Armed Forces
missionNamespace setVariable ["usafHashmap", 
    ["US Armed Forces", [
        ["rhs_faction_usarmy", ["infantry", "motorized", "mechanized", "airRotaryWing"]],
        ["rhs_faction_socom", ["specops", "navy"]],
        ["rhs_faction_usaf", ["airFixedWing"]]
    ]] call DSC_core_fnc_getFactionMapper, 
true];

// // Log faction hashmaps for verification
["US BluFor (Aegis)", missionNamespace getVariable "aegisBluForHashmap"] call DSC_logHashmap;
["USAF (RHS)", missionNamespace getVariable "usafHashmap"] call DSC_logHashmap;

// // Configure factions for this map
// // Player faction: US SOCOM (specops) + USAF (air support)
// missionNamespace setVariable ["playerFactionHashmap", 
//     ["US Armed Forces", [
//         ["rhs_faction_socom", ["specops", "navy"]],
//         ["rhs_faction_usaf", ["air"]]
//     ]] call DSC_getFactionMapper, 
// true];

// // Host nation: AAF (all branches from single faction)
// missionNamespace setVariable ["hostNationFactionHashmap", 
//     ["Altis Armed Forces", [
//         ["IND_F", ["infantry", "armor", "mechanized", "air"]]
//     ]] call DSC_getFactionMapper, 
// true];

// // Invader faction: Russian MSV (infantry/armor) + VVS (air)
// missionNamespace setVariable ["invaderFactionHashmap", 
//     ["Russian Armed Forces", [
//         ["rhs_faction_msv", ["infantry", "armor", "mechanized"]],
//         ["rhs_faction_vvs", ["air"]]
//     ]] call DSC_getFactionMapper, 
// true];

// // Log faction hashmaps for verification
// ["Player Faction", missionNamespace getVariable "playerFactionHashmap"] call DSC_logHashmap;
// ["Host Nation Faction", missionNamespace getVariable "hostNationFactionHashmap"] call DSC_logHashmap;
// ["Invader Faction", missionNamespace getVariable "invaderFactionHashmap"] call DSC_logHashmap;

