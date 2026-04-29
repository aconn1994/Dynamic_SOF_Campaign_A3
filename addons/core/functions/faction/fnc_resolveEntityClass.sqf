#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_resolveEntityClass
 * Description:
 *     Resolves an archetype's "unitClassResolver" value into a concrete
 *     CfgVehicles classname. Three resolution paths:
 *
 *       1. Literal classname — if the resolver string is itself a valid
 *          CfgVehicles class, return it as-is.
 *       2. Well-known role key — handled with custom logic:
 *            "officer"           Search _context.faction for unit names
 *                                containing officer|commander|leader.
 *            "civilian"          Random man from any civilian-side faction
 *                                in DSC_factionData.
 *            "civilian_suit"     Civilian, preferring keywords
 *                                suit|business|formal|priest.
 *            "civilian_labcoat"  Civilian, preferring keywords
 *                                scientist|labcoat|doctor|medic.
 *       3. Fallback — return _context.fallback (or "" if none).
 *
 *     Civilian resolvers iterate civilian factions registered in
 *     DSC_factionData. If no civilian faction is registered, falls back to
 *     vanilla "C_man_1".
 *
 * Arguments:
 *     0: _resolverKey <STRING>  Archetype unitClassResolver value.
 *     1: _context     <HASHMAP> Resolution context:
 *        "faction"      <STRING>   Target faction classname (officer path)
 *        "side"         <SIDE>     Side (informational; not currently used)
 *        "factionData"  <HASHMAP>  Override DSC_factionData
 *        "fallback"     <STRING>   Class to return on total failure
 *
 * Return Value:
 *     <STRING> - CfgVehicles classname, or "" if nothing resolved.
 *
 * Example:
 *     private _class = ["officer", createHashMapFromArray [
 *         ["faction", "rhsgref_faction_chdkz"]
 *     ]] call DSC_core_fnc_resolveEntityClass;
 */

params [
    ["_resolverKey", "", [""]],
    ["_context", createHashMap, [createHashMap]]
];

private _fallback = _context getOrDefault ["fallback", ""];

if (_resolverKey isEqualTo "") exitWith { _fallback };

// --- Path 1: literal classname (must be concrete, not abstract base) ---
private _literalCfg = configFile >> "CfgVehicles" >> _resolverKey;
if (isClass _literalCfg && { getNumber (_literalCfg >> "scope") >= 2 }) exitWith { _resolverKey };

private _faction = _context getOrDefault ["faction", ""];
private _factionData = _context getOrDefault ["factionData", missionNamespace getVariable ["DSC_factionData", createHashMap]];

// --- Helper: scan a faction's man-class list ---
private _fnc_factionMen = {
    params ["_factionClass"];
    private _filterStr = format [
        "getNumber (_x >> 'scope') >= 2 && getText (_x >> 'faction') == '%1' && getNumber (_x >> 'isMan') == 1",
        _factionClass
    ];
    (_filterStr configClasses (configFile >> "CfgVehicles")) apply { configName _x }
};

// --- Civilian classname pool from registered civilian factions ---
private _fnc_civilianPool = {
    params ["_data"];
    private _civRole = _data getOrDefault ["civilians", createHashMap];
    private _civFactions = _civRole getOrDefault ["factions", []];
    private _pool = [];
    {
        _pool append ([_x] call _fnc_factionMen);
    } forEach _civFactions;
    _pool
};

// --- Path 2: well-known resolver keys ---
switch (_resolverKey) do {

    case "officer": {
        if (_faction isEqualTo "") exitWith { _fallback };
        private _factionUnits = [_faction] call _fnc_factionMen;
        private _hit = "";
        {
            private _name = toLower _x;
            if ("officer" in _name || { "commander" in _name } || { "leader" in _name }) exitWith {
                _hit = _x;
            };
        } forEach _factionUnits;
        if (_hit != "") exitWith { _hit };
        // No officer keyword match — fall back to caller's fallback (preserves
        // pre-resolver behavior where irregular factions used a vanilla officer
        // class). Smarter "irregular HVT" handling belongs in archetype data.
        _fallback
    };

    case "civilian": {
        private _pool = [_factionData] call _fnc_civilianPool;
        if (_pool isNotEqualTo []) exitWith { selectRandom _pool };
        if (isClass (configFile >> "CfgVehicles" >> "C_man_1")) exitWith { "C_man_1" };
        _fallback
    };

    case "civilian_suit": {
        private _pool = [_factionData] call _fnc_civilianPool;
        private _keywords = ["suit", "business", "formal", "priest"];
        private _hit = "";
        {
            private _name = toLower _x;
            if (_keywords findIf { _x in _name } != -1) exitWith { _hit = _x };
        } forEach _pool;
        if (_hit != "") exitWith { _hit };
        if (_pool isNotEqualTo []) exitWith { selectRandom _pool };
        if (isClass (configFile >> "CfgVehicles" >> "C_man_1")) exitWith { "C_man_1" };
        _fallback
    };

    case "civilian_labcoat": {
        private _pool = [_factionData] call _fnc_civilianPool;
        private _keywords = ["scientist", "labcoat", "doctor", "medic"];
        private _hit = "";
        {
            private _name = toLower _x;
            if (_keywords findIf { _x in _name } != -1) exitWith { _hit = _x };
        } forEach _pool;
        if (_hit != "") exitWith { _hit };
        if (_pool isNotEqualTo []) exitWith { selectRandom _pool };
        if (isClass (configFile >> "CfgVehicles" >> "C_man_1")) exitWith { "C_man_1" };
        _fallback
    };

    default {
        diag_log format ["DSC: resolveEntityClass - unknown resolver '%1'", _resolverKey];
        _fallback
    };
}
