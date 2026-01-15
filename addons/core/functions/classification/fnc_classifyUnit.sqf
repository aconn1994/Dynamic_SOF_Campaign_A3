#include "script_component.hpp"

/*
 * Classify a single unit from CfgVehicles.
 * 
 * Inspects a unit classname and extracts classification data including
 * role, equipment, weapons, and capabilities.
 * 
 * Arguments:
 *   0: Unit classname <STRING>
 * 
 * Returns:
 *   Hashmap with classification data:
 *     - "classname": The input classname
 *     - "displayName": Unit display name
 *     - "isMan": Whether this is infantry (not vehicle)
 *     - "isVehicle": Whether this is a vehicle
 *     - "vehicleType": Type of vehicle (car, tank, helicopter, etc.)
 *     - "isOfficer": Whether unit has officer rank
 *     - "rank": Unit rank string
 *     - "hasAT": Has anti-tank capability
 *     - "hasAA": Has anti-air capability
 *     - "hasMG": Has machine gun
 *     - "hasSniper": Has sniper rifle
 *     - "hasMortar": Has mortar/indirect fire
 *     - "isMedic": Is a medic unit
 *     - "isEngineer": Is an engineer unit
 *     - "isPilot": Is a pilot
 *     - "isCrew": Is vehicle crew
 *     - "isDiver": Is a combat diver
 *     - "isRecon": Is recon/SF unit
 *     - "hasNVG": Has night vision
 *     - "editorSubcategory": Editor subcategory string
 *     - "vehicleClass": vehicleClass config value
 *     - "faction": Unit faction
 *     - "traits": Array of detected trait strings
 * 
 * Example:
 *   ["rhs_msv_rifleman"] call DSC_core_fnc_classifyUnit
 */

params ["_classname"];

private _result = createHashMap;
_result set ["classname", _classname];

// Default values
_result set ["displayName", ""];
_result set ["isMan", false];
_result set ["isVehicle", false];
_result set ["vehicleType", "unknown"];
_result set ["isOfficer", false];
_result set ["rank", "PRIVATE"];
_result set ["hasAT", false];
_result set ["hasAA", false];
_result set ["hasMG", false];
_result set ["hasSniper", false];
_result set ["hasMortar", false];
_result set ["isMedic", false];
_result set ["isEngineer", false];
_result set ["isPilot", false];
_result set ["isCrew", false];
_result set ["isDiver", false];
_result set ["isRecon", false];
_result set ["hasNVG", false];
_result set ["editorSubcategory", ""];
_result set ["vehicleClass", ""];
_result set ["faction", ""];
_result set ["traits", []];

// Get config
private _cfg = configFile >> "CfgVehicles" >> _classname;
if (!isClass _cfg) exitWith {
    diag_log format ["DSC: fnc_classifyUnit - Class '%1' not found in CfgVehicles", _classname];
    _result
};

// Basic info
_result set ["displayName", getText (_cfg >> "displayName")];
_result set ["faction", getText (_cfg >> "faction")];
_result set ["editorSubcategory", getText (_cfg >> "editorSubcategory")];
_result set ["vehicleClass", getText (_cfg >> "vehicleClass")];

// Man vs Vehicle
private _isMan = getNumber (_cfg >> "isMan") == 1;
_result set ["isMan", _isMan];
_result set ["isVehicle", !_isMan];

