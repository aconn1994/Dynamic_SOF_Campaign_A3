/*
    File: fn_findRoadsideParking.sqf
    Author: ChatGPT & Adam
    Description:
        Finds natural-looking roadside vehicle parking positions around a marker.
        Vehicles align parallel to nearby roads and prefer openings or gates in perimeter walls/fences.

    Usage:
        [_markerName, _count] call DJC_fnc_findRoadsideParking;

    Returns:
        Array of [position, direction] pairs.
*/

params ["_marker", ["_count", 3]];

// --- Marker info ---
private _center = getMarkerPos _marker;
private _size = getMarkerSize _marker;
private _radius = (_size select 0) max (_size select 1);

// --- Find nearest roads (expand radius gradually) ---
private _roads = [];
for "_i" from 0 to 200 step 25 do {
    _roads = _center nearRoads (_radius + _i);
    if !(_roads isEqualTo []) exitWith {};
};

if (_roads isEqualTo []) exitWith {
    diag_log format ["[findRoadsideParking] No roads found near marker %1", _marker];
    []
};

// --- Prepare storage ---
private _positions = [];

// --- Helper function to detect wall openings facing road ---
private _fn_isWallOpening = {
    params ["_pos", "_dir"];

    private _walls = nearestTerrainObjects [_pos, ["Wall","Fence"], 15, false];
    if (_walls isEqualTo []) exitWith { false };

    private _wallDirs = [];
    {
        _wallDirs pushBack (_x getDir _pos);
    } forEach _walls;

    // If there are walls on both sides but a gap within ~8m ahead, treat as opening
    private _forwardPos = _pos getPos [8, _dir];
    private _hasFrontWall = (count (nearestTerrainObjects [_forwardPos, ["Wall","Fence"], 3])) > 0;
    private _hasSideWalls = (count _walls) > 1;

    (!_hasFrontWall && _hasSideWalls)
};

// --- Iterate over roads ---
{
    private _road = _x;
    private _roadPos = getPosATL _road;
    private _connected = roadsConnectedTo _road;
    if ((count _connected) == 0) then { continue; };

    // Direction of the road (using actual segment)
    private _roadDir = _road getDir (_connected select 0);

    // Try both sides
    for "_i" from 0 to 1 do {
        private _side = if (_i == 0) then {-1} else {1};

        // Offset away from the road center, TODO, check furthest offset for collision, move inward if so
        private _offset = 3 + random 2;
        private _pos = _roadPos getPos [_offset * _side, _roadDir + 90];

        // Shift slightly along the road for spacing
        _pos = _pos getPos [random [3, 8, 12], _roadDir + (random 10 - 5)];

        // Terrain and obstacle checks
        if (surfaceIsWater _pos) then { continue };
        private _obstacles = nearestTerrainObjects [_pos, ["House","Wall","Fence","Tree","Bush"], 3];
        if ((count _obstacles) > 0) then { continue };

        // Score based on wall openings and natural proximity
        private _score = 1;
        if ([_pos, _roadDir] call _fn_isWallOpening) then { _score = _score + 2; }; // prioritize wall gaps
        if ((count (nearestTerrainObjects [_pos, ["House"], 10])) > 0) then { _score = _score + 1; }; // near compound

        // Add to pool
        _positions pushBack [_pos, _roadDir + (random 10 - 5), _score];
    };
} forEach _roads;

// --- Weighted random selection ---
private _final = [];
for "_i" from 1 to _count do {
    if (_positions isEqualTo []) exitWith {};
    private _weighted = [];
    {
        private _w = _x select 2;
        for "_j" from 1 to _w do { _weighted pushBack _x };
    } forEach _positions;

    private _pick = selectRandom _weighted;
    _positions deleteAt (_positions find _pick);
    _final pushBack [_pick select 0, _pick select 1];
};

// --- Debug markers ---
// {
//     _x params ["_pos", "_dir"];
//     private _m = createMarker [format ["parking_%1_%2", _marker, _forEachIndex], _pos];
//     _m setMarkerType "mil_dot";
//     _m setMarkerColor "ColorOrange";
//     _m setMarkerDir _dir;
//     _m setMarkerText format ["%1°", round _dir];
// } forEach _final;

_final;





// /*
//     File: fn_findRoadsideParking.sqf
//     Author: ChatGPT & Adam
//     Description:
//         Finds natural-looking roadside vehicle parking positions around a marker.

//     Usage:
//         [_markerName, _count] call DJC_fnc_findRoadsideParking;

//     Returns:
//         Array of [position, direction] pairs.
// */

// params ["_marker", ["_count", 3]];

// // --- Basic marker info ---
// private _center = getMarkerPos _marker;
// private _size = getMarkerSize _marker;
// private _radius = (_size select 0) max (_size select 1);

// // --- Find roads nearby ---
// private _roads = [];
// for "_i" from 25 to 200 step 25 do {
//     _roads = _center nearRoads (_radius + _i);
// };

// if (_roads isEqualTo []) exitWith {
//     diag_log format ["[findRoadsideParking] No roads found near marker %1", _marker];
//     []
// };

// // --- Prepare storage ---
// private _positions = [];

// // --- Iterate over roads ---
// {
//     private _road = _x;
//     private _roadPos = getPos _road;
//     private _roadDir = getDir _road;  // direction of road segment

//     // Try to find positions along both sides of the road
//     for "_i" from 0 to 1 do {
//         private _side = if (_i == 0) then {-1} else {1};
//         private _offset = 6 + (random 2);  // meters off the road edge
//         private _pos = _roadPos getPos [_offset * _side, _roadDir + 90 * _side];

//         // Optional small spacing offset along the road
//         _pos = _pos getPos [random [3, 8, 12], _roadDir + (random 10 - 5)];

//         // Simple terrain and obstacle checks
//         if (surfaceIsWater _pos) then { continue };
//         if (count (nearestTerrainObjects [_pos, ["House","Wall","Fence","Tree","Bush"], 3]) > 0) then { continue };

//         // Push the spot with a natural alignment
//         _positions pushBack [_pos, _roadDir + (random 10 - 5)];
//     };

// } forEach _roads;

// // --- Pick N random results ---
// private _final = [];
// for "_i" from 1 to _count do {
//     if (_positions isEqualTo []) exitWith {};
//     _final pushBack (selectRandom _positions);
// };

// // --- Debug markers ---
// {
//     private _pos = _x select 0;
//     private _dir = _x select 1;
//     private _m = createMarker [format ["parking_%1_%2", _marker, _forEachIndex], _pos];
//     _m setMarkerType "mil_dot";
//     _m setMarkerColor "ColorYellow";
//     _m setMarkerDir _dir;
//     _m setMarkerText format ["%1°", round _dir];
// } forEach _final;

// _final;