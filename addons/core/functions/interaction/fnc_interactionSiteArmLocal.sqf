#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_interactionSiteArmLocal
 * Description:
 *     Client-local. Arms one `player addAction` for a single ARMED
 *     interaction site, if not already armed. The action is added to
 *     `player`, NOT to any placed object (§13.3 of the session 5 spec) —
 *     availability is distance-only, never gated on AREA_CLEAR or object
 *     state.
 *
 *     The condition string is built with `format` so `pos`/`radius`/`id`
 *     are baked in as literals (mirrors the existing
 *     `"_target distance _target < 5"` idiom used elsewhere in this
 *     codebase, just without a placed-object `_target`). The site's live
 *     `state` is still looked up dynamically at each condition evaluation
 *     against the global registry, so a site that completes or gets
 *     removed drops its own action without needing a rescan.
 *
 *     Idempotent — a site id that already has an armed action, an unknown
 *     id, or a non-ARMED site are all silent no-ops.
 *
 * Arguments:
 *     0: _id <STRING> - Site id.
 *
 * Return Value:
 *     <BOOL> - true if an action was armed.
 *
 * Example:
 *     ["site_12345_678"] call DSC_core_fnc_interactionSiteArmLocal;
 */

params [["_id", "", [""]]];

if (_id == "") exitWith { false };

private _actionIds = player getVariable ["DSC_interactionActionIds", createHashMap];
if (_id in _actionIds) exitWith { false };

private _sites = missionNamespace getVariable ["DSC_interactionSites", createHashMap];
private _site = _sites getOrDefault [_id, createHashMap];
if (_site isEqualTo createHashMap) exitWith { false };
if ((_site getOrDefault ["state", ""]) != "ARMED") exitWith { false };

private _pos = _site get "pos";
private _radius = _site get "radius";
private _actionText = _site getOrDefault ["action", "Conduct SSE"];

private _cond = format [
    "(_target distance %1 < %2) && {(((missionNamespace getVariable ['DSC_interactionSites', createHashMap]) getOrDefault ['%3', createHashMap]) getOrDefault ['state', 'REMOVED']) == 'ARMED'}",
    str _pos, _radius, _id
];

private _newActionId = player addAction [
    _actionText,
    {
        params ["_target", "_caller", "_actionId", "_args"];
        _args params ["_siteId"];
        [_siteId] spawn DSC_core_fnc_interactionSiteHold;
    },
    [_id],
    1.5,
    true,
    false,
    "",
    _cond
];

_actionIds set [_id, _newActionId];
player setVariable ["DSC_interactionActionIds", _actionIds];

LOG_1("interactionSiteArmLocal - armed action for %1",_id);

true
