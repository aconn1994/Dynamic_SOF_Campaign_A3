#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_scanLocations
 * Description:
 *     Unified location scanner. Scans all enterable structures on the map,
 *     clusters by proximity, extracts features, applies tags, and merges
 *     with Arma named locations for context.
 *
 *     Returns an array of rich location objects that downstream systems
 *     (garrison, guards, HVT, mission selection) consume directly.
 *
 * Arguments:
 *     0: _config <HASHMAP> - Optional configuration overrides
 *        - "clusterRadius": Distance for grouping structures (default: 150)
 *        - "minStructures": Minimum enterable structures to form a site (default: 1)
 *        - "debug": Show debug markers on map (default: false)
 *
 * Return Value:
 *     <ARRAY> - Array of location hashmaps
 *
 * Example:
 *     private _locations = [createHashMapFromArray [["debug", true]]] call DSC_core_fnc_scanLocations;
 */

params [
    ["_config", createHashMap, [createHashMap]]
];

private _clusterRadius = _config getOrDefault ["clusterRadius", 150];
private _minStructures = _config getOrDefault ["minStructures", 1];
private _debug = _config getOrDefault ["debug", false];

diag_log "DSC: ========== Location Scan Started ==========";

// ============================================================================
// STAGE 1: Raw World Sampling - Gather all enterable structures
// ============================================================================
private _structureTypes = call DSC_core_fnc_getStructureTypes;
private _mainTypes = _structureTypes get "main";
private _sideTypes = _structureTypes get "side";
private _mainMilTypes = _structureTypes get "mainMilitary";
private _sideMilTypes = _structureTypes get "sideMilitary";
private _exclusions = _structureTypes get "exclusions";

private _centerPosition = [worldSize / 2, worldSize / 2, 0];
private _allStructures = [_centerPosition, ["House", "Building", "Strategic"], worldSize] call DSC_core_fnc_getMapStructures;

diag_log format ["DSC: Stage 1 - Found %1 raw structures on map", count _allStructures];

// Filter to enterable only, apply exclusions, classify
// Store classification per structure using parallel arrays (indexed together)
private _enterableStructures = [];
private _structureClasses = [];  // "main" | "side" | "unclassified" (parallel to _enterableStructures)
private _structureMilitary = []; // true | false (parallel to _enterableStructures)

{
    private _struct = _x;
    if ((_struct buildingPos -1) isEqualTo []) then { continue };

    // Check exclusions
    private _isExcluded = false;
    { if (_struct isKindOf _x) exitWith { _isExcluded = true } } forEach _exclusions;
    if (_isExcluded) then { continue };

    // Classify
    private _isMain = false;
    private _isSide = false;
    private _isMilitary = false;

    { if (_struct isKindOf _x) exitWith { _isMain = true } } forEach _mainTypes;
    if (!_isMain) then {
        { if (_struct isKindOf _x) exitWith { _isSide = true } } forEach _sideTypes;
    };

    // Check if military type
    { if (_struct isKindOf _x) exitWith { _isMilitary = true } } forEach _mainMilTypes;
    if (!_isMilitary) then {
        { if (_struct isKindOf _x) exitWith { _isMilitary = true } } forEach _sideMilTypes;
    };

    private _class = if (_isMain) then { "main" } else { ["unclassified", "side"] select _isSide };

    _enterableStructures pushBack _struct;
    _structureClasses pushBack _class;
    _structureMilitary pushBack _isMilitary;

} forEach _allStructures;

diag_log format ["DSC: Stage 1 - %1 enterable structures after filtering", count _enterableStructures];

// Filter out structures inside player base
private _playerBaseMarker = "player_base";
if (getMarkerType _playerBaseMarker != "") then {
    private _countBefore = count _enterableStructures;
    private _keepIndices = [];
    {
        if (!(getPos _x inArea _playerBaseMarker)) then {
            _keepIndices pushBack _forEachIndex;
        };
    } forEach _enterableStructures;
    _enterableStructures = _keepIndices apply { _enterableStructures select _x };
    _structureClasses = _keepIndices apply { _structureClasses select _x };
    _structureMilitary = _keepIndices apply { _structureMilitary select _x };
    diag_log format ["DSC: Excluded %1 structures inside player_base", _countBefore - count _enterableStructures];
};

// Build a lookup: object -> index in _enterableStructures (for fast classification retrieval)
private _structIndexMap = createHashMap;
{
    _structIndexMap set [str _x, _forEachIndex];
} forEach _enterableStructures;

