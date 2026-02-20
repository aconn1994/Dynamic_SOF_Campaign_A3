#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_convergePatrols
 * Description:
 *     Orders patrol groups to converge on a position to defend it.
 *     Clears existing waypoints and creates new SAD waypoint at target.
 *
 * Arguments:
 *     0: _patrolGroups <ARRAY> - Array of patrol groups
 *     1: _targetPos <ARRAY> - Position to converge on
 *     2: _config <HASHMAP> - Optional configuration
 *        - "radius": Spread radius around target (default: 50)
 *        - "behaviour": Group behaviour (default: "AWARE")
 *        - "combatMode": Combat mode (default: "RED")
 *        - "speed": Movement speed (default: "FULL")
 *
 * Return Value:
 *     <BOOL> - True if any groups were redirected
 *
 * Example:
 *     [_patrols, _hvtPos] call DSC_core_fnc_convergePatrols
 */

params [
    ["_patrolGroups", [], [[]]],
    ["_targetPos", [], [[]]],
    ["_config", createHashMap, [createHashMap]]
];

if (_patrolGroups isEqualTo [] || _targetPos isEqualTo []) exitWith {
    diag_log "DSC: fnc_convergePatrols - Invalid parameters";
    false
};

private _radius = _config getOrDefault ["radius", 50];
private _behaviour = _config getOrDefault ["behaviour", "AWARE"];
private _combatMode = _config getOrDefault ["combatMode", "RED"];
private _speed = _config getOrDefault ["speed", "FULL"];

private _redirectedCount = 0;

{
    private _group = _x;
    
    if (isNull _group) then { continue };
    if (!([_group] call DSC_core_fnc_groupActive)) then { continue };
    
    // Clear existing waypoints
    while { (waypoints _group) isNotEqualTo [] } do {
        deleteWaypoint [_group, 0];
    };
    
    // Set group behavior for combat response
    _group setBehaviour _behaviour;
    _group setCombatMode _combatMode;
    _group setSpeedMode _speed;
    
    // Create converge waypoint with some spread
    private _offsetPos = _targetPos getPos [random _radius, random 360];
    private _wp = _group addWaypoint [_offsetPos, 20];
    _wp setWaypointType "SAD";
    _wp setWaypointBehaviour _behaviour;
    _wp setWaypointCombatMode _combatMode;
    _wp setWaypointSpeed _speed;
    
    _group setCurrentWaypoint _wp;
    
    _redirectedCount = _redirectedCount + 1;
    
    diag_log format ["DSC: Patrol %1 converging on %2", _group, _targetPos];
} forEach _patrolGroups;

diag_log format ["DSC: fnc_convergePatrols - Redirected %1 patrols to defend position", _redirectedCount];

_redirectedCount > 0
