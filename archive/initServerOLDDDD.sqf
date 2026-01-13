// DSC - Dynamic SOF Campaign - Altis
// Using Aegis and RHS for now, eventually vanilla will be default and code will check for Aegis/RHS mods

diag_log "========== DSC: Faction Discovery Starting ==========";

// ============================================================================
// STEP 1: Get all available factions from CfgFactionClasses
// ============================================================================
private _factions = [];
{
    private _factionClass = configName _x;
    private _displayName = getText (_x >> "displayName");
    private _side = getNumber (_x >> "side");
    
    // Side mapping: 0=OPFOR, 1=BLUFOR, 2=INDFOR, 3=CIV
    private _sideName = ["OPFOR", "BLUFOR", "INDFOR", "CIVILIAN"] select (_side min 3);
    
    _factions pushBack [_factionClass, _displayName, _side, _sideName];
    
    diag_log format ["DSC: Faction found - %1 (%2) [%3]", _displayName, _factionClass, _sideName];
} forEach ("true" configClasses (configFile >> "CfgFactionClasses"));

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


// Build Aegis Mod BluFor
missionNamespace setVariable ["aegisBluForHashmap", 
    ["US BluFor", [
        ["BLU_F", ["infantry", "specops", "motorized", "mechanized", "airFixedWing", "airRotaryWing", "navy"]]
    ]] call DSC_core_fnc_getFactionMapper, 
true];

// Build US Armed Forces
missionNamespace setVariable ["usafHashmap", 
    ["US Armed Forces", [
        ["rhs_faction_usarmy_wd", ["infantry", "motorized", "mechanized", "airRotaryWing"]],
        ["rhs_faction_socom", ["specops", "navy"]],
        ["rhs_faction_usaf", ["airFixedWing"]]
    ]] call DSC_core_fnc_getFactionMapper, 
true];

// // Log faction hashmaps for verification
["US BluFor (Aegis)", missionNamespace getVariable "aegisBluForHashmap"] call DSC_logHashmap;
["USAF (RHS)", missionNamespace getVariable "usafHashmap"] call DSC_logHashmap;