// ============================================================================
// STAGE 2: Spatial Clustering (using nearObjects for performance)
// ============================================================================
private _processedSet = createHashMap; // str _object -> true
private _clusters = [];

{
    private _struct = _x;
    private _strKey = str _struct;
    if (_strKey in _processedSet) then { continue };

    // Flood-fill using nearObjects for spatial lookup (much faster than O(n) scan)
    private _clusterStructures = [];
    private _queue = [_struct];
    _processedSet set [_strKey, true];

    while { _queue isNotEqualTo [] } do {
        private _current = _queue deleteAt 0;
        _clusterStructures pushBack _current;

        // Find nearby enterable structures using engine spatial query
        private _nearby = nearestObjects [getPos _current, ["House", "Building", "Strategic"], _clusterRadius];
        {
            private _nearKey = str _x;
            if !(_nearKey in _processedSet) then {
                // Only include if it's in our filtered set
                if (_nearKey in _structIndexMap) then {
                    _processedSet set [_nearKey, true];
                    _queue pushBack _x;
                };
            };
        } forEach _nearby;
    };

    // Calculate cluster center
    private _sumX = 0;
    private _sumY = 0;
    {
        private _pos = getPos _x;
        _sumX = _sumX + (_pos select 0);
        _sumY = _sumY + (_pos select 1);
    } forEach _clusterStructures;

    private _clusterCenter = [
        _sumX / count _clusterStructures,
        _sumY / count _clusterStructures,
        0
    ];

    // Calculate radius (max distance from center to any structure)
    private _maxDist = 0;
    {
        private _dist = _x distance2D _clusterCenter;
        if (_dist > _maxDist) then { _maxDist = _dist };
    } forEach _clusterStructures;

    _clusters pushBack [_clusterCenter, _maxDist, _clusterStructures];

} forEach _enterableStructures;

diag_log format ["DSC: Stage 2 - Formed %1 clusters", count _clusters];

// ============================================================================
// STAGE 3: Feature Extraction + Tagging
// ============================================================================
private _locations = [];
private _locationIndex = 0;

// Pre-fetch Arma named locations for matching
private _armaLocations = nearestLocations [_centerPosition, ["NameCityCapital", "NameCity", "NameVillage", "NameLocal"], worldSize];

{
    _x params ["_clusterCenter", "_clusterRadiusActual", "_clusterStructures"];

    // Skip clusters below minimum
    if (count _clusterStructures < _minStructures) then { continue };

    // Separate main/side using the parallel arrays
    private _mainStructures = [];
    private _sideStructures = [];
    private _militaryStructures = [];

    {
        private _idx = _structIndexMap getOrDefault [str _x, -1];
        if (_idx >= 0) then {
            private _class = _structureClasses select _idx;
            private _isMil = _structureMilitary select _idx;
            if (_class == "main") then { _mainStructures pushBack _x };
            if (_class == "side") then { _sideStructures pushBack _x };
            if (_isMil) then { _militaryStructures pushBack _x };
        };
    } forEach _clusterStructures;

    // Find nearest Arma named location
    private _name = "";
    private _namedLocType = "";
    private _bestDist = 999999;
    {
        private _locPos = locationPosition _x;
        private _dist = _clusterCenter distance2D _locPos;
        if (_dist < _bestDist && _dist < 500) then {
            _bestDist = _dist;
            _name = text _x;
            _namedLocType = type _x;
        };
    } forEach _armaLocations;

    if (_name == "") then {
        _name = mapGridPosition _clusterCenter;
    };

    // --- Tagging ---
    private _tags = [];

    // Density tags
    private _buildingCount = count _clusterStructures;
    if (_buildingCount >= 30) then {
        _tags pushBack "high_density";
    } else {
        if (_buildingCount >= 10) then {
            _tags pushBack "medium_density";
        } else {
            _tags pushBack "low_density";
        };
    };

    // Size tags
    if (_buildingCount >= 50) then { _tags pushBack "city" };
    if (_buildingCount >= 15 && _buildingCount < 50) then { _tags pushBack "town" };
    if (_buildingCount >= 5 && _buildingCount < 15) then { _tags pushBack "settlement" };
    if (_buildingCount < 5) then { _tags pushBack "isolated" };

    // Military presence
    private _milCount = count _militaryStructures;
    if (_milCount > 0) then {
        _tags pushBack "military";
        if (_milCount >= 8) then { _tags pushBack "base" };
        if (_milCount >= 4 && _milCount < 8) then { _tags pushBack "outpost" };
        if (_milCount < 4) then { _tags pushBack "camp" };
    };

    // Civilian character
    if (_milCount == 0) then { _tags pushBack "civilian" };
    if (_milCount > 0 && _buildingCount > _milCount * 2) then { _tags pushBack "mixed" };

    // Named location type context
    if (_namedLocType == "NameCityCapital" || _namedLocType == "NameCity") then {
        _tags pushBackUnique "urban";
    };
    if (_namedLocType == "NameVillage") then {
        _tags pushBackUnique "rural";
    };

    // Build location object
    private _location = createHashMapFromArray [
        ["id", format ["loc_%1", _locationIndex]],
        ["position", _clusterCenter],
        ["name", _name],
        ["radius", _clusterRadiusActual max 50],
        ["structures", _clusterStructures],
        ["mainStructures", _mainStructures],
        ["sideStructures", _sideStructures],
        ["buildingCount", _buildingCount],
        ["mainCount", count _mainStructures],
        ["sideCount", count _sideStructures],
        ["militaryCount", _milCount],
        ["tags", _tags],
        ["source", "cluster"]
    ];

    _locations pushBack _location;
    _locationIndex = _locationIndex + 1;

} forEach _clusters;

