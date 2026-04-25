#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_scanLocations
 * Description:
 *     Anchor-based location scanner. Scans all enterable structures on the map,
 *     classifies them (main/side, military/civilian, functional category),
 *     assigns to named-location anchors, tags each location, and returns
 *     rich hashmap objects ready for downstream consumption.
 *
 *     Orphaned military clusters get synthetic anchors.
 *     Non-occupiable structures are scanned per-cluster for functional tagging.
 *
 * Arguments:
 *     0: _config <HASHMAP> - Optional configuration overrides
 *        - "debug": Show debug markers on map (default: false)
 *
 * Return Value:
 *     <ARRAY> - Array of location hashmaps, each containing:
 *        "id", "position", "name", "locType", "isMilitary", "militaryTier",
 *        "structures", "mainStructures", "sideStructures",
 *        "buildingCount", "mainCount", "sideCount", "militaryCount",
 *        "radius", "tags", "functionalProfile", "source"
 *
 * Example:
 *     private _locations = [createHashMapFromArray [["debug", true]]] call DSC_core_fnc_scanLocations;
 */

params [
    ["_config", createHashMap, [createHashMap]]
];

private _debug = _config getOrDefault ["debug", false];

// ============================================================================
// STAGE 1: Raw World Sampling
// ============================================================================
diag_log "DSC: ========== Anchor-Based Location Scan ==========";

private _structureTypes = call DSC_core_fnc_getStructureTypes;
private _mainTypes = _structureTypes get "main";
private _sideTypes = _structureTypes get "side";
private _mainMilTypes = _structureTypes get "mainMilitary";
private _sideMilTypes = _structureTypes get "sideMilitary";
private _exclusions = _structureTypes get "exclusions";
private _functionalLookup = _structureTypes get "functionalLookup";

private _centerPosition = [worldSize / 2, worldSize / 2, 0];
private _allStructures = [_centerPosition, ["House", "Building", "Strategic"], worldSize] call DSC_core_fnc_getMapStructures;

diag_log format ["DSC: Stage 1 - Found %1 raw structures on map", count _allStructures];

private _enterableStructures = [];
private _structureClasses = [];
private _structureMilitary = [];
private _structureFunctional = [];

{
    private _struct = _x;
    if ((_struct buildingPos -1) isEqualTo []) then { continue };

    private _isExcluded = false;
    { if (_struct isKindOf _x) exitWith { _isExcluded = true } } forEach _exclusions;
    if (_isExcluded) then { continue };

    private _isMain = false;
    private _isSide = false;
    private _isMilitary = false;

    { if (_struct isKindOf _x) exitWith { _isMain = true } } forEach _mainTypes;
    if (!_isMain) then {
        { if (_struct isKindOf _x) exitWith { _isSide = true } } forEach _sideTypes;
    };

    { if (_struct isKindOf _x) exitWith { _isMilitary = true } } forEach _mainMilTypes;
    if (!_isMilitary) then {
        { if (_struct isKindOf _x) exitWith { _isMilitary = true } } forEach _sideMilTypes;
    };

    private _class = if (_isMain) then { "main" } else { ["unclassified", "side"] select _isSide };
    private _funcCategory = _functionalLookup getOrDefault [typeOf _struct, ""];

    _enterableStructures pushBack _struct;
    _structureClasses pushBack _class;
    _structureMilitary pushBack _isMilitary;
    _structureFunctional pushBack _funcCategory;

} forEach _allStructures;

diag_log format ["DSC: Stage 1 - %1 enterable structures after filtering", count _enterableStructures];

// Filter out structures inside player base markers
private _playerBaseMarkers = allMapMarkers select { _x find "player_base" == 0 };
{
    private _marker = _x;
    private _countBefore = count _enterableStructures;
    private _keepIndices = [];
    {
        if (!(getPos _x inArea _marker)) then {
            _keepIndices pushBack _forEachIndex;
        };
    } forEach _enterableStructures;
    _enterableStructures = _keepIndices apply { _enterableStructures select _x };
    _structureClasses = _keepIndices apply { _structureClasses select _x };
    _structureMilitary = _keepIndices apply { _structureMilitary select _x };
    _structureFunctional = _keepIndices apply { _structureFunctional select _x };
    private _excluded = _countBefore - (count _enterableStructures);
    if (_excluded > 0) then {
        diag_log format ["DSC: Excluded %1 structures inside %2", _excluded, _marker];
    };
} forEach _playerBaseMarkers;

diag_log format ["DSC: Stage 1 - %1 structures after player base exclusion", count _enterableStructures];

