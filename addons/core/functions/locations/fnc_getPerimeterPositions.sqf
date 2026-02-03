#include "script_component.hpp"
/*
 * Gets perimeter positions around a structure's bounding box.
 * 
 * Calculates the four corner positions of a structure's bounding box
 * in world coordinates, suitable for placing guards or sentries.
 * 
 * Arguments:
 *   0: Structure object <OBJECT>
 * 
 * Returns:
 *   Array of four position arrays (corner positions)
 * 
 * Example:
 *   private _corners = [_building] call DSC_core_fnc_getPerimeterPositions;
 */

params ["_struct"];

private _bbox = boundingBoxReal _struct;
private _min = _bbox select 0;
private _max = _bbox select 1;
private _corners = [
    _struct modelToWorld [_min select 0, _min select 1, 0],
    _struct modelToWorld [_max select 0, _min select 1, 0],
    _struct modelToWorld [_min select 0, _max select 1, 0],
    _struct modelToWorld [_max select 0, _max select 1, 0]
];

_corners;
