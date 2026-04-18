[] call DSC_core_fnc_initServer;

// ============================================================================
// STAGE 1: Raw World Sampling (same as before)
// ============================================================================
// diag_log "DSC: ========== Anchor-Based Location Scan ==========";

// private _structureTypes = call DSC_core_fnc_getStructureTypes;
// private _mainTypes = _structureTypes get "main";
// private _sideTypes = _structureTypes get "side";
// private _mainMilTypes = _structureTypes get "mainMilitary";
// private _sideMilTypes = _structureTypes get "sideMilitary";
// private _exclusions = _structureTypes get "exclusions";

// private _centerPosition = [worldSize / 2, worldSize / 2, 0];
// private _allStructures = [_centerPosition, ["House", "Building", "Strategic"], worldSize] call DSC_core_fnc_getMapStructures;

// diag_log format ["DSC: Stage 1 - Found %1 raw structures on map", count _allStructures];

// private _enterableStructures = [];
// private _structureClasses = [];
// private _structureMilitary = [];

// {
//     private _struct = _x;
//     if ((_struct buildingPos -1) isEqualTo []) then { continue };

//     private _isExcluded = false;
//     { if (_struct isKindOf _x) exitWith { _isExcluded = true } } forEach _exclusions;
//     if (_isExcluded) then { continue };

//     private _isMain = false;
//     private _isSide = false;
//     private _isMilitary = false;

//     { if (_struct isKindOf _x) exitWith { _isMain = true } } forEach _mainTypes;
//     if (!_isMain) then {
//         { if (_struct isKindOf _x) exitWith { _isSide = true } } forEach _sideTypes;
//     };

//     { if (_struct isKindOf _x) exitWith { _isMilitary = true } } forEach _mainMilTypes;
//     if (!_isMilitary) then {
//         { if (_struct isKindOf _x) exitWith { _isMilitary = true } } forEach _sideMilTypes;
//     };

//     private _class = if (_isMain) then { "main" } else { ["unclassified", "side"] select _isSide };

//     _enterableStructures pushBack _struct;
//     _structureClasses pushBack _class;
//     _structureMilitary pushBack _isMilitary;

// } forEach _allStructures;

// diag_log format ["DSC: Stage 1 - %1 enterable structures after filtering", count _enterableStructures];

// // Filter out structures inside player base markers
// private _playerBaseMarkers = allMapMarkers select { _x find "player_base_" == 0 };
// {
//     private _marker = _x;    
//     private _countBefore = count _enterableStructures;
//     private _keepIndices = [];
//     {
//         if (!(getPos _x inArea _marker)) then {
//             _keepIndices pushBack _forEachIndex;
//         };
//     } forEach _enterableStructures;
//     _enterableStructures = _keepIndices apply { _enterableStructures select _x };
//     _structureClasses = _keepIndices apply { _structureClasses select _x };
//     _structureMilitary = _keepIndices apply { _structureMilitary select _x };
//     private _excluded = _countBefore - count _enterableStructures;
//     if (_excluded > 0) then {
//         diag_log format ["DSC: Excluded %1 structures inside %2", _excluded, _marker];
//     };
// } forEach _playerBaseMarkers;

// diag_log format ["DSC: Stage 1 - %1 structures after player base exclusion", count _enterableStructures];

// // Build lookup
// private _structIndexMap = createHashMap;
// { _structIndexMap set [str _x, _forEachIndex] } forEach _enterableStructures;

// // Debug: structure dots
// {
//     private _structureMarker = createMarkerLocal [format ["s_%1", _forEachIndex], getPos _x];
//     _structureMarker setMarkerTypeLocal "Contact_dot1";
//     _structureMarker setMarkerColorLocal ([["ColorYellow", "ColorRed"] select (_structureMilitary select _forEachIndex)] select 0);
// } forEach _enterableStructures;

// // ============================================================================
// // STAGE 2: Anchor-based assignment
// // ============================================================================
// // Use Arma's named locations as anchors. Each structure gets assigned to its
// // nearest anchor. Military structures cluster separately from civilian ones.

// // Get all named locations from the engine
// private _namedLocations = nearestLocations [_centerPosition, ["NameCityCapital", "NameCity", "NameVillage", "NameLocal"], worldSize];

// // Filter out named locations inside player bases
// _namedLocations = _namedLocations select {
//     private _locPos = locationPosition _x;
//     private _insideBase = false;
//     { if (_locPos inArea _x) exitWith { _insideBase = true } } forEach _playerBaseMarkers;
//     !_insideBase
// };

// diag_log format ["DSC: Stage 2 - Found %1 named locations from engine (after base exclusion)", count _namedLocations];

// // Build anchor list: [position, name, type, isMilitary, assignedStructures]
// private _anchors = [];

// // Named civilian/village/city anchors
// {
//     private _loc = _x;
//     private _locPos = locationPosition _loc;
//     private _locName = text _loc;
//     private _locType = type _loc;
//     private _locSize = size _loc; // [width, height] from Arma
    
//     // Determine if this named location is military
//     private _nameLower = toLower _locName;
//     private _isMilAnchor = false;
//     {
//         if (_x in _nameLower) exitWith { _isMilAnchor = true };
//     } forEach ["military", "airfield", "airbase", "base", "camp", "mil."];
    
//     // Skip very small unnamed locations — these create noise
//     // Keep cities/villages/military always
//     if (_locType == "NameLocal" && !_isMilAnchor) then {
//         // Check if there are actually structures nearby before creating an anchor
//         private _nearbyCount = count (_enterableStructures select { _x distance2D _locPos < 200 });
//         if (_nearbyCount < 3) then { continue };
//     };
    
