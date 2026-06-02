/*
 * Function: DSC_core_fnc_spawnGroupYielding
 * Description:
 *     Yielding drop-in replacement for BIS_fnc_spawnGroup. Reads a CfgGroups
 *     group config and creates each member unit one at a time, yielding via
 *     uiSleep between createUnit calls so the engine can interleave renderer
 *     frames. Prevents the multi-unit spawn burst that BIS_fnc_spawnGroup
 *     causes (it creates all units back-to-back in a single scheduler slot).
 *
 *     Supports two input modes for the group descriptor:
 *       1. A CfgGroups config entry (same as BIS_fnc_spawnGroup arg 3)
 *       2. A "path" string ("Side/Faction/Type/GroupName") that this fn walks
 *
 *     Skips waypoint creation — caller is responsible for tasking (e.g.
 *     BIS_fnc_taskPatrol).
 *
 * Arguments:
 *     0: _spawnPos  <ARRAY>          [x,y,z] center spawn position
 *     1: _side      <SIDE>           Group side (east, west, independent, civilian)
 *     2: _groupRef  <CONFIG|STRING>  Either a CfgGroups config entry or a path string
 *     3: _config    <HASHMAP> (optional)
 *        "yieldPerUnit" <NUMBER>  uiSleep between createUnit calls (default 0.1)
 *        "scatter"      <NUMBER>  meters of random offset per unit (default 5)
 *
 * Return Value:
 *     <GROUP> - The created group (grpNull if no units could be spawned)
 *
 * Example:
 *     private _g = [_pos, east, (configFile >> "CfgGroups" >> "East" >> ...)] call DSC_core_fnc_spawnGroupYielding;
 *     private _g = [_pos, east, "East/CHDKZ/Infantry/InfantryTeam"] call DSC_core_fnc_spawnGroupYielding;
 */

params [
    ["_spawnPos", [], [[]]],
    ["_side", east, [east]],
    ["_groupRef", configNull, [configNull, ""]],
    ["_config", createHashMap, [createHashMap]]
];

private _yieldPerUnit = _config getOrDefault ["yieldPerUnit", 0.1];
private _scatter      = _config getOrDefault ["scatter", 5];

if (_spawnPos isEqualTo []) exitWith {
    diag_log "DSC: spawnGroupYielding - no spawn position";
    grpNull
};

// Resolve a path string into a CfgGroups config entry
private _groupCfg = _groupRef;
if (_groupRef isEqualType "") then {
    _groupCfg = configFile >> "CfgGroups";
    { _groupCfg = _groupCfg >> _x } forEach (_groupRef splitString "/");
};

if (isNull _groupCfg || {!isClass _groupCfg}) exitWith {
    diag_log format ["DSC: spawnGroupYielding - invalid groupRef: %1", _groupRef];
    grpNull
};

// Collect unit entries from the group config (BIS pattern: nested classes with "vehicle" property)
private _unitEntries = [];
{
    if (isClass _x) then {
        private _vehicleClass = getText (_x >> "vehicle");
        if (_vehicleClass != "" && {isClass (configFile >> "CfgVehicles" >> _vehicleClass)}) then {
            private _pos = getArray (_x >> "position");
            if (_pos isEqualTo []) then { _pos = [0, 0, 0] };
            private _rank = getText (_x >> "rank");
            _unitEntries pushBack [_vehicleClass, _pos, _rank];
        };
    };
} forEach configProperties [_groupCfg, "isClass _x"];

if (_unitEntries isEqualTo []) exitWith {
    diag_log format ["DSC: spawnGroupYielding - no unit entries in %1", configName _groupCfg];
    grpNull
};

private _group = createGroup [_side, true];

{
    _x params ["_vehicleClass", "_relPos", "_rank"];

    // Use the relative position from cfg + small random scatter to prevent stacking
    private _ang = random 360;
    private _offset = random _scatter;
    private _absPos = [
        (_spawnPos select 0) + (_relPos select 0) + (_offset * sin _ang),
        (_spawnPos select 1) + (_relPos select 1) + (_offset * cos _ang),
        0
    ];

    private _unit = _group createUnit [_vehicleClass, _absPos, [], 0, "NONE"];
    if (!isNull _unit) then {
        if (_rank != "") then { _unit setRank _rank };
        _unit setPosATL _absPos;
    };

    uiSleep _yieldPerUnit;
} forEach _unitEntries;

if ((units _group) isEqualTo []) exitWith {
    deleteGroup _group;
    grpNull
};

// Select leader: highest ranking unit (BIS_fnc_spawnGroup does this implicitly)
private _ranked = (units _group) apply { [rank _x, _x] };
_ranked sort false;
private _leader = (_ranked select 0) select 1;
_group selectLeader _leader;

_group
