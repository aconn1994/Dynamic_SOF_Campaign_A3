#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_extractAssets
 * Description:
 *     Auto-scans CfgVehicles to extract and classify all vehicle/asset types
 *     for a given faction. Replaces hardcoded fnc_getFactionAssets.
 *     Works with any faction - vanilla, RHS, CUP, 3CB, Legion, etc.
 *
 * Arguments:
 *     0: _faction <STRING> - Faction classname (e.g. "OPF_F", "rhs_faction_msv")
 *
 * Return Value:
 *     <HASHMAP> - Classified assets:
 *       "staticWeapons" <HASHMAP>: "HMG", "GMG", "AT", "AA", "mortar", "cannon", "other"
 *       "cars"          <HASHMAP>: "unarmed", "armed", "mrap"
 *       "trucks"        <ARRAY>
 *       "apcs"          <ARRAY>
 *       "tanks"         <ARRAY>
 *       "helicopters"   <HASHMAP>: "attack", "transport"
 *       "planes"        <HASHMAP>: "attack", "transport"
 *       "boats"         <ARRAY>
 *       "drones"        <ARRAY>
 *
 * Example:
 *     private _assets = ["OPF_F"] call DSC_core_fnc_extractAssets;
 *     private _hmgs = (_assets get "staticWeapons") get "HMG";
 */

params [
    ["_faction", "", [""]]
];

if (_faction == "") exitWith {
    diag_log "DSC: fnc_extractAssets - No faction provided";
    createHashMap
};

private _filterStr = format ["getNumber (_x >> 'scope') >= 2 && getText (_x >> 'faction') == '%1'", _faction];
private _vehicles = _filterStr configClasses (configFile >> "CfgVehicles");

private _staticWeapons = createHashMapFromArray [["HMG", []], ["GMG", []], ["AT", []], ["AA", []], ["mortar", []], ["cannon", []], ["other", []]];
private _cars = createHashMapFromArray [["unarmed", []], ["armed", []], ["mrap", []]];
private _trucks = [];
private _apcs = [];
private _tanks = [];
private _helicopters = createHashMapFromArray [["attack", []], ["transport", []]];
private _planes = createHashMapFromArray [["attack", []], ["transport", []]];
private _boats = [];
private _drones = [];

