#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_scanMapStructures
 * Description:
 *     Debug utility - scans the entire map for all enterable structures and logs
 *     their class names, categorized as classified (main/side) or unclassified.
 *     Run once per map, copy RPT output to add missing classes to fnc_getStructureTypes.
 *
 * Arguments:
 *     None
 *
 * Return Value:
 *     <HASHMAP> - Keys: "main", "side", "unclassified", "excluded"
 *
 * Example:
 *     call DSC_core_fnc_scanMapStructures
 */

private _structureTypes = call DSC_core_fnc_getStructureTypes;
private _mainTypes = _structureTypes get "main";
private _sideTypes = _structureTypes get "side";
private _exclusions = _structureTypes get "exclusions";

private _centerPosition = [worldSize / 2, worldSize / 2, 0];

// Use both nearestObjects (class-based) and nearestTerrainObjects (type-based) for full coverage
private _classObjects = nearestObjects [_centerPosition, ["House", "Building", "Strategic"], worldSize];
private _typeCategories = ["BUILDING", "HOUSE", "BUNKER", "FORTRESS", "HOSPITAL", "VIEW-TOWER", "MILITARY", "VILLAGE", "CITY"];
private _terrainObjects = nearestTerrainObjects [_centerPosition, _typeCategories, worldSize];
private _allStructures = _classObjects + _terrainObjects;
_allStructures = _allStructures arrayIntersect _allStructures;

private _classifiedMain = createHashMap;
private _classifiedSide = createHashMap;
private _unclassified = createHashMap;
private _excluded = createHashMap;

{
    private _struct = _x;
    private _type = typeOf _struct;
    private _positions = count (_struct buildingPos -1);

    if (_positions == 0) then { continue };

    // Check exclusions
    private _isExcluded = false;
    { if (_struct isKindOf _x) exitWith { _isExcluded = true } } forEach _exclusions;

    if (_isExcluded) then {
        if !(_type in _excluded) then {
            _excluded set [_type, _positions];
        };
        continue;
    };

    // Check main
    private _isMain = false;
    { if (_struct isKindOf _x) exitWith { _isMain = true } } forEach _mainTypes;

    if (_isMain) then {
        if !(_type in _classifiedMain) then {
            _classifiedMain set [_type, _positions];
        };
        continue;
    };

    // Check side
    private _isSide = false;
    { if (_struct isKindOf _x) exitWith { _isSide = true } } forEach _sideTypes;

    if (_isSide) then {
        if !(_type in _classifiedSide) then {
            _classifiedSide set [_type, _positions];
        };
        continue;
    };

    // Unclassified
    if !(_type in _unclassified) then {
        _unclassified set [_type, _positions];
    };
} forEach _allStructures;

// Log results
diag_log "========== DSC MAP STRUCTURE SCAN ==========";
diag_log format ["Map: %1 | Total enterable structures scanned: %2", worldName, count _allStructures];
diag_log "";

diag_log format ["--- CLASSIFIED MAIN (%1 types) ---", count _classifiedMain];
{
    diag_log format ["  [MAIN] %1 (%2 positions)", _x, _y];
} forEach _classifiedMain;

diag_log "";
diag_log format ["--- CLASSIFIED SIDE (%1 types) ---", count _classifiedSide];
{
    diag_log format ["  [SIDE] %1 (%2 positions)", _x, _y];
} forEach _classifiedSide;

diag_log "";
diag_log format ["--- EXCLUDED (%1 types) ---", count _excluded];
{
    diag_log format ["  [EXCLUDED] %1 (%2 positions)", _x, _y];
} forEach _excluded;

diag_log "";
diag_log format ["--- UNCLASSIFIED (%1 types) - ADD THESE ---", count _unclassified];
{
    diag_log format ["  [UNCLASSIFIED] %1 (%2 positions)", _x, _y];
} forEach _unclassified;

diag_log "========== END MAP STRUCTURE SCAN ==========";

private _result = createHashMapFromArray [
    ["main", _classifiedMain],
    ["side", _classifiedSide],
    ["unclassified", _unclassified],
    ["excluded", _excluded]
];

_result