// Build lookup
private _structIndexMap = createHashMap;
{ _structIndexMap set [str _x, _forEachIndex] } forEach _enterableStructures;

// ============================================================================
// STAGE 2: Anchor-based assignment
// ============================================================================
private _namedLocations = nearestLocations [_centerPosition, ["NameCityCapital", "NameCity", "NameVillage", "NameLocal"], worldSize];

_namedLocations = _namedLocations select {
    private _locPos = locationPosition _x;
    private _insideBase = false;
    { if (_locPos inArea _x) exitWith { _insideBase = true } } forEach _playerBaseMarkers;
    !_insideBase
};

diag_log format ["DSC: Stage 2 - Found %1 named locations from engine (after base exclusion)", count _namedLocations];

private _anchors = [];

{
    private _loc = _x;
    private _locPos = locationPosition _loc;
    private _locName = text _loc;
    private _locType = type _loc;

    private _nameLower = toLower _locName;
    private _isMilAnchor = false;
    {
        if (_x in _nameLower) exitWith { _isMilAnchor = true };
    } forEach ["military", "airfield", "airbase", "base", "camp", "mil."];

    private _isAirbase = false;
    { if (_x in _nameLower) exitWith { _isAirbase = true } } forEach ["airfield", "airbase", "airport", "air base", "air station"];
    if (_isAirbase) then {
        diag_log format ["DSC: Stage 2 - Skipping airbase anchor: %1", _locName];
        continue;
    };

    if (_locType == "NameLocal" && !_isMilAnchor) then {
        private _nearbyCount = count (_enterableStructures select { _x distance2D _locPos < 200 });
        if (_nearbyCount < 3) then { continue };
    };

    _anchors pushBack [_locPos, _locName, _locType, _isMilAnchor, []];
} forEach _namedLocations;

// Synthetic military anchors for orphaned clusters
private _milStructures = [];
{
    if (_structureMilitary select _forEachIndex) then {
        _milStructures pushBack _x;
    };
} forEach _enterableStructures;

private _milProcessed = createHashMap;
{
    private _struct = _x;
    private _strKey = str _struct;
    if (_strKey in _milProcessed) then { continue };

    private _nearAnchor = false;
    { if ((getPos _struct) distance2D (_x select 0) < 500) exitWith { _nearAnchor = true } } forEach _anchors;
    if (_nearAnchor) then { continue };

    private _cluster = [_struct];
    private _queue = [_struct];
    _milProcessed set [_strKey, true];

    while { _queue isNotEqualTo [] } do {
        private _current = _queue deleteAt 0;
        private _nearby = _milStructures select {
            !(str _x in _milProcessed) && (_x distance2D _current < 400)
        };
        {
            _milProcessed set [str _x, true];
            _cluster pushBack _x;
            _queue pushBack _x;
        } forEach _nearby;
    };

    if ((count _cluster) >= 3) then {
        private _sumX = 0; private _sumY = 0;
        { _sumX = _sumX + (getPos _x select 0); _sumY = _sumY + (getPos _x select 1) } forEach _cluster;
        private _milCenter = [_sumX / (count _cluster), _sumY / (count _cluster), 0];
        _anchors pushBack [_milCenter, format ["Military %1", count _anchors], "Military", true, []];
        diag_log format ["DSC: Stage 2 - Created unnamed military anchor at %1 (%2 structures)", _milCenter, count _cluster];
    };
} forEach _milStructures;

diag_log format ["DSC: Stage 2 - Total anchors: %1", count _anchors];

// ============================================================================
// STAGE 3: Assign structures to nearest anchor
// ============================================================================
private _maxAssignDist = 500;

{
    private _struct = _x;
    private _structPos = getPos _struct;
    private _structIdx = _forEachIndex;
    private _isMil = _structureMilitary select _structIdx;

    private _bestAnchorIdx = -1;
    private _bestDist = _maxAssignDist;

    {
        _x params ["_anchorPos", "_anchorName", "_anchorType", "_anchorIsMil", "_anchorStructs"];
        private _dist = _structPos distance2D _anchorPos;

        if (_dist < _bestDist) then {
            if (_isMil && _anchorIsMil) then {
                _bestDist = _dist;
                _bestAnchorIdx = _forEachIndex;
            } else {
                if (!_isMil) then {
                    _bestDist = _dist;
                    _bestAnchorIdx = _forEachIndex;
                } else {
                    if (_bestAnchorIdx < 0) then {
                        _bestDist = _dist;
                        _bestAnchorIdx = _forEachIndex;
                    };
                };
            };
        };
    } forEach _anchors;

    if (_bestAnchorIdx >= 0) then {
        ((_anchors select _bestAnchorIdx) select 4) pushBack _struct;
    };
} forEach _enterableStructures;

