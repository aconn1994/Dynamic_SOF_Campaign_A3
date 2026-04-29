#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_placeInterior
 * Description:
 *     Object placement strategy: drop N objects inside a building on random
 *     buildingPos -1 slots. Used for caches, intel laptops, bomb parts,
 *     documents — anything that lives on the inside of a structure.
 *
 *     Building selection priority:
 *       1. Caller-provided _config "building"
 *       2. Caller-provided _config "buildingCandidates" (random pick)
 *       3. AO's first garrisonCluster anchor + nearby buildings
 *       4. Any location structure with buildingPos slots
 *
 *     Returns objNull-free array. If no usable building is found at all,
 *     returns []. The strategy never spawns at the location centerpoint —
 *     interior placement requires an interior.
 *
 * Arguments:
 *     0: _spec <HASHMAP> - Placement spec:
 *        "classname"  <STRING>   Object classname to spawn (required)
 *        "count"      <NUMBER>   How many to place (default 1)
 *        "zOffset"    <NUMBER>   Vertical offset added on top of slot Z
 *                                (default 0)
 *     1: _location <HASHMAP> - Location object
 *     2: _ao <HASHMAP> - Populated AO (for cluster discovery)
 *     3: _config <HASHMAP> - Optional overrides:
 *        "building"           <OBJECT>  Force placement in this building
 *        "buildingCandidates" <ARRAY>   Pick random building from this list
 *
 * Return Value:
 *     <ARRAY> - Placed objects (may be shorter than count if not enough
 *               positions available).
 *
 * Example:
 *     private _objects = [
 *         createHashMapFromArray [
 *             ["classname", "Box_NATO_Ammo_F"],
 *             ["count", 5]
 *         ],
 *         _location, _ao
 *     ] call DSC_core_fnc_placeInterior;
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

if (_classname isEqualTo "") exitWith {
    diag_log "DSC: placeInterior - empty classname";
    []
};

// ----------------------------------------------------------------------------
// Resolve candidate buildings
// ----------------------------------------------------------------------------
private _candidates = [];

private _forcedBuilding = _config getOrDefault ["building", objNull];
if (!isNull _forcedBuilding) then {
    _candidates = [_forcedBuilding];
} else {
    private _provided = _config getOrDefault ["buildingCandidates", []];
    if (_provided isNotEqualTo []) then {
        _candidates = _provided;
    };
};

// Cluster-derived candidates from AO
if (_candidates isEqualTo []) then {
    private _clusters = _ao getOrDefault ["garrisonClusters", []];
    {
        _candidates append (_x getOrDefault ["buildings", []]);
    } forEach _clusters;
};

// Final fallback: any location structure
if (_candidates isEqualTo []) then {
    _candidates = _location getOrDefault ["structures", []];
};

// Filter to buildings that actually have interior positions
_candidates = _candidates select { (_x buildingPos -1) isNotEqualTo [] };

if (_candidates isEqualTo []) exitWith {
    diag_log format ["DSC: placeInterior - no building with positions for %1", _classname];
    []
};

// ----------------------------------------------------------------------------
// Place objects
// ----------------------------------------------------------------------------
private _placed = [];
private _attempts = 0;
private _maxAttempts = _count * 4;

while { count _placed < _count && _attempts < _maxAttempts } do {
    _attempts = _attempts + 1;

    private _building = selectRandom _candidates;
    private _positions = _building buildingPos -1;
    if (_positions isEqualTo []) then { continue };

    private _pos = selectRandom _positions;
    if (_zOffset != 0) then {
        _pos = [_pos select 0, _pos select 1, (_pos select 2) + _zOffset];
    };

    private _obj = createVehicle [_classname, _pos, [], 0, "CAN_COLLIDE"];
    if (isNull _obj) then { continue };

    _obj setPosATL _pos;
    _obj setDir random 360;
    _placed pushBack _obj;
};

diag_log format ["DSC: placeInterior - placed %1/%2 %3 across %4 candidate building(s)",
    count _placed, _count, _classname, count _candidates];

_placed
