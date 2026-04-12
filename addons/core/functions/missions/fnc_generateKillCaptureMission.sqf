#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_generateKillCaptureMission
 * Description:
 *     Generates a kill/capture mission by placing an HVT at a populated AO.
 *     Consumes a location object and populated AO data.
 *     Places HVT with garrison bodyguards when possible, creates mission marker.
 *
 * Arguments:
 *     0: _location <HASHMAP> - Location object from fnc_scanLocations
 *     1: _ao <HASHMAP> - Populated AO data from fnc_populateAO
 *     2: _config <HASHMAP> - Optional configuration
 *        - "faction": OpFor faction classname (default: from missionNamespace)
 *        - "side": OpFor side (default: east)
 *
 * Return Value:
 *     <HASHMAP> - Mission data:
 *        "type"            - "KILL_CAPTURE"
 *        "location"        - Position array
 *        "locationName"    - String name
 *        "locationTags"    - Tags from location object
 *        "entity"          - The HVT unit
 *        "entityBuilding"  - Building the HVT is in (objNull if none)
 *        "groups"          - All groups (AO + HVT)
 *        "patrolGroups"    - Patrol groups (for QRF)
 *        "defenderUnits"   - Guard + garrison units (for combat triggers)
 *        "units"           - All units (AO + HVT)
 *        "vehicles"        - All vehicles
 *        "marker"          - Mission marker name
 *        "startTime"       - Server time at creation
 *        "status"          - "ACTIVE"
 *
 * Example:
 *     private _mission = [_location, _ao] call DSC_core_fnc_generateKillCaptureMission;
 */

params [
    ["_location", createHashMap, [createHashMap]],
    ["_ao", createHashMap, [createHashMap]],
    ["_config", createHashMap, [createHashMap]]
];

private _opForFaction = _config getOrDefault ["faction", missionNamespace getVariable ["opForFaction", "OPF_F"]];
private _opForSide = _config getOrDefault ["side", east];

private _locationPos = _location get "position";
private _locationName = _location get "name";
private _locationTags = _location get "tags";

private _aoGroups = _ao get "groups";
private _aoUnits = _ao get "units";
private _aoVehicles = _ao get "vehicles";
private _defenderUnits = _ao get "defenderUnits";
private _patrolGroups = _ao get "patrolGroups";
private _garrisonUnits = _ao get "garrisonUnits";

// ============================================================================
// Place HVT
// ============================================================================
private _hvtUnit = objNull;
private _hvtBuilding = objNull;

// Get officer class from faction
private _hvtClass = "O_officer_F";
private _filterStr = format ["getNumber (_x >> 'scope') >= 2 && getText (_x >> 'faction') == '%1' && getNumber (_x >> 'isMan') == 1", _opForFaction];
private _factionUnits = _filterStr configClasses (configFile >> "CfgVehicles");

{
    private _unitName = toLower (configName _x);
    if ("officer" in _unitName || "commander" in _unitName || "leader" in _unitName) exitWith {
        _hvtClass = configName _x;
    };
} forEach _factionUnits;

// Try placing HVT with garrison bodyguards
private _placedWithBodyguard = false;

if (_garrisonUnits isNotEqualTo []) then {
    private _candidateUnits = _garrisonUnits select {
        private _building = nearestBuilding _x;
        !isNull _building && { count (_building buildingPos -1) >= 3 }
    };
    
    if (_candidateUnits isNotEqualTo []) then {
        private _bodyguard = selectRandom _candidateUnits;
        _hvtBuilding = nearestBuilding _bodyguard;
        private _buildingPositions = _hvtBuilding buildingPos -1;
        
        private _occupiedPositions = _garrisonUnits apply { getPos _x };
        private _freePositions = _buildingPositions select {
            private _pos = _x;
            (_occupiedPositions findIf { _x distance _pos < 1 }) == -1
        };
        
        if (_freePositions isNotEqualTo []) then {
            private _hvtPos = selectRandom _freePositions;
            private _hvtGroup = group _bodyguard;
            _hvtUnit = _hvtGroup createUnit [_hvtClass, _hvtPos, [], 0, "NONE"];
            _hvtUnit setPos _hvtPos;
            _hvtUnit setUnitPos "UP";
            _hvtUnit disableAI "PATH";
            _placedWithBodyguard = true;
            diag_log format ["DSC: HVT placed with bodyguards in %1", _hvtBuilding];
        };
    };
};

// Fallback: place in any location structure
if (!_placedWithBodyguard) then {
    private _allStructures = (_location get "mainStructures") + (_location get "sideStructures");
    _allStructures = _allStructures select { (_x buildingPos -1) isNotEqualTo [] };
    
    private _hvtGroup = createGroup [_opForSide, true];
    
    if (_allStructures isNotEqualTo []) then {
        _hvtBuilding = selectRandom _allStructures;
        private _buildingPositions = _hvtBuilding buildingPos -1;
        private _hvtPos = selectRandom _buildingPositions;
        _hvtUnit = _hvtGroup createUnit [_hvtClass, _hvtPos, [], 0, "NONE"];
        _hvtUnit setPos _hvtPos;
        _hvtUnit setUnitPos "UP";
        diag_log format ["DSC: HVT placed alone in %1", _hvtBuilding];
    } else {
        _hvtUnit = _hvtGroup createUnit [_hvtClass, _locationPos, [], 5, "NONE"];
        diag_log "DSC: HVT spawned at location center (no buildings)";
    };
    
    _hvtGroup setBehaviour "SAFE";
    _hvtGroup setCombatMode "GREEN";
    _hvtGroup enableAttack false;
    [_hvtGroup] call DSC_core_fnc_addCombatActivation;
    _aoGroups pushBack _hvtGroup;
};

_hvtUnit setVariable ["DSC_isHVT", true, true];
_hvtUnit setVariable ["DSC_hvtName", format ["Target %1", floor (random 1000)], true];
_aoUnits pushBack _hvtUnit;

// ============================================================================
// Mission Marker
// ============================================================================
private _markerPos = if (!isNull _hvtBuilding) then { getPos _hvtBuilding } else { _locationPos };
private _targetMarker = createMarker ["target_location_marker", _markerPos];
_targetMarker setMarkerTypeLocal "hd_objective";
_targetMarker setMarkerColorLocal "ColorRed";
_targetMarker setMarkerText format ["HVT: %1", _locationName];

// ============================================================================
// Build Mission Data
// ============================================================================
private _mission = createHashMapFromArray [
    ["type", "KILL_CAPTURE"],
    ["location", _locationPos],
    ["locationName", _locationName],
    ["locationTags", _locationTags],
    ["entity", _hvtUnit],
    ["entityBuilding", _hvtBuilding],
    ["groups", _aoGroups],
    ["patrolGroups", _patrolGroups],
    ["defenderUnits", _defenderUnits],
    ["units", _aoUnits],
    ["vehicles", _aoVehicles],
    ["marker", _targetMarker],
    ["startTime", serverTime],
    ["status", "ACTIVE"]
];

missionNamespace setVariable ["DSC_currentMission", _mission, true];

diag_log format ["DSC: Kill/Capture mission generated - HVT at %1 (%2 groups, %3 units)",
    _locationName, count _aoGroups, count _aoUnits];

_mission
