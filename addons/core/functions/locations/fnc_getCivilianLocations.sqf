#include "script_component.hpp"
/*
 * Creates a list of civilian locations on the map.
 * 
 * Uses Arma 3's built-in location data to find named civilian areas
 * and categorizes them into cities, villages, special locations, and more.
 * 
 * Arguments:
 *   None
 * 
 * Returns:
 *   Hashmap with:
 *     - "cities": Array of position arrays (NameCityCapital + NameCity)
 *     - "villages": Array of position arrays (NameVillage)
 *     - "special": Array of position arrays (industrial POIs - factories, quarries, etc.)
 *     - "compounds": Array of position arrays (small building clusters - HVT hideouts)
 *     - "maritime": Array of position arrays (piers, docks - covert insertions)
 *     - "landmarks": Array of position arrays (capes, points - observation/cache sites)
 *     - "unmarked": Array of position arrays (uncategorized - for debugging)
 *     - "locations": Raw location data for debugging [pos, type, size, name]
 * 
 * Example:
 *   private _locations = call DSC_core_fnc_getCivilianLocations;
 *   private _compounds = _locations get "compounds";
 */

// Get map center and size for search
private _centerPosition = [worldSize / 2, worldSize / 2, 0];
private _searchRadius = worldSize;

// Location types to search for
private _locationTypes = [
    "NameCityCapital",  // Major cities
    "NameCity",         // Cities
    "NameVillage",      // Villages
    "NameLocal"         // Local areas/landmarks - filtered and scanned
];

// Keywords to filter out from NameLocal (military/infrastructure handled elsewhere)
private _excludeKeywords = ["military", "airbase", "airfield"];

// Keywords that identify special locations (industrial/POIs)
private _specialKeywords = ["power plant", "factory", "quarry", "mine", "dump", 
    "storage", "terminal", "castle", "stadium", "dam"];

// Keywords that identify landmarks (observation/cache sites)
private _landmarkKeywords = ["cape", "point", "rock", "hill"];

// Structure classes for pier/dock detection
private _maritimeStructures = [
    "Land_Pier_F", "Land_Pier_small_F", "Land_Pier_Box_F",
    "Land_Dock_F", "Land_Dock_Small_F", "Land_Dock_Big_F",
    "Land_NavigLight", "Land_LampHarbour_F", "Land_nav_pier_m_F",
    "Land_Boat_01_abandoned_F", "Land_Boat_02_abandoned_F"
];

// Structure base classes to exclude from compound building count
// These have building positions but aren't actual structures for garrison purposes
private _excludeStructureTypes = [
    "Piers_base_F",
    "Land_Pier_F",
    "Land_NavigLight",
    "Bridge_base_F"
];

// Find all named locations on map
private _allLocations = nearestLocations [_centerPosition, _locationTypes, _searchRadius];

diag_log format ["DSC: fnc_getCivilianLocations - Found %1 named locations on map", count _allLocations];

// Filter out locations inside player base marker
private _playerBaseMarker = "player_base";
if (getMarkerType _playerBaseMarker != "") then {
    private _countBefore = count _allLocations;
    _allLocations = _allLocations select {
        !(locationPosition _x inArea _playerBaseMarker)
    };
    private _excluded = _countBefore - count _allLocations;
    if (_excluded > 0) then {
        diag_log format ["DSC: fnc_getCivilianLocations - Excluded %1 locations inside player_base marker", _excluded];
    };
};

// Categorize locations
private _cities = [];
private _villages = [];
private _special = [];
private _compounds = [];
private _maritime = [];
private _landmarks = [];
private _unmarked = [];
private _rawData = [];