// ============================================================================
// STAGE 3.5: Orphan recovery — cluster unassigned structures into new anchors
// ============================================================================
// Structures beyond maxAssignDist from any named location are orphaned.
// Flood-fill at 150m to form civilian clusters, same pattern as military orphans.

private _assignedSet = createHashMap;
{
    _x params ["", "", "", "", "_anchorStructs"];
    { _assignedSet set [str _x, true] } forEach _anchorStructs;
} forEach _anchors;

private _orphans = _enterableStructures select { !(str _x in _assignedSet) };
diag_log format ["DSC: Stage 3.5 - %1 orphaned structures to cluster", count _orphans];

private _orphanProcessed = createHashMap;
private _orphanClusterRadius = 150;
private _orphanAnchorsCreated = 0;

{
    private _struct = _x;
    private _strKey = str _struct;
    if (_strKey in _orphanProcessed) then { continue };

    private _cluster = [_struct];
    private _queue = [_struct];
    _orphanProcessed set [_strKey, true];

    while { _queue isNotEqualTo [] } do {
        private _current = _queue deleteAt 0;
        private _nearby = _orphans select {
            !(str _x in _orphanProcessed) && (_x distance2D _current < _orphanClusterRadius)
        };
        {
            _orphanProcessed set [str _x, true];
            _cluster pushBack _x;
            _queue pushBack _x;
        } forEach _nearby;
    };

    private _sumX = 0; private _sumY = 0;
    { _sumX = _sumX + (getPos _x select 0); _sumY = _sumY + (getPos _x select 1) } forEach _cluster;
    private _clusterCenter = [_sumX / (count _cluster), _sumY / (count _cluster), 0];

    // Name from nearest named location if close, otherwise grid reference
    private _orphanName = mapGridPosition _clusterCenter;
    {
        private _locPos = locationPosition _x;
        private _dist = _clusterCenter distance2D _locPos;
        if (_dist < 800) exitWith {
            _orphanName = text _x;
        };
    } forEach _namedLocations;

    _anchors pushBack [_clusterCenter, _orphanName, "Orphan", false, _cluster];
    _orphanAnchorsCreated = _orphanAnchorsCreated + 1;
} forEach _orphans;

diag_log format ["DSC: Stage 3.5 - Created %1 orphan anchors from %2 structures", _orphanAnchorsCreated, count _orphans];

// ============================================================================
// STAGE 4: Military tier + build location hashmaps with tags
// ============================================================================
private _nonOccLookup = _structureTypes get "nonOccupiableLookup";
private _locations = [];
private _locationIndex = 0;

