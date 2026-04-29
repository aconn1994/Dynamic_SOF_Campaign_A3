#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_placeOutdoorPile
 * Description:
 *     Object placement strategy: cluster N objects on the ground in a small
 *     radius near a chosen anchor point. Used for outdoor weapons crates,
 *     supply piles, sabotage targets that live outside a building.
 *
 *     Anchor priority:
 *       1. Caller-provided _config "anchorPos"
 *       2. AO's first garrisonCluster center
 *       3. Location centerpoint
 *
 *     Objects are spaced randomly within "spread" radius and rejected if
 *     they collide with a structure. Falls back to placement after a few
 *     attempts even on collision to avoid infinite loops.
 *
 * Arguments:
 *     0: _spec <HASHMAP> - Placement spec:
 *        "classname"  <STRING>  Object classname (required)
 *        "count"      <NUMBER>  How many to place (default 1)
 *        "zOffset"    <NUMBER>  Vertical offset (default 0)
 *     1: _location <HASHMAP> - Location object
 *     2: _ao <HASHMAP> - Populated AO (for anchor discovery)
 *     3: _config <HASHMAP> - Optional overrides:
 *        "anchorPos"  <ARRAY>   Force anchor position
 *        "spread"     <NUMBER>  Radius of cluster spread (default 4)
 *
 * Return Value:
 *     <ARRAY> - Placed objects.
 *
 * Example:
 *     private _objects = [
 *         createHashMapFromArray [
 *             ["classname", "Box_East_WpsLaunch_F"],
 *             ["count", 2]
 *         ],
 *         _location, _ao
 *     ] call DSC_core_fnc_placeOutdoorPile;
 */

params [
    ["_spec", createHashMap, [createHashMap]],
    ["_location", createHashMap, [createHashMap]],
    ["_ao", createHashMap, [createHashMap]],
    ["_config", createHashMap, [createHashMap]]
];

private _classname = _spec getOrDefault ["classname", ""];
private _count = _spec getOrDefault ["count", 1];
private _zOffset = _spec getOrDefault ["zOffset", 0];
private _spread = _config getOrDefault ["spread", 4];

if (_classname isEqualTo "") exitWith {
    diag_log "DSC: placeOutdoorPile - empty classname";
    []
};

// ----------------------------------------------------------------------------
// Resolve anchor position
// ----------------------------------------------------------------------------
private _anchorPos = _config getOrDefault ["anchorPos", []];

if (_anchorPos isEqualTo []) then {
    private _clusters = _ao getOrDefault ["garrisonClusters", []];
    if (_clusters isNotEqualTo []) then {
        _anchorPos = (_clusters select 0) getOrDefault ["center", []];
    };
};

if (_anchorPos isEqualTo []) then {
    _anchorPos = _location getOrDefault ["position", [0,0,0]];
};

// ----------------------------------------------------------------------------
// Place objects in a small cluster
// ----------------------------------------------------------------------------
private _placed = [];

for "_i" from 0 to (_count - 1) do {
    // Try a few candidate offsets, pick first non-colliding
    private _chosenPos = [];
    for "_attempt" from 0 to 3 do {
        private _angle = random 360;
        private _dist = (_spread * 0.3) + random (_spread * 0.7);
        private _candidate = [
            (_anchorPos select 0) + (_dist * sin _angle),
            (_anchorPos select 1) + (_dist * cos _angle),
            0
        ];
        // Reject if a House sits within 1m
        private _nearStruct = (nearestObjects [_candidate, ["House"], 1.5]) isNotEqualTo [];
        if (!_nearStruct) exitWith { _chosenPos = _candidate };
    };

    if (_chosenPos isEqualTo []) then {
        // Took collisions all 4 tries — drop one anyway near anchor
        _chosenPos = [(_anchorPos select 0) + (random _spread - _spread/2),
                      (_anchorPos select 1) + (random _spread - _spread/2),
                      0];
    };

    private _obj = createVehicle [_classname, _chosenPos, [], 0, "CAN_COLLIDE"];
    if (isNull _obj) then { continue };

    if (_zOffset != 0) then {
        _chosenPos = [_chosenPos select 0, _chosenPos select 1, _zOffset];
        _obj setPosATL _chosenPos;
    };
    _obj setDir random 360;
    _placed pushBack _obj;
};

diag_log format ["DSC: placeOutdoorPile - placed %1/%2 %3 around %4",
    count _placed, _count, _classname, _anchorPos];

_placed