{
    private _location = _x;
    private _pos = locationPosition _location;
    private _type = type _location;
    private _size = size _location;  // Returns [width, height]
    private _avgSize = ((_size select 0) + (_size select 1)) / 2;
    private _name = text _location;
    private _nameLower = toLower _name;
    
    // Store raw data for debugging
    _rawData pushBack [_pos, _type, _size, _name];
    
    // Categorize based on type
    switch (_type) do {
        case "NameCityCapital";
        case "NameCity": {
            _cities pushBack _pos;
            diag_log format ["DSC: City: %1 at %2", _name, _pos];
        };
        case "NameVillage": {
            // NameVillage is pre-tagged by BI, trust it as a village
            _villages pushBack _pos;
            diag_log format ["DSC: Village: %1 at %2", _name, _pos];
        };
        case "NameLocal": {
            // Check if this should be excluded (military locations)
            private _excluded = false;
            {
                if (_x in _nameLower) exitWith { _excluded = true };
            } forEach _excludeKeywords;
            
            if (_excluded) then {
                diag_log format ["DSC: Excluded (military): %1 at %2", _name, _pos];
            } else {
                // Check if this is a special location (industrial)
                private _isSpecial = false;
                {
                    if (_x in _nameLower) exitWith { _isSpecial = true };
                } forEach _specialKeywords;
                
                if (_isSpecial) then {
                    _special pushBack _pos;
                    diag_log format ["DSC: Special: %1 at %2", _name, _pos];
                } else {
                    // Check if this is a landmark by name
                    private _isLandmark = false;
                    {
                        if (_x in _nameLower) exitWith { _isLandmark = true };
                    } forEach _landmarkKeywords;
                    
                    if (_isLandmark) then {
                        _landmarks pushBack _pos;
                        diag_log format ["DSC: Landmark: %1 at %2", _name, _pos];
                    } else {
                        // Structure scan for remaining unmarked locations
                        // Check for maritime structures (piers, docks)
                        private _nearbyMaritime = [_pos, _maritimeStructures, 100] call DSC_core_fnc_getMapStructures;
                        
                        if (_nearbyMaritime isNotEqualTo []) then {
                            _maritime pushBack _pos;
                            diag_log format ["DSC: Maritime: %1 at %2 (%3 structures)", _name, _pos, count _nearbyMaritime];
                        } else {
                            // Check for buildings (potential compound)
                            private _nearbyBuildings = [_pos, ["BUILDING", "HOUSE", "VILLAGE", "CITY"], 300] call DSC_core_fnc_getMapStructures;
                            // Filter to only buildings with interiors (enterable) and exclude non-structure types
                            _nearbyBuildings = _nearbyBuildings select { 
                                private _obj = _x;
                                // Must have building positions
                                private _hasPositions = (_obj buildingPos -1) isNotEqualTo [];
                                // Must not be an excluded structure type
                                private _isExcluded = false;
                                {
                                    if (_obj isKindOf _x) exitWith { _isExcluded = true };
                                } forEach _excludeStructureTypes;
                                
                                _hasPositions && !_isExcluded
                            };
                            
                            private _buildingCount = count _nearbyBuildings;
                            if (_buildingCount == 0) then {
                                // No structures - truly unmarked/empty
                                _unmarked pushBack _pos;
                                diag_log format ["DSC: Unmarked (empty): %1 at %2", _name, _pos];
                            } else {
                                if (_buildingCount <= 7) then {
                                    // Small cluster - compound (HVT hideout potential)
                                    _compounds pushBack _pos;
                                    diag_log format ["DSC: Compound: %1 at %2 (%3 buildings)", _name, _pos, _buildingCount];
                                } else {
                                    // Larger cluster - treat as village-sized settlement
                                    _villages pushBack _pos;
                                    diag_log format ["DSC: Village (detected): %1 at %2 (%3 buildings)", _name, _pos, _buildingCount];
                                };
                            };
                        };
                    };
                };
            };
        };
    };
} forEach _allLocations;

diag_log format ["DSC: fnc_getCivilianLocations - Cities: %1, Villages: %2, Special: %3, Compounds: %4, Maritime: %5, Landmarks: %6, Unmarked: %7", 
    count _cities, count _villages, count _special, count _compounds, count _maritime, count _landmarks, count _unmarked];

// Build result
private _result = createHashMap;
_result set ["cities", _cities];
_result set ["villages", _villages];
_result set ["special", _special];
_result set ["compounds", _compounds];
_result set ["maritime", _maritime];
_result set ["landmarks", _landmarks];
_result set ["unmarked", _unmarked];
_result set ["locations", _rawData];

