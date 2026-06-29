/*
 * Function: DSC_core_fnc_setupContestedSkirmish
 * Description:
 *     For contested zones: spawns a single small bluFor-side patrol opposite
 *     the dominant (opFor-aligned) presence. Because west (bluFor) is hostile
 *     to east (opForPartner) by default, the two patrols engage on sight when
 *     they meet in the zone. Used in populated areas and military camps.
 *
 *     If no west-side bluFor groups are available, falls back to bluForPartner
 *     and force-spawns them on the west side so they're still hostile to east.
 *
 *     The opposing patrol is spawned at the supplied angle (degrees from zone
 *     center) so the caller can place it on the far side of the primary
 *     patrol — increasing the chance of contact in the player's view.
 *
 * Arguments:
 *     0: _zonePos    <ARRAY>   - [x,y,z] zone center
 *     1: _zoneRadius <NUMBER>  - zone radius (drives spawn + patrol distances)
 *     2: _config     <HASHMAP>
 *        "factionData" <HASHMAP> overrides DSC_factionData
 *        "spawnAngle"  <NUMBER>  degrees from zone center (default random)
 *
 * Return Value:
 *     <HASHMAP> "units", "groups"
 */

params [
    ["_zonePos", [], [[]]],
    ["_zoneRadius", 200, [0]],
    ["_config", createHashMap, [createHashMap]]
];

#include "script_component.hpp"

private _result = createHashMapFromArray [
    ["units", []],
    ["groups", []]
];

if (_zonePos isEqualTo []) exitWith { _result };

private _factionData = _config getOrDefault ["factionData",
    missionNamespace getVariable ["DSC_factionData", createHashMap]];

private _spawnAngle = _config getOrDefault ["spawnAngle", random 360];

// Candidate roles for the opposing force, in priority order. Prefer west-side
// bluFor (US factions) — guaranteed hostile to east by default Arma diplomacy.
private _candidateRoles = ["bluFor", "bluForPartner"];

private _pickedGroups = [];
private _pickedSide = west;
private _pickedRole = "";

{
    private _role = _x;
    private _roleData = _factionData getOrDefault [_role, createHashMap];
    private _roleSide = _roleData getOrDefault ["side", west];
    private _groupsHM = _roleData getOrDefault ["groups", createHashMap];

    private _flat = [];
    {
        _flat append (_y select {
            private _tags = _x getOrDefault ["doctrineTags", []];
            ("FOOT" in _tags || "PATROL" in _tags)
                && {!("ARMOR" in _tags)}
                && {!("NAVAL" in _tags)}
        });
    } forEach _groupsHM;

    if (_flat isNotEqualTo []) exitWith {
        _pickedGroups = _flat;
        // Force west-side. Even if the underlying CfgGroups entry is
        // independent (CDF, SAF), placing it into a west-side group makes the
        // units fight east — which is what "contested" actually means.
        _pickedSide = west;
        _pickedRole = _role;
    };
} forEach _candidateRoles;

if (_pickedGroups isEqualTo []) exitWith {
    WARNING("setupContestedSkirmish - no bluFor-side groups available");
    _result
};

// Recce-sized only
private _patrolPool = [_pickedGroups] call DSC_core_fnc_filterPatrolGroups;
if (_patrolPool isEqualTo []) then { _patrolPool = _pickedGroups };

private _patrolConfig = createHashMapFromArray [
    ["patrolCount",  [1, 1]],
    ["spawnRadius",  [(_zoneRadius max 120), (_zoneRadius max 220) + 80]],
    ["patrolRadius", [(_zoneRadius max 180), (_zoneRadius max 320) + 100]],
    ["spawnAngle",   _spawnAngle]
];

private _patrolResult = [_zonePos, _patrolPool, _pickedSide, _patrolConfig] call DSC_core_fnc_setupPatrols;

(_result get "units")  append (_patrolResult getOrDefault ["units", []]);
(_result get "groups") append (_patrolResult getOrDefault ["groups", []]);

LOG_3("setupContestedSkirmish - %1 opposing patrol units (role '%2', side west, angle %3)",count (_result get "units"),_pickedRole,_spawnAngle toFixed 0);

_result
