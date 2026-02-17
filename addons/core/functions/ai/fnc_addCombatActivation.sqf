#include "script_component.hpp" // TODO, NEEDS TESTINGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG

/*
 * Adds combat activation to a group - units start with path disabled,
 * and path is enabled when any unit in the group detects nearby gunfire.
 * 
 * This creates emergent behavior where groups near combat get activated
 * by spreading gunfire, while isolated groups remain unaware.
 * 
 * Arguments:
 *   0: Group <GROUP> - The group to add combat activation to
 *   1: (Optional) Reaction delay <NUMBER> - Seconds before enabling path (default: 0.5)
 * 
 * Returns:
 *   None
 * 
 * Examples:
 *   [_group] call DSC_core_fnc_addCombatActivation;
 *   [_group, 1.0] call DSC_core_fnc_addCombatActivation;
 */

params [
    ["_group", grpNull, [grpNull]],
    ["_reactionDelay", 0.5, [0]]
];

if (isNull _group) exitWith {
    diag_log "DSC: fnc_addCombatActivation - Null group provided";
};

private _units = units _group;

if (_units isEqualTo []) exitWith {
    diag_log "DSC: fnc_addCombatActivation - Group has no units";
};

// Disable path for all units in group
{
    _x disableAI "PATH";
} forEach _units;

// Mark group as not yet activated
_group setVariable ["DSC_combatActivated", false];

// Add FiredNear EH to each unit
{
    private _unit = _x;
    
    private _ehId = _unit addEventHandler ["FiredNear", {
        params ["_unit", "_firer", "_distance", "_weapon", "_muzzle", "_mode", "_ammo", "_gunner"];
        
        private _group = group _unit;
        
        // Check if already activated (another unit in group may have triggered first)
        if (_group getVariable ["DSC_combatActivated", false]) exitWith {};
        
        // Mark as activated
        _group setVariable ["DSC_combatActivated", true];
        
        private _reactionDelay = _group getVariable ["DSC_reactionDelay", 0.5];
        
        // Enable path for all units after reaction delay
        [{
            params ["_group"];
            
            {
                // Remove the EH from each unit
                private _ehId = _x getVariable ["DSC_combatActivationEH", -1];
                if (_ehId != -1) then {
                    _x removeEventHandler ["FiredNear", _ehId];
                    _x setVariable ["DSC_combatActivationEH", nil];
                };
                
                // Enable path
                _x enableAI "PATH";
            } forEach (units _group);
            
            diag_log format ["DSC: Combat activation triggered for group %1", _group];
            
        }, [_group], _reactionDelay] call CBA_fnc_waitAndExecute;
    }];
    
    // Store EH ID on unit for later removal
    _unit setVariable ["DSC_combatActivationEH", _ehId];
    
} forEach _units;

// Store reaction delay on group for use in EH
_group setVariable ["DSC_reactionDelay", _reactionDelay];

diag_log format ["DSC: Combat activation added to group %1 (%2 units)", _group, count _units];
