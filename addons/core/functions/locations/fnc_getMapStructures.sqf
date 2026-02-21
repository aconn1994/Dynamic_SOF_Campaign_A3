#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_getMapStructures
 * Description:
 *     Finds structures using both nearestObjects and nearestTerrainObjects
 *     to ensure compatibility across all maps (editor-placed and terrain-baked).
 *
 * Arguments:
 *     0: _position <ARRAY> - Center position to search from
 *     1: _types <ARRAY> - Array of structure type strings
 *     2: _radius <NUMBER> - Search radius in meters
 *
 * Return Value:
 *     <ARRAY> - Deduplicated array of structure objects
 *
 * Example:
 *     [getPos player, ["BUILDING", "HOUSE"], 200] call DSC_core_fnc_getMapStructures
 */

params [
    ["_position", [], [[]]],
    ["_types", [], [[]]],
    ["_radius", 200, [0]]
];

if (_position isEqualTo [] || _types isEqualTo []) exitWith {
    diag_log "DSC: fnc_getMapStructures - Invalid parameters";
    []
};

// Get editor-placed objects and terrain-baked objects
private _editorObjects = nearestObjects [_position, _types, _radius];
private _terrainObjects = nearestTerrainObjects [_position, _types, _radius];

// Combine and remove duplicates
private _allStructures = _editorObjects + _terrainObjects;
_allStructures = _allStructures arrayIntersect _allStructures;

_allStructures
