#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_generateKillCaptureMission
 * Description:
 *     Generates a kill/capture mission at a suitable location.
 *     Spawns an HVT unit, guards, garrison, and patrols.
 *
 * Arguments:
 *     0: _militaryLocations <HASHMAP> - Military locations from getMilitaryLocations
 *     1: _civilianLocations <HASHMAP> - Civilian locations from getCivilianLocations
 *     2: _classifiedGroups <ARRAY> - Pre-classified group data
 *     3: _config <HASHMAP> - Optional configuration overrides
 *
 * Return Value:
 *     <HASHMAP> - Mission data structure
 *
 * Example:
 *     [_milLocs, _civLocs, _groups] call DSC_core_fnc_generateKillCaptureMission
 */

params [
    ["_militaryLocations", createHashMap, [createHashMap]],
    ["_civilianLocations", createHashMap, [createHashMap]],
    ["_classifiedGroups", [], [[]]],
    ["_config", createHashMap, [createHashMap]]
];

// ============================================================================
// Configuration
// ============================================================================
private _opForFaction = missionNamespace getVariable ["opForFaction", "OPF_F"];
private _opForSide = east;

// Valid location types for kill/capture missions (compounds, camps, outposts, villages)
private _validMilTypes = _config getOrDefault ["validMilTypes", ["camps", "outposts"]];
private _validCivTypes = _config getOrDefault ["validCivTypes", ["compounds", "villages"]];
private _density = _config getOrDefault ["density", "medium"]; // light, medium, heavy

// ============================================================================
// Select Location
// ============================================================================
private _candidateLocations = [];

// Gather military locations
{
    private _locs = _militaryLocations getOrDefault [_x, []];
    {
        _candidateLocations pushBack [_x, _forEachIndex, "military", _x];
    } forEach _locs;
} forEach _validMilTypes;

// Gather civilian locations
{
    private _locs = _civilianLocations getOrDefault [_x, []];
    {
        _candidateLocations pushBack [_x, _forEachIndex, "civilian", _x];
    } forEach _locs;
} forEach _validCivTypes;

if (_candidateLocations isEqualTo []) exitWith {
    diag_log "DSC: ERROR - No valid locations for kill/capture mission";
    createHashMap
};

// Select random location
private _selectedEntry = selectRandom _candidateLocations;
_selectedEntry params ["_locationPos", "_locationIndex", "_locationType", "_categoryType"];

// Generate location name from nearest Arma location or grid reference
private _nearestLoc = nearestLocation [_locationPos, ""];
private _locationName = if (!isNull _nearestLoc) then {
    text _nearestLoc
} else {
    mapGridPosition _locationPos
};
private _locationId = format ["%1_%2_%3", _locationType, _categoryType, _locationIndex];

diag_log format ["DSC: Kill/Capture mission at %1 (%2) - %3", _locationName, _locationType, _locationPos];

// ============================================================================
// Get Group Classifications
// ============================================================================
private _basicInfantrySquadGroups = [_classifiedGroups, ["FOOT", "INFANTRY_SQUAD", "PATROL"], ["ELITE", "SCOUT_RECON", "AMPHIBIOUS"]] call DSC_core_fnc_getGroupsByTag;
private _basicInfantryFireteamGroups = [_classifiedGroups, ["FOOT", "FIRETEAM", "PATROL"], ["ELITE", "SCOUT_RECON", "AMPHIBIOUS"]] call DSC_core_fnc_getGroupsByTag;
private _eliteInfantrySquadGroups = [_classifiedGroups, ["FOOT", "INFANTRY_SQUAD", "PATROL", "ELITE"], ["SCOUT_RECON", "AMPHIBIOUS"]] call DSC_core_fnc_getGroupsByTag;
private _eliteInfantryFireteamGroups = [_classifiedGroups, ["FOOT", "FIRETEAM", "PATROL", "ELITE"], ["SCOUT_RECON", "AMPHIBIOUS"]] call DSC_core_fnc_getGroupsByTag;
private _atInfantryGroups = [_classifiedGroups, ["FOOT", "AT_TEAM"], ["AMPHIBIOUS"]] call DSC_core_fnc_getGroupsByTag;
private _aaInfantryGroups = [_classifiedGroups, ["FOOT", "AA_TEAM"], ["AMPHIBIOUS"]] call DSC_core_fnc_getGroupsByTag;

// ============================================================================
// Setup Area Defense
// ============================================================================
private _missionGroups = [];
private _totalUnits = [];
private _totalVehicles = [];
private _tagsPerGroup = [];

