#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_buildRoadRoute
 * Description:
 *     Builds a connected road route by walking the road network graph from a
 *     start position. Prefers forward direction, avoids U-turns, backtracks
 *     out of dead ends. Returns an array of road positions suitable for
 *     vehicle waypoints.
 *
 *     WHY THIS IS MORE COMPLICATED THAN IT LOOKS
 *
 *     The naive version (walk from the single nearest road, stop at the first
 *     dead end) failed constantly in playtest — logs were full of
 *     `Built route: 1 waypoints, 0m total (target: 1700m)`. Three separate
 *     causes, all fixed here:
 *
 *     1. THE NEAREST ROAD IS OFTEN A STUB. `nearRoads` returns whatever is
 *        physically closest, which is frequently a driveway, parking spur,
 *        bridge ramp or an isolated segment with no graph neighbours. The walk
 *        died on iteration one. Now up to 4 nearest roads are tried as start
 *        candidates and the first one that produces a usable route wins.
 *
 *     2. A DEAD END ENDED THE WHOLE ROUTE. If the first step off the start
 *        road happened to be a stub, the walk terminated with a single point
 *        even though other branches were available. The walk now keeps the
 *        chain it has travelled and backs up on a dead end to try a different
 *        branch (bounded DFS), which is also just a better route shape.
 *
 *     3. A DEGENERATE ROUTE IS WORSE THAN NO ROUTE. Returning a 1-point route
 *        positioned at the caller's own location is actively harmful: the
 *        patrol loops set a MOVE waypoint there, the vehicle is already inside
 *        the completion radius, arrival fires instantly, and the rover holds
 *        and re-plans in place forever. That is the "ground rovers spawn and
 *        never move" symptom. Anything shorter than 25% of the requested
 *        distance now returns [] so the caller retries with a new direction.
 *
 *     `roadsConnectedTo` is also defensively filtered — it can report the
 *     query segment itself and can contain null entries on bridge geometry,
 *     both of which previously counted as valid neighbours.
 *
 * Arguments:
 *     0: _startPos <ARRAY> - Starting position [x, y, z]
 *     1: _targetDistance <NUMBER> - Desired total route distance in meters (default: 500)
 *     2: _preferredDir <NUMBER> - Preferred travel direction in degrees (default: random)
 *
 * Return Value:
 *     <ARRAY> - Array of positions along roads. EMPTY if no usable route was
 *               found — callers must treat [] as "retry later", not "drive to
 *               where you already are".
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
    ERROR("fnc_buildRoadRoute - No start position provided");
    []
};

if (_preferredDir < 0) then {
    _preferredDir = random 360;
};

// ============================================================================
// Collect candidate start roads
// ============================================================================
private _nearestRoads = _startPos nearRoads 300;
if (_nearestRoads isEqualTo []) exitWith {
    LOG_1("fnc_buildRoadRoute - No roads within 300m of %1",_startPos);
    []
};

_nearestRoads = [_nearestRoads, [], { _x distance2D _startPos }, "ASCEND"] call BIS_fnc_sortBy;

