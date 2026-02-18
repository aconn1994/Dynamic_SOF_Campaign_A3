#include "script_component.hpp"
/*
 * Creates a list of civilian locations on the map.
 * 
 * Uses Arma 3's built-in location data to find named civilian areas
 * and categorizes them into cities, villages, and special locations.
 * 
 * Arguments:
 *   None
 * 
 * Returns:
 *   Hashmap with:
 *     - "cities": Array of position arrays (NameCityCapital + NameCity)
 *     - "villages": Array of position arrays (NameVillage)
 *     - "special": Array of position arrays (filtered NameLocal - non-military POIs)
 *     - "locations": Raw location data for debugging [pos, type, size, name]
 * 
 * Example:
 *   private _locations = call DSC_core_fnc_getCivilianLocations;
 *   private _villages = _locations get "villages";
 */

// Get map center and size for search
private _centerPosition = [worldSize / 2, worldSize / 2, 0];
private _searchRadius = worldSize;

// Location types to search for
private _locationTypes = [
    "NameCityCapital",  // Major cities
    "NameCity",         // Cities
    "NameVillage",      // Villages
    "NameLocal"         // Local areas/landmarks - filtered for special locations
];

// Keywords to filter out from NameLocal (military/infrastructure handled elsewhere)
private _excludeKeywords = ["military", "airbase", "airfield"];

// Keywords that identify special locations (industrial/POIs)
private _specialKeywords = ["power plant", "factory", "quarry", "mine", "dump", 
    "storage", "Terminal", "castle", "Stadium", "Pier", "Dam"];

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
                // Check if this is a special location
                private _isSpecial = false;
                {
                    if ((toLower _x) in _nameLower) exitWith { _isSpecial = true };
                } forEach _specialKeywords;
                
                if (_isSpecial) then {
                    _special pushBack _pos;
                    diag_log format ["DSC: Special: %1 at %2", _name, _pos];
                };
                // Non-special NameLocal entries are dropped (small landmarks, capes, etc.)
            };
        };
    };
} forEach _allLocations;

diag_log format ["DSC: fnc_getCivilianLocations - Cities: %1, Villages: %2, Special: %3", 
    count _cities, count _villages, count _special];

// Build result
private _result = createHashMap;
_result set ["cities", _cities];
_result set ["villages", _villages];
_result set ["special", _special];
_result set ["locations", _rawData];  // Raw data for debugging

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
    
    diag_log format ["DSC: fnc_getCivilianLocations - Created %1 debug markers", 
        (count _cities) + (count _villages) + (count _special)];
#endif

_result
