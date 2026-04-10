#include "script_component.hpp"
/*
 * Generates potential guard post positions around structures.
 * 
 * Analyzes building corners and perimeter objects (fences, walls) to find
 * suitable positions for placing guards or sentries.
 * 
 * Arguments:
 *   0: Center position <ARRAY>
 *   1: Array of structures from fnc_getAreaStructures <ARRAY>
 * 
 * Returns:
 *   Array of position arrays suitable for guard placement
 * 
 * Example:
 *   private _structures = [_basePos, 250] call DSC_core_fnc_getAreaStructures;
 *   private _guardPosts = [_basePos, _structures] call DSC_core_fnc_getGuardPosts;
 */

params ["_location"];  // TODO, TEST WITH DIFFERENT AREA MARKERS

// Step 1: collect candidate positions
private _allGuardPosts = [];
private _offsetDist = 2;

// // TODO: add perimeter sampling for walls/gates
private _perimeterObjs = [
    _location,
    ["Wall", "Fence"],
    selectRandom [250, 400, 600],
    ["FENCE", "WALL", "HIDE"]
] call DSC_core_fnc_getMapStructures;

// Filter: only keep objects near the marker’s border
private _minBorderDist = (10 * 0.75);  // tweak 0.75 for tighter/looser filtering
_perimeterObjs = _perimeterObjs select {
    (_x distance2D _location) > _minBorderDist
};

// Now shift positions outward
private _shiftedPositions = [];
{
    private _pos = getPosWorld _x;

    // Direction from center to object
    private _dir = _location getDir _pos;

    // New position offset 2m away from center
    private _shiftedPos = _pos getPos [_offsetDist, _dir];

    _shiftedPositions pushBack _shiftedPos;
} forEach _perimeterObjs;

// LOG_1("Test Objecsts: %1", _shiftedPositions);

_allGuardPosts = _allGuardPosts + _shiftedPositions;

// Filter out positions in water
_allGuardPosts = _allGuardPosts select {
    !surfaceIsWater _x
};

_allGuardPosts;
