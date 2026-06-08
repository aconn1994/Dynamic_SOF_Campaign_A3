#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_setupAnchoredGuard
 * Description:
 *     Lightweight anchored guard cluster for microzones (Sprint D.5). Spawns
 *     a single small group (2-4 units) around an anchor point with no
 *     waypoints — they stand/sit and react via combat activation
 *     (FiredNear EH) using the garrison_light skill profile.
 *
 *     Distinct from fnc_setupGarrison (which does anchor + satellite
 *     buildings + interior placement) and fnc_setupGuards (which binds
 *     guards to specific buildings' fronts via road detection). For a
 *     2-3 unit guard at an industrial shed cluster or isolated compound,
 *     both are overkill — this helper is a minimal class-pool + offset
 *     + createUnit loop.
 *
 *     Yields with uiSleep between createUnit calls so multiple microzone
 *     activations in a single worker cycle don't burst-spawn.
 *
 * Arguments:
 *     0: _anchorPos      <ARRAY>   [x,y,z]
 *     1: _groupTemplates <ARRAY>   classified foot group hashmaps (for class pool)
 *     2: _side           <SIDE>
 *     3: _config         <HASHMAP>
 *        "size"           <ARRAY>   [min,max] units (default [2,3])
 *        "radius"         <NUMBER>  satellite spawn radius (default 30)
 *        "skillProfile"   <STRING>  default "garrison_light"
 *        "skillVariance"  <NUMBER>  default 0.05
 *        "structures"     <ARRAY>   optional; if supplied, prefer building
 *                                   positions before random ground offsets
 *        "combatActivation" <BOOL>  default true
 *        "reactionDelay"  <NUMBER>  seconds before PATH re-enables (default 0.5)
 *
 * Return Value:
 *     <HASHMAP> "units", "groups"
 *
 * Example:
 *     [_pos, _footGroups, east, createHashMapFromArray [
 *         ["size", [2, 4]], ["radius", 30], ["structures", _structs]
 *     ]] call DSC_core_fnc_setupAnchoredGuard;
 */

params [
    ["_anchorPos", [], [[]]],
    ["_groupTemplates", [], [[]]],
    ["_side", east, [east]],
    ["_config", createHashMap, [createHashMap]]
];

private _result = createHashMapFromArray [["units", []], ["groups", []]];

if (_anchorPos isEqualTo []) exitWith {
    diag_log "DSC: setupAnchoredGuard - no anchor position";
    _result
};
if (_groupTemplates isEqualTo []) exitWith {
    diag_log "DSC: setupAnchoredGuard - no group templates";
    _result
};

private _sizeRange       = _config getOrDefault ["size", [2, 3]];
private _radius          = _config getOrDefault ["radius", 30];
private _skillProfile    = _config getOrDefault ["skillProfile", "garrison_light"];
private _skillVariance   = _config getOrDefault ["skillVariance", 0.05];
private _structures      = _config getOrDefault ["structures", []];
private _combatActivation = _config getOrDefault ["combatActivation", true];
private _reactionDelay   = _config getOrDefault ["reactionDelay", 0.5];

// Build class pool from group templates (same approach as fnc_setupGuards)
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
    diag_log "DSC: setupAnchoredGuard - no unit classes extracted";
    _result
};

// Pick spawn anchors — building positions if available, else random offsets
private _bldgPositions = [];
{
    private _bp = _x buildingPos -1;
    if (_bp isNotEqualTo []) then { _bldgPositions append _bp };
} forEach _structures;
_bldgPositions = _bldgPositions call BIS_fnc_arrayShuffle;

private _count = (_sizeRange select 0) + floor random ((_sizeRange select 1) - (_sizeRange select 0) + 1);
if (_count < 1) exitWith { _result };

private _group = createGroup [_side, true];
private _spawned = 0;

for "_i" from 0 to (_count - 1) do {
    private _spawnPos = if (_i < count _bldgPositions) then {
        _bldgPositions select _i
    } else {
        private _ang = random 360;
        private _d = 3 + random (_radius - 3);
        [
            (_anchorPos select 0) + _d * sin _ang,
            (_anchorPos select 1) + _d * cos _ang,
            0
        ]
    };

    // Skip water
    if (surfaceIsWater _spawnPos) then { continue };

    private _class = selectRandom _unitPool;
    private _unit = _group createUnit [_class, _spawnPos, [], 0, "NONE"];
    if (isNull _unit) then { continue };

    _unit setPosATL _spawnPos;
    _unit setDir random 360;
    _unit setUnitPos "AUTO";

    [_unit, _skillProfile, _skillVariance] call DSC_core_fnc_applySkillProfile;

    (_result get "units") pushBack _unit;
    _spawned = _spawned + 1;

    uiSleep 0.1;
};

if ((units _group) isEqualTo []) exitWith {
    deleteGroup _group;
    diag_log "DSC: setupAnchoredGuard - no units spawned, group dropped";
    _result
};

// Sentry-style: short patrol behavior keeps them alert but anchored
_group setBehaviour "AWARE";
_group setCombatMode "YELLOW";
_group setSpeedMode "LIMITED";

// Single SENTRY waypoint at anchor — they hold position, react on contact
private _wp = _group addWaypoint [_anchorPos, 0];
_wp setWaypointType "SENTRY";
_wp setWaypointCompletionRadius _radius;

(_result get "groups") pushBack _group;
_group enableDynamicSimulation true;

// if (_combatActivation) then {
//     [_group, _reactionDelay] call DSC_core_fnc_addCombatActivation;
// };

diag_log format ["DSC: setupAnchoredGuard - spawned %1 units (side=%2 skill=%3 r=%4)",
    _spawned, _side, _skillProfile, _radius];

_result
