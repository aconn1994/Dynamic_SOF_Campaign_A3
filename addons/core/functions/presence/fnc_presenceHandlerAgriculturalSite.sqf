/*
 * Function: DSC_core_fnc_presenceHandlerAgriculturalSite
 * Description:
 *     Microzone handler (Sprint D.5) for agricultural-tagged sites — farms,
 *     orchards, livestock pens. Low-value, militaries rarely garrison
 *     these (typeMultiplier 0.5).
 *
 *     Spawn pass:
 *       1. 1-2 farmer/worker civilians (resolved via classMix), CARELESS
 *       2. Rare lone armed civilian (5%) on hostile-controlled territory
 *
 *     No anchored guard or patrol — handler registers without a guard/patrol
 *     military block, so the projection helper returns zero chance for both.
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

// ----- Civilian workers -----
private _civCount = 2 + floor random 3; // 2-4
private _civMix   = [_zoneTags, _primaryFn] call DSC_core_fnc_resolveCivilianMix;
private _civResult = [_pos, createHashMapFromArray [
    ["count",      _civCount],
    ["radius",     _radius max 80],
    ["structures", _structures],
    ["classMix",   _civMix]
]] call DSC_core_fnc_setupCivilians;
(_zone get "units")  append (_civResult getOrDefault ["units", []]);
(_zone get "groups") append (_civResult getOrDefault ["groups", []]);

// ----- Lone armed civilian — "guy with a rifle watching the goats" -----
// Real life: even mountain farmsteads in contested terrain often have a
// rifle in the corner. Not common, but not nothing.
private _ctrlControl = _zone getOrDefault ["controllerControl", "neutral"];
private _armedChance = switch (_ctrlControl) do {
    case "opFor":     { 0.30 };
    case "contested": { 0.25 };
    case "neutral":   { 0.12 };
    default            { 0 };
};
if (_armedChance > 0 && {random 1 < _armedChance}) then {
    private _factionData = missionNamespace getVariable ["DSC_factionData", createHashMap];
    private _pool = [];
    {
        private _roleData = _factionData getOrDefault [_x, createHashMap];
        private _rg = _roleData getOrDefault ["groups", createHashMap];
        private _collected = [];
        {
            _collected append (_y select {
                private _t = _x getOrDefault ["doctrineTags", []];
                ("FOOT" in _t || "PATROL" in _t) && {!("ARMOR" in _t)} && {!("NAVAL" in _t)}
            });
        } forEach _rg;
        if (_collected isNotEqualTo []) exitWith { _pool = _collected };
    } forEach ["irregulars", "opForPartner"];

    if (_pool isNotEqualTo []) then {
        // Single guard, no patrol — "lone guy with a gun watching the farm"
        private _g = [_pos, _pool, east, createHashMapFromArray [
            ["size",         [1, 1]],
            ["radius",       20],
            ["skillProfile", "garrison_light"],
            ["structures",   _structures]
        ]] call DSC_core_fnc_setupAnchoredGuard;
        (_zone get "units")  append (_g getOrDefault ["units", []]);
        (_zone get "groups") append (_g getOrDefault ["groups", []]);
    };
};

// Curator
private _curator = if (allCurators isNotEqualTo []) then { allCurators select 0 } else { objNull };
if (!isNull _curator && {(_zone get "units") isNotEqualTo []}) then {
    _curator addCuratorEditableObjects [_zone get "units", true];
};

LOG_3("activatePresenceZone [%1] - agriculturalSite: %2u (ctrl=%3)",_id,count (_zone get "units"),_ctrlControl);

((_zone get "units") isNotEqualTo [])
