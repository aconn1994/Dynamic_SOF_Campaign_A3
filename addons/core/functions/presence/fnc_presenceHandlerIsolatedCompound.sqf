/*
 * Function: DSC_core_fnc_presenceHandlerIsolatedCompound
 * Description:
 *     Microzone handler (Sprint D.5) for orphan-cluster compounds with no
 *     functional tags — small isolated building groups out in the
 *     countryside. The classic "random encounter" microzone.
 *
 *     No civilian baseline (compound, not a populated place). Projection
 *     resolver decides whether the nearest controlling installation throws
 *     a guard cluster + patrol here. With no controller in range, falls
 *     back to a small irregular fireteam roll so the player still has a
 *     chance to bump into something out in empty terrain.
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

// ----- Civilians — "people live everywhere" baseline -----
// Even in the middle of nowhere, somebody is home. Small count keeps the
// budget light but the world stops feeling empty between major zones.
private _civCount = 2 + floor random 2; // 2-3
private _civMix   = [_zoneTags, _primaryFn] call DSC_core_fnc_resolveCivilianMix;
private _civResult = [_pos, createHashMapFromArray [
    ["count",      _civCount],
    ["radius",     _radius max 80],
    ["structures", _structures],
    ["classMix",   _civMix]
]] call DSC_core_fnc_setupCivilians;
(_zone get "units")  append (_civResult getOrDefault ["units", []]);
(_zone get "groups") append (_civResult getOrDefault ["groups", []]);

private _proj = [_zone] call DSC_core_fnc_resolveMicrozoneProjection;
private _ctrlSide    = _proj get "controllerSide";
private _ctrlFaction = _proj get "controllerFaction";
private _ctrlControl = _proj get "controllerControl";
private _guardChance = _proj get "guardChance";
private _patrolChance = _proj get "patrolChance";

private _factionData = missionNamespace getVariable ["DSC_factionData", createHashMap];

// Pick foot-group pool by controller side, fallback to irregulars
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

private _useIrregularFallback = (_proj get "strength") <= 0;
private _spawnedAny = false;

// ----- Controller-side guard/patrol -----
if (!_useIrregularFallback && {_ctrlControl in ["opFor", "bluFor", "contested"]}) then {
    private _roles = switch (_ctrlControl) do {
        case "opFor":     { ["opFor", "opForPartner", "irregulars"] };
        case "bluFor":    { ["bluForPartner", "bluFor"] };
        case "contested": { ["opForPartner", "irregulars", "opFor"] };
        default            { [] };
    };
    ([_roles] call _fnc_pickFootGroups) params ["_pool", "_side"];

    if (_pool isNotEqualTo []) then {
        if (random 1 < _guardChance) then {
            private _gResult = [_pos, _pool, _side, createHashMapFromArray [
                ["size",       _proj get "guardSize"],
                ["radius",     _proj get "guardRadius"],
                ["skillProfile", _proj get "guardSkill"],
                ["structures", _structures]
            ]] call DSC_core_fnc_setupAnchoredGuard;
            (_zone get "units")  append (_gResult getOrDefault ["units", []]);
            (_zone get "groups") append (_gResult getOrDefault ["groups", []]);
            if ((_gResult getOrDefault ["units", []]) isNotEqualTo []) then { _spawnedAny = true };
        };

        if (random 1 < _patrolChance) then {
            private _pPool = [_pool] call DSC_core_fnc_filterPatrolGroups;
            if (_pPool isEqualTo []) then { _pPool = _pool };
            private _pResult = [_pos, _pPool, _side, createHashMapFromArray [
                ["size",         _proj get "patrolSize"],
                ["radius",       _proj get "patrolRadius"],
                ["skillProfile", _proj get "patrolSkill"]
            ]] call DSC_core_fnc_setupAnchoredPatrol;
            (_zone get "units")  append (_pResult getOrDefault ["units", []]);
            (_zone get "groups") append (_pResult getOrDefault ["groups", []]);
            if ((_pResult getOrDefault ["units", []]) isNotEqualTo []) then { _spawnedAny = true };
        };
    };
};

// ----- Irregular fallback when no controller in range -----
// 65% chance of a small armed fireteam. Compounds in empty terrain are
// exactly where insurgents/militia tuck themselves away — bumped from 55%
// during stress-test tuning since fewer overall microzones are live with
// the tighter 1.1km activate radius.
if (_useIrregularFallback && {(_proj get "irregularFallback")} && {random 1 < 0.65}) then {
    ([["irregulars", "opForPartner"]] call _fnc_pickFootGroups) params ["_pool", ""];
    if (_pool isNotEqualTo []) then {
        // Force east side for player-hostility (same trick as resolveIrregularOverlay)
        private _pPool = [_pool] call DSC_core_fnc_filterPatrolGroups;
        if (_pPool isEqualTo []) then { _pPool = _pool };
        private _pResult = [_pos, _pPool, east, createHashMapFromArray [
            ["size",         [4, 5]],
            ["radius",       300],
            ["skillProfile", "garrison_light"]
        ]] call DSC_core_fnc_setupAnchoredPatrol;
        (_zone get "units")  append (_pResult getOrDefault ["units", []]);
        (_zone get "groups") append (_pResult getOrDefault ["groups", []]);
        if ((_pResult getOrDefault ["units", []]) isNotEqualTo []) then { _spawnedAny = true };
    };
};

// Curator
private _curator = if (allCurators isNotEqualTo []) then { allCurators select 0 } else { objNull };
if (!isNull _curator && {(_zone get "units") isNotEqualTo []}) then {
    _curator addCuratorEditableObjects [_zone get "units", true];
};

private _icU = count (_zone get "units");
private _icInf = (_zone getOrDefault ["controllerInfluence", 0]) toFixed 2;
private _icStr = (_proj get "strength") toFixed 2;
LOG_7("activatePresenceZone [%1] - isolatedCompound: %2u (ctrl=%3 inf=%4 str=%5 gC=%6 pC=%7)",_id,_icU,_ctrlControl,_icInf,_icStr,_guardChance toFixed 2,_patrolChance toFixed 2);

_spawnedAny