{
    _x params ["_anchorPos", "_anchorName", "_anchorType", "_anchorIsMil", "_anchorStructs"];

    if ((count _anchorStructs) < 1) then { continue };

    // Calculate radius
    private _maxDist = 0;
    {
        private _dist = _x distance2D _anchorPos;
        if (_dist > _maxDist) then { _maxDist = _dist };
    } forEach _anchorStructs;

    // Separate main/side/military and count functional categories
    private _mainStructures = [];
    private _sideStructures = [];
    private _milCount = 0;
    private _funcCounts = createHashMap;

    {
        private _idx = _structIndexMap getOrDefault [str _x, -1];
        if (_idx >= 0) then {
            private _class = _structureClasses select _idx;
            private _isMil = _structureMilitary select _idx;
            private _func = _structureFunctional select _idx;

            if (_class == "main") then { _mainStructures pushBack _x };
            if (_class == "side") then { _sideStructures pushBack _x };
            if (_isMil) then { _milCount = _milCount + 1 };
            if (_func != "") then {
                _funcCounts set [_func, (_funcCounts getOrDefault [_func, 0]) + 1];
            };
        };
    } forEach _anchorStructs;

    // Military tier
    private _militaryTier = "";
    if (_anchorIsMil) then {
        _militaryTier = if (_milCount >= 8) then {
            "base"
        } else {
            ["camp", "outpost"] select (_milCount >= 4)
        };
    };

    // Non-occupiable scan for functional tagging
    private _scanRadius = (_maxDist max 50) + 50;
    private _nearbyObjects = nearestObjects [_anchorPos, ["House", "Building", "Strategic", "Thing"], _scanRadius];
    {
        private _objKey = str _x;
        if !(_objKey in _structIndexMap) then {
            private _nonOccFunc = _nonOccLookup getOrDefault [typeOf _x, ""];
            if (_nonOccFunc != "") then {
                _funcCounts set [_nonOccFunc, (_funcCounts getOrDefault [_nonOccFunc, 0]) + 1];
            };
        };
    } forEach _nearbyObjects;

    // --- TAGGING ---
    private _tags = [];
    private _buildingCount = count _anchorStructs;

    // Density
    if (_buildingCount >= 30) then {
        _tags pushBack "high_density";
    } else {
        if (_buildingCount >= 10) then {
            _tags pushBack "medium_density";
        } else {
            _tags pushBack "low_density";
        };
    };

    // Size
    if (_buildingCount >= 50) then { _tags pushBack "city" };
    if (_buildingCount >= 15 && { _buildingCount < 50 }) then { _tags pushBack "town" };
    if (_buildingCount >= 5 && { _buildingCount < 15 }) then { _tags pushBack "settlement" };
    if (_buildingCount < 5) then { _tags pushBack "isolated" };

    // Military
    if (_milCount > 0) then {
        _tags pushBack "military";
        if (_militaryTier != "") then { _tags pushBack _militaryTier };
    };

    // Character
    if (_milCount == 0) then { _tags pushBack "civilian" };
    if (_milCount > 0 && { _buildingCount > _milCount * 2 }) then { _tags pushBack "mixed" };

    // Context from named location type
    if (_anchorType in ["NameCityCapital", "NameCity"]) then { _tags pushBackUnique "urban" };
    if (_anchorType == "NameVillage") then { _tags pushBackUnique "rural" };

    // Functional tags — add "has_<category>" for each category present
    {
        if (_y > 0) then {
            _tags pushBack format ["has_%1", _x];
        };
    } forEach _funcCounts;

    // Build location hashmap
    private _location = createHashMapFromArray [
        ["id", format ["loc_%1", _locationIndex]],
        ["position", _anchorPos],
        ["name", _anchorName],
        ["locType", _anchorType],
        ["isMilitary", _anchorIsMil],
        ["militaryTier", _militaryTier],
        ["structures", _anchorStructs],
        ["mainStructures", _mainStructures],
        ["sideStructures", _sideStructures],
        ["buildingCount", _buildingCount],
        ["mainCount", count _mainStructures],
        ["sideCount", count _sideStructures],
        ["militaryCount", _milCount],
        ["radius", _maxDist max 50],
        ["tags", _tags],
        ["functionalProfile", _funcCounts],
        ["source", "anchor"]
    ];

    _locations pushBack _location;
    _locationIndex = _locationIndex + 1;
} forEach _anchors;

// Second pass: tag isolation (distance to nearest other location)
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

// ============================================================================
// SUMMARY
// ============================================================================
private _tagCounts = createHashMap;
{
    { _tagCounts set [_x, (_tagCounts getOrDefault [_x, 0]) + 1] } forEach (_x get "tags");
} forEach _locations;

diag_log format ["DSC: Location Scan Complete - %1 locations", count _locations];
diag_log format ["DSC: Tag distribution: %1", _tagCounts];

// ============================================================================
// DEBUG: Marker Visualization
// ============================================================================
if (_debug) then {
    {
        private _loc = _x;
        private _pos = _loc get "position";
        private _locName = _loc get "name";
        private _locTags = _loc get "tags";
        private _id = _loc get "id";
        private _bCount = _loc get "buildingCount";

        private _color = "ColorGrey";
        if ("military" in _locTags && "base" in _locTags) then { _color = "ColorRed" };
        if ("military" in _locTags && "outpost" in _locTags) then { _color = "ColorOrange" };
        if ("military" in _locTags && "camp" in _locTags) then { _color = "ColorYellow" };
        if ("urban" in _locTags) then { _color = "ColorBlue" };
        if ("civilian" in _locTags && "settlement" in _locTags) then { _color = "ColorGreen" };
        if ("civilian" in _locTags && "isolated" in _locTags) then { _color = "ColorWhite" };
        if ("remote" in _locTags) then { _color = "ColorBrown" };

        private _markerType = "mil_dot";
        if ("city" in _locTags || "town" in _locTags) then { _markerType = "mil_objective" };
        if ("settlement" in _locTags) then { _markerType = "mil_triangle" };
        if ("base" in _locTags) then { _markerType = "mil_objective" };
        if ("outpost" in _locTags) then { _markerType = "mil_triangle" };

        private _markerName = format ["dsc_loc_%1", _id];
        private _marker = createMarkerLocal [_markerName, _pos];
        _marker setMarkerTypeLocal _markerType;
        _marker setMarkerColorLocal _color;
        _marker setMarkerTextLocal format ["%1 [%2] (%3)", _locName, _bCount, _locTags joinString ","];
        _marker setMarkerSizeLocal [0.7, 0.7];

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
