#include "script_component.hpp"
/*
 * Places units at random positions from a list.
 * 
 * Disables AI movement and places infantry units at random positions.
 * Vehicles are tracked separately and have their engines started.
 * 
 * Arguments:
 *   0: Array of units to position <ARRAY>
 *   1: Array of available positions <ARRAY>
 *   2: Array to track spawned vehicles (modified in place) <ARRAY>
 * 
 * Returns:
 *   Nothing
 * 
 * Example:
 *   private _vehicles = [];
 *   [units _group, _buildingPositions, _vehicles] call DSC_core_fnc_setUnitsAtPositions;
 */

params ["_units", "_positions", "_vehicles"];

{
    private _unit = vehicle _x;

    // Disable damage during positioning to prevent fall damage
    _x allowDamage false;

    _unit disableAI "MOVE";
    _unit disableAI "TARGET";
    _unit disableAI "AUTOTARGET";

    if (_unit == _x) then {
        private _randomPosition = selectRandom _positions;

        _unit setPos _randomPosition;
        _randomPosition = _randomPosition - [_randomPosition];
    } else {
        // This will handle if an actual vehicle is spawned later
        _vehicles pushBackUnique _unit;
            if (driver _unit == _x) then {
                _unit engineOn true;
            };
    };

    sleep 1;
} forEach _units;
