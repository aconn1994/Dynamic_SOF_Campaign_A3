#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_setupAnchoredPatrol
 * Description:
 *     Lightweight anchored patrol for microzones (Sprint D.5). Spawns a
 *     single small group (2-3 units) that patrols within a fixed radius of
 *     the anchor via BIS_fnc_taskPatrol.
 *
 *     Different from fnc_setupPatrols (which uses a full CfgGroups entry
 *     verbatim with spawnGroupYielding — gives 5-8 unit squads). This
 *     helper assembles a custom-sized group from a class pool so we get a
 *     2-3 man fireteam without depending on the faction having a recce
 *     subclass that small.
 *
 *     Yields with uiSleep between createUnit calls.
 *
 * Arguments:
 *     0: _anchorPos      <ARRAY>   [x,y,z]
 *     1: _groupTemplates <ARRAY>   classified foot group hashmaps (class pool)
 *     2: _side           <SIDE>
 *     3: _config         <HASHMAP>
 *        "size"            <ARRAY>  [min,max] (default [2,3])
 *        "radius"          <NUMBER> patrol waypoint radius (default 250)
 *        "spawnOffset"     <NUMBER> distance from anchor to spawn group (default 30)
 *        "skillProfile"    <STRING> default "garrison_light"
 *        "skillVariance"   <NUMBER> default 0.05
 *        "combatActivation" <BOOL>  default false (patrols need PATH enabled
 *                                   to actually patrol — addCombatActivation
 *                                   disables PATH. Dyn-sim already freezes
 *                                   the group when player is far.)
 *        "reactionDelay"   <NUMBER> default 0.5
 *
 * Return Value:
 *     <HASHMAP> "units", "groups"
 */

params [
    ["_anchorPos", [], [[]]],
    ["_groupTemplates", [], [[]]],
    ["_side", east, [east]],
    ["_config", createHashMap, [createHashMap]]
];

private _result = createHashMapFromArray [["units", []], ["groups", []]];

if (_anchorPos isEqualTo []) exitWith {
    diag_log "DSC: setupAnchoredPatrol - no anchor position";
    _result
};
if (_groupTemplates isEqualTo []) exitWith {
    diag_log "DSC: setupAnchoredPatrol - no group templates";
    _result
};

private _sizeRange       = _config getOrDefault ["size", [2, 3]];
private _patrolRadius    = _config getOrDefault ["radius", 250];
private _spawnOffset     = _config getOrDefault ["spawnOffset", 30];
private _skillProfile    = _config getOrDefault ["skillProfile", "garrison_light"];
private _skillVariance   = _config getOrDefault ["skillVariance", 0.05];
private _combatActivation = _config getOrDefault ["combatActivation", false];
private _reactionDelay   = _config getOrDefault ["reactionDelay", 0.5];

// Build class pool from group templates
private _unitPool = [];
{
    private _path = _x getOrDefault ["path", ""];
    if (_path == "") then { continue };
    private _pathParts = _path splitString "/";
    private _groupCfg = configFile >> "CfgGroups";
    { _groupCfg = _groupCfg >> _x } forEach _pathParts;
    if (!isClass _groupCfg) then { continue };

    {
        if (isClass _x) then {
            private _class = getText (_x >> "vehicle");
            if (_class != ""
                && {isClass (configFile >> "CfgVehicles" >> _class)}
                && {_class isKindOf "Man"}
            ) then {
                _unitPool pushBack _class;
            };
        };
    } forEach configProperties [_groupCfg, "isClass _x"];
} forEach _groupTemplates;

if (_unitPool isEqualTo []) exitWith {
    diag_log "DSC: setupAnchoredPatrol - no unit classes extracted";
    _result
};

// Find a safe spawn position near the anchor
private _spawnAng = random 360;
private _spawnPos = [
    (_anchorPos select 0) + _spawnOffset * sin _spawnAng,
    (_anchorPos select 1) + _spawnOffset * cos _spawnAng,
    0
];
if (surfaceIsWater _spawnPos) then {
    _spawnPos = [_anchorPos, 0, _spawnOffset + 50, 5, 0, 20, 0] call BIS_fnc_findSafePos;
};
if (surfaceIsWater _spawnPos) exitWith {
    diag_log format ["DSC: setupAnchoredPatrol - no land near %1, skipping", _anchorPos];
    _result
};

private _count = (_sizeRange select 0) + floor random ((_sizeRange select 1) - (_sizeRange select 0) + 1);
if (_count < 1) exitWith { _result };

private _group = createGroup [_side, true];
private _spawned = 0;

for "_i" from 0 to (_count - 1) do {
    private _ang = random 360;
    private _d = random 4;
    private _p = [
        (_spawnPos select 0) + _d * sin _ang,
        (_spawnPos select 1) + _d * cos _ang,
        0
    ];
    private _class = selectRandom _unitPool;
    private _unit = _group createUnit [_class, _p, [], 0, "NONE"];
    if (isNull _unit) then { continue };

    _unit setPosATL _p;
    _unit setDir random 360;
    [_unit, _skillProfile, _skillVariance] call DSC_core_fnc_applySkillProfile;

    (_result get "units") pushBack _unit;
    _spawned = _spawned + 1;
    uiSleep 0.1;
};

if ((units _group) isEqualTo []) exitWith {
    deleteGroup _group;
    _result
};

// Patrol task — BIS_fnc_taskPatrol generates a randomized loop within radius
[_group, _anchorPos, _patrolRadius] call BIS_fnc_taskPatrol;

(_result get "groups") pushBack _group;
_group enableDynamicSimulation true;

// if (_combatActivation) then {
//     [_group, _reactionDelay] call DSC_core_fnc_addCombatActivation;
// };

diag_log format ["DSC: setupAnchoredPatrol - spawned %1 units patrolling r=%2 (side=%3 skill=%4)",
    _spawned, _patrolRadius, _side, _skillProfile];

_result
