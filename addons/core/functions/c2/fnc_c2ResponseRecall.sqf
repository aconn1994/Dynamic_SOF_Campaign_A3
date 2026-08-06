#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_c2ResponseRecall
 * Description:
 *     Sprint F.3 — the cheapest and most common response: tell people who
 *     are ALREADY THERE to go look.
 *
 *     Recall costs nothing to spawn. It redirects existing patrol/rover
 *     groups belonging to this node toward the last known position. This is
 *     what an AMBER alert produces, and it is deliberately the first rung on
 *     the ladder because it is also the most realistic: the immediate
 *     reaction to "something happened over there" is to send the people
 *     nearest to it, not to launch a base QRF.
 *
 *     Only MOBILE roles are recalled. A garrison holds its building and a
 *     static gunner holds his tower — pulling them out to sweep a treeline
 *     would strip the installation the player may be about to hit, and it
 *     looks absurd in game.
 *
 *     Search geometry comes from LKP confidence, not from truth:
 *
 *         searchRadius = baseSpread * (1 + (1 - confidence) * 2)
 *
 *     A direct contact report (confidence 1.0) sends them to a tight box on
 *     the right spot. A third-hand relay (confidence 0.4) sends them
 *     sweeping a radius nearly twice as wide, centred on a position that is
 *     already stale. The enemy acts on what it was told, which is the whole
 *     point of tracking confidence in the first place.
 *
 *     LAMBS is a soft dependency. `lambs_wp_fnc_taskHunt` produces markedly
 *     better search behaviour than a SAD waypoint (it sweeps, splits, and
 *     rechecks buildings), so use it when present and fall back to
 *     fnc_convergePatrols otherwise.
 *
 * Arguments:
 *     0: _nodeId <STRING>  - the responding node
 *     1: _cfg    <HASHMAP> - ladder entry for the current alert level
 *
 * Return Value:
 *     <NUMBER> - how many groups were redirected
 */

params [
    ["_nodeId", "", [""]],
    ["_cfg",    createHashMap, [createHashMap]]
];

if (!isServer) exitWith { 0 };
if (_nodeId isEqualTo "") exitWith { 0 };

private _nodes = missionNamespace getVariable ["DSC_c2Nodes", createHashMap];
private _node = _nodes getOrDefault [_nodeId, createHashMap];
if (_node isEqualTo createHashMap) exitWith { 0 };

private _lkp = _node getOrDefault ["lkp", createHashMap];
private _lkpPos = _lkp getOrDefault ["position", []];
if (_lkpPos isEqualTo []) exitWith {
    LOG_1("c2Recall [%1] - no LKP, nothing to search",_node get "callsign");
    0
};

private _confidence  = _lkp getOrDefault ["confidence", 0.5];
private _baseSpread  = _cfg getOrDefault ["searchSpread", 250];
private _recallRadius= _cfg getOrDefault ["recallRadius", 1500];

// Stale / low-confidence intel widens the sweep.
private _searchRadius = _baseSpread * (1 + ((1 - _confidence) * 2));

private _cs = _node get "callsign";

// ============================================================================
// Pick candidates
// ============================================================================
// Mobile roles only, still alive, within the node's recall radius of the LKP,
// and not already committed to this same search.
private _mobileRoles = ["patrol", "rover"];
private _roster = _node getOrDefault ["groups", []];
private _candidates = [];

{
    private _grp = _x;
    if (isNull _grp) then { continue };

    private _role = _grp getVariable ["DSC_c2Role", ""];
    if !(_role in _mobileRoles) then { continue };

    private _ldr = leader _grp;
    if (isNull _ldr || {!alive _ldr}) then { continue };

    // Already hunting this exact report? Leave them to it.
    if ((_grp getVariable ["DSC_c2RecallLkp", []]) isEqualTo _lkpPos) then { continue };

    if ((getPosATL _ldr) distance2D _lkpPos <= _recallRadius) then {
        _candidates pushBack _grp;
    };
} forEach _roster;

if (_candidates isEqualTo []) exitWith {
    LOG_2("c2Recall [%1] - no mobile groups within %2m of LKP",_cs,_recallRadius);
    0
};

// ============================================================================
// Redirect
// ============================================================================
private _hasLambs = isClass (configFile >> "CfgPatches" >> "lambs_wp");
private _redirected = 0;

{
    private _grp = _x;
    _grp setVariable ["DSC_c2RecallLkp", _lkpPos];

    // Responders are actively hunting — unlike ambient rovers, they get
    // their combat AI back on. Roving spawns deliberately disable
    // AUTOCOMBAT/TARGET/AUTOTARGET to stay passive; a recalled element is
    // no longer ambient and must be able to acquire and engage.
    {
        if (alive _x) then {
            _x enableAI "AUTOCOMBAT";
            _x enableAI "TARGET";
            _x enableAI "AUTOTARGET";
        };
    } forEach units _grp;

    _grp setBehaviour "AWARE";
    _grp setCombatMode "YELLOW";
    _grp setSpeedMode "NORMAL";

    // Rovers may be mounted. taskHunt makes vehicles mill about rather than
    // cover ground, so mounted elements get a plain move-and-engage order.
    private _mounted = !isNull (objectParent (leader _grp));

    if (_hasLambs && {!_mounted}) then {
        // Signature: [_group, _radius, _cycle, _area, _pos, _onlyPlayers, ...]
        // Position is arg 4, NOT arg 2 — passing it as arg 2 silently sets
        // the cycle time to a position array and leaves the search centred on
        // the group instead of the LKP.
        // onlyPlayers=false so they will also find AI the player is fighting
        // alongside, and so the sweep is real rather than player-magnetised.
        [_grp, _searchRadius, 15, [], _lkpPos, false] spawn (missionNamespace getVariable "lambs_wp_fnc_taskHunt");
    } else {
        private _convCfg = createHashMapFromArray [
            ["radius",     _searchRadius],
            ["behaviour",  "AWARE"],
            ["combatMode", "YELLOW"],
            ["speed",      "NORMAL"]
        ];
        [[_grp], _lkpPos, _convCfg] call DSC_core_fnc_convergePatrols;
    };

    _redirected = _redirected + 1;
} forEach _candidates;

private _mode = ["convergePatrols", "LAMBS taskHunt"] select _hasLambs;
INFO_4("c2 RECALL [%1] - %2 groups searching r=%3m (conf=%4)",_cs,_redirected,round _searchRadius,_confidence toFixed 2);
LOG_1("c2Recall - search driver: %1",_mode);

private _grid = mapGridPosition _lkpPos;
[
    "COMMAND",
    _cs,
    "all elements",
    format ["Sweep grid %1, report anything you find", _grid],
    _nodeId,
    "BASIC",
    _lkpPos
] call DSC_core_fnc_c2FeedAdd;

// ============================================================================
// F.4 — player-facing recall notification
// ============================================================================
// A recall is quieter than a QRF (no spawn, no travel — existing groups simply
// change task) so it is easy for the player to miss entirely. Surfacing it is
// what lets them notice "the patrols nearby just started sweeping toward me"
// and break contact before being found.
//
// Gated at ENHANCED for the same reason as QRF dispatch: this is the payoff
// information that justifies keeping a drone alive.
[
    "ISR",
    "",
    "",
    format ["%1 has recalled %2 element(s) to sweep your area", _cs, _redirected],
    _nodeId,
    "ENHANCED",
    _lkpPos
] call DSC_core_fnc_c2FeedAdd;

_redirected