//     _anchors pushBack [_locPos, _locName, _locType, _isMilAnchor, []];
// } forEach _namedLocations;

// // Also create anchors for military structure clusters that aren't near any named location
// // (catches bases that Arma doesn't name)
// private _milStructures = [];
// {
//     if (_structureMilitary select _forEachIndex) then {
//         _milStructures pushBack _x;
//     };
// } forEach _enterableStructures;

// // Simple clustering for orphaned military structures
// private _milProcessed = createHashMap;
// {
//     private _struct = _x;
//     private _strKey = str _struct;
//     if (_strKey in _milProcessed) then { continue };
    
//     // Check if near an existing anchor
//     private _nearAnchor = false;
//     { if ((getPos _struct) distance2D (_x select 0) < 500) exitWith { _nearAnchor = true } } forEach _anchors;
//     if (_nearAnchor) then { continue };
    
//     // Flood-fill nearby military structures
//     private _cluster = [_struct];
//     private _queue = [_struct];
//     _milProcessed set [_strKey, true];
    
//     while { _queue isNotEqualTo [] } do {
//         private _current = _queue deleteAt 0;
//         private _nearby = _milStructures select { 
//             !(str _x in _milProcessed) && (_x distance2D _current < 400)
//         };
//         {
//             _milProcessed set [str _x, true];
//             _cluster pushBack _x;
//             _queue pushBack _x;
//         } forEach _nearby;
//     };
    
//     if (count _cluster >= 3) then {
//         private _sumX = 0; private _sumY = 0;
//         { _sumX = _sumX + (getPos _x select 0); _sumY = _sumY + (getPos _x select 1) } forEach _cluster;
//         private _milCenter = [_sumX / count _cluster, _sumY / count _cluster, 0];
//         _anchors pushBack [_milCenter, format ["Military %1", count _anchors], "Military", true, []];
//         diag_log format ["DSC: Stage 2 - Created unnamed military anchor at %1 (%2 structures)", _milCenter, count _cluster];
//     };
// } forEach _milStructures;

// diag_log format ["DSC: Stage 2 - Total anchors: %1", count _anchors];

// // ============================================================================
// // STAGE 3: Assign structures to nearest anchor
// // ============================================================================
// // Max assignment distance — structures beyond this become "isolated"
// private _maxAssignDist = 500;
// private _isolatedStructures = [];

// {
//     private _struct = _x;
//     private _structPos = getPos _struct;
//     private _structIdx = _forEachIndex;
//     private _isMil = _structureMilitary select _structIdx;
    
//     private _bestAnchorIdx = -1;
//     private _bestDist = _maxAssignDist;
    
//     {
//         _x params ["_anchorPos", "_anchorName", "_anchorType", "_anchorIsMil", "_anchorStructs"];
//         private _dist = _structPos distance2D _anchorPos;
        
//         if (_dist < _bestDist) then {
//             // Military structures prefer military anchors
//             if (_isMil && _anchorIsMil) then {
//                 _bestDist = _dist;
//                 _bestAnchorIdx = _forEachIndex;
//             } else {
//                 if (!_isMil) then {
//                     _bestDist = _dist;
//                     _bestAnchorIdx = _forEachIndex;
//                 } else {
//                     // Military struct, no military anchor nearby — use civilian as fallback
//                     if (_bestAnchorIdx < 0) then {
//                         _bestDist = _dist;
//                         _bestAnchorIdx = _forEachIndex;
//                     };
//                 };
//             };
//         };
//     } forEach _anchors;
    
//     if (_bestAnchorIdx >= 0) then {
//         ((_anchors select _bestAnchorIdx) select 4) pushBack _struct;
//     } else {
//         _isolatedStructures pushBack _struct;
//     };
// } forEach _enterableStructures;

// diag_log format ["DSC: Stage 3 - %1 isolated structures not assigned to any anchor", count _isolatedStructures];

// // ============================================================================
// // DEBUG: Visualize anchors with area markers
// // ============================================================================
// {
//     _x params ["_anchorPos", "_anchorName", "_anchorType", "_anchorIsMil", "_anchorStructs"];
    
//     if (count _anchorStructs < 1) then { continue };
    
//     // Calculate radius from assigned structures
//     private _maxDist = 0;
//     {
//         private _dist = _x distance2D _anchorPos;
//         if (_dist > _maxDist) then { _maxDist = _dist };
//     } forEach _anchorStructs;
    
//     private _color = ["ColorOrange", "ColorRed"] select _anchorIsMil;
    
//     // Area marker
//     private _areaMarker = createMarkerLocal [format ["anchor_area_%1", _forEachIndex], _anchorPos];
//     _areaMarker setMarkerShapeLocal "ELLIPSE";
//     _areaMarker setMarkerSizeLocal [_maxDist max 50, _maxDist max 50];
//     _areaMarker setMarkerColorLocal _color;
//     _areaMarker setMarkerAlphaLocal 0.3;
    
//     // Label marker
//     private _labelMarker = createMarkerLocal [format ["anchor_label_%1", _forEachIndex], _anchorPos];
//     _labelMarker setMarkerTypeLocal (["mil_triangle", "mil_objective"] select _anchorIsMil);
//     _labelMarker setMarkerColorLocal _color;
//     _labelMarker setMarkerTextLocal format ["%1 [%2]", _anchorName, count _anchorStructs];
    
//     diag_log format ["DSC: Anchor '%1' (%2): %3 structures, radius %4m", _anchorName, _anchorType, count _anchorStructs, round _maxDist];
    
// } forEach _anchors;

// diag_log "DSC: ========== Anchor-Based Scan Complete ==========";
