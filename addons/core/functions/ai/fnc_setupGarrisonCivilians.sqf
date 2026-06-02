#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_setupGarrisonCivilians
 * Description:
 *     Thin wrapper around fnc_setupGarrison that places civilians inside
 *     building positions instead of military units. Used by the presence
 *     manager to give towns/settlements/compounds the feeling of "people
 *     live here" without paying for wandering-civilian pathing cost.
 *
 *     Pool is sampled up-front from a weighted classMix (resolver-key →
 *     classname via fnc_resolveEntityClass). Spawned units are post-
 *     processed to CARELESS / BLUE / allowFleeing 0 — they stand around
 *     their building, do not react to combat.
 *
 *     Density is controlled by a per-zone-size table. Larger zones get
 *     FEWER indoor garrisons (and a roll to skip entirely) so that cities
 *     remain affordable. See `_sizeTier` below.
 *
 * Arguments:
 *     0: _locationPos <ARRAY>   - [x,y,z] zone center
 *     1: _config      <HASHMAP> -
 *        "mainStructures" <ARRAY>  Required — pre-classified main bldgs
 *        "sideStructures" <ARRAY>  Required — pre-classified side bldgs
 *        "classMix"       <ARRAY>  [[resolverKey, weight], ...] from
 *                                  fnc_resolveCivilianMix. Defaults to
 *                                  plain civilian.
 *        "sizeTier"       <STRING> Override zone-size tier:
 *                                  "isolated" | "settlement" | "town" | "city".
 *                                  When unset, derived from total bldg count.
 *        "forceSpawn"     <BOOL>   Skip the spawn-chance roll (default false).
 *        "anchorCount"    <NUMBER> Force exact anchor count, bypasses tier
 *                                  range. Used by handlers orchestrating
 *                                  multi-cluster civ/mil splits.
 *
 * Return Value:
 *     <HASHMAP> - "units", "groups", "clusters" (passthrough from setupGarrison)
 *
 * Example:
 *     private _mix = [_zone get "tags", _zone get "primaryFunction"] call
 *                    DSC_core_fnc_resolveCivilianMix;
 *     [_pos, createHashMapFromArray [
 *         ["mainStructures", _main],
 *         ["sideStructures", _side],
 *         ["classMix",       _mix]
 *     ]] call DSC_core_fnc_setupGarrisonCivilians;
 */

params [
    ["_locationPos", [], [[]]],
    ["_config", createHashMap, [createHashMap]]
];

private _empty = createHashMapFromArray [
    ["units", []], ["groups", []], ["clusters", []]
];

if (_locationPos isEqualTo []) exitWith { _empty };

private _mainStructures = _config getOrDefault ["mainStructures", []];
private _sideStructures = _config getOrDefault ["sideStructures", []];
private _classMix       = _config getOrDefault ["classMix", [["civilian", 1]]];
private _forceSpawn     = _config getOrDefault ["forceSpawn", false];

private _totalStructures = (count _mainStructures) + (count _sideStructures);
if (_totalStructures == 0) exitWith { _empty };

// ============================================================================
// SIZE-TIER TABLE — inverse density: cities get LESS indoor population
// ============================================================================
// Goal: small settlements feel occupied as a defining feature; cities only
// occasionally surprise the player with an indoor encounter. Total headcount
// is hard-capped, not building-percentage-based.
//
// [anchorMin, anchorMax, mainCap, sideCap, spawnChance]
private _sizeTier = _config getOrDefault ["sizeTier", ""];
if (_sizeTier == "") then {
    _sizeTier = switch (true) do {
        case (_totalStructures < 5):  { "isolated" };
        case (_totalStructures < 15): { "settlement" };
        case (_totalStructures < 50): { "town" };
        default                       { "city" };
    };
};