// ============================================================================
// VEHICLE CLASSIFICATION
// ============================================================================
if (!_isMan) then {
    private _vehClass = toLower getText (_cfg >> "vehicleClass");
    private _simulation = toLower getText (_cfg >> "simulation");
    
    private _vehicleType = switch (true) do {
        case (_simulation == "tankx" || {_vehClass find "tank" >= 0} || {_vehClass find "armor" >= 0}): { "tank" };
        case (_vehClass find "apc" >= 0 || {_vehClass find "ifv" >= 0}): { "apc" };
        case (_vehClass find "mrap" >= 0): { "mrap" };
        case (_vehClass find "car" >= 0 || {_vehClass find "truck" >= 0}): { "car" };
        case (_simulation == "helicopterrtd" || {_simulation == "helicopter"} || {_vehClass find "heli" >= 0}): { "helicopter" };
        case (_simulation == "airplanex" || {_vehClass find "plane" >= 0} || {_vehClass find "jet" >= 0}): { "plane" };
        case (_vehClass find "ship" >= 0 || {_vehClass find "boat" >= 0}): { "boat" };
        case (_vehClass find "static" >= 0): { "static" };
        default { "vehicle" };
    };
    _result set ["vehicleType", _vehicleType];
    
    // Check for weapon systems on vehicle
    private _weapons = getArray (_cfg >> "weapons");
    {
        private _wepLower = toLower _x;
        if (_wepLower find "missile" >= 0 || {_wepLower find "rocket" >= 0} || {_wepLower find "cannon" >= 0}) then {
            _result set ["hasAT", true];
        };
        if (_wepLower find "aa" >= 0 || {_wepLower find "stinger" >= 0} || {_wepLower find "igla" >= 0}) then {
            _result set ["hasAA", true];
        };
    } forEach _weapons;
} else {
    // ============================================================================
    // INFANTRY CLASSIFICATION
    // ============================================================================
    
    // Rank detection
    private _rank = getText (_cfg >> "rank");
    if (_rank == "") then { _rank = "PRIVATE" };
    _result set ["rank", _rank];
    
    // Officer detection - ranks that indicate command
    private _officerRanks = ["OFFICER", "COLONEL", "MAJOR", "CAPTAIN", "LIEUTENANT", "SERGEANT"];
    {
        if (toUpper _rank find _x >= 0) exitWith {
            _result set ["isOfficer", true];
        };
    } forEach _officerRanks;
    
    // Get linked items and weapons for classification
    private _linkedItems = getArray (_cfg >> "linkedItems");
    private _weapons = getArray (_cfg >> "weapons");
    private _respawnWeapons = getArray (_cfg >> "respawnWeapons");
    private _allWeapons = _weapons + _respawnWeapons;
    
    // Get magazines - critical for AT vs AA distinction (same launcher, different ammo)
    private _magazines = getArray (_cfg >> "magazines");
    private _respawnMagazines = getArray (_cfg >> "respawnMagazines");
    private _allMagazines = _magazines + _respawnMagazines;
    
    // NVG detection
    {
        if (toLower _x find "nvg" >= 0 || {toLower _x find "night" >= 0}) exitWith {
            _result set ["hasNVG", true];
        };
    } forEach _linkedItems;
    
    // Magazine-based AA/AT detection (must come first - determines launcher role)
    // Vanilla Titan launcher is multi-purpose; ammo determines if AA or AT
    private _hasAAMag = false;
    private _hasATMag = false;
    {
        private _magLower = toLower _x;
        
        // AA magazines
        if (
            _magLower find "titan_aa" >= 0 ||
            {_magLower find "_aa_" >= 0} ||
            {_magLower find "stinger" >= 0} ||
            {_magLower find "igla" >= 0} ||
            {_magLower find "9k38" >= 0} ||
            {_magLower find "fim92" >= 0}
        ) then {
            _hasAAMag = true;
            _result set ["hasAA", true];
        };
        
        // AT magazines  
        if (
            _magLower find "titan_at" >= 0 ||
            {_magLower find "titan_ap" >= 0} ||
            {_magLower find "rpg" >= 0} ||
            {_magLower find "nlaw" >= 0} ||
            {_magLower find "javelin" >= 0} ||
            {_magLower find "maaws" >= 0} ||
            {_magLower find "smaw" >= 0} ||
            {_magLower find "panzerfaust" >= 0} ||
            {_magLower find "_at_" >= 0} ||
            {_magLower find "_heat" >= 0} ||
            {_magLower find "_pg7" >= 0}
        ) then {
            _hasATMag = true;
        };
    } forEach _allMagazines;
    
    // Weapon-based role detection
    {
        private _wepLower = toLower _x;
        
        // AT weapons - but only set hasAT if we don't have AA ammo
        // (soldier with Titan + AA ammo is AA, not AT)
        if (
            _wepLower find "rpg" >= 0 ||
            {_wepLower find "javelin" >= 0} ||
            {_wepLower find "nlaw" >= 0} ||
            {_wepLower find "smaw" >= 0} ||
            {_wepLower find "maaws" >= 0} ||
            {_wepLower find "_at_" >= 0} ||
            {_wepLower find "panzerfaust" >= 0}
        ) then {
            _result set ["hasAT", true];
        };
        
        // Generic launcher - only mark as AT if has AT ammo or no AA ammo
        if (_wepLower find "launch" >= 0 || {_wepLower find "titan" >= 0}) then {
            if (_hasATMag || {!_hasAAMag}) then {
                _result set ["hasAT", true];
            };
        };
        
        // AA weapons (dedicated AA launchers, not multi-purpose)
        if (
            _wepLower find "stinger" >= 0 ||
            {_wepLower find "igla" >= 0} ||
            {_wepLower find "fim92" >= 0} ||
            {_wepLower find "9k38" >= 0}
        ) then {
            _result set ["hasAA", true];
        };
        
        // Machine guns
        if (
            _wepLower find "lmg" >= 0 ||
            {_wepLower find "mmg" >= 0} ||
            {_wepLower find "hmg" >= 0} ||
            {_wepLower find "m249" >= 0} ||
            {_wepLower find "m240" >= 0} ||
            {_wepLower find "mk48" >= 0} ||
            {_wepLower find "pkm" >= 0} ||
            {_wepLower find "pkp" >= 0} ||
            {_wepLower find "m60" >= 0}
        ) then {
            _result set ["hasMG", true];
        };
        
        // Sniper rifles
        if (
            _wepLower find "sniper" >= 0 ||
            {_wepLower find "dmr" >= 0} ||
            {_wepLower find "ebr" >= 0} ||
            {_wepLower find "m24" >= 0} ||
            {_wepLower find "m40" >= 0} ||
            {_wepLower find "svd" >= 0} ||
            {_wepLower find "vss" >= 0} ||
            {_wepLower find "lynx" >= 0} ||
            {_wepLower find "m107" >= 0} ||
            {_wepLower find "mar10" >= 0}
        ) then {
            _result set ["hasSniper", true];
        };
        
        // Mortar
        if (_wepLower find "mortar" >= 0) then {
            _result set ["hasMortar", true];
        };
    } forEach _allWeapons;
    
    // Editor subcategory based detection
    private _editorSubcat = toLower getText (_cfg >> "editorSubcategory");
    private _displayNameLower = toLower getText (_cfg >> "displayName");
    private _classnameLower = toLower _classname;
    
    // Medic detection
    if (
        _editorSubcat find "medic" >= 0 ||
        {_displayNameLower find "medic" >= 0} ||
        {_classnameLower find "medic" >= 0} ||
        {_classnameLower find "corpsman" >= 0}
    ) then {
        _result set ["isMedic", true];
    };
    
    // Engineer detection
    if (
        _editorSubcat find "engineer" >= 0 ||
        {_displayNameLower find "engineer" >= 0} ||
        {_classnameLower find "engineer" >= 0} ||
        {_classnameLower find "sapper" >= 0} ||
        {_classnameLower find "eod" >= 0}
    ) then {
        _result set ["isEngineer", true];
    };
    
    // Pilot detection
    if (
        _editorSubcat find "pilot" >= 0 ||
        {_displayNameLower find "pilot" >= 0} ||
        {_classnameLower find "pilot" >= 0} ||
        {_classnameLower find "helipilot" >= 0}
    ) then {
        _result set ["isPilot", true];
    };
    
    // Crew detection
    if (
        _editorSubcat find "crew" >= 0 ||
        {_displayNameLower find "crew" >= 0} ||
        {_classnameLower find "crew" >= 0} ||
        {_classnameLower find "crewman" >= 0}
    ) then {
        _result set ["isCrew", true];
    };
    
    // Diver detection
    if (
        _editorSubcat find "diver" >= 0 ||
        {_displayNameLower find "diver" >= 0} ||
        {_classnameLower find "diver" >= 0} ||
        {_classnameLower find "frogman" >= 0}
    ) then {
        _result set ["isDiver", true];
    };
    
    // Recon/SF detection
    if (
        _editorSubcat find "recon" >= 0 ||
        {_editorSubcat find "special" >= 0} ||
        {_displayNameLower find "recon" >= 0} ||
        {_displayNameLower find "scout" >= 0} ||
        {_classnameLower find "recon" >= 0} ||
        {_classnameLower find "scout" >= 0} ||
        {_classnameLower find "sf_" >= 0} ||
        {_classnameLower find "_sf" >= 0} ||
        {_classnameLower find "specop" >= 0} ||
        {_classnameLower find "spetsnaz" >= 0} ||
        {_classnameLower find "vdv" >= 0} ||
        {_classnameLower find "seal" >= 0} ||
        {_classnameLower find "ranger" >= 0} ||
        {_classnameLower find "marsoc" >= 0} ||
        {_classnameLower find "ctrg" >= 0}
    ) then {
        _result set ["isRecon", true];
    };
    
    // Build traits array
    private _traits = [];
    if (_result get "isOfficer") then { _traits pushBack "OFFICER" };
    if (_result get "hasAT") then { _traits pushBack "AT" };
    if (_result get "hasAA") then { _traits pushBack "AA" };
    if (_result get "hasMG") then { _traits pushBack "MG" };
    if (_result get "hasSniper") then { _traits pushBack "SNIPER" };
    if (_result get "hasMortar") then { _traits pushBack "MORTAR" };
    if (_result get "isMedic") then { _traits pushBack "MEDIC" };
    if (_result get "isEngineer") then { _traits pushBack "ENGINEER" };
    if (_result get "isPilot") then { _traits pushBack "PILOT" };
    if (_result get "isCrew") then { _traits pushBack "CREW" };
    if (_result get "isDiver") then { _traits pushBack "DIVER" };
    if (_result get "isRecon") then { _traits pushBack "RECON" };
    if (_result get "hasNVG") then { _traits pushBack "NVG" };
    _result set ["traits", _traits];
};

_result
