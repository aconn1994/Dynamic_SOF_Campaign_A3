#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_c2InitSignalSources
 * Description:
 *     Sprint F.2 — wires up the event handlers that feed the network.
 *
 *     Deliberately built from a SMALL number of server-side handlers rather
 *     than per-unit event handlers. The existing combat-activation code uses
 *     per-unit `FiredNear`, which is fine for a few dozen units in a mission
 *     AO, but the presence manager can have 150 units standing at once and
 *     the roving manager adds more. Two mission handlers plus one handler
 *     per player scales flat regardless of how busy the world is.
 *
 *     Sources wired here:
 *
 *       1. `EntityKilled` (mission EH, server)
 *          The single richest signal in the game. A death tells us:
 *            - a noise event happened (graded by what died and how)
 *            - if the victim was C2-stamped, its group is in contact NOW
 *            - if a whole element is gone, that is a SILENCE candidate
 *          Also the only reliable way to detect "the player is shooting at
 *          my patrol" without polling.
 *
 *       2. `Fired` (per player, local -> server event)
 *          Catches the case where the player opens fire and MISSES, which
 *          `EntityKilled` cannot see. Suppressor state is read here, on the
 *          client that actually owns the weapon, because muzzle attachment
 *          data is unreliable across the network.
 *          Throttled per player so a machine gun burst is one noise event
 *          rather than thirty.
 *
 *       3. Contact scan (in the C2 tick, see fnc_initC2Network)
 *          Backstop for a standoff where nobody has died or fired yet but
 *          groups know about each other.
 *
 * Arguments:
 *     None
 *
 * Return Value:
 *     None
 */

if (!isServer) exitWith {};

// ============================================================================
// CBA event: client-reported weapon discharge
// ============================================================================
// Clients own suppressor truth, so they classify and the server acts.
["DSC_c2_playerFired", {
    params [["_pos", [], [[]]], ["_noiseType", "SMALL_ARMS", [""]]];
    if (_pos isEqualTo []) exitWith {};
    [_pos, _noiseType] call DSC_core_fnc_c2NoiseEvent;
}] call CBA_fnc_addEventHandler;

