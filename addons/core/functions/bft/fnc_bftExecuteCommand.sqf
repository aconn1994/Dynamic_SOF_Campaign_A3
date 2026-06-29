#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_bftExecuteCommand
 * Description:
 *     Server-side executor for Blue Force Tracker command actions. Triggered
 *     by the CBA event "DSC_bft_command" (registered at the bottom of this
 *     file when first called) and dispatched by panel button clicks from
 *     the tablet's BFT info card.
 *
 *     Actions:
 *       "take"     — flag the group as under player command, transfer it
 *                    out of its parent system (presence zone or roving
 *                    record) into DSC_bftCommandedGroups so despawn sweeps
 *                    leave it alone. HC roster assignment (hcSetGroup) is
 *                    done client-side by the caller — HC is locality-bound
 *                    to the commander.
 *       "moveHere" — issue a fresh move order (waypoints cleared) to the
 *                    given world position with AUTOCOMBAT re-enabled (rovers
 *                    disable it for ambient feel). Re-flags as "moving".
 *       "moveObj"  — same as moveHere but targets the active mission
 *                    objective position passed in _params.
 *       "qrf"      — staging move + role flagged "QRF" + AUTOCOMBAT on.
 *       "release"  — clear role flag. Group stays in
 *                    DSC_bftCommandedGroups so BFT still tracks it. hcRemoveGroup
 *                    is done client-side by the caller.
 *
 *     The role tag (`group setVariable "DSC_bftRole"`) is the protection
 *     signal that fnc_rovingDespawnSweep and fnc_despawnPresenceZone read
 *     to skip cleanup of commandeered groups.
 *
 * Arguments:
 *     0: _netId  <STRING>  - group network id from `netId _grp`
 *     1: _action <STRING>  - one of "take"|"moveHere"|"moveObj"|"qrf"|"release"
 *     2: _params <ARRAY>   - action-specific extra data (e.g. [worldPos])
 *     3: _uid    <STRING>  - calling player's UID (for log/MP gating)
 *     4: _name   <STRING>  - calling player's name (for log)
 */

if (!isServer) exitWith {};

params [
    ["_netId",  "",            [""]],
    ["_action", "",            [""]],
    ["_params", [],            [[]]],
    ["_uid",    "",            [""]],
    ["_name",   "",            [""]]
];

private _grp = groupFromNetId _netId;
if (isNull _grp) exitWith {
    WARNING_4("bftExecuteCommand - unknown netId '%1' (action=%2) from %3 [%4]",_netId,_action,_name,_uid);
};

// ----------------------------------------------------------------------------
// Helper: remove this group from its parent presence zone / roving record so
// despawn sweeps stop reasoning about it. Called once on first "take" — after
// that the group lives in DSC_bftCommandedGroups.
// ----------------------------------------------------------------------------
private _detachFromParents = {
    params ["_g"];

    // Presence zones — strip the group from any zone's groups array
    private _zones = missionNamespace getVariable ["DSC_presenceZones", createHashMap];
    {
        private _zgrps = _y getOrDefault ["groups", []];
        private _idx = _zgrps find _g;
        if (_idx >= 0) then { _zgrps deleteAt _idx };
    } forEach _zones;

    // Roving manager — drop the record for this group
    private _active = missionNamespace getVariable ["DSC_rovingActive", []];
    private _kept   = _active select { (_x getOrDefault ["group", grpNull]) isNotEqualTo _g };
    if (count _kept != count _active) then {
        missionNamespace setVariable ["DSC_rovingActive", _kept, true];
    };
};

// ----------------------------------------------------------------------------
// Helper: prepare a commanded group for combat orders — re-enable autocombat
// (rovers disable it for ambient feel) and bump behaviour up to AWARE.
// ----------------------------------------------------------------------------
private _wakeForCombat = {
    params ["_g"];
    { _x enableAI "AUTOCOMBAT"; _x enableAI "TARGET"; _x enableAI "AUTOTARGET" } forEach (units _g);
    _g setBehaviour "AWARE";
    _g setCombatMode "RED";
};

// ----------------------------------------------------------------------------
// Helper: clear all waypoints from a group so the next `move` order takes
// effect immediately instead of queueing behind ambient roving patrols.
// ----------------------------------------------------------------------------
private _clearWaypoints = {
    params ["_g"];
    while { (waypoints _g) isNotEqualTo [] } do {
        deleteWaypoint [_g, 0];
    };
};

// ----------------------------------------------------------------------------
// Register this group in the BFT commanded list (idempotent)
// ----------------------------------------------------------------------------
private _ensureCommanded = {
    params ["_g"];
    private _list = missionNamespace getVariable ["DSC_bftCommandedGroups", []];
    if !(_g in _list) then {
        _list pushBack _g;
        missionNamespace setVariable ["DSC_bftCommandedGroups", _list, true];
        [_g] call _detachFromParents;
    };
};

