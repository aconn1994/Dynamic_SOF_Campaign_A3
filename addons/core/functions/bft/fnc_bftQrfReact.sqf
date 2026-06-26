#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_bftQrfReact
 * Description:
 *     Per-group reaction loop spawned when a friendly group is set as QRF.
 *     Two things happen on a slow tick (~8 s):
 *
 *       1. Mission-end watchdog
 *          - If missionInProgress is false, OR DSC_currentMission is gone,
 *            OR the mission's objective is no longer readable,
 *            auto-release: clear DSC_bftRole + drop the HC main-map icon +
 *            exit the loop. The group stays in DSC_bftCommandedGroups so it
 *            still shows on the BFT — just no longer protected and no
 *            longer wearing the QRF tag.
 *
 *       2. Contact reaction
 *          - Count hostile (enemy-side) units within 400 m of the current
 *            objective. If any are found and the group hasn't already been
 *            triggered, clear waypoints and push the group at the objective.
 *            Group stays QRF-tagged after triggering so the BFT visual
 *            highlight stays consistent and mission-end auto-release still
 *            applies if the player runs out of time.
 *
 *     Cleanly exits if the group dies / the role tag is cleared by the
 *     player via RELEASE / mission ends.
 *
 * Arguments:
 *     0: _grp <GROUP> - the QRF group
 */

if (!isServer) exitWith {};

params [["_grp", grpNull, [grpNull]]];

if (isNull _grp) exitWith {};

private _autoRelease = {
    params ["_g"];
    _g setVariable ["DSC_bftRole", "", true];
    _g setVariable ["DSC_bftQrfTriggered", nil, true];
    _g setGroupIconParams [[0.30, 0.55, 1.00, 0.0], "", 1, false];
    private _iconId = _g getVariable ["DSC_bftIconId", -1];
    if (_iconId >= 0) then {
        _g removeGroupIcon _iconId;
        _g setVariable ["DSC_bftIconId", -1, true];
    };
    diag_log format ["DSC: bftQrfReact - auto-released %1 (mission ended or group cleared)", groupId _g];
};

private _enemySides = [east, resistance];  // anything OPFOR-side counts as a trigger

while {true} do {
    uiSleep 8;

    // Group still exists and alive?
    if (isNull _grp) exitWith {};
    if (((units _grp) findIf {alive _x}) < 0) exitWith {
        diag_log format ["DSC: bftQrfReact - group %1 wiped out, exiting loop", groupId _grp];
    };

    // Player still wants this as QRF? (RELEASE / re-tasked / etc clears the tag)
    private _role = _grp getVariable ["DSC_bftRole", ""];
    if (_role != "QRF") exitWith {
        diag_log format ["DSC: bftQrfReact - group %1 no longer QRF (role=%2), exiting loop", groupId _grp, _role];
    };

    // Mission-end watchdog
    private _inProgress = missionNamespace getVariable ["missionInProgress", false];
    private _mission    = missionNamespace getVariable ["DSC_currentMission", createHashMap];
    private _objPos     = _mission getOrDefault ["location", []];
    private _missionGone = (!_inProgress) ||
                          {_mission isEqualTo createHashMap} ||
                          {!(_objPos isEqualType []) || (count _objPos < 2)};

    if (_missionGone) exitWith {
        [_grp] call _autoRelease;
    };

    // Contact reaction — already pushed? Just keep monitoring mission end.
    private _triggered = _grp getVariable ["DSC_bftQrfTriggered", false];
    if (_triggered) then { continue };

    // Look for hostile presence around the objective. nearEntities with
    // ["Man","Car","Tank"] catches infantry + vehicles. 400m matches the
    // typical mission AO radius.
    private _hostile = (_objPos nearEntities [["Man", "Car", "Tank", "Air"], 400])
        select { alive _x && {(side _x) in _enemySides} };

    if (_hostile isNotEqualTo []) then {
        _grp setVariable ["DSC_bftQrfTriggered", true, true];

        // Clear any standing orders + move to objective
        while { (waypoints _grp) isNotEqualTo [] } do {
            deleteWaypoint [_grp, 0];
        };
        { _x enableAI "AUTOCOMBAT"; _x enableAI "TARGET"; _x enableAI "AUTOTARGET" } forEach (units _grp);
        _grp setBehaviour "AWARE";
        _grp setCombatMode "RED";
        _grp move _objPos;

        diag_log format ["DSC: bftQrfReact - %1 TRIGGERED on contact (%2 hostiles near AO), pushing to %3",
            groupId _grp, count _hostile, _objPos];
    };
};
