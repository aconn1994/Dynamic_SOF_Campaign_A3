#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_queryLocationPOIs
 * Description:
 *     Pure query over a scanned location's POI indices (Session 02, Ambient
 *     World Overhaul — docs/overhauls/ambient_world/
 *     session_02_location_poi_registry.md). Reads only the "poiBySubtype" /
 *     "poiByCategory" / "poiByFlag" indices built by fnc_scanLocations Stage
 *     4 — no world query, no `typeOf` pass, no missionNamespace reads.
 *
 *     Supported filter keys (all optional, combined as AND across keys):
 *         "subtype"      <STRING>          - single subtype
 *         "subtypes"     <ARRAY of STRING> - OR'd together with "subtype"
 *         "category"     <STRING>          - POI category
 *         "flag"         <STRING>          - single required flag
 *         "flags"        <ARRAY of STRING> - ALL of these flags required
 *         "anyFlag"      <ARRAY of STRING> - ANY of these flags required
 *         "excludeFlags" <ARRAY of STRING> - none of these flags allowed
 *         "near"         <ARRAY> [pos, radius] - distance2D gate
 *         "limit"        <NUMBER>          - cap result count (after random)
 *         "random"       <BOOL>            - shuffle order, does not change
 *                                            the result SET
 *
 *     A location scanned before Session 02 (no "poiBySubtype" key) degrades
 *     to [] with one WARNING, never a crash. An index miss (unknown subtype/
 *     category/flag) degrades to [] silently — "this location can't host
 *     that" is not an error.
 *
 * Arguments:
 *     0: _location <HASHMAP> - A location hashmap from fnc_scanLocations.
 *     1: _filter <HASHMAP> - Filter per the keys above (default: no filter,
 *        returns every POI in the location).
 *
 * Return Value:
 *     <ARRAY> - Matching POI objects. [] on no match.
 *
 * Example:
 *     private _schools = [_location, createHashMapFromArray [["subtype", "school"]]] call DSC_core_fnc_queryLocationPOIs;
 *     private _hvtSpots = [_location, createHashMapFromArray [["flags", ["hvt_suitable"]], ["excludeFlags", ["sentry_only"]]]] call DSC_core_fnc_queryLocationPOIs;
 */

params [
    ["_location", createHashMap, [createHashMap]],
    ["_filter", createHashMap, [createHashMap]]
];

if !("poiBySubtype" in _location) exitWith {
    WARNING("queryLocationPOIs - location has no poiBySubtype index (scanned before Session 02?), returning []");
    []
};

private _poiBySubtype = _location getOrDefault ["poiBySubtype", createHashMap];
private _poiByCategory = _location getOrDefault ["poiByCategory", createHashMap];
private _poiByFlag = _location getOrDefault ["poiByFlag", createHashMap];

// ----------------------------------------------------------------------
// Seed the candidate set: subtype(s) > category > "all POIs".
// ----------------------------------------------------------------------
private _subtypesWanted = [];
if ("subtype" in _filter) then { _subtypesWanted pushBackUnique (_filter get "subtype") };
if ("subtypes" in _filter) then { { _subtypesWanted pushBackUnique _x } forEach (_filter get "subtypes") };

private _candidates = [];

if (_subtypesWanted isNotEqualTo []) then {
    { _candidates append (_poiBySubtype getOrDefault [_x, []]) } forEach _subtypesWanted;
    if ("category" in _filter) then {
        private _catSet = _poiByCategory getOrDefault [(_filter get "category"), []];
        _candidates = _candidates select { _x in _catSet };
    };
} else {
    if ("category" in _filter) then {
        _candidates = +(_poiByCategory getOrDefault [(_filter get "category"), []]);
    } else {
        { _candidates append _y } forEach _poiBySubtype;
    };
};

// ----------------------------------------------------------------------
// Flags — "flags"/"flag" is ALL-of, "anyFlag" is ANY-of, "excludeFlags"
// removes matches.
// ----------------------------------------------------------------------
private _flagsWanted = [];
if ("flag" in _filter) then { _flagsWanted pushBackUnique (_filter get "flag") };
if ("flags" in _filter) then { { _flagsWanted pushBackUnique _x } forEach (_filter get "flags") };

{
    private _flagName = _x;
    private _flagSet = _poiByFlag getOrDefault [_flagName, []];
    _candidates = _candidates select { _x in _flagSet };
} forEach _flagsWanted;

if ("anyFlag" in _filter) then {
    private _unionSet = [];
    { _unionSet append (_poiByFlag getOrDefault [_x, []]) } forEach (_filter get "anyFlag");
    _candidates = _candidates select { _x in _unionSet };
};

if ("excludeFlags" in _filter) then {
    private _exSet = [];
    { _exSet append (_poiByFlag getOrDefault [_x, []]) } forEach (_filter get "excludeFlags");
    _candidates = _candidates select { !(_x in _exSet) };
};

// ----------------------------------------------------------------------
// Distance gate.
// ----------------------------------------------------------------------
if ("near" in _filter) then {
    (_filter get "near") params [["_nearPos", [0, 0, 0], [[]]], ["_nearRadius", 0, [0]]];
    _candidates = _candidates select {
        private _isLocatable = ((_x isEqualType objNull) && {!isNull _x}) || (_x isEqualType []);
        _isLocatable && {(_x distance2D _nearPos) < _nearRadius}
    };
};

// ----------------------------------------------------------------------
// Random order (set-preserving), then limit.
// ----------------------------------------------------------------------
if (_filter getOrDefault ["random", false]) then {
    private _pool = +_candidates;
    private _shuffled = [];
    while { count _pool > 0 } do {
        private _i = floor (random (count _pool));
        _shuffled pushBack (_pool deleteAt _i);
    };
    _candidates = _shuffled;
};

if ("limit" in _filter) then {
    private _limit = _filter get "limit";
    _candidates = _candidates select [0, (_limit min (count _candidates))];
};

_candidates