// ============================================================================
// Graph walk — bounded DFS with dead-end backtracking
// ============================================================================
// Returns [routePositions, totalDistance, terminationReason].
private _fnc_walk = {
    params ["_startRoad", "_dir", "_target"];

    // Road segments in Arma 3 average 20-30m. 300 caps the walk at ~7.5km of
    // road, plenty for any caller while still preventing runaway loops on
    // pathological road networks (e.g. dirt-track spirals).
    private _maxSegments = 300;
    private _maxBacktracks = 12;

    private _visited = createHashMap;
    _visited set [str _startRoad, true];

    // _chain, _route and _segDists stay index-aligned so a backtrack can pop
    // all three together and restore the running distance exactly.
    private _chain    = [_startRoad];
    private _route    = [getPosATL _startRoad];
    private _segDists = [0];

    private _totalDistance = 0;
    private _currentDir    = _dir;
    private _segmentCount  = 0;
    private _backtracks    = 0;
    private _reason        = "target-reached";
    private _running       = true;

    while { _running } do {
        if (_totalDistance >= _target) then {
            _reason = "target-reached";
            _running = false;
        };

        if (_running && { _segmentCount >= _maxSegments }) then {
            _reason = "segment-cap";
            _running = false;
        };

        if (_running) then {
            private _currentRoad = _chain select -1;
            private _currentPos  = _route select -1;

            // Defensive filter: drop nulls, self-references and anything
            // already explored on this walk.
            private _connected = (roadsConnectedTo _currentRoad) select {
                !(isNull _x)
                    && { _x isNotEqualTo _currentRoad }
                    && { !(str _x in _visited) }
            };

            if (_connected isEqualTo []) then {
                // Dead end. Back up one segment and try a different branch
                // rather than abandoning the route. The popped road stays in
                // _visited so we don't re-explore the stub we just left.
                if (count _chain > 1 && { _backtracks < _maxBacktracks }) then {
                    _chain    deleteAt (count _chain - 1);
                    _route    deleteAt (count _route - 1);
                    _totalDistance = _totalDistance - (_segDists deleteAt (count _segDists - 1));
                    _backtracks = _backtracks + 1;

                    // Restore heading from the segment we're now standing on
                    // so forward-preference still means something.
                    if (count _route > 1) then {
                        _currentDir = (_route select -2) getDir (_route select -1);
                    } else {
                        _currentDir = _dir;
                    };
                } else {
                    _reason = "dead-end";
                    _running = false;
                };
            } else {
                // Score connected roads: prefer ones continuing in the current
                // direction. Reject sharp U-turns (>120 deg deviation).
                private _bestRoad  = objNull;
                private _bestScore = -999;

                {
                    private _nextPos   = getPosATL _x;
                    private _segDir    = _currentPos getDir _nextPos;
                    private _angleDiff = abs (_segDir - _currentDir);
                    if (_angleDiff > 180) then { _angleDiff = 360 - _angleDiff };

                    if (_angleDiff <= 120) then {
                        private _score = 180 - _angleDiff;
                        if (_score > _bestScore) then {
                            _bestScore = _score;
                            _bestRoad  = _x;
                        };
                    };
                } forEach _connected;

                // Every option was a U-turn — take one anyway rather than
                // treating a hairpin as a dead end.
                if (isNull _bestRoad) then {
                    _bestRoad = _connected select 0;
                };

                private _nextPos = getPosATL _bestRoad;
                private _segDist = _currentPos distance2D _nextPos;

                _chain    pushBack _bestRoad;
                _route    pushBack _nextPos;
                _segDists pushBack _segDist;
                _totalDistance = _totalDistance + _segDist;
                _visited set [str _bestRoad, true];

                _currentDir   = _currentPos getDir _nextPos;
                _segmentCount = _segmentCount + 1;
            };
        };
    };

    [_route, _totalDistance, _reason]
};

// ============================================================================
// Try successive start candidates until one produces a usable route
// ============================================================================
// A route that doesn't actually go anywhere makes the caller's arrival check
// pass immediately and the patrol stall in place, so "short" counts as
// failure and we move on to the next start road.
private _minUsefulDistance = (_targetDistance * 0.25) max 100;
private _maxCandidates = 4 min (count _nearestRoads);

private _route         = [];
private _totalDistance = 0;
private _reason        = "no-usable-start";
private _candidateIdx  = 0;
private _found         = false;

while { !_found && { _candidateIdx < _maxCandidates } } do {
    private _startRoad = _nearestRoads select _candidateIdx;
    private _attempt = [_startRoad, _preferredDir, _targetDistance] call _fnc_walk;
    _attempt params ["_aRoute", "_aDist", "_aReason"];

    // Keep the best attempt so far so a marginal route still beats nothing
    // if every candidate falls short.
    if (_aDist > _totalDistance) then {
        _route         = _aRoute;
        _totalDistance = _aDist;
        _reason        = _aReason;
    };

    if (_aDist >= _minUsefulDistance && { count _aRoute > 1 }) then {
        _found = true;
    } else {
        private _rejectDist = round _aDist;
        LOG_3("fnc_buildRoadRoute - start candidate %1 unusable (%2m, %3)",_candidateIdx,_rejectDist,_aReason);
    };

    _candidateIdx = _candidateIdx + 1;
};

if (!_found) exitWith {
    private _bestDist = round _totalDistance;
    private _wanted = round _targetDistance;
    LOG_3("fnc_buildRoadRoute - No usable route after %1 start candidates (best %2m of %3m)",_maxCandidates,_bestDist,_wanted);
    []
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

// Thinning can collapse a short winding route back down to a single point.
// Same degenerate case as above — refuse it.
if (count _thinned < 2) exitWith {
    private _collapsed = round _totalDistance;
    LOG_1("fnc_buildRoadRoute - Route collapsed to 1 waypoint after thinning (%1m), rejecting",_collapsed);
    []
};

private _builtDist = round _totalDistance;
LOG_4("fnc_buildRoadRoute - Built route: %1 waypoints, %2m total (target: %3m, %4)",count _thinned,_builtDist,_targetDistance,_reason);

_thinned
