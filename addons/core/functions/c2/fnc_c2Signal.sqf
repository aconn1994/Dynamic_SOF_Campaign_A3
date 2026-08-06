#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_c2Signal
 * Description:
 *     Sprint F.2 — signal intake and relay propagation. The heart of the
 *     communication simulation.
 *
 *     A signal is a piece of information entering the network at one node.
 *     This function decides whether it survives, how far it travels, how
 *     degraded it is when it arrives, and what alert level it justifies at
 *     each stop.
 *
 *     Three things make this feel like communication rather than telepathy:
 *
 *       1. RELIABILITY ROLLS. Every hop, including intake at the origin,
 *          rolls against the node's archetype reliability. A failed roll
 *          means the message was lost, garbled, or dismissed by whoever
 *          took the call. Irregulars sit at 0.35, so most of what they try
 *          to pass along simply never arrives.
 *
 *       2. GRADE DEGRADATION. A relayed report is hearsay. Each hop drops
 *          the alert grade one rank, so a confirmed contact (RED) makes
 *          neighbors merely suspicious (AMBER) rather than equally certain.
 *          AMBER-grade signals do not relay at all — unverified local noise
 *          is not worth a regional phone call, and this is what keeps the
 *          network quiet enough that a real alert means something.
 *
 *       3. CONFIDENCE DECAY. Last-known-position confidence multiplies down
 *          per hop. F.3 responses search a radius derived from confidence,
 *          so information that crossed three relays produces a wide, lazy
 *          sweep while a direct report produces a tight, dangerous one.
 *
 *     Propagation is breadth-first with a hop cap. Latency accumulates per
 *     hop from each node's tier, so a signal climbing an outstation ->
 *     relay -> command chain genuinely takes minutes to reach the people
 *     with air support. That delay IS the conventional-forces tradeoff:
 *     slow to start, hard when it lands.
 *
 * Arguments:
 *     0: _signalType <STRING>  - see grade table below
 *     1: _originId   <STRING>  - node id where the signal enters
 *     2: _pos        <ARRAY>   - where the event happened (becomes LKP)
 *     3: _payload    <HASHMAP> - optional context:
 *          "callsign"   <STRING> reporting group's identity for the feed
 *          "confidence" <NUMBER> starting LKP confidence (default 1.0)
 *          "detail"     <STRING> human-readable text for the radio feed
 *
 * Return Value:
 *     <NUMBER> - how many nodes ended up raising their alert
 *
 * Example:
 *     ["CONTACT_REPORT", "Kavala", _pos, _payload] call DSC_core_fnc_c2Signal;
 */

params [
    ["_signalType", "", [""]],
    ["_originId",   "", [""]],
    ["_pos",        [], [[]]],
    ["_payload",    createHashMap, [createHashMap]]
];

if (_signalType isEqualTo "" || {_originId isEqualTo ""}) exitWith { 0 };

private _nodes = missionNamespace getVariable ["DSC_c2Nodes", createHashMap];
private _origin = _nodes getOrDefault [_originId, createHashMap];
if (_origin isEqualTo createHashMap) exitWith {
    LOG_2("c2Signal - unknown origin node '%1' for %2",_originId,_signalType);
    0
};

private _arch = [] call DSC_core_fnc_getC2Archetypes;
private _rank = _arch get "alertRank";
private _grades = _arch get "signalGrades";

private _gradeCfg = _grades getOrDefault [_signalType, createHashMap];
if (_gradeCfg isEqualTo createHashMap) exitWith {
    WARNING_1("c2Signal - unknown signal type '%1'",_signalType);
    0
};

private _grade    = _gradeCfg getOrDefault ["grade", "AMBER"];
private _maxHops  = _gradeCfg getOrDefault ["maxHops", 2];
private _label    = _gradeCfg getOrDefault ["label", _signalType];
private _refresh  = _gradeCfg getOrDefault ["refresh", true];
private _echoWin  = _gradeCfg getOrDefault ["echo", 0];

private _confidence = _payload getOrDefault ["confidence", 1.0];
private _callsign   = _payload getOrDefault ["callsign", ""];
private _detail     = _payload getOrDefault ["detail", ""];

private _stats = missionNamespace getVariable ["DSC_c2Stats", createHashMap];
_stats set ["signalsRaised", (_stats getOrDefault ["signalsRaised", 0]) + 1];

// ============================================================================
// Intake roll at the origin
// ============================================================================
// Even the first link in the chain can fail. Somebody has to actually pick
// up, understand, and believe the report. A militia radio watch that misses
// the call is the difference between a quiet exfil and a QRF.
private _originReliability = _origin getOrDefault ["reliability", 0.5];
private _originCallsign    = _origin get "callsign";

if (random 1 > _originReliability) exitWith {
    _stats set ["signalsLost", (_stats getOrDefault ["signalsLost", 0]) + 1];
    LOG_3("c2Signal - %1 LOST at intake [%2] (reliability %3)",_signalType,_originCallsign,_originReliability);

    [
        "LOST",
        _callsign,
        _originCallsign,
        format ["%1 (not received)", _label],
        _originId,
        "BASIC",
        _pos
    ] call DSC_core_fnc_c2FeedAdd;

    0
};

