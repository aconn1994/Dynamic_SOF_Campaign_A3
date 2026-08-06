#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_c2Respond
 * Description:
 *     Sprint F.3 — the response dispatcher. Decides whether a node acts on
 *     its current alert state, and what it is capable of sending.
 *
 *     Called from the C2 tick for every alerted node. Three gates have to
 *     pass before anything is launched, and each one exists to preserve a
 *     specific design property:
 *
 *       1. LATENCY — a node does not react the instant it hears something.
 *          It waits out its tier's decision delay (COMMAND 60-120s, RELAY
 *          45-90s, OUTSTATION 15-45s) from the moment the alert was raised.
 *          This is the mechanic that makes conventional forces SLOW TO START
 *          but hard when they land, and gives the player a real window to
 *          break contact after being spotted.
 *
 *       2. COOLDOWN — after dispatching, a node will not dispatch again for
 *          the ladder's cooldown. Without this a node sitting at RED for its
 *          full 7-minute decay would launch a fresh wave every 10s tick and
 *          bury the player under 40 groups.
 *
 *       3. CAPABILITY — the ladder says what this alert level *wants*; the
 *          tier says what this installation *has*. Intersecting them is what
 *          makes a village at RED send people looking while an airbase at RED
 *          sends vehicles. A town cannot conjure a mounted QRF it never had.
 *
 *     Responses are dispatched in ladder order (recall before QRF), because
 *     recall is free and instant while QRF is expensive and slow — and
 *     because that is genuinely the order a real command post would work in.
 *
 * Arguments:
 *     0: _nodeId <STRING> - node to evaluate
 *
 * Return Value:
 *     <BOOL> - true if anything was dispatched
 */

params [["_nodeId", "", [""]]];

if (!isServer) exitWith { false };
if (_nodeId isEqualTo "") exitWith { false };

private _nodes = missionNamespace getVariable ["DSC_c2Nodes", createHashMap];
private _node = _nodes getOrDefault [_nodeId, createHashMap];
if (_node isEqualTo createHashMap) exitWith { false };

private _alert = _node getOrDefault ["alert", "GREEN"];
if (_alert isEqualTo "GREEN") exitWith { false };

private _arch   = [] call DSC_core_fnc_getC2Archetypes;
private _ladder = _arch get "responseLadder";
private _tierResponses = _arch get "tierResponses";

private _cfg = _ladder getOrDefault [_alert, createHashMap];
if (_cfg isEqualTo createHashMap) exitWith { false };

private _cs = _node get "callsign";

// ============================================================================
// Gate 1: decision latency
// ============================================================================
// Stored as an ABSOLUTE DEADLINE (`responseDueAt`), not as an elapsed-time
// comparison against `alertSince`. Sustained contact refreshes `alertSince`
// on every incoming report, so gating on elapsed-since-alert meant the
// deadline receded faster than the clock advanced and the node never acted.
// An absolute deadline set once per escalation cannot be pushed back.
private _tier = _node getOrDefault ["tier", "OUTSTATION"];
private _dueAt = _node getOrDefault ["responseDueAt", -1];

if (_dueAt < 0) then {
    private _latencyRange = _node getOrDefault ["latency", [30, 60]];
    _latencyRange params [["_lMin", 30], ["_lMax", 60]];
    private _roll = _lMin + random (_lMax - _lMin);
    _dueAt = serverTime + _roll;
    _node set ["responseDueAt", _dueAt];
    LOG_3("c2Respond [%1] - %2 deciding, will act in %3s",_cs,_tier,round _roll);
};

if (serverTime < _dueAt) exitWith { false };

// ============================================================================
// Gate 2: cooldown
// ============================================================================
private _lastDispatch = _node getOrDefault ["lastDispatch", -99999];
private _cooldown = _cfg getOrDefault ["cooldown", 300];
if ((serverTime - _lastDispatch) < _cooldown) exitWith {
    false
};

// ============================================================================
// Gate 3: capability — ladder wants ∩ tier has
// ============================================================================
private _wanted = _cfg getOrDefault ["responses", []];
private _canDo  = _tierResponses getOrDefault [_tier, []];
private _available = _wanted select { _x in _canDo };

if (_available isEqualTo []) exitWith {
    // Back off rather than re-testing every tick for the rest of the alert.
    _node set ["lastDispatch", serverTime];
    LOG_3("c2Respond [%1] - %2 at %3 has no capable response",_cs,_tier,_alert);
    false
};

// ============================================================================
// Dispatch
// ============================================================================
private _did = false;

{
    switch (_x) do {
        case "recall": {
            private _n = [_nodeId, _cfg] call DSC_core_fnc_c2ResponseRecall;
            if (_n > 0) then { _did = true };
        };
        case "qrf": {
            private _want = _cfg getOrDefault ["qrfCount", 0];
            for "_i" from 1 to _want do {
                private _n = [_nodeId, _cfg] call DSC_core_fnc_c2ResponseQrf;
                if (_n > 0) then { _did = true };
                // Yield between waves so a BLACK double-dispatch doesn't
                // stack two vehicle spawns into one frame.
                if (_want > 1) then { uiSleep 0.5 };
            };
        };
    };
} forEach _available;

if (_did) then {
    _node set ["lastDispatch", serverTime];

    // Mark the owning presence zone as in-combat so it stops acquiring new
    // ambient population while the response plays out. See the combat
    // substitution note in .crush/c2-network.md — the QRF becomes the local
    // density rather than adding to it.
    private _zones = missionNamespace getVariable ["DSC_presenceZones", createHashMap];
    private _zone = _zones getOrDefault [_nodeId, createHashMap];
    if (_zone isNotEqualTo createHashMap) then {
        _zone set ["combatUntil", serverTime + 300];
    };
} else {
    // Nothing could be launched — most often "recall found no mobile groups
    // in range". Apply a short backoff so the node isn't re-evaluated (and
    // re-logged) on every 10s tick for the entire alert window. A playtest
    // produced four nodes each printing "no mobile groups within 1200m"
    // every tick for minutes.
    _node set ["lastDispatch", serverTime - _cooldown + 90];
};

_did
