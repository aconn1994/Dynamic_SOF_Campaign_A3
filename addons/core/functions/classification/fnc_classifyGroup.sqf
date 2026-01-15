#include "script_component.hpp"

/*
 * Classify a group and assign doctrine tags.
 * 
 * Takes a group data hashmap from fnc_extractGroups and enriches it with
 * doctrine tags based on unit composition, weapons, and naming patterns.
 * 
 * Arguments:
 *   0: Group data hashmap from fnc_extractGroups <HASHMAP>
 * 
 * Returns:
 *   Hashmap with original data plus:
 *     - "doctrineTags": Array of doctrine tag strings
 *     - "unitAnalysis": Summary of unit composition
 *     - "confidence": Classification confidence 0.0-1.0
 * 
 * Example:
 *   [_groupData] call DSC_core_fnc_classifyGroup
 */

params ["_groupData"];

// ============================================================================
// CONFIGURABLE TAG ARRAYS - Adjust these to tune classification
// ============================================================================

// Size thresholds
private _sizeFireteamMin = 2;
private _sizeFireteamMax = 5;
private _sizeSquadMin = 6;
private _sizeSquadMax = 14;
private _sizePlatoonMin = 15;

// Name patterns for elite units
private _elitePatterns = [
    "sf", "sof", "specop", "special", "spetsnaz", "vdv", "seal", "ranger",
    "marsoc", "ctrg", "recon", "lrrp", "pathfinder", "para", "airborne",
    "commando", "delta", "devgru", "sas", "jtf", "socom"
];

// Name patterns for militia/insurgent units  
private _militiaPatterns = [
    "militia", "insurgent", "rebel", "guerr", "irreg", "partisan",
    "fighter", "local", "tribal"
];

// Name patterns for conscript/low-tier units
private _conscriptPatterns = [
    "conscript", "recruit", "reserve", "auxiliary", "trainee", "cadet"
];

// ============================================================================
// ANALYZE UNITS
// ============================================================================

private _vehicles = _groupData get "vehicles";
private _unitCount = _groupData get "unitCount";
private _category = toLower (_groupData get "category");
private _groupName = toLower (_groupData get "groupName");

// Classify each unit
private _unitClassifications = [];
private _infantryCount = 0;
private _vehicleCount = 0;
private _officerCount = 0;
private _atCount = 0;
private _aaCount = 0;
private _mgCount = 0;
private _sniperCount = 0;
private _mortarCount = 0;
private _medicCount = 0;
private _engineerCount = 0;
private _reconCount = 0;
private _crewCount = 0;
private _pilotCount = 0;
private _diverCount = 0;
private _nvgCount = 0;

private _vehicleTypes = [];

{
    private _unitData = [_x] call DSC_core_fnc_classifyUnit;
    _unitClassifications pushBack _unitData;
    
    if (_unitData get "isMan") then {
        _infantryCount = _infantryCount + 1;
        if (_unitData get "isOfficer") then { _officerCount = _officerCount + 1 };
        if (_unitData get "hasAT") then { _atCount = _atCount + 1 };
        if (_unitData get "hasAA") then { _aaCount = _aaCount + 1 };
        if (_unitData get "hasMG") then { _mgCount = _mgCount + 1 };
        if (_unitData get "hasSniper") then { _sniperCount = _sniperCount + 1 };
        if (_unitData get "hasMortar") then { _mortarCount = _mortarCount + 1 };
        if (_unitData get "isMedic") then { _medicCount = _medicCount + 1 };
        if (_unitData get "isEngineer") then { _engineerCount = _engineerCount + 1 };
        if (_unitData get "isRecon") then { _reconCount = _reconCount + 1 };
        if (_unitData get "isCrew") then { _crewCount = _crewCount + 1 };
        if (_unitData get "isPilot") then { _pilotCount = _pilotCount + 1 };
        if (_unitData get "isDiver") then { _diverCount = _diverCount + 1 };
        if (_unitData get "hasNVG") then { _nvgCount = _nvgCount + 1 };
    } else {
        _vehicleCount = _vehicleCount + 1;
        _vehicleTypes pushBackUnique (_unitData get "vehicleType");
    };
} forEach _vehicles;

