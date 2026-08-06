#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_c2NoiseEvent
 * Description:
 *     Sprint F.2 — turns a loud thing happening into information the enemy
 *     network can act on.
 *
 *     This is the layer that makes tradecraft matter outside of ambush
 *     timing. A suppressed kill is audible at 75 m and effectively never
 *     reaches anybody. Unsuppressed small arms carry 800 m and make the
 *     neighborhood suspicious. An explosion carries 2500 m and skips the
 *     "unverified" step entirely, because nobody mistakes demolitions for
 *     someone hunting rabbits.
 *
 *     That gap between 800 m and 2500 m is the whole quiet-AFO vs loud-DA
 *     tradeoff expressed as one number, and it is why blowing a comms relay
 *     rather than quietly disabling it is a strategically different act.
 *
 *     Two independent things can hear a noise, and both matter:
 *
 *       1. NODES in radius — an installation hears it directly. A
 *          firefight inside a town's audible radius means the garrison
 *          knows something is happening without anybody phoning it in.
 *
 *       2. STAMPED GROUPS in radius — a patrol that hears gunfire reports
 *          it to ITS OWN parent node, which may be a completely different
 *          installation. This is the "another friendly force in the area
 *          heard it and called it in" case, and it means clearing the
 *          nearest outpost does not make you safe if a rover was passing.
 *
 *     Deliberately does NOT check line of sight or terrain masking. Sound
 *     travels over ridges, and a radius check that already loses to walls
 *     would make the system feel arbitrary rather than harsh.
 *
 * Arguments:
 *     0: _pos       <ARRAY>  - where the noise happened
 *     1: _noiseType <STRING> - "SUPPRESSED"|"SMALL_ARMS"|"EXPLOSION"|"VEHICLE_KILL"
 *     2: _detail    <STRING> - optional radio feed text
 *
 * Return Value:
 *     <NUMBER> - how many distinct nodes were signalled
 *
 * Example:
 *     [getPos _veh, "VEHICLE_KILL"] call DSC_core_fnc_c2NoiseEvent;
 */

params [
    ["_pos",       [], [[]]],
    ["_noiseType", "SMALL_ARMS", [""]],
    ["_detail",    "", [""]]
];

if (!isServer) exitWith { 0 };
if (_pos isEqualTo []) exitWith { 0 };

private _nodes = missionNamespace getVariable ["DSC_c2Nodes", createHashMap];
if (_nodes isEqualTo createHashMap) exitWith { 0 };

private _arch = [] call DSC_core_fnc_getC2Archetypes;
private _noiseGrades = _arch get "noiseGrades";
private _cfg = _noiseGrades getOrDefault [_noiseType, createHashMap];
if (_cfg isEqualTo createHashMap) exitWith { 0 };

private _radius = _cfg getOrDefault ["radius", 0];
private _signal = _cfg getOrDefault ["signal", ""];

// Suppressed fire generates no signal at all. The radius exists in the data
// purely for readability.
if (_signal isEqualTo "" || {_radius <= 0}) exitWith { 0 };

// ============================================================================
// Relevance gate
// ============================================================================
// `EntityKilled` fires for every death on the map, including AI-vs-AI fights
// the player will never see. Those still cost a full node sweep plus a
// nearEntities call each. Gate on player distance so a war on the far side
// of Altis doesn't tax the tick.
//
// 12 km is deliberately generous — comfortably beyond the widest node reach
// (8 km COMMAND) so nothing that could ever produce a response the player
// might encounter gets culled. This is a perf guard, not a gameplay rule.
private _relevanceRange = 12000;
private _anyPlayerNear = false;
{
    if ((getPosATL _x) distance2D _pos < _relevanceRange) exitWith { _anyPlayerNear = true };
} forEach allPlayers;

if (!_anyPlayerNear) exitWith { 0 };

private _stats = missionNamespace getVariable ["DSC_c2Stats", createHashMap];
_stats set ["noiseEvents", (_stats getOrDefault ["noiseEvents", 0]) + 1];

// Nodes already signalled this event — a single gunshot must not raise the
// same installation twice just because a patrol of its own also heard it.
private _signalled = [];
private _count = 0;

// Cardinal bearing reads more like radio traffic than a raw degree value.
private _fnc_cardinal = {
    params ["_from", "_to"];
    private _dir = _from getDir _to;
    private _points = ["north","north-east","east","south-east","south","south-west","west","north-west"];
    _points select (round (_dir / 45) % 8)
};

// ============================================================================
// 1. Nodes that hear it directly
// ============================================================================
{
    private _nodeId = _x;
    private _node = _nodes get _nodeId;
    private _nPos = _node get "position";
    private _dist = _nPos distance2D _pos;

    if (_dist <= _radius) then {
        // Confidence falls off with distance — a node that barely heard it
        // has a much vaguer idea of where it came from, so F.3 will search
        // a correspondingly wider area.
        private _conf = 1 - ((_dist / _radius) * 0.6);
        private _text = if (_detail != "") then { _detail } else {
            private _card = [_nPos, _pos] call _fnc_cardinal;
            format ["Sounds of contact to our %1", _card]
        };

        private _payload = createHashMapFromArray [
            ["callsign",   ""],
            ["confidence", _conf],
            ["detail",     _text]
        ];

        [_signal, _nodeId, _pos, _payload] call DSC_core_fnc_c2Signal;
        _signalled pushBack _nodeId;
        _count = _count + 1;
    };
} forEach (keys _nodes);

// ============================================================================
// 2. Stamped groups that hear it and call their own parent
// ============================================================================
// nearEntities is bounded by the noise radius, so an explosion sweeps a
// wider net than a rifle shot. Only C2-stamped groups count — civilians and
// unaffiliated units have nobody to report to.
private _heard = _pos nearEntities [["Man", "Car", "Tank", "Air", "Ship"], _radius];
private _reportingGroups = [];

{
    private _grp = group _x;
    if (alive _x && {!isNull _grp} && {!(_grp in _reportingGroups)}) then {
        private _parent = _grp getVariable ["DSC_c2Parent", ""];
        if (_parent != "" && {!(_parent in _signalled)}) then {
            _reportingGroups pushBack _grp;
        };
    };
} forEach _heard;

// Describe what was actually heard. Previously hardcoded "gunfire", which
// produced feed lines reading "We have gunfire to our west" for a vehicle
// brewing up 3 km away.
private _heardDesc = switch (_noiseType) do {
    case "EXPLOSION":    { "an explosion" };
    case "VEHICLE_KILL": { "a vehicle burning" };
    default              { "gunfire" };
};

{
    private _grp = _x;
    private _parent = _grp getVariable ["DSC_c2Parent", ""];
    if (_parent != "" && {!(_parent in _signalled)}) then {
        private _gPos = getPosATL (leader _grp);
        private _gDist = _gPos distance2D _pos;
        private _conf = 1 - ((_gDist / _radius) * 0.4);
        private _card = [_gPos, _pos] call _fnc_cardinal;

        private _payload = createHashMapFromArray [
            ["callsign",   groupId _grp],
            ["confidence", _conf],
            ["detail",     format ["We have %1 to our %2", _heardDesc, _card]]
        ];

        [_signal, _parent, _pos, _payload] call DSC_core_fnc_c2Signal;
        _signalled pushBack _parent;
        _count = _count + 1;
    };
} forEach _reportingGroups;

if (_count > 0) then {
    LOG_4("c2Noise - %1 (r=%2m) heard by %3 nodes, %4 relaying groups",_noiseType,_radius,_count,count _reportingGroups);
};

_count
