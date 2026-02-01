#include "script_component.hpp"
/*
 * Gets all terrain structures within a radius of a location.
 * 
 * Searches for buildings, houses, bunkers, towers, and other structures
 * that can be used for garrison placement or tactical analysis.
 * 
 * Arguments:
 *   0: Center position <ARRAY>
 *   1: Search radius in meters <NUMBER>
 * 
 * Returns:
 *   Array of terrain objects
 * 
 * Example:
 *   private _structures = [getPos player, 500] call DSC_core_fnc_getAreaStructures;
 */

params ["_location", "_radius"];

private _mainStructures = [];
private _sideStructures = [];

private _structureCategories = ["BUILDING", "HOUSE", "BUNKER", "FORTRESS", "HOSPITAL", "VIEW-TOWER", "MILITARY", "VILLAGE", "CITY"];
private _locationStructures = nearestTerrainObjects [_location, _structureCategories, _radius];

// {
//     private _struct = _x;
//     private _noOfPositions = count (_x buildingPos -1);

//     if (_noOfPositions == 0) then { continue };

//     if (_noOfPositions >= 4) then {
//         _mainStructures pushBack _struct;
//     };
//     if (_noOfPositions < 4) then {
//         _sideStructures pushBack _struct;
//     };
// } forEach _locationStructures;

_locationStructures;

// _structuresMapper = createHashMap;
// _structuresMapper set ["mainStructures", _mainStructures];
// _structuresMapper set ["sideStructures", _sideStructures];

// _structuresMapper;
