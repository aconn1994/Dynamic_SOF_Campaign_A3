#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_getMapStructures
 * Description:
 *     Finds structures using both nearestObjects and nearestTerrainObjects
 *     to ensure compatibility across all maps (editor-placed and terrain-baked).
 *
 * Arguments:
 *     0: _position <ARRAY> - Center position to search from
 *     1: _classNames <ARRAY> - Class names for nearestObjects (e.g. ["House", "Building"])
 *     2: _radius <NUMBER> - Search radius in meters
 *     3: _terrainTypes <ARRAY> - (Optional) Type strings for nearestTerrainObjects
 *        Defaults to broad coverage if not provided
 *
 * Return Value:
 *     <ARRAY> - Deduplicated array of structure objects
 *
 * Example:
 *     [getPos player, ["House", "Building"], 200] call DSC_core_fnc_getMapStructures
 *     [getPos player, ["House"], 200, ["BUILDING", "HOUSE"]] call DSC_core_fnc_getMapStructures
 */

params [
    ["_position", [], [[]]],
    ["_classNames", [], [[]]],
    ["_radius", 200, [0]],
    ["_terrainTypes", ["BUILDING", "HOUSE", "BUNKER", "FORTRESS", "HOSPITAL", "VIEW-TOWER", "MILITARY", "VILLAGE", "CITY"], [[]]]
];

if (_position isEqualTo [] || _classNames isEqualTo []) exitWith {
    diag_log "DSC: fnc_getMapStructures - Invalid parameters";
    []
};

private _editorObjects = nearestObjects [_position, _classNames, _radius];

private _allStructures = if (_terrainTypes isEqualTo []) then {
    _editorObjects
} else {
    private _terrainObjects = nearestTerrainObjects [_position, _terrainTypes, _radius];
    private _combined = _editorObjects + _terrainObjects;
    _combined arrayIntersect _combined
};

_allStructures
