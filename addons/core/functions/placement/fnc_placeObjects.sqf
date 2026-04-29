#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_placeObjects
 * Description:
 *     Dispatcher for object archetype placement. Resolves an archetype by
 *     name (or accepts an inline archetype hashmap), picks a classname from
 *     its pool, resolves its count, and routes to the matching placement
 *     strategy:
 *
 *       "INTERIOR_FLOOR" -> fnc_placeInterior
 *       "OUTDOOR_PILE"   -> fnc_placeOutdoorPile
 *
 *     The raid generator calls this once per object spec in its config.
 *     Inline overrides (count, classname, anchorPos, building) flow through
 *     to the strategy.
 *
 * Arguments:
 *     0: _spec <HASHMAP> - Placement request:
 *        "archetype"      <STRING>   Archetype name (e.g. "INTEL_LAPTOP")
 *                                    OR
 *        "archetypeData"  <HASHMAP>  Inline archetype hashmap
 *
 *        Optional overrides:
 *        "count"          <NUMBER|ARRAY> Override archetype count.
 *        "classname"      <STRING>   Force a specific classname (skips pool).
 *        "building"       <OBJECT>   Force interior placement here.
 *        "anchorPos"      <ARRAY>    Force outdoor anchor here.
 *        "spread"         <NUMBER>   Outdoor cluster spread.
 *     1: _location <HASHMAP> - Location object
 *     2: _ao <HASHMAP> - Populated AO
 *
 * Return Value:
 *     <HASHMAP>:
 *       "objects"           <ARRAY>   Placed objects
 *       "archetype"         <STRING>  Archetype name (or "" for inline)
 *       "destroyable"       <BOOL>    From archetype
 *       "interactable"      <BOOL>    From archetype
 *       "interactionResult" <STRING>  From archetype
 *
 * Example:
 *     private _result = [
 *         createHashMapFromArray [["archetype", "SUPPLY_CACHE"]],
 *         _location, _ao
 *     ] call DSC_core_fnc_placeObjects;
 *     _aoUnits append (_result get "objects");
 */

params [
    ["_spec", createHashMap, [createHashMap]],
    ["_location", createHashMap, [createHashMap]],
    ["_ao", createHashMap, [createHashMap]]
];

// ----------------------------------------------------------------------------
// Resolve archetype data
// ----------------------------------------------------------------------------
private _archetypeName = _spec getOrDefault ["archetype", ""];
private _archetype = _spec getOrDefault ["archetypeData", createHashMap];

if (_archetype isEqualTo createHashMap && _archetypeName != "") then {
    private _registry = call DSC_core_fnc_getObjectArchetypes;
    _archetype = _registry getOrDefault [_archetypeName, createHashMap];
};

if (_archetype isEqualTo createHashMap) exitWith {
    diag_log format ["DSC: placeObjects - unknown archetype '%1'", _archetypeName];
    createHashMapFromArray [
        ["objects", []],
        ["archetype", _archetypeName],
        ["destroyable", false],
        ["interactable", false],
        ["interactionResult", ""]
    ]
};

// ----------------------------------------------------------------------------
// Resolve classname
// ----------------------------------------------------------------------------
private _classname = _spec getOrDefault ["classname", ""];
if (_classname isEqualTo "") then {
    private _pool = _archetype getOrDefault ["classnames", []];
    if (_pool isNotEqualTo []) then {
        // Filter to classes that actually exist (mod compatibility)
        private _valid = _pool select { isClass (configFile >> "CfgVehicles" >> _x) };
        if (_valid isNotEqualTo []) then {
            _classname = selectRandom _valid;
        } else {
            _classname = selectRandom _pool;
        };
    };
};

// ----------------------------------------------------------------------------
// Resolve count (number or [min, max])
// ----------------------------------------------------------------------------
private _countSpec = _spec getOrDefault ["count", _archetype getOrDefault ["count", 1]];
private _count = if (_countSpec isEqualType []) then {
    (_countSpec select 0) + (floor (random ((_countSpec select 1) - (_countSpec select 0) + 1)))
} else {
    _countSpec
};

private _zOffset = _archetype getOrDefault ["zOffset", 0];
private _placement = _archetype getOrDefault ["placement", "INTERIOR_FLOOR"];

private _strategySpec = createHashMapFromArray [
    ["classname", _classname],
    ["count", _count],
    ["zOffset", _zOffset]
];

// Forward optional overrides to the strategy
private _strategyConfig = createHashMap;
{
    if (_x in _spec) then { _strategyConfig set [_x, _spec get _x] };
} forEach ["building", "buildingCandidates", "anchorPos", "spread"];

// ----------------------------------------------------------------------------
// Dispatch to placement strategy
// ----------------------------------------------------------------------------
private _objects = switch (_placement) do {
    case "INTERIOR_FLOOR": {
        [_strategySpec, _location, _ao, _strategyConfig] call DSC_core_fnc_placeInterior
    };
    case "OUTDOOR_PILE": {
        [_strategySpec, _location, _ao, _strategyConfig] call DSC_core_fnc_placeOutdoorPile
    };
    default {
        diag_log format ["DSC: placeObjects - unknown placement strategy '%1' for archetype '%2'", _placement, _archetypeName];
        []
    };
};

createHashMapFromArray [
    ["objects", _objects],
    ["archetype", _archetypeName],
    ["destroyable", _archetype getOrDefault ["destroyable", false]],
    ["interactable", _archetype getOrDefault ["interactable", false]],
    ["interactionResult", _archetype getOrDefault ["interactionResult", ""]]
]
