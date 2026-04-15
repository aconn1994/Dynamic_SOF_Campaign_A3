#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_handlePlayerDown
 * Description:
 *     Handles player incapacitation. Sends assigned medic to revive.
 *     Works with both vanilla damage model and ACE Medical.
 *
 *     Vanilla: Intercepts fatal damage, sets unconscious, heals with setDamage 0
 *     ACE: Listens for ACE unconscious event, heals with ace fullHeal
 *
 *     Should be spawned, not called (contains sleep/waitUntil).
 *     Works in SP, hosted MP, and dedicated server.
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

private _hasACEMedical = missionNamespace getVariable ["DSC_hasACEMedical", false];

// ============================================================================
// Enter incapacitated state
// ============================================================================
if (!_hasACEMedical) then {
    _player allowDamage false;
    _player setUnconscious true;
};

[format ["%1 is down!", name _player]] remoteExec ["systemChat", 0];
diag_log format ["DSC: Player %1 is incapacitated (ACE: %2)", name _player, _hasACEMedical];

// ============================================================================
// Find medic
// ============================================================================
private _medic = _player getVariable ["DSC_assignedMedic", objNull];

if (isNull _medic || !alive _medic) then {
    diag_log "DSC: No medic available - respawning at base after timeout";
    ["No medic available.\nRespawning at base in 15 seconds..."] remoteExec ["hint", _player];
    
    sleep 15;
    
    if (_hasACEMedical) then {
        [_player] call ace_medical_treatment_fnc_fullHealLocal;
    } else {
        _player setUnconscious false;
        _player setDamage 0;
        _player allowDamage true;
    };
    
    _player setVariable ["DSC_isDown", false, true];
    _player setPos ((getPos jointOperationCenter) getPos [3, random 360]);
    
    ["Respawned at base."] remoteExec ["hint", _player];
} else {
    ["Medic is on the way..."] remoteExec ["hint", _player];
    
    // Order medic to move to player
    private _medicOwner = owner _medic;
    [_medic, getPos _player] remoteExec ["doMove", _medicOwner];
    [_medic, "FULL"] remoteExec ["setSpeedMode", _medicOwner];
    [_medic, "CARELESS"] remoteExec ["setBehaviour", _medicOwner];
    
    // Wait for medic to arrive (within 3m) or timeout after 120s
    private _timeout = time + 120;
    waitUntil {
        sleep 1;
        [_medic, getPos _player] remoteExec ["doMove", _medicOwner];
        (_medic distance2D _player < 3) || (time > _timeout) || !alive _medic
    };
    
    if (!alive _medic || time > _timeout) exitWith {
        diag_log "DSC: Medic failed to reach player - respawning at base";
        ["Medic could not reach you.\nRespawning at base..."] remoteExec ["hint", _player];
        
        sleep 3;
        
        if (_hasACEMedical) then {
            [_player] call ace_medical_treatment_fnc_fullHealLocal;
        } else {
            _player setUnconscious false;
            _player setDamage 0;
            _player allowDamage true;
        };
        
        _player setVariable ["DSC_isDown", false, true];
        _player setPos ((getPos jointOperationCenter) getPos [3, random 360]);
    };
    
    // ============================================================================
    // Medic performs revive
    // ============================================================================
    diag_log "DSC: Medic arrived - performing revive";
    
    [_medic] remoteExec ["doStop", _medicOwner];
    [_medic, _medic getDir _player] remoteExec ["setDir", _medicOwner];
    [_medic, "AinvPknlMstpSnonWnonDnon_medic"] remoteExec ["playMoveNow", _medicOwner];
    
    ["Medic is treating you..."] remoteExec ["hint", _player];
    
    sleep 8;
    
    // Heal player (ACE or vanilla)
    if (_hasACEMedical) then {
        [_player] call ace_medical_treatment_fnc_fullHealLocal;
    } else {
        _player setUnconscious false;
        _player setDamage 0;
        _player allowDamage true;
    };
    
    _player setVariable ["DSC_isDown", false, true];
    
    // Reset medic behavior
    [_medic, ""] remoteExec ["playMoveNow", _medicOwner];
    [_medic, leader group _medic] remoteExec ["doFollow", _medicOwner];
    [_medic, "NORMAL"] remoteExec ["setSpeedMode", _medicOwner];
    [_medic, "AWARE"] remoteExec ["setBehaviour", _medicOwner];
    
    [format ["%1 has been revived!", name _player]] remoteExec ["systemChat", 0];
    ["You have been revived."] remoteExec ["hint", _player];
    
    diag_log format ["DSC: Player %1 revived by medic", name _player];
};
