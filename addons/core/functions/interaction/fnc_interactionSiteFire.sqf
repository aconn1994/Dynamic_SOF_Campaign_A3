#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_interactionSiteFire
 * Description:
 *     SERVER-ONLY completion entrypoint for an interaction site — this is
 *     the actual "action fired" completion referenced by the session 5
 *     mini-spec §13.2, not the client-side timer UI (see
 *     `fnc_interactionSiteHold` for that).
 *
 *     Re-validates server-side (site still ARMED, `_unit` still within
 *     `radius`) as a race guard against a client that fired late (site
 *     completed by someone else, or removed by cleanup, mid-hold). Marks
 *     the site COMPLETE, bumps the owning mission's
 *     `completionState.sitesCompleted` if the site is mission-scoped
 *     (standalone sites, e.g. the universal search hook, skip this step),
 *     calls the site's `onComplete`, then removes the site.
 *
 * Arguments:
 *     0: _id <STRING> - Site id.
 *     1: _unit <OBJECT> - The player who completed the hold.
 *
 * Return Value:
 *     <BOOL> - Whether it actually completed (false = rejected by
 *              re-validation, or called off the server).
 *
 * Example:
 *     [_id, player] call DSC_core_fnc_interactionSiteFire;
 */

params [
    ["_id", "", [""]],
    ["_unit", objNull, [objNull]]
];

if (!isServer) exitWith { false };

if (_id == "") exitWith {
    WARNING("interactionSiteFire - empty id");
    false
};

private _sites = missionNamespace getVariable ["DSC_interactionSites", createHashMap];
private _site = _sites getOrDefault [_id, createHashMap];

if (_site isEqualTo createHashMap) exitWith {
    WARNING_1("interactionSiteFire - unknown site id %1",_id);
    false
};

if ((_site get "state") != "ARMED") exitWith {
    LOG_1("interactionSiteFire - site %1 not ARMED, ignoring (race/late fire)",_id);
    false
};

private _pos = _site get "pos";
private _radius = _site get "radius";

if (isNull _unit || {(_unit distance _pos) > _radius}) exitWith {
    WARNING_1("interactionSiteFire - unit out of range or null for site %1, rejecting",_id);
    false
};

_site set ["state", "COMPLETE"];
_site set ["completedBy", _unit];
_sites set [_id, _site];
missionNamespace setVariable ["DSC_interactionSites", _sites, true];

// Mission-scoped bookkeeping — standalone sites (universal search) don't
// carry "missionScoped" and skip this entirely.
if (_site getOrDefault ["missionScoped", false]) then {
    private _mission = missionNamespace getVariable ["DSC_currentMission", createHashMap];
    if (_mission isNotEqualTo createHashMap) then {
        private _state = _mission getOrDefault ["completionState", createHashMap];
        private _completed = (_state getOrDefault ["sitesCompleted", 0]) + 1;
        _state set ["sitesCompleted", _completed];
        _mission set ["completionState", _state];
        missionNamespace setVariable ["DSC_currentMission", _mission, true];
        private _required = _state getOrDefault ["sitesRequired", 1];
        LOG_2("interactionSiteFire - mission sitesCompleted now %1/%2",_completed,_required);
    };
};

private _onComplete = _site getOrDefault ["onComplete", {}];
if (_onComplete isNotEqualTo {}) then {
    [_site, _unit] call _onComplete;
};

[_id] call DSC_core_fnc_removeInteractionSite;

INFO_2("interactionSiteFire - %1 completed by %2",_id,name _unit);

true
