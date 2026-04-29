#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_placeOnGround
 * Description:
 *     Placement strategy: spawn a unit on the ground (sitting, kneeling,
 *     or prone) inside a building or at a building edge. Used for hostages,
 *     captives, surrendered prisoners.
 *
 *     Building selection priority:
 *       1. AO's first garrisonCluster anchor (preferred — keeps captives
 *          near the existing garrison so the player has to clear it)
 *       2. Any location structure with buildingPos slots
 *
 *     Placement priority:
 *       1. Random buildingPos -1 slot inside the building
 *       2. Position 2m from a random building edge as fallback
 *       3. Building anchor center as last resort
 *
 * Arguments:
 *     0: _archetype <HASHMAP> - Placement parameters:
 *        "unitClass"    <STRING>  Resolved classname (required)
 *        "side"         <SIDE>    Side for the fresh group (default civilian)
 *        "stance"       <STRING>  "SIT" | "KNEEL" | "DOWN" (default "SIT")
 *     1: _location <HASHMAP> - Location object
 *     2: _ao <HASHMAP> - Populated AO
 *
 * Return Value:
 *     <HASHMAP>:
 *        "unit"           <OBJECT>
 *        "building"       <OBJECT>
 *        "position"       <ARRAY>
 *        "group"          <GROUP>
 *        "withBodyguards" <BOOL>     Always false
 *        "fallback"       <STRING>   "interior" | "edge" | "center" | "none"
 */

params [
    ["_archetype", createHashMap, [createHashMap]],
    ["_location", createHashMap, [createHashMap]],
    ["_ao", createHashMap, [createHashMap]]
];

private _unitClass = _archetype getOrDefault ["unitClass", ""];
private _side = _archetype getOrDefault ["side", civilian];
private _stance = _archetype getOrDefault ["stance", "SIT"];

if (_unitClass isEqualTo "") exitWith {
    diag_log "DSC: placeOnGround called without unitClass";
    createHashMapFromArray [
        ["unit", objNull], ["building", objNull], ["position", [0,0,0]],
        ["group", grpNull], ["withBodyguards", false], ["fallback", "none"]
    ]
};

// ----------------------------------------------------------------------------
// Pick a building
// ----------------------------------------------------------------------------
private _candidates = [];
private _clusters = _ao getOrDefault ["garrisonClusters", []];
{
    _candidates append (_x getOrDefault ["buildings", []]);
} forEach _clusters;

if (_candidates isEqualTo []) then {
    _candidates = _location getOrDefault ["structures", []];
};

private _candidatesWithPos = _candidates select { (_x buildingPos -1) isNotEqualTo [] };

private _building = objNull;
private _pos = [0,0,0];
private _fallback = "";

if (_candidatesWithPos isNotEqualTo []) then {
    _building = selectRandom _candidatesWithPos;
    _pos = selectRandom (_building buildingPos -1);
    _fallback = "interior";
} else {
    if (_candidates isNotEqualTo []) then {
        _building = selectRandom _candidates;
        // 2m off a random side of the building
        _pos = (getPos _building) getPos [2.5, random 360];
        _fallback = "edge";
    } else {
        _pos = _location getOrDefault ["position", [0,0,0]];
        _fallback = "center";
    };
};

// ----------------------------------------------------------------------------
// Spawn unit
// ----------------------------------------------------------------------------
private _group = createGroup [_side, true];
private _unit = _group createUnit [_unitClass, _pos, [], 0, "NONE"];
_unit setPos _pos;

switch (_stance) do {
    case "SIT":   { _unit setUnitPos "MIDDLE" };
    case "KNEEL": { _unit setUnitPos "MIDDLE" };
    case "DOWN":  { _unit setUnitPos "DOWN" };
    default      { _unit setUnitPos "MIDDLE" };
};

_unit disableAI "PATH";
_unit setDir random 360;

diag_log format ["DSC: placeOnGround - %1 path: %2 in %3", _stance, _fallback, _building];

createHashMapFromArray [
    ["unit", _unit],
    ["building", _building],
    ["position", _pos],
    ["group", _group],
    ["withBodyguards", false],
    ["fallback", _fallback]
]