// Second pass: tag isolation (distance to nearest other cluster)
{
    private _loc = _x;
    private _pos = _loc get "position";
    private _nearestDist = 999999;

    {
        if (_x isNotEqualTo _loc) then {
            private _dist = _pos distance2D (_x get "position");
            if (_dist < _nearestDist) then { _nearestDist = _dist };
        };
    } forEach _locations;

    if (_nearestDist > 1000) then {
        (_loc get "tags") pushBackUnique "remote";
    };
} forEach _locations;

diag_log format ["DSC: Stage 3 - Tagged %1 locations", count _locations];

// ============================================================================
// STAGE 4: Summary Logging
// ============================================================================
private _tagCounts = createHashMap;
{
    private _tags = _x get "tags";
    {
        private _count = _tagCounts getOrDefault [_x, 0];
        _tagCounts set [_x, _count + 1];
    } forEach _tags;
} forEach _locations;

diag_log format ["DSC: Location Scan Complete - %1 locations found", count _locations];
diag_log format ["DSC: Tag distribution: %1", _tagCounts toArray true];

// ============================================================================
// DEBUG: Marker Visualization
// ============================================================================
if (_debug) then {
    diag_log "DSC: Creating debug markers for locations...";

    {
        private _loc = _x;
        private _pos = _loc get "position";
        private _locName = _loc get "name";
        private _tags = _loc get "tags";
        private _id = _loc get "id";
        private _buildingCount = _loc get "buildingCount";

        // Determine marker color from tags
        private _color = "ColorGrey";
        if ("military" in _tags && "base" in _tags) then { _color = "ColorRed" };
        if ("military" in _tags && "outpost" in _tags) then { _color = "ColorOrange" };
        if ("military" in _tags && "camp" in _tags) then { _color = "ColorYellow" };
        if ("urban" in _tags) then { _color = "ColorBlue" };
        if ("civilian" in _tags && "settlement" in _tags) then { _color = "ColorGreen" };
        if ("civilian" in _tags && "isolated" in _tags) then { _color = "ColorWhite" };
        if ("remote" in _tags) then { _color = "ColorBrown" };

        // Determine marker type from size
        private _markerType = "mil_dot";
        if ("city" in _tags || "town" in _tags) then { _markerType = "mil_objective" };
        if ("settlement" in _tags) then { _markerType = "mil_triangle" };
        if ("base" in _tags) then { _markerType = "mil_objective" };
        if ("outpost" in _tags) then { _markerType = "mil_triangle" };

        // Point marker
        private _markerName = format ["dsc_loc_%1", _id];
        private _marker = createMarkerLocal [_markerName, _pos];
        _marker setMarkerTypeLocal _markerType;
        _marker setMarkerColorLocal _color;
        _marker setMarkerTextLocal format ["%1 [%2] (%3)", _locName, _buildingCount, _tags joinString ","];
        _marker setMarkerSizeLocal [0.7, 0.7];

        // Radius area marker
        private _areaName = format ["dsc_loc_%1_area", _id];
        private _areaMarker = createMarkerLocal [_areaName, _pos];
        _areaMarker setMarkerShapeLocal "ELLIPSE";
        _areaMarker setMarkerSizeLocal [_loc get "radius", _loc get "radius"];
        _areaMarker setMarkerColorLocal _color;
        _areaMarker setMarkerAlphaLocal 0.15;

    } forEach _locations;

    diag_log format ["DSC: Created %1 debug markers", count _locations];
};

diag_log "DSC: ========== Location Scan Complete ==========";

_locations