{
    private _cfg = _x;
    private _class = configName _cfg;
    private _isMan = getNumber (_cfg >> "isMan");
    if (_isMan == 1) then { continue };
    
    private _isUAV = getNumber (_cfg >> "isUav");
    private _sim = toLower (getText (_cfg >> "simulation"));
    private _editorSubcat = getText (_cfg >> "editorSubcategory");
    
    // ============================================================================
    // Static Weapons (check FIRST - they use tankX sim)
    // ============================================================================
    if (_class isKindOf "StaticWeapon") then {
        if (_isUAV == 1) then {
            (_staticWeapons get "other") pushBack _class;
            continue;
        };
        
        if (_class isKindOf "StaticMortar") then {
            (_staticWeapons get "mortar") pushBack _class;
        } else {
            if (_class isKindOf "StaticCannon") then {
                (_staticWeapons get "cannon") pushBack _class;
            } else {
                if (_class isKindOf "StaticAAWeapon") then {
                    (_staticWeapons get "AA") pushBack _class;
                } else {
                    if (_class isKindOf "StaticATWeapon") then {
                        (_staticWeapons get "AT") pushBack _class;
                    } else {
                        if (_class isKindOf "StaticGrenadeLauncher") then {
                            (_staticWeapons get "GMG") pushBack _class;
                        } else {
                            private _classLower = toLower _class;
                            if ("_aa_" in _classLower || "static_aa" in _classLower || "stinger" in _classLower || "igla" in _classLower) then {
                                (_staticWeapons get "AA") pushBack _class;
                            } else {
                                if ("_at_" in _classLower || "static_at" in _classLower || "tow_" in _classLower || "spg9" in _classLower) then {
                                    (_staticWeapons get "AT") pushBack _class;
                                } else {
                                    if (_class isKindOf "StaticMGWeapon") then {
                                        (_staticWeapons get "HMG") pushBack _class;
                                    } else {
                                        (_staticWeapons get "other") pushBack _class;
                                    };
                                };
                            };
                        };
                    };
                };
            };
        };
        continue;
    };
    
    // ============================================================================
    // Drones / UAVs
    // ============================================================================
    if (_isUAV == 1) then {
        _drones pushBack _class;
        continue;
    };
    
    // ============================================================================
    // Aircraft
    // ============================================================================
    if (_sim in ["helicopter", "helicopterrtd", "helicopterx"]) then {
        private _transport = getNumber (_cfg >> "transportSoldier");
        [_helicopters get "attack", _helicopters get "transport"] select (_transport >= 6) pushBack _class;
        continue;
    };
    
    if (_sim in ["airplane", "airplanex"]) then {
        private _transport = getNumber (_cfg >> "transportSoldier");
        [_planes get "attack", _planes get "transport"] select (_transport >= 6) pushBack _class;
        continue;
    };
    
    // ============================================================================
    // Boats
    // ============================================================================
    if (_sim in ["shipx", "ship"]) then {
        _boats pushBack _class;
        continue;
    };
    
    // ============================================================================
    // Ground Vehicles
    // ============================================================================
    if (_sim in ["carx", "car", "tankx", "tank"]) then {
        if (_class isKindOf "Truck_F" && !(_class isKindOf "Wheeled_APC_F")) then {
            _trucks pushBack _class;
            continue;
        };
        
        if (_class isKindOf "Wheeled_APC_F") then {
            _apcs pushBack _class;
            continue;
        };
        
        if (_class isKindOf "Tank_F" || _class isKindOf "Tank") then {
            private _editorLower = toLower _editorSubcat;
            if ("tank" in _editorLower || "mbt" in _editorLower) then {
                _tanks pushBack _class;
            } else {
                if ("apc" in _editorLower || "ifv" in _editorLower) then {
                    _apcs pushBack _class;
                } else {
                    private _transport = getNumber (_cfg >> "transportSoldier");
                    [_tanks, _apcs] select (_transport >= 5) pushBack _class;
                };
            };
            continue;
        };
        
        private _armor = getNumber (_cfg >> "armor");
        if (_armor >= 100) then {
            (_cars get "mrap") pushBack _class;
            continue;
        };
        
        private _hasWeapon = false;
        private _turrets = "true" configClasses (_cfg >> "Turrets");
        {
            private _weapons = getArray (_x >> "weapons");
            { if !(_x in ["", "SmokeLauncher", "TruckHorn", "CarHorn"]) exitWith { _hasWeapon = true } } forEach _weapons;
        } forEach _turrets;
        
        [_cars get "unarmed", _cars get "armed"] select _hasWeapon pushBack _class;
        continue;
    };
    
} forEach _vehicles;

private _result = createHashMapFromArray [
    ["staticWeapons", _staticWeapons],
    ["cars", _cars],
    ["trucks", _trucks],
    ["apcs", _apcs],
    ["tanks", _tanks],
    ["helicopters", _helicopters],
    ["planes", _planes],
    ["boats", _boats],
    ["drones", _drones]
];

diag_log format ["DSC: Extracted assets for %1 - statics: %2, cars: %3, trucks: %4, apcs: %5, tanks: %6, helis: %7, planes: %8",
    _faction,
    (count (_staticWeapons get "HMG")) + (count (_staticWeapons get "GMG")) + (count (_staticWeapons get "AT")) + (count (_staticWeapons get "AA")) + (count (_staticWeapons get "mortar")),
    (count (_cars get "unarmed")) + (count (_cars get "armed")) + (count (_cars get "mrap")),
    count _trucks, count _apcs, count _tanks,
    (count (_helicopters get "attack")) + (count (_helicopters get "transport")),
    (count (_planes get "attack")) + (count (_planes get "transport"))
];

_result
