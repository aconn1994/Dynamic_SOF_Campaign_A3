#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_buildRoadRoute
 * Description:
 *     Builds a connected road route by walking the road network graph from a
 *     start position. Prefers forward direction, avoids U-turns, handles dead ends.
 *     Returns an array of road positions suitable for vehicle waypoints.
 *
 * Arguments:
 *     0: _startPos <ARRAY> - Starting position [x, y, z]
 *     1: _targetDistance <NUMBER> - Desired total route distance in meters (default: 500)
 *     2: _preferredDir <NUMBER> - Preferred travel direction in degrees (default: random)
 *
 * Return Value:
 *     <ARRAY> - Array of positions along roads (empty if no roads found)
 *
 * Example:
 *     private _route = [getPos player, 600, 90] call DSC_core_fnc_buildRoadRoute;
 */

params [
    ["_startPos", [], [[]]],
    ["_targetDistance", 500, [0]],
    ["_preferredDir", -1, [0]]
];

if (_startPos isEqualTo []) exitWith {
    diag_log "DSC: fnc_buildRoadRoute - No start position provided";
    []
};

if (_preferredDir < 0) then {
    _preferredDir = random 360;
};

// ============================================================================
// Find nearest road to start position
// ============================================================================
private _nearestRoads = _startPos nearRoads 300;
if (_nearestRoads isEqualTo []) exitWith {
    diag_log format ["DSC: fnc_buildRoadRoute - No roads within 300m of %1", _startPos];
    []
};

// Pick the road closest to start position
_nearestRoads = [_nearestRoads, [], { _x distance2D _startPos }, "ASCEND"] call BIS_fnc_sortBy;
private _currentRoad = _nearestRoads select 0;

// ============================================================================
// Walk the road graph
// ============================================================================
private _route = [getPosATL _currentRoad];
private _visitedRoads = createHashMap;
_visitedRoads set [str _currentRoad, true];

private _totalDistance = 0;
private _currentDir = _preferredDir;
private _maxSegments = 50;
private _segmentCount = 0;

while { _totalDistance < _targetDistance && _segmentCount < _maxSegments } do {
    private _connected = roadsConnectedTo _currentRoad;

    // Filter out already-visited roads
    _connected = _connected select { !(str _x in _visitedRoads) };

    if (_connected isEqualTo []) exitWith {
        // Dead end — route stops here (good dismount point)
    };

    // Score connected roads: prefer ones continuing in the current direction
    // Reject sharp U-turns (>120° deviation from current heading)
    private _currentPos = getPosATL _currentRoad;
    private _bestRoad = objNull;
    private _bestScore = -999;

    {
        private _nextPos = getPosATL _x;
        private _segDir = _currentPos getDir _nextPos;
        private _angleDiff = abs (_segDir - _currentDir);
        if (_angleDiff > 180) then { _angleDiff = 360 - _angleDiff };

        // Reject U-turns
        if (_angleDiff > 120) then { continue };

        // Score: lower angle difference = better (more forward)
        private _score = 180 - _angleDiff;

        if (_score > _bestScore) then {
            _bestScore = _score;
            _bestRoad = _x;
        };
    } forEach _connected;

    // If no forward road found (all are U-turns), pick any connected road
    if (isNull _bestRoad) then {
        _bestRoad = _connected select 0;
    };

    // Add to route
    private _nextPos = getPosATL _bestRoad;
    private _segDist = _currentPos distance2D _nextPos;
    _totalDistance = _totalDistance + _segDist;

    _route pushBack _nextPos;
    _visitedRoads set [str _bestRoad, true];

    // Update direction for next iteration
    _currentDir = _currentPos getDir _nextPos;
    _currentRoad = _bestRoad;
    _segmentCount = _segmentCount + 1;
};

// ============================================================================
// Thin out waypoints — keep every Nth point for cleaner driving
// ============================================================================
private _thinned = [_route select 0];
private _minWaypointDist = 50;

{
    private _lastKept = _thinned select -1;
    if (_x distance2D _lastKept >= _minWaypointDist) then {
        _thinned pushBack _x;
    };
} forEach _route;

// Always include the last point
if (count _route > 1) then {
    private _lastPoint = _route select -1;
    if (_lastPoint distance2D (_thinned select -1) > 10) then {
        _thinned pushBack _lastPoint;
    };
};

diag_log format ["DSC: fnc_buildRoadRoute - Built route: %1 waypoints, %2m total (target: %3m)",
    count _thinned, round _totalDistance, _targetDistance];

_thinned