// Density settings
private _patrolCount = switch (_density) do {
    case "light": { [3, 5] };
    case "medium": { [4, 6] };
    case "heavy": { [6, 9] };
    default { [3, 5] };
};

// ==================================
// Guards (Static Weapons on Towers)
// ==================================
private _guardUnits = [];
if (_locationType == "military") then {
    private _guardResult = [_locationPos, "military", _opForFaction, _opForSide] call DSC_core_fnc_setupGuards;
    _missionGroups append (_guardResult get "groups");
    _guardUnits = _guardResult get "units";
    _totalUnits append _guardUnits;
    _totalVehicles append (_guardResult get "vehicles");
};

// ==================================
// Garrison (Infantry in Structures)
// ==================================
private _garrisonGroups = _basicInfantrySquadGroups + _basicInfantryFireteamGroups + _eliteInfantrySquadGroups + _eliteInfantryFireteamGroups;
private _garrisonUnits = [];
if (_garrisonGroups isNotEqualTo []) then {
    private _garrisonConfig = createHashMapFromArray [
        ["density", _density]
    ];
    private _garrisonResult = [_locationPos, _garrisonGroups, _opForSide, _garrisonConfig] call DSC_core_fnc_setupGarrison;
    _missionGroups append (_garrisonResult get "groups");
    _garrisonUnits = _garrisonResult get "units";
    _totalUnits append _garrisonUnits;
    _tagsPerGroup append (_garrisonResult get "tags");
};

// ============================================================================
// Spawn HVT (with bodyguards from garrison)
// ============================================================================
private _hvtUnit = objNull;
private _hvtBuilding = objNull;

// Get officer unit class from faction
private _hvtClass = "O_officer_F"; // Default fallback
private _filterStr = format ["getNumber (_x >> 'scope') >= 2 && getText (_x >> 'faction') == '%1' && getNumber (_x >> 'isMan') == 1", _opForFaction];
private _factionUnits = _filterStr configClasses (configFile >> "CfgVehicles");

{
    private _unitName = toLower (configName _x);
    if ("officer" in _unitName || "commander" in _unitName || "leader" in _unitName) exitWith {
        _hvtClass = configName _x;
    };
} forEach _factionUnits;

// Try to place HVT with existing garrison unit (bodyguard)
private _placedWithBodyguard = false;

if (_garrisonUnits isNotEqualTo []) then {
    // Find a garrison unit in a building with multiple positions
    private _candidateUnits = _garrisonUnits select {
        private _building = nearestBuilding _x;
        !isNull _building && { count (_building buildingPos -1) >= 3 }
    };
    
    if (_candidateUnits isNotEqualTo []) then {
        private _bodyguard = selectRandom _candidateUnits;
        _hvtBuilding = nearestBuilding _bodyguard;
        private _buildingPositions = _hvtBuilding buildingPos -1;
        
        // Find an unoccupied position in the building
        private _occupiedPositions = _garrisonUnits apply { getPos _x };
        private _freePositions = _buildingPositions select {
            private _pos = _x;
            (_occupiedPositions findIf { _x distance _pos < 1 }) == -1
        };
        
        if (_freePositions isNotEqualTo []) then {
            private _hvtPos = selectRandom _freePositions;
            
            // Join the bodyguard's group instead of creating new one
            private _hvtGroup = group _bodyguard;
            _hvtUnit = _hvtGroup createUnit [_hvtClass, _hvtPos, [], 0, "NONE"];
            _hvtUnit setPos _hvtPos;
            _hvtUnit setUnitPos "UP";
            _hvtUnit disableAI "PATH";
            
            _placedWithBodyguard = true;
            diag_log format ["DSC: HVT placed with bodyguards in %1", _hvtBuilding];
        } else {
            diag_log format ["DSC: No free positions in bodyguard building %1 (%2 positions, %3 occupied)", _hvtBuilding, count _buildingPositions, count _occupiedPositions];
        };
    } else {
        diag_log format ["DSC: No candidate garrison units in buildings with 3+ positions (checked %1 units)", count _garrisonUnits];
    };
};