// ============================================================================
// BUILD DOCTRINE TAGS
// ============================================================================

private _doctrineTags = [];
private _confidence = 0.5; // Base confidence

// --- SIZE-BASED TAGS ---
if (_infantryCount >= _sizeFireteamMin && {_infantryCount <= _sizeFireteamMax} && {_vehicleCount == 0}) then {
    _doctrineTags pushBack "FIRETEAM";
    _confidence = _confidence + 0.1;
};

if (_infantryCount >= _sizeSquadMin && {_infantryCount <= _sizeSquadMax} && {_vehicleCount == 0}) then {
    _doctrineTags pushBack "INFANTRY_SQUAD";
    _confidence = _confidence + 0.1;
};

if (_infantryCount >= _sizePlatoonMin) then {
    _doctrineTags pushBack "PLATOON_ELEMENT";
};

// --- WEAPONS-BASED TAGS ---
if (_atCount >= 1) then {
    _doctrineTags pushBack "ANTI_ARMOR";
    if (_atCount >= 2 || {_infantryCount <= 4 && _atCount >= 1}) then {
        _doctrineTags pushBack "AT_TEAM";
        _confidence = _confidence + 0.15;
    };
};

if (_aaCount >= 1) then {
    _doctrineTags pushBack "ANTI_AIR";
    if (_aaCount >= 2 || {_infantryCount <= 4 && _aaCount >= 1}) then {
        _doctrineTags pushBack "AA_TEAM";
        _confidence = _confidence + 0.15;
    };
};

if (_mgCount >= 2) then {
    _doctrineTags pushBack "WEAPONS_SQUAD";
    _doctrineTags pushBack "SUPPORT_BY_FIRE";
};

if (_sniperCount >= 1 && {_infantryCount <= 3}) then {
    _doctrineTags pushBack "SNIPER_TEAM";
    _confidence = _confidence + 0.2;
};

if (_mortarCount >= 1) then {
    _doctrineTags pushBack "MORTAR_SECTION";
    _doctrineTags pushBack "INDIRECT_FIRE";
    _confidence = _confidence + 0.15;
};

// --- ROLE-BASED TAGS ---
if (_officerCount >= 1 && {_infantryCount <= 6}) then {
    _doctrineTags pushBack "COMMAND_ELEMENT";
    _confidence = _confidence + 0.1;
};

if (_medicCount >= 1 && {_atCount == 0} && {_mgCount == 0}) then {
    _doctrineTags pushBack "MEDICAL_TEAM";
};

if (_engineerCount >= 1) then {
    _doctrineTags pushBack "ENGINEER_TEAM";
};

if (_reconCount >= 1 || {_category find "recon" >= 0} || {_category find "specop" >= 0}) then {
    _doctrineTags pushBack "SCOUT_RECON";
    _confidence = _confidence + 0.1;
};

if (_diverCount >= 1) then {
    _doctrineTags pushBack "AMPHIBIOUS";
};

if (_crewCount == _infantryCount && {_crewCount >= 2}) then {
    _doctrineTags pushBack "VEHICLE_CREW";
};

if (_pilotCount >= 1) then {
    _doctrineTags pushBack "AIR_CREW";
};

// --- MOBILITY TAGS ---
if (_vehicleCount == 0) then {
    _doctrineTags pushBack "FOOT";
} else {
    if ("tank" in _vehicleTypes) then {
        _doctrineTags pushBack "ARMORED";
        _doctrineTags pushBack "ARMOR";
        _confidence = _confidence + 0.15;
    };
    
    if ("apc" in _vehicleTypes) then {
        _doctrineTags pushBack "MECHANIZED";
        _confidence = _confidence + 0.1;
    };
    
    if ("car" in _vehicleTypes || {"mrap" in _vehicleTypes}) then {
        if (!("MECHANIZED" in _doctrineTags) && {!("ARMORED" in _doctrineTags)}) then {
            _doctrineTags pushBack "MOTORIZED";
        };
    };
    
    if ("helicopter" in _vehicleTypes) then {
        _doctrineTags pushBack "AIRBORNE";
        if (_infantryCount > 0) then {
            _doctrineTags pushBack "AIR_ASSAULT";
        };
    };
    
    if ("plane" in _vehicleTypes) then {
        _doctrineTags pushBack "FIXED_WING";
    };
    
    if ("static" in _vehicleTypes) then {
        _doctrineTags pushBack "STATIC";
        _doctrineTags pushBack "GARRISON";
    };
    
    if (("boat") in _vehicleTypes) then {
        _doctrineTags pushBack "AMPHIBIOUS";
        _doctrineTags pushBack "NAVAL";
    };
};

