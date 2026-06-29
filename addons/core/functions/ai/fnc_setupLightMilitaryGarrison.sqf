#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_setupLightMilitaryGarrison
 * Description:
 *     Thin wrapper around fnc_setupGarrison that places a small number of
 *     armed units inside building positions. Used by the presence manager
 *     to give occupied/hostile territory a "patrols and hardpoints" feel
 *     OUTSIDE of formal bases/outposts — checkpoints, occupied compounds,
 *     guerrilla holdouts, etc.
 *
 *     Caller picks the side and group templates (typically the controlling
 *     side's foot-infantry pool, pre-filtered). Uses combat activation so
 *     units stay frozen until gunfire — preserves the "is this house
 *     occupied?" tension for players approaching.
 *
 *     Like setupGarrisonCivilians, density is hard-capped by a zone-size
 *     tier. Light military garrisons are intentionally small (1-3 units)
 *     — they are atmospheric encounters, not mini-bases.
 *
 * Arguments:
 *     0: _locationPos    <ARRAY>  - [x,y,z] zone center
 *     1: _groupTemplates <ARRAY>  - Classified group hashmaps (foot only)
 *     2: _side           <SIDE>   - Side to spawn under
 *     3: _config         <HASHMAP> -
 *        "mainStructures" <ARRAY>  Required
 *        "sideStructures" <ARRAY>  Required
 *        "sizeTier"       <STRING> "isolated|settlement|town|city" override
 *        "forceSpawn"     <BOOL>   Skip spawn-chance roll (default false)
 *        "anchorCount"    <NUMBER> Force exact anchor count, bypasses tier
 *
 * Return Value:
 *     <HASHMAP> - "units", "groups", "clusters"
 *
 * Example:
 *     [_pos, _footGroups, east, createHashMapFromArray [
 *         ["mainStructures", _main],
 *         ["sideStructures", _side]
 *     ]] call DSC_core_fnc_setupLightMilitaryGarrison;
 */

params [
    ["_locationPos", [], [[]]],
    ["_groupTemplates", [], [[]]],
    ["_side", east, [east]],
    ["_config", createHashMap, [createHashMap]]
];

private _empty = createHashMapFromArray [
    ["units", []], ["groups", []], ["clusters", []]
];

if (_locationPos isEqualTo []) exitWith { _empty };
if (_groupTemplates isEqualTo []) exitWith {
    WARNING("setupLightMilitaryGarrison - no group templates");
    _empty
};

private _mainStructures = _config getOrDefault ["mainStructures", []];
private _sideStructures = _config getOrDefault ["sideStructures", []];
private _forceSpawn     = _config getOrDefault ["forceSpawn", false];

private _totalStructures = (count _mainStructures) + (count _sideStructures);
if (_totalStructures == 0) exitWith { _empty };

// ============================================================================
// SIZE-TIER TABLE — military garrisons even sparser than civilian
// ============================================================================
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

// City === town intentionally for first rollout.
// [anchorMin, anchorMax, mainCap, sideCap, spawnChance, satMin, satMax]
private _tier = switch (_sizeTier) do {
    case "isolated":   { [1, 1, 4, 2, 0.70, 1, 2] };
    case "settlement": { [1, 2, 4, 2, 0.70, 1, 3] };
    case "town":       { [1, 2, 4, 2, 0.70, 1, 3] };
    case "city":       { [1, 3, 4, 2, 0.70, 1, 3] };
    default            { [1, 3, 4, 2, 0.70, 1, 3] };
};
_tier params ["_aMin", "_aMax", "_mainCap", "_sideCap", "_spawnChance", "_satMin", "_satMax"];

private _anchorOverride = _config getOrDefault ["anchorCount", -1];
if (_anchorOverride >= 0) then {
    _aMin = _anchorOverride;
    _aMax = _anchorOverride;
};

if (!_forceSpawn && { random 1 > _spawnChance }) exitWith {
    LOG_2("setupLightMilitaryGarrison - skip (tier=%1 chance=%2)",_sizeTier,_spawnChance toFixed 2);
    _empty
};

// ============================================================================
// DELEGATE TO setupGarrison — combat activation ON
// ============================================================================
private _garrisonConfig = createHashMapFromArray [
    ["mainStructures",   _mainStructures],
    ["sideStructures",   _sideStructures],
    ["mainStructureCap", _mainCap],
    ["sideStructureCap", _sideCap],
    ["density",          "light"],
    ["scalingTable", [
        [99999, [_aMin, _aMax], [_satMin, _satMax]]
    ]],
    ["satelliteRadius",  50],
    ["skillProfile",     "garrison_light"],
    ["skillVariance",    0.05],
    ["combatActivation", true],
    ["reactionDelay",    0.8]
];

private _result = [_locationPos, _groupTemplates, _side, _garrisonConfig] call DSC_core_fnc_setupGarrison;

private _milCt = count (_result getOrDefault ["units", []]);
LOG_4("setupLightMilitaryGarrison - %1 indoor mil at %2 (side=%3 tier=%4)",_milCt,_locationPos,_side,_sizeTier);

_result
