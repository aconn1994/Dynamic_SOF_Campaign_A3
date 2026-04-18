#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_initFactionData
 * Description:
 *     Takes a faction profile config and extracts groups + assets for every
 *     faction in every role. Returns a single data structure that the mission
 *     loop, populateAO, and influence system all read from.
 *
 *     Validates that factions exist in CfgFactionClasses. Skips missing factions
 *     (mod not loaded) with a warning instead of failing.
 *
 * Arguments:
 *     0: _profileConfig <HASHMAP> - Faction profile with roles as keys
 *        Keys: "bluFor", "bluForPartner", "opFor", "opForPartner", "irregulars", "civilians", "environmentalActors"
 *        Values: Arrays of faction classnames
 *
 * Return Value:
 *     <HASHMAP> - Processed faction data:
 *        Per role key (e.g. "opFor"):
 *          <HASHMAP> with:
 *            "factions"  - Array of validated faction classnames
 *            "side"      - Side for this role (east, west, etc.)
 *            "groups"    - Hashmap of faction -> classified groups
 *            "assets"    - Hashmap of faction -> extracted assets
 *
 * Example:
 *     private _factionData = [_factionProfileConfig] call DSC_core_fnc_initFactionData;
 *     private _opForGroups = (_factionData get "opFor") get "groups";
 */

params [
    ["_profileConfig", createHashMap, [createHashMap]]
];

if (_profileConfig isEqualTo createHashMap) exitWith {
    diag_log "DSC: fnc_initFactionData - No profile config provided";
    createHashMap
};

// Roles that need group + asset extraction (skip civilians/environmental for now)
private _combatRoles = ["bluFor", "bluForPartner", "opFor", "opForPartner", "irregulars"];

private _result = createHashMap;

{
    private _role = _x;
    private _roleConfig = _profileConfig getOrDefault [_role, createHashMap];
    if (_roleConfig isEqualTo createHashMap) then { continue };
    
    private _factionList = _roleConfig getOrDefault ["factions", []];
    private _side = _roleConfig getOrDefault ["side", civilian];
    
    private _validFactions = [];
    private _roleGroups = createHashMap;
    private _roleAssets = createHashMap;
    
    {
        private _faction = _x;
        
        // Validate faction exists in loaded configs
        private _factionCfg = configFile >> "CfgFactionClasses" >> _faction;
        if (!isClass _factionCfg) then {
            diag_log format ["DSC: fnc_initFactionData - WARNING: Faction '%1' not found (mod not loaded?), skipping", _faction];
            continue;
        };
        
        _validFactions pushBack _faction;
        
        // Extract groups and assets for combat roles
        if (_role in _combatRoles) then {
            // Groups
            private _rawGroups = [_faction] call DSC_core_fnc_extractGroups;
            private _classifiedGroups = [_rawGroups] call DSC_core_fnc_classifyGroups;
            _roleGroups set [_faction, _classifiedGroups];
            
            diag_log format ["DSC: initFactionData - %1/%2: %3 groups classified", _role, _faction, count _classifiedGroups];
            
            // Assets
            private _assets = [_faction] call DSC_core_fnc_extractAssets;
            _roleAssets set [_faction, _assets];
            
            diag_log format ["DSC: initFactionData - %1/%2: assets extracted", _role, _faction];
        };
    } forEach _factionList;
    
    private _roleData = createHashMapFromArray [
        ["factions", _validFactions],
        ["side", _side],
        ["groups", _roleGroups],
        ["assets", _roleAssets]
    ];
    
    _result set [_role, _roleData];
    
    diag_log format ["DSC: initFactionData - Role '%1': %2/%3 factions valid", _role, count _validFactions, count _factionList];
    
} forEach keys _profileConfig;

// Summary
private _totalFactions = 0;
private _totalGroups = 0;
{
    private _roleData = _y;
    _totalFactions = _totalFactions + count (_roleData get "factions");
    {
        _totalGroups = _totalGroups + count _y;
    } forEach (_roleData get "groups");
} forEach _result;

diag_log format ["DSC: initFactionData complete - %1 factions, %2 total group sets across all roles", _totalFactions, _totalGroups];

_result