// ============================================================================
// Echo suppression
// ============================================================================
// A repeat of the same signal type at the same node inside its echo window is
// corroboration, not news. Record it (LKP + feed) and stop — do not re-raise
// and do not re-walk the relay tree. This is what keeps one firefight from
// generating one full propagation pass per defending group.
private _echoLog = _origin getOrDefault ["lastSignalAt", createHashMap];
private _lastAt  = _echoLog getOrDefault [_signalType, -99999];

if (_echoWin > 0 && {(serverTime - _lastAt) < _echoWin}) exitWith {
    if (_pos isNotEqualTo []) then {
        _origin set ["lkp", createHashMapFromArray [
            ["position",   _pos],
            ["time",       serverTime],
            ["confidence", _confidence],
            ["source",     _signalType]
        ]];
    };

    _stats set ["signalsEchoed", (_stats getOrDefault ["signalsEchoed", 0]) + 1];
    LOG_2("c2Signal - %1 echoed at [%2] (already reported, LKP updated)",_signalType,_originCallsign);

    [
        "INTERCEPT",
        _callsign,
        _originCallsign,
        format ["%1 (corroborating)", _label],
        _originId,
        "BASIC",
        _pos
    ] call DSC_core_fnc_c2FeedAdd;

    0
};

_echoLog set [_signalType, serverTime];
_origin set ["lastSignalAt", _echoLog];

// ============================================================================
// Origin alert
// ============================================================================
private _raised = 0;

// Latency is modelled as an information delay, not a spawn delay. F.1's
// raise is immediate; F.3 will consume the node's latency range when it
// decides how long to wait before actually dispatching anything.
if ([_originId, _grade, _signalType, _pos, _confidence, _refresh] call DSC_core_fnc_c2RaiseAlert) then {
    _raised = _raised + 1;
};

private _feedText = [_label, _detail] select (_detail != "");
[
    "INTERCEPT",
    _callsign,
    _originCallsign,
    _feedText,
    _originId,
    "BASIC",
    _pos
] call DSC_core_fnc_c2FeedAdd;

// ============================================================================
// Relay propagation — breadth-first with degradation
// ============================================================================
// AMBER signals stop at the origin. Unverified noise does not travel; only
// a confirmed contact or a lost element justifies waking the neighbors.
private _originRank = _rank getOrDefault [_grade, 0];
if (_originRank <= 1) exitWith {
    LOG_3("c2Signal - %1 -> [%2] %3 (no relay, unverified grade)",_signalType,_originCallsign,_grade);
    _raised
};

private _visited = [_originId];
// Frontier entries: [nodeId, hopCount, gradeRank, confidence]
private _frontier = [[_originId, 0, _originRank, _confidence]];
private _relayAttempts = 0;
private _relayLost = 0;

while { _frontier isNotEqualTo [] } do {
    private _entry = _frontier deleteAt 0;
    _entry params ["_curId", "_hop", "_curRank", "_curConf"];

    if (_hop >= _maxHops) then { continue };

    private _curNode = _nodes getOrDefault [_curId, createHashMap];
    if (_curNode isEqualTo createHashMap) then { continue };

    // Hearsay is less alarming than a direct report.
    private _nextRank = _curRank - 1;
    if (_nextRank < 1) then { continue };

    private _nextGrade = switch (_nextRank) do {
        case 3: { "BLACK" };
        case 2: { "RED" };
        default { "AMBER" };
    };

    private _nextConf = _curConf * 0.75;

    {
        private _linkId = _x;
        if !(_linkId in _visited) then {
            _visited pushBack _linkId;
            private _linkNode = _nodes getOrDefault [_linkId, createHashMap];

            if (_linkNode isNotEqualTo createHashMap) then {
                _relayAttempts = _relayAttempts + 1;
                private _linkReliability = _linkNode getOrDefault ["reliability", 0.5];

                if (random 1 <= _linkReliability) then {
                    private _relaySource = format ["relay:%1", _signalType];
                    if ([_linkId, _nextGrade, _relaySource, _pos, _nextConf, _refresh] call DSC_core_fnc_c2RaiseAlert) then {
                        _raised = _raised + 1;
                    };

                    private _linkCs = _linkNode get "callsign";
                    [
                        "INTERCEPT",
                        _originCallsign,
                        _linkCs,
                        format ["Relaying: %1", _label],
                        _linkId,
                        "BASIC",
                        _pos
                    ] call DSC_core_fnc_c2FeedAdd;

                    _frontier pushBack [_linkId, _hop + 1, _nextRank, _nextConf];
                } else {
                    _relayLost = _relayLost + 1;
                    private _lostCs = _linkNode get "callsign";
                    LOG_2("c2Signal - relay to [%1] failed reliability roll (%2)",_lostCs,_linkReliability);
                };
            };
        };
    } forEach (_curNode getOrDefault ["links", []]);
};

if (_relayLost > 0) then {
    _stats set ["relaysLost", (_stats getOrDefault ["relaysLost", 0]) + _relayLost];
};

LOG_4("c2Signal - %1 from [%2]: %3 nodes alerted (%4 relay attempts)",_signalType,_originCallsign,_raised,_relayAttempts);

_raised