// --- NAME-BASED DOCTRINE TAGS ---

// Elite detection
private _isElite = false;
{
    if (_groupName find _x >= 0 || {_category find _x >= 0}) exitWith {
        _isElite = true;
    };
} forEach _elitePatterns;
if (_isElite) then {
    _doctrineTags pushBack "ELITE";
    _confidence = _confidence + 0.1;
};

// Militia detection
private _isMilitia = false;
{
    if (_groupName find _x >= 0 || {_category find _x >= 0}) exitWith {
        _isMilitia = true;
    };
} forEach _militiaPatterns;
if (_isMilitia) then {
    _doctrineTags pushBack "MILITIA";
    _confidence = _confidence + 0.1;
};

// Conscript detection
private _isConscript = false;
{
    if (_groupName find _x >= 0 || {_category find _x >= 0}) exitWith {
        _isConscript = true;
    };
} forEach _conscriptPatterns;
if (_isConscript) then {
    _doctrineTags pushBack "CONSCRIPTS";
    _confidence = _confidence + 0.1;
};

// --- CAPABILITY TAGS ---
private _nvgRatio = 0;
if (_infantryCount > 0) then {
    _nvgRatio = _nvgCount / _infantryCount;
};
if (_nvgRatio >= 0.5) then {
    _doctrineTags pushBack "NIGHT_CAPABLE";
};

// --- PATROL/GARRISON INFERENCE ---
if (_infantryCount >= 2 && {_infantryCount <= 8} && {_vehicleCount == 0} && {!("SNIPER_TEAM" in _doctrineTags)}) then {
    _doctrineTags pushBack "PATROL";
};

// Clamp confidence
if (_confidence > 1.0) then { _confidence = 1.0 };
if (_confidence < 0.1) then { _confidence = 0.1 };

// ============================================================================
// BUILD UNIT ANALYSIS SUMMARY
// ============================================================================

private _unitAnalysis = createHashMap;
_unitAnalysis set ["totalUnits", _unitCount];
_unitAnalysis set ["infantryCount", _infantryCount];
_unitAnalysis set ["vehicleCount", _vehicleCount];
_unitAnalysis set ["officerCount", _officerCount];
_unitAnalysis set ["atCount", _atCount];
_unitAnalysis set ["aaCount", _aaCount];
_unitAnalysis set ["mgCount", _mgCount];
_unitAnalysis set ["sniperCount", _sniperCount];
_unitAnalysis set ["mortarCount", _mortarCount];
_unitAnalysis set ["medicCount", _medicCount];
_unitAnalysis set ["engineerCount", _engineerCount];
_unitAnalysis set ["reconCount", _reconCount];
_unitAnalysis set ["crewCount", _crewCount];
_unitAnalysis set ["pilotCount", _pilotCount];
_unitAnalysis set ["diverCount", _diverCount];
_unitAnalysis set ["nvgCount", _nvgCount];
_unitAnalysis set ["vehicleTypes", _vehicleTypes];

// ============================================================================
// RETURN ENRICHED GROUP DATA
// ============================================================================

// Copy original data
private _result = createHashMap;
{
    _result set [_x, _groupData get _x];
} forEach keys _groupData;

// Add classification data
_result set ["doctrineTags", _doctrineTags];
_result set ["unitAnalysis", _unitAnalysis];
_result set ["confidence", _confidence];

_result