// ============================================================================
// DEBUG MARKERS
// ============================================================================
#ifdef DEBUG_MODE_FULL
    // Clear any existing debug markers
    {
        if ("DSC_civloc_" in _x) then { deleteMarker _x };
    } forEach allMapMarkers;
    
    // City markers (orange)
    {
        private _markerName = format ["DSC_civloc_city_%1", _forEachIndex];
        private _marker = createMarker [_markerName, _x];
        _marker setMarkerShapeLocal "ICON";
        _marker setMarkerTypeLocal "mil_dot";
        _marker setMarkerColorLocal "ColorOrange";
        _marker setMarkerSizeLocal [0.8, 0.8];
        _marker setMarkerText "City";
    } forEach _cities;
    
    // Village markers (yellow)
    {
        private _markerName = format ["DSC_civloc_village_%1", _forEachIndex];
        private _marker = createMarker [_markerName, _x];
        _marker setMarkerShapeLocal "ICON";
        _marker setMarkerTypeLocal "mil_dot";
        _marker setMarkerColorLocal "ColorYellow";
        _marker setMarkerSizeLocal [0.6, 0.6];
        _marker setMarkerText "Village";
    } forEach _villages;
    
    // Special location markers (green)
    {
        private _markerName = format ["DSC_civloc_special_%1", _forEachIndex];
        private _marker = createMarker [_markerName, _x];
        _marker setMarkerShapeLocal "ICON";
        _marker setMarkerTypeLocal "mil_circle";
        _marker setMarkerColorLocal "ColorGreen";
        _marker setMarkerSizeLocal [0.6, 0.6];
        _marker setMarkerText "Special";
    } forEach _special;
    
    // Compound markers (brown/khaki)
    {
        private _markerName = format ["DSC_civloc_compound_%1", _forEachIndex];
        private _marker = createMarker [_markerName, _x];
        _marker setMarkerShapeLocal "ICON";
        _marker setMarkerTypeLocal "mil_triangle";
        _marker setMarkerColorLocal "ColorKhaki";
        _marker setMarkerSizeLocal [0.6, 0.6];
        _marker setMarkerText "Compound";
    } forEach _compounds;
    
    // Maritime markers (blue)
    {
        private _markerName = format ["DSC_civloc_maritime_%1", _forEachIndex];
        private _marker = createMarker [_markerName, _x];
        _marker setMarkerShapeLocal "ICON";
        _marker setMarkerTypeLocal "mil_box";
        _marker setMarkerColorLocal "ColorBlue";
        _marker setMarkerSizeLocal [0.6, 0.6];
        _marker setMarkerText "Maritime";
    } forEach _maritime;
    
    // Landmark markers (white)
    {
        private _markerName = format ["DSC_civloc_landmark_%1", _forEachIndex];
        private _marker = createMarker [_markerName, _x];
        _marker setMarkerShapeLocal "ICON";
        _marker setMarkerTypeLocal "mil_dot";
        _marker setMarkerColorLocal "ColorWhite";
        _marker setMarkerSizeLocal [0.5, 0.5];
        _marker setMarkerText "Landmark";
    } forEach _landmarks;
    
    // Unmarked location markers (black) - for debugging uncategorized NameLocal
    {
        private _markerName = format ["DSC_civloc_unmarked_%1", _forEachIndex];
        private _marker = createMarker [_markerName, _x];
        _marker setMarkerShapeLocal "ICON";
        _marker setMarkerTypeLocal "mil_circle";
        _marker setMarkerColorLocal "ColorBlack";
        _marker setMarkerSizeLocal [0.5, 0.5];
        _marker setMarkerText "Unmarked";
    } forEach _unmarked;
    
    diag_log format ["DSC: fnc_getCivilianLocations - Created %1 debug markers", 
        (count _cities) + (count _villages) + (count _special) + (count _compounds) + (count _maritime) + (count _landmarks) + (count _unmarked)];
#endif

_result