// ============================================================================
// Action dispatch
// ============================================================================
switch (_action) do {

    case "take": {
        [_grp] call _ensureCommanded;
        _grp setVariable ["DSC_bftRole", "commanded", true];
        // Give the commanded group a visible icon on the main map / 3D world
        // (NATO blue, label "BFT", scale 1, visible). Group locality is the
        // server, so this is the right place to set it. setGroupIconParams
        // is globally broadcast and JIP-synced.
        _grp setGroupIconParams [[0.30, 0.55, 1.00, 1.0], "BFT", 1, true];

        // Attach a NATO type-specific icon (b_inf / b_armor / b_air / etc)
        // on top of the default HC dashed-circle so the player can read the
        // group's role at a glance on the main map. Same classification the
        // BFT tablet uses for its own icons. addGroupIcon takes a
        // CfgGroupIcons CLASS NAME (not a texture path) — fall back to
        // b_inf if the class isn't defined on this build (e.g. b_plane
        // isn't always present). Icon id stored on the group so release
        // can remove it cleanly.
        private _existingId = _grp getVariable ["DSC_bftIconId", -1];
        if (_existingId >= 0) then {
            _grp removeGroupIcon _existingId;
        };
        private _iconType  = [_grp] call DSC_core_fnc_bftResolveIconType;
        private _iconClass = "b_" + _iconType;
        if (!isClass (configFile >> "CfgGroupIcons" >> _iconClass)) then {
            _iconClass = "b_inf";
        };
        private _iconId = _grp addGroupIcon [_iconClass, [0, 0]];
        _grp setVariable ["DSC_bftIconId", _iconId, true];

        LOG_5("bftExecuteCommand - %1 took %2 [%3] icon=%4 (%5)",_name,groupId _grp,_netId,_iconId,_iconClass);
    };

    case "moveHere": {
        _params params [["_pos", [0,0,0], [[]]]];
        [_grp] call _ensureCommanded;
        [_grp] call _wakeForCombat;
        [_grp] call _clearWaypoints;
        _grp move _pos;
        _grp setVariable ["DSC_bftRole", "moving", true];
        LOG_3("bftExecuteCommand - %1 ordered %2 to move to %3",_name,groupId _grp,_pos);
    };

    case "moveObj": {
        _params params [["_pos", [0,0,0], [[]]]];
        [_grp] call _ensureCommanded;
        [_grp] call _wakeForCombat;
        [_grp] call _clearWaypoints;
        _grp move _pos;
        _grp setVariable ["DSC_bftRole", "moving_obj", true];
        LOG_3("bftExecuteCommand - %1 ordered %2 to objective %3",_name,groupId _grp,_pos);
    };

    case "qrf": {
        _params params [["_pos", [0,0,0], [[]]]];
        [_grp] call _ensureCommanded;
        [_grp] call _wakeForCombat;
        [_grp] call _clearWaypoints;

        // Stage at a road position 500-800m off the objective instead of
        // dropping the group on top of the kill box. The QRF reactor below
        // pushes them in when contact starts (or the mission ends).
        private _stagingPos = [_pos] call DSC_core_fnc_bftQrfStaging;
        _grp move _stagingPos;
        _grp setVariable ["DSC_bftRole", "QRF", true];
        _grp setVariable ["DSC_bftQrfTriggered", false, true];

        // Spawn the per-group reaction loop once. Idempotent: a previous
        // loop will exit on its own when it sees role != "QRF", but we
        // still flag the group so a re-tag (release + set QRF again) gets
        // a fresh loop.
        if (isNil { _grp getVariable "DSC_bftQrfLoopActive" }) then {
            _grp setVariable ["DSC_bftQrfLoopActive", true, true];
            [_grp] spawn {
                params ["_g"];
                [_g] call DSC_core_fnc_bftQrfReact;
                _g setVariable ["DSC_bftQrfLoopActive", nil, true];
            };
        };

        LOG_4("bftExecuteCommand - %1 staged %2 as QRF at %3 (obj=%4)",_name,groupId _grp,_stagingPos,_pos);
    };

    case "release": {
        _grp setVariable ["DSC_bftRole", "", true];
        // Hide the HC main-map icon so the released group stops looking
        // commanded. The track still appears on the BFT (via section 5 of
        // the snapshot) so the player can re-take it.
        _grp setGroupIconParams [[0.30, 0.55, 1.00, 0.0], "", 1, false];

        // Drop the custom NATO type icon we attached on take
        private _iconId = _grp getVariable ["DSC_bftIconId", -1];
        if (_iconId >= 0) then {
            _grp removeGroupIcon _iconId;
            _grp setVariable ["DSC_bftIconId", -1, true];
        };

        // Group stays in DSC_bftCommandedGroups so it remains visible on the
        // BFT and the player can re-take it. It just no longer carries the
        // protection flag.
        LOG_2("bftExecuteCommand - %1 released %2",_name,groupId _grp);
    };

    default {
        WARNING_2("bftExecuteCommand - unknown action '%1' from %2",_action,_name);
    };
};
