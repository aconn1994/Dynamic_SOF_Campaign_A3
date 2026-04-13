#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_handlePlayerDown
 * Description:
 *     Handles player incapacitation. Instead of dying, the player goes
 *     unconscious. If a medic is assigned, the medic moves to the player
 *     and performs a revive. If no medic, player respawns at base after timeout.
 *
 *     Called from a HandleDamage EH when fatal damage is detected.
 *     Should be spawned, not called (contains sleep/waitUntil).
 *
 * Arguments:
 *     0: _player <OBJECT> - The downed player
 *
 * Return Value:
 *     None
 *
 * Example:
 *     [player] spawn DSC_core_fnc_handlePlayerDown;
 */

params [
    ["_player", objNull, [objNull]]
];

if (isNull _player) exitWith {};
if (_player getVariable ["DSC_isDown", false]) exitWith {};

_player setVariable ["DSC_isDown", true, true];

// ============================================================================
// Enter incapacitated state
// ============================================================================
_player allowDamage false;
_player setUnconscious true;

systemChat format ["%1 is down!", name _player];
diag_log format ["DSC: Player %1 is incapacitated", name _player];

// ============================================================================
// Find medic
// ============================================================================
private _medic = _player getVariable ["DSC_assignedMedic", objNull];

if (isNull _medic || !alive _medic) then {
    // No medic available - respawn at base after timeout
    diag_log "DSC: No medic available - respawning at base after timeout";
    hint "No medic available.\nRespawning at base in 15 seconds...";
    
    sleep 15;
    
    _player setUnconscious false;
    _player setDamage 0;
    _player allowDamage true;
    _player setVariable ["DSC_isDown", false, true];
    _player setPos ((getPos jointOperationCenter) getPos [3, random 360]);
    
    hint "Respawned at base.";
} else {
    // Medic available - send to revive
    hint "Medic is on the way...";
    
    // Order medic to move to player
    _medic doMove (getPos _player);
    _medic setSpeedMode "FULL";
    _medic setBehaviour "CARELESS";
    
    // Wait for medic to arrive (within 3m) or timeout after 120s
    private _timeout = time + 120;
    waitUntil {
        sleep 1;
        _medic doMove (getPos _player);
        (_medic distance2D _player < 3) || (time > _timeout) || !alive _medic
    };
    
    if (!alive _medic || time > _timeout) exitWith {
        // Medic died or took too long - respawn at base
        diag_log "DSC: Medic failed to reach player - respawning at base";
        hint "Medic could not reach you.\nRespawning at base...";
        
        sleep 3;
        
        _player setUnconscious false;
        _player setDamage 0;
        _player allowDamage true;
        _player setVariable ["DSC_isDown", false, true];
        _player setPos ((getPos jointOperationCenter) getPos [3, random 360]);
    };
    
    // ============================================================================
    // Medic performs revive
    // ============================================================================
    diag_log "DSC: Medic arrived - performing revive";
    
    // Stop medic and face patient
    doStop _medic;
    _medic setDir (_medic getDir _player);
    
    // Play healing animation
    _medic playMoveNow "AinvPknlMstpSnonWnonDnon_medic";
    
    hint "Medic is treating you...";
    
    // Simulate treatment time
    sleep 8;
    
    // Revive player
    _player setUnconscious false;
    _player setDamage 0;
    _player allowDamage true;
    _player setVariable ["DSC_isDown", false, true];
    
    // Reset medic behavior
    _medic playMoveNow "";
    _medic doFollow leader group _medic;
    _medic setSpeedMode "NORMAL";
    _medic setBehaviour "AWARE";
    
    systemChat format ["%1 has been revived!", name _player];
    hint "You have been revived.";
    
    diag_log format ["DSC: Player %1 revived by medic", name _player];
};
