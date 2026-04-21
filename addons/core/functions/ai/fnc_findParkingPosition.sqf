#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_findParkingPosition
 * Description:
 *     Finds natural-looking vehicle parking positions near a cluster of structures.
 *     Prefers roadside positions aligned to road direction, scores candidates by
 *     wall openings and compound proximity. Falls back to flat ground near structures
 *     when no roads are available.
 *
 *     Adapted from archived fn_findRoadsideParking.sqf and fn_findPerimeterParking.sqf.
 *
 * Arguments:
 *     0: _center <ARRAY> - Center position [x, y, z]
 *     1: _radius <NUMBER> - Search radius from center (default: 50)
 *     2: _count <NUMBER> - Max parking spots to return (default: 2)
 *
 * Return Value:
 *     <ARRAY> - Array of [position, direction] pairs
 *
 * Example:
 *     private _spots = [getPos _building, 50, 2] call DSC_core_fnc_findParkingPosition;
 *     { _x params ["_pos", "_dir"]; } forEach _spots;
 */

params [
    ["_center", [], [[]]],
    ["_radius", 50, [0]],
    ["_count", 2, [0]]
];

if (_center isEqualTo []) exitWith {
    diag_log "DSC: fnc_findParkingPosition - No center position provided";
    []
};

// ============================================================================
// Step 1: Find nearby roads (expand search if needed)
// ============================================================================
private _roads = [];
{
    _roads = _center nearRoads (_radius + _x);
    if (_roads isNotEqualTo []) exitWith {};
} forEach [0, 25, 50, 100, 150, 200];

// ============================================================================
// Step 2: Generate candidates from road segments
// ============================================================================
private _candidates = [];

if (_roads isNotEqualTo []) then {
    {
        private _road = _x;
        private _roadPos = getPosATL _road;
        private _connected = roadsConnectedTo _road;
        if (_connected isEqualTo []) then { continue };

        private _roadDir = _road getDir (_connected select 0);

        // Try both sides of the road
        {
            private _side = _x;
            private _offset = 3 + random 2;
            private _pos = _roadPos getPos [_offset * _side, _roadDir + 90];
            _pos = _pos getPos [random [3, 8, 12], _roadDir + (random 10 - 5)];
            _pos set [2, 0];

            if (surfaceIsWater _pos) then { continue };
            if ((nearestTerrainObjects [_pos, ["House", "Tree", "Wall", "Fence", "Bush"], 3]) isNotEqualTo []) then { continue };

            // Score the position
            private _score = 1;

            // Wall opening detection: walls on sides but gap ahead
            private _walls = nearestTerrainObjects [_pos, ["Wall", "Fence"], 15];
            if (_walls isNotEqualTo []) then {
                private _forwardPos = _pos getPos [8, _roadDir];
                private _hasFrontWall = (nearestTerrainObjects [_forwardPos, ["Wall", "Fence"], 3]) isNotEqualTo [];
                if (!_hasFrontWall && { count _walls > 1 }) then {
                    _score = _score + 2;
                };
            };

            // Near structures bonus
            if ((nearestTerrainObjects [_pos, ["House"], 15]) isNotEqualTo []) then {
                _score = _score + 1;
            };

            _candidates pushBack [_pos, _roadDir + (random 10 - 5), _score];
        } forEach [-1, 1];
    } forEach _roads;
};

// ============================================================================
// Step 3: Fallback — flat ground near structures (no roads found)
// ============================================================================
if (_candidates isEqualTo []) then {
    private _numAttempts = _count * 4;
    for "_i" from 0 to (_numAttempts - 1) do {
        private _angle = random 360;
        private _dist = 10 + random (_radius * 0.5);
        private _pos = _center getPos [_dist, _angle];
        _pos set [2, 0];

        if (surfaceIsWater _pos) then { continue };
        if ((nearestTerrainObjects [_pos, ["House", "Tree", "Wall", "Fence", "Bush"], 3]) isNotEqualTo []) then { continue };

        private _dirToCenter = _pos getDir _center;
        _candidates pushBack [_pos, _dirToCenter + (random 20 - 10), 1];
    };
};

// ============================================================================
// Step 4: Weighted random selection
// ============================================================================
private _results = [];

for "_i" from 1 to _count do {
    if (_candidates isEqualTo []) exitWith {};

    private _weighted = [];
    {
        private _w = _x select 2;
        for "_j" from 1 to _w do { _weighted pushBack _x };
    } forEach _candidates;

    private _pick = selectRandom _weighted;
    _candidates deleteAt (_candidates find _pick);

    // Reject if too close to an already-picked spot
    private _tooClose = false;
    { if ((_pick select 0) distance2D (_x select 0) < 8) exitWith { _tooClose = true } } forEach _results;
    if (_tooClose) then { continue };

    _results pushBack [_pick select 0, _pick select 1];
};

_results