// City === town intentionally for first rollout — observe behavior before
// dialing cities down further.
private _tier = switch (_sizeTier) do {
    case "isolated":   { [1, 1, 2, 1, 0.80] };
    case "settlement": { [1, 2, 2, 1, 0.70] };
    case "town":       { [1, 1, 2, 1, 0.45] };
    case "city":       { [1, 1, 2, 1, 0.45] };
    default            { [1, 1, 1, 1, 0.30] };
};
_tier params ["_aMin", "_aMax", "_mainCap", "_sideCap", "_spawnChance"];

private _anchorOverride = _config getOrDefault ["anchorCount", -1];
if (_anchorOverride >= 0) then {
    _aMin = _anchorOverride;
    _aMax = _anchorOverride;
};

// Spawn-chance gate — perf safety valve. Half the zones add nothing in towns,
// 80% add nothing in cities (would-be, when we lower city later).
if (!_forceSpawn && { random 1 > _spawnChance }) exitWith {
    diag_log format ["DSC: setupGarrisonCivilians - skip (tier=%1 chance=%2)",
        _sizeTier, _spawnChance toFixed 2];
    _empty
};

// ============================================================================
// PRE-BUILD UNIT POOL FROM CLASSMIX (~20 picks ≫ any expected headcount)
// ============================================================================
private _mixTotalWeight = 0;
{ _mixTotalWeight = _mixTotalWeight + (_x param [1, 0]) } forEach _classMix;
if (_mixTotalWeight <= 0) exitWith {
    diag_log "DSC: setupGarrisonCivilians - empty classMix, skipping";
    _empty
};

private _resolverCtx = createHashMapFromArray [["fallback", ""]];
private _unitPool = [];
for "_i" from 1 to 20 do {
    private _roll = random _mixTotalWeight;
    private _acc = 0;
    private _picked = "civilian";
    {
        _acc = _acc + (_x param [1, 0]);
        if (_roll <= _acc) exitWith { _picked = _x param [0, "civilian"] };
    } forEach _classMix;

    private _resolved = [_picked, _resolverCtx] call DSC_core_fnc_resolveEntityClass;
    if (_resolved == "" && {isClass (configFile >> "CfgVehicles" >> "C_man_1")}) then {
        _resolved = "C_man_1";
    };
    if (_resolved != "") then { _unitPool pushBack _resolved };
};

if (_unitPool isEqualTo []) exitWith {
    diag_log "DSC: setupGarrisonCivilians - resolver produced empty pool";
    _empty
};

// ============================================================================
// DELEGATE TO setupGarrison
// ============================================================================
private _garrisonConfig = createHashMapFromArray [
    ["unitPoolOverride", _unitPool],
    ["mainStructures",   _mainStructures],
    ["sideStructures",   _sideStructures],
    ["mainStructureCap", _mainCap],
    ["sideStructureCap", _sideCap],
    ["density",          "light"],
    // Single tier — caps already encode size choice. Range [aMin, aMax].
    ["scalingTable", [
        [99999, [_aMin, _aMax], [0, 1]]
    ]],
    ["satelliteRadius",  35],
    ["skillProfile",     "moderate"],  // overridden below; placeholder
    ["combatActivation", false]
];

private _result = [_locationPos, [], civilian, _garrisonConfig] call DSC_core_fnc_setupGarrison;

// ============================================================================
// POST-PROCESS — civilians don't fight, don't flee, just exist
// ============================================================================
{
    private _u = _x;
    if (!alive _u) then { continue };
    _u allowFleeing 0;
    _u setBehaviour "CARELESS";
    _u setCombatMode "BLUE";
    _u setSpeedMode "LIMITED";
    _u setUnitPos "AUTO";
    _u setSkill 0.3;
    (group _u) setBehaviour "CARELESS";
    (group _u) setCombatMode "BLUE";
} forEach (_result getOrDefault ["units", []]);

diag_log format ["DSC: setupGarrisonCivilians - %1 indoor civs at %2 (tier=%3)",
    count (_result getOrDefault ["units", []]), _locationPos, _sizeTier];

_result