// Fallback - place HVT in a building near the location center (not far away)
if (!_placedWithBodyguard) then {
    private _structureTypes = call DSC_core_fnc_getStructureTypes;
    private _validTypes = (_structureTypes get "main") + (_structureTypes get "side");
    private _exclusions = _structureTypes get "exclusions";
    
    private _buildings = [_locationPos, ["BUILDING", "HOUSE", "HOSPITAL", "VIEW-TOWER", "MILITARY", "VILLAGE", "CITY"], 300] call DSC_core_fnc_getMapStructures;
    _buildings = _buildings select {
        private _struct = _x;
        private _hasPositions = (_struct buildingPos -1) isNotEqualTo [];
        private _isExcluded = false;
        { if (_struct isKindOf _x) exitWith { _isExcluded = true } } forEach _exclusions;
        private _isValid = (_validTypes findIf { _struct isKindOf _x }) > -1;
        _hasPositions && !_isExcluded && _isValid
    };
    
    private _hvtGroup = createGroup [_opForSide, true];
    
    if (_buildings isNotEqualTo []) then {
        _hvtBuilding = selectRandom _buildings;
        private _buildingPositions = _hvtBuilding buildingPos -1;
        private _hvtPos = selectRandom _buildingPositions;
        
        _hvtUnit = _hvtGroup createUnit [_hvtClass, _hvtPos, [], 0, "NONE"];
        _hvtUnit setPos _hvtPos;
        _hvtUnit setUnitPos "UP";
        
        diag_log format ["DSC: HVT placed alone in %1 (no garrison available)", _hvtBuilding];
    } else {
        _hvtUnit = _hvtGroup createUnit [_hvtClass, _locationPos, [], 5, "NONE"];
        diag_log "DSC: HVT spawned at location center (no buildings found)";
    };
    
    // Setup standalone HVT group behavior
    _hvtGroup setBehaviour "SAFE";
    _hvtGroup setCombatMode "GREEN";
    _hvtGroup enableAttack false;
    [_hvtGroup] call DSC_core_fnc_addCombatActivation;
    
    _missionGroups pushBack _hvtGroup;
};

// Mark as HVT
_hvtUnit setVariable ["DSC_isHVT", true, true];
_hvtUnit setVariable ["DSC_hvtName", format ["Target %1", floor (random 1000)], true];
_totalUnits pushBack _hvtUnit;

// ==================================
// Patrols (Mobile Units)
// ==================================
private _patrolGroupsSpawned = [];
private _patrolGroups = _basicInfantrySquadGroups + _basicInfantryFireteamGroups + _eliteInfantrySquadGroups + _eliteInfantryFireteamGroups;
if (_patrolGroups isNotEqualTo []) then {
    private _specialGroups = _atInfantryGroups + _aaInfantryGroups;
    private _patrolConfig = createHashMapFromArray [
        ["specialGroups", _specialGroups],
        ["specialChance", 0.15],
        ["patrolCount", _patrolCount]
    ];
    private _patrolResult = [_locationPos, _patrolGroups, _opForSide, _patrolConfig] call DSC_core_fnc_setupPatrols;
    _patrolGroupsSpawned = _patrolResult get "groups";
    _missionGroups append _patrolGroupsSpawned;
    _totalUnits append (_patrolResult get "units");
    _tagsPerGroup append (_patrolResult get "tags");
};

// ============================================================================
// Create Mission Marker
// ============================================================================
private _markerPos = if (!isNull _hvtBuilding) then { getPos _hvtBuilding } else { _locationPos };
private _targetMarker = createMarker ["target_location_marker", _markerPos];
_targetMarker setMarkerTypeLocal "hd_objective";
_targetMarker setMarkerColorLocal "ColorRed";
_targetMarker setMarkerText format ["HVT: %1", _locationName];

// ============================================================================
// Build Mission Data Structure
// ============================================================================
private _mission = createHashMapFromArray [
    ["type", "KILL_CAPTURE"],
    ["location", _locationPos],
    ["locationName", _locationName],
    ["locationId", _locationId],
    ["locationType", _locationType],
    ["entity", _hvtUnit],
    ["entityBuilding", _hvtBuilding],
    ["groups", _missionGroups],
    ["patrolGroups", _patrolGroupsSpawned],
    ["defenderUnits", _guardUnits + _garrisonUnits],
    ["units", _totalUnits],
    ["vehicles", _totalVehicles],
    ["tags", _tagsPerGroup],
    ["density", _density],
    ["marker", _targetMarker],
    ["startTime", serverTime],
    ["status", "ACTIVE"]
];

// Store mission globally
missionNamespace setVariable ["DSC_currentMission", _mission, true];

diag_log format ["DSC: Kill/Capture mission generated - %1 groups, %2 units at %3", 
    count _missionGroups, count _totalUnits, _locationName];

_mission
