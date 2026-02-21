#include "script_component.hpp"
/*
 * Creates a list of military installation locations on the map.
 * 
 * Scans for military structures, clusters them by proximity, and categorizes
 * them into bases (large), outposts (medium), and camps (small).
 * 
 * Arguments:
 *   None
 * 
 * Returns:
 *   Hashmap with:
 *     - "bases": Array of position arrays (8+ structures)
 *     - "outposts": Array of position arrays (4-7 structures)
 *     - "camps": Array of position arrays (1-3 structures)
 * 
 * Example:
 *   private _locations = call DSC_core_fnc_getMilitaryLocations;
 *   private _bases = _locations get "bases";
 */

// ********** This will need to be map based eventually **********
private _militaryObjects = [
    // Altis Types
    "Cargo_HQ_base_F",
    "Cargo_Patrol_base_F",
    "Cargo_Tower_base_F",
    "Cargo_House_base_F",
    "Land_MilOffices_V1_F"
];

// List of config parent types to exclude
private _excludedTypes = ["Ruins", "Ruins_F", "_V2_"]; // _V2_ is for rusty structures, typically in abandoned areas

// Helper function that checks if an object inherits from any excluded type
private _isRuins = {
    params ["_obj", "_excludedTypes"];
    private _result = false;
    
    {
        if ((_obj isKindOf _x) || (_x in (typeOf _obj))) exitWith { _result = true };
    } forEach _excludedTypes;

    _result
};

// Cluster radius - structures within this distance are considered part of same location
private _clusterRadius = 400;

// Find all military structures on map
private _centerPosition = [worldSize / 2, worldSize / 2, 0];
private _militaryEntitiesList = [_centerPosition, _militaryObjects, worldSize] call DSC_core_fnc_getMapStructures;

// Filter out ruins
// _militaryEntitiesList = _militaryEntitiesList select {
//     !([_x, _excludedTypes] call _isRuins)
// };

// Filter out structures inside player base marker
private _playerBaseMarker = "player_base";
if (getMarkerType _playerBaseMarker != "") then {
    private _countBefore = count _militaryEntitiesList;
    _militaryEntitiesList = _militaryEntitiesList select {
        !(getPos _x inArea _playerBaseMarker)
    };
    private _excluded = _countBefore - count _militaryEntitiesList;
    if (_excluded > 0) then {
        diag_log format ["DSC: Excluded %1 structures inside player_base marker", _excluded];
    };
};

diag_log format ["DSC: Found %1 military structures on map", count _militaryEntitiesList];

// ============================================================================
// Cluster structures by proximity
// ============================================================================
private _processedObjects = [];
private _clusters = [];

{
    private _obj = _x;
    
    // Skip if already processed
    if (_obj in _processedObjects) then { continue };
    
    // Find all structures within cluster radius of this object
    private _clusterObjects = _militaryEntitiesList select {
        _x distance _obj <= _clusterRadius && !(_x in _processedObjects)
    };
    
    // Mark all as processed
    _processedObjects append _clusterObjects;
    
    // Calculate cluster center (average position)
    private _sumX = 0;
    private _sumY = 0;
    {
        private _pos = getPos _x;
        _sumX = _sumX + (_pos select 0);
        _sumY = _sumY + (_pos select 1);
    } forEach _clusterObjects;
    
    private _clusterCenter = [
        _sumX / (count _clusterObjects),
        _sumY / (count _clusterObjects),
        0
    ];
    
    _clusters pushBack [_clusterCenter, count _clusterObjects, _clusterObjects];
    
} forEach _militaryEntitiesList;

diag_log format ["DSC: Identified %1 military location clusters", count _clusters];

// ============================================================================
// Categorize clusters by size
// ============================================================================
private _bases = [];    // 8+ structures
private _outposts = []; // 4-7 structures
private _camps = [];    // 1-3 structures

{
    _x params ["_center", "_count", "_objects"];
    
    if (_count >= 8) then {
        _bases pushBack _center;
    } else {
        if (_count >= 4) then {
            _outposts pushBack _center;
        } else {
            _camps pushBack _center;
        };
    };
} forEach _clusters;

diag_log format ["DSC: Bases: %1, Outposts: %2, Camps: %3", count _bases, count _outposts, count _camps];

// ============================================================================
// Return result
// ============================================================================
private _result = createHashMap;
_result set ["bases", _bases];
_result set ["outposts", _outposts];
_result set ["camps", _camps];
_result set ["clusters", _clusters]; // Raw cluster data for debugging

// ============================================================================
// DEBUG MARKERS
// ============================================================================
#ifdef DEBUG_MODE_FULL
    // Clear any existing debug markers
    {
        if ("DSC_milloc_" in _x) then { deleteMarker _x };
    } forEach allMapMarkers;
    
    // Base markers (red)
    {
        private _markerName = format ["DSC_milloc_base_%1", _forEachIndex];
        private _marker = createMarker [_markerName, _x];
        _marker setMarkerShapeLocal "ICON";
        _marker setMarkerTypeLocal "mil_objective";
        _marker setMarkerColorLocal "ColorRed";
        _marker setMarkerSizeLocal [1, 1];
        _marker setMarkerText "Base";
    } forEach _bases;
    
    // Outpost markers (red, smaller)
    {
        private _markerName = format ["DSC_milloc_outpost_%1", _forEachIndex];
        private _marker = createMarker [_markerName, _x];
        _marker setMarkerShapeLocal "ICON";
        _marker setMarkerTypeLocal "mil_triangle";
        _marker setMarkerColorLocal "ColorRed";
        _marker setMarkerSizeLocal [0.8, 0.8];
        _marker setMarkerText "Outpost";
    } forEach _outposts;
    
    // Camp markers (red, smallest)
    {
        private _markerName = format ["DSC_milloc_camp_%1", _forEachIndex];
        private _marker = createMarker [_markerName, _x];
        _marker setMarkerShapeLocal "ICON";
        _marker setMarkerTypeLocal "mil_dot";
        _marker setMarkerColorLocal "ColorRed";
        _marker setMarkerSizeLocal [0.6, 0.6];
        _marker setMarkerText "Camp";
    } forEach _camps;
    
    diag_log format ["DSC: fnc_getMilitaryLocations - Created %1 debug markers", 
        (count _bases) + (count _outposts) + (count _camps)];
#endif

_result