// ============================================================================
// EntityKilled — noise + contact detection
// ============================================================================
addMissionEventHandler ["EntityKilled", {
    params ["_killed", "_killer", "_instigator"];

    if (isNull _killed) exitWith {};

    // ------------------------------------------------------------------
    // Exclusions — things that "die" without making any noise
    // ------------------------------------------------------------------
    // A deployed parachute is a vehicle (ParachuteBase -> Air ->
    // AllVehicles), and it is DESTROYED rather than deleted when the
    // jumper lands. Ungated, that graded as VEHICLE_KILL and broadcast a
    // 3500 m EXPLOSION: every HALO insertion turned the surrounding
    // installations RED before the player had fired a single shot, which
    // is the exact opposite of a covert infil.
    //
    // Weapon holders and ground-holder props are the same class of
    // false positive — engine bookkeeping objects, not events.
    private _silentClasses = ["ParachuteBase", "WeaponHolder", "WeaponHolderSimulated", "GroundWeaponHolder"];
    private _isSilent = false;
    {
        if (_killed isKindOf _x) exitWith { _isSilent = true };
    } forEach _silentClasses;
    if (_isSilent) exitWith {};

    private _pos = getPosATL _killed;

    // ------------------------------------------------------------------
    // TEMPORARY DIAGNOSTIC (August 2026) — fratricide detector
    // ------------------------------------------------------------------
    // Remove with the faction overhaul (Plan A). See .crush/faction-overhaul.md.
    //
    // !! `side` AND `rating` ARE USELESS ON A DEAD UNIT !!
    //
    // Inside EntityKilled the victim is already dead, and for a dead unit the
    // engine returns `side` = CIVILIAN and `rating` = 0, regardless of what
    // the unit was in life. The first version of this probe read them anyway
    // and consequently reported EVERY kill as
    // "FRATRICIDE-ALLIED (friend=1)" — because it was comparing the killer's
    // real side against a corpse's civilian placeholder, and east->civilian
    // is friendly. Ten completely legitimate west-kills-east engagements were
    // flagged as fratricide. The probe was the bug.
    //
    // `side (group _killed)` DOES survive the death, because the group object
    // outlives the unit, so the victim's side is read from its group. Victim
    // rating is not recoverable post-mortem and is not printed.
    private _shooterD = _instigator;
    if (isNull _shooterD) then { _shooterD = _killer };

    private _vSide = side (group _killed);
    private _vCls  = typeOf _killed;
    private _vFac  = getText (configFile >> "CfgVehicles" >> _vCls >> "faction");

    if (isNull _shooterD) then {
        diag_log format [
            "DSCDIAG KILL  victim=%1(grpSide=%2/%3) killer=NULL — collateral/environment, not AI targeting",
            _vCls, _vSide, _vFac
        ];
    } else {
        private _kSide  = side (group _shooterD);
        private _kCls   = typeOf _shooterD;
        private _kFac   = getText (configFile >> "CfgVehicles" >> _kCls >> "faction");
        private _friend = _kSide getFriend _vSide;

        // Killer is usually still alive, so its rating IS meaningful. Worth
        // printing: a friendly-fire or civilian kill drives it toward the
        // -2000 renegade threshold, and that applies to the PLAYER'S squad
        // too (they get no addRating protection from us).
        private _kRating = round (rating _shooterD);

        private _verdict = "cross-side (expected)";
        if (_shooterD isEqualTo _killed) then {
            _verdict = "SELF-KILL (explosive/fall)";
        } else {
            if (_kSide isEqualTo _vSide) then {
                _verdict = "*** FRATRICIDE-SAMESIDE ***";
            } else {
                if (_friend >= 0.6) then {
                    _verdict = "*** FRATRICIDE-ALLIED (check setFriend symmetry) ***";
                };
            };
            if (_kSide isEqualTo sideEnemy || {_vSide isEqualTo sideEnemy}) then {
                _verdict = _verdict + " +RENEGADE-INVOLVED";
            };
        };

        if (_kRating < -1200) then {
            _verdict = _verdict + format [" !! KILLER NEAR RENEGADE (%1) !!", _kRating];
        };

        diag_log format [
            "DSCDIAG KILL  killer=%1(%2/%3 r=%4 grp=%5) victim=%6(%7/%8 grp=%9) friend=%10 %11",
            _kCls, _kSide, _kFac, _kRating, groupId (group _shooterD),
            _vCls, _vSide, _vFac, groupId (group _killed),
            _friend, _verdict
        ];
    };

    // --- Noise grading ----------------------------------------------------
    // A destroyed vehicle is a fireball; a dead infantryman is the gunshot
    // that killed him. We grade on the victim because that is what makes the
    // sound, and because it lets a satchel on an empty truck be as loud as
    // it should be.
    private _noiseType = "SMALL_ARMS";
    if (_killed isKindOf "AllVehicles" && {!(_killed isKindOf "Man")}) then {
        _noiseType = "VEHICLE_KILL";
    } else {
        // Suppressed weapon on the killer downgrades to near-silent. Read
        // defensively — the killer may be dead, null, or a vehicle.
        private _shooter = _instigator;
        if (isNull _shooter) then { _shooter = _killer };
        if (!isNull _shooter && {_shooter isKindOf "Man"}) then {
            private _muzzle = currentMuzzle _shooter;
            private _acc = _shooter weaponAccessories _muzzle;
            if (_acc isNotEqualTo [] && {(_acc select 0) != ""}) then {
                _noiseType = "SUPPRESSED";
            };
        };
    };

    [_pos, _noiseType] call DSC_core_fnc_c2NoiseEvent;

    // --- Contact detection on the victim's group ---------------------------
    // Losing a man is unambiguous proof of contact. Start the report timer
    // immediately; fnc_c2ContactReport guards against duplicates itself.
    private _victimGroup = group _killed;
    if (!isNull _victimGroup) then {
        private _parent = _victimGroup getVariable ["DSC_c2Parent", ""];
        if (_parent != "") then {
            [_victimGroup] spawn DSC_core_fnc_c2ContactReport;
        };
    };
}];

INFO("c2 signal sources wired (EntityKilled + client fired relay)");
