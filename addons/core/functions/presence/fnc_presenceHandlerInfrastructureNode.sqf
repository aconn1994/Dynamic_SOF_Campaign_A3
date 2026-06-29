/*
 * Function: DSC_core_fnc_presenceHandlerInfrastructureNode
 * Description:
 *     Microzone handler (Sprint D.5) for infrastructure-tagged sites — comms
 *     towers, fuel depots, power infrastructure pockets.
 *
 *     No civilian baseline (these are utility sites, not population centers).
 *     Projection has typeMultiplier 2.0 — real militaries protect critical
 *     infra before they bother garrisoning random farms. No irregular
 *     fallback: when no controller is around, infrastructure just sits
 *     quietly.
 *
 * Arguments:
 *     0: _zone <HASHMAP>
 *
 * Return Value:
 *     <BOOL>
 */

params [["_zone", createHashMap, [createHashMap]]];

#include "..\..\script_component.hpp"

private _id         = _zone get "id";
private _pos        = _zone get "position";
private _radius     = _zone getOrDefault ["radius", 100];
private _structures = _zone getOrDefault ["structures", []];
private _zoneTags   = _zone getOrDefault ["tags", []];
private _primaryFn  = _zone getOrDefault ["primaryFunction", ""];

// ----- Civilians — utility workers / nearby residents -----
// Infrastructure isn't unmanned in real life — there are technicians,
// inspectors, somebody living in the cottage next door. Small count.
private _civCount = 1 + floor random 3; // 1-3
private _civMix   = [_zoneTags, _primaryFn] call DSC_core_fnc_resolveCivilianMix;
private _civResult = [_pos, createHashMapFromArray [
    ["count",      _civCount],
    ["radius",     _radius max 60],
    ["structures", _structures],
    ["classMix",   _civMix]
]] call DSC_core_fnc_setupCivilians;
(_zone get "units")  append (_civResult getOrDefault ["units", []]);
(_zone get "groups") append (_civResult getOrDefault ["groups", []]);

private _proj = [_zone] call DSC_core_fnc_resolveMicrozoneProjection;
private _ctrlControl = _proj get "controllerControl";
private _factionData = missionNamespace getVariable ["DSC_factionData", createHashMap];

private _fnc_pickFootGroups = {
    params ["_roles"];
    private _picked = [];
    private _side = east;
    {
        private _roleData = _factionData getOrDefault [_x, createHashMap];
        private _rg = _roleData getOrDefault ["groups", createHashMap];
        private _collected = [];
        {
            _collected append (_y select {
                private _t = _x getOrDefault ["doctrineTags", []];
                ("FOOT" in _t || "PATROL" in _t)
                    && {!("ARMOR" in _t)} && {!("NAVAL" in _t)}
            });
        } forEach _rg;
        if (_collected isNotEqualTo []) exitWith {
            _picked = _collected;
            _side = _roleData getOrDefault ["side", east];
        };
    } forEach _roles;
    [_picked, _side]
};

private _hasController = (_proj get "strength") > 0;

if (_hasController && {_ctrlControl in ["opFor", "bluFor", "contested"]}) then {
    private _roles = switch (_ctrlControl) do {
        case "opFor":     { ["opFor", "opForPartner"] };
        case "bluFor":    { ["bluForPartner", "bluFor"] };
        case "contested": { ["opForPartner", "opFor"] };
        default            { [] };
    };
    ([_roles] call _fnc_pickFootGroups) params ["_pool", "_side"];

    if (_pool isNotEqualTo []) then {
        if (random 1 < (_proj get "guardChance")) then {
            private _g = [_pos, _pool, _side, createHashMapFromArray [
                ["size",         _proj get "guardSize"],
                ["radius",       _proj get "guardRadius"],
                ["skillProfile", _proj get "guardSkill"],
                ["structures",   _structures]
            ]] call DSC_core_fnc_setupAnchoredGuard;
            (_zone get "units")  append (_g getOrDefault ["units", []]);
            (_zone get "groups") append (_g getOrDefault ["groups", []]);
        };
        if (random 1 < (_proj get "patrolChance")) then {
            private _pPool = [_pool] call DSC_core_fnc_filterPatrolGroups;
            if (_pPool isEqualTo []) then { _pPool = _pool };
            private _p = [_pos, _pPool, _side, createHashMapFromArray [
                ["size",         _proj get "patrolSize"],
                ["radius",       _proj get "patrolRadius"],
                ["skillProfile", _proj get "patrolSkill"]
            ]] call DSC_core_fnc_setupAnchoredPatrol;
            (_zone get "units")  append (_p getOrDefault ["units", []]);
            (_zone get "groups") append (_p getOrDefault ["groups", []]);
        };
    };
};

// Curator
private _curator = if (allCurators isNotEqualTo []) then { allCurators select 0 } else { objNull };
if (!isNull _curator && {(_zone get "units") isNotEqualTo []}) then {
    _curator addCuratorEditableObjects [_zone get "units", true];
};

LOG_6("activatePresenceZone [%1] - infrastructureNode: %2u (ctrl=%3 str=%4 gC=%5 pC=%6)",_id,count (_zone get "units"),_ctrlControl,(_proj get "strength") toFixed 2,(_proj get "guardChance") toFixed 2,(_proj get "patrolChance") toFixed 2);

((_zone get "units") isNotEqualTo [])
