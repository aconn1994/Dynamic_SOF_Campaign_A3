/*
    File: fn_findPerimeterParking.sqf
    Author: ChatGPT & Adam
    Description:
        Finds realistic parking spots near wall openings along roads.
*/

params ["_marker", ["_maxCount", 4]];

// --- Marker info ---
private _center = getMarkerPos _marker;
private _size = getMarkerSize _marker;
private _dir = markerDir _marker;
private _radius = (_size select 0) max (_size select 1);

// --- Data containers ---
private _results = [];
private _openings = [];

// --- Step 1: Get walls and roads ---
private _walls = nearestTerrainObjects [_center, ["WALL","FENCE"], _radius + 20];
private _roads = _center nearRoads (_radius + 50);

// --- Step 2: Sample the perimeter ---
for "_i" from 0 to 359 step 10 do {
    private _rad = (_i + _dir) * (pi / 180);
    private _samplePos = [
        (_center select 0) + (_size select 0) * sin _rad,
        (_center select 1) + (_size select 1) * cos _rad,
        0
    ];

    // Road proximity check
    private _nearRoads = _samplePos nearRoads 25;
    if ((count _nearRoads) == 0) then { continue; };

    // Wall density check (low = opening)
    private _nearWalls = nearestTerrainObjects [_samplePos, ["WALL","FENCE"], 4];
    if ((count _nearWalls) == 0) then {
        _openings pushBack _samplePos;
    };
};

// --- Step 3: Merge nearby openings ---
private _filtered = [];
{
    private _pos = _x;
    if (_filtered findIf { _x distance2D _pos < 8 } == -1) then {
        _filtered pushBack _pos;
    };
} forEach _openings;
_openings = _filtered;

// --- Step 4: Generate parking positions ---
{
    private _pos = _x;

    // Find nearest road to align direction
    private _roadsNear = _pos nearRoads 25;
    private _roadDir = 0;
    if ((count _roadsNear) > 0) then {
        private _road = _roadsNear select 0;
        private _connected = roadsConnectedTo _road;
        if ((count _connected) > 0) then {
            _roadDir = _road getDir (_connected select 0);
        };
    };

    // Direction facing compound center (to offset outward)
    private _dirToCenter = [_pos, _center] call BIS_fnc_dirTo;

    // Park slightly toward road
    private _offsetDist = 5 + random 3;
    private _parkDir = if (_roadDir != 0) then { _roadDir } else { _dirToCenter + 180 };
    private _parkPos = [
        (_pos select 0) + (sin _parkDir * _offsetDist),
        (_pos select 1) + (cos _parkDir * _offsetDist),
        0
    ];

    // Safety validation
    if (
        !(surfaceIsWater _parkPos)
        && {count (nearestTerrainObjects [_parkPos, ["House","Tree","Wall","Fence","Bush"], 3]) == 0}
    ) then {
        _results pushBack [_parkPos, _parkDir];
    };
} forEach _openings;

// --- Step 5: Limit and debug markers ---
if ((count _results) > _maxCount) then {
    _results resize _maxCount;
};

{
    _x params ["_pos", "_dir"];
    private _m = createMarker [format ["%1_gatePark_%2", _marker, _forEachIndex], _pos];
    _m setMarkerType "mil_dot";
    _m setMarkerColor "ColorOrange";
    _m setMarkerDir _dir;
    _m setMarkerText format ["Gate %1°", round _dir];
} forEach _results;

_results;
