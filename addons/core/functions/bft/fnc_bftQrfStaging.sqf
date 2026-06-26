#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_bftQrfStaging
 * Description:
 *     Picks a hold position for a QRF group so it stages near an objective
 *     without sitting inside the kill box. Tries to land on a road 500-800 m
 *     out from the objective in a random direction; falls back to a road
 *     in a wider ring if nothing is found, and ultimately to the random
 *     ring point itself if the area has no roads at all.
 *
 *     Same staging-by-road pattern fnc_rovingSpawnGround uses so QRF
 *     vehicles stay drivable when they get the move-in order.
 *
 * Arguments:
 *     0: _objPos <ARRAY> - objective world position [x, y, z]
 *
 * Return Value:
 *     <ARRAY> - staging world position
 */

params [["_objPos", [0,0,0], [[]]]];

if (count _objPos < 2) exitWith { _objPos };

private _stagingPos = [];

// Pass 1: tight ring (500-800 m) on a random heading, snap to nearest road
for "_attempt" from 0 to 4 do {
    if (_stagingPos isEqualTo []) then {
        private _angle = random 360;
        private _dist  = 500 + random 300;
        private _seed  = _objPos getPos [_dist, _angle];
        private _roads = _seed nearRoads 400;
        if (_roads isNotEqualTo []) then {
            _stagingPos = getPosATL (selectRandom _roads);
        };
    };
};

// Pass 2: wider ring (300-1000 m) — looser road search
if (_stagingPos isEqualTo []) then {
    private _angle = random 360;
    private _dist  = 300 + random 700;
    private _seed  = _objPos getPos [_dist, _angle];
    private _roads = _seed nearRoads 800;
    if (_roads isNotEqualTo []) then {
        _stagingPos = getPosATL (selectRandom _roads);
    };
};

// Fallback: just use the random ring point off-road
if (_stagingPos isEqualTo []) then {
    private _angle = random 360;
    private _dist  = 500 + random 300;
    _stagingPos = _objPos getPos [_dist, _angle];
};

_stagingPos
