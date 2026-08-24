#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_intelAdd
 * Description:
 *     Writes one token into the persistent Intel Ledger (`DSC_intelLedger`),
 *     filling in every field the caller omitted per the token schema
 *     (`.crush/campaign-overhaul.md` §4.1):
 *
 *         intelToken = createHashMapFromArray [
 *             ["id",           "<uid>"],
 *             ["type",         "HVT_LOCATION"],   // see §4.2 type catalog
 *             ["subjectKind",  "ENTITY|LOCATION|FACTION|THREAD|AREA"],
 *             ["subjectRef",   "<id of the thing this is about>"],
 *             ["confidence",   0.65],              // clamped to [0,1]
 *             ["source",       "SSE|BODY_SEARCH|RECON|HQ|CIV_TIP|SIGINT|ISR"],
 *             ["scope",        "AREA|LOCATION|SERIES|DEPLOYMENT"],
 *             ["discoveredAt", serverTime],
 *             ["expiresAt",    serverTime + <per-type TTL>],
 *             ["payload",      createHashMap]      // type-specific
 *         ]
 *
 *     Token composition (default-filling + confidence clamping) is a pure,
 *     self-contained step below — it only ever reads `_partialToken` and
 *     `serverTime`, never the ledger. The ONLY side effect in this function
 *     is the single write to `DSC_intelLedger` at the end.
 *
 *     The §4.2 type catalog is NOT a closed enum: an unrecognized `type`
 *     still gets a sane fallback TTL (3600s) rather than being rejected, so
 *     future token types never need this function to change.
 *
 *     A past `expiresAt` is still stored as-is (already-dead intel is valid
 *     input, e.g. a stale legacy token being retrofitted) — `fnc_intelQuery`
 *     / `fnc_intelBest` are what exclude dead tokens, not this function.
 *
 * Arguments:
 *     0: _partialToken <HASHMAP> - any subset of the schema fields above.
 *
 * Return Value:
 *     <STRING> - the token's id (generated if the caller didn't supply one)
 *
 * Example:
 *     private _id = [createHashMapFromArray [
 *         ["type", "HVT_LOCATION"],
 *         ["subjectRef", "hvt_bombmaker"],
 *         ["confidence", 0.4],
 *         ["source", "SSE"]
 *     ]] call DSC_core_fnc_intelAdd;
 */

params [["_partialToken", createHashMap, [createHashMap]]];

// ============================================================================
// Pure composition — reads only _partialToken + serverTime, never the ledger.
// ============================================================================
private _defaultTtlByType = createHashMapFromArray [
    ["HVT_LOCATION",       7200],
    ["HVT_IDENTITY",       14400],
    ["ENEMY_STRENGTH",     3600],
    ["PATROL_PATTERN",     1800],
    ["AREA_LAYOUT",        10800],
    ["TACTICAL_ADVANTAGE", 3600],
    ["NETWORK_LINK",       21600],
    ["CACHE_LOCATION",     7200],
    ["QRF_POSTURE",        1800],
    ["generic",            3600]
];

private _id = _partialToken getOrDefault ["id", format ["intel_%1_%2", floor (diag_tickTime * 1000), floor (random 1000000)]];
private _type = _partialToken getOrDefault ["type", "generic"];
private _subjectKind = _partialToken getOrDefault ["subjectKind", "AREA"];
private _subjectRef = _partialToken getOrDefault ["subjectRef", ""];

private _confidenceRaw = _partialToken getOrDefault ["confidence", 0.5];
private _confidence = 0 max (1 min _confidenceRaw);

private _source = _partialToken getOrDefault ["source", "SSE"];
private _scope = _partialToken getOrDefault ["scope", "AREA"];
private _discoveredAt = _partialToken getOrDefault ["discoveredAt", serverTime];

private _defaultTtl = _defaultTtlByType getOrDefault [_type, 3600];
private _expiresAt = _partialToken getOrDefault ["expiresAt", _discoveredAt + _defaultTtl];

private _payload = _partialToken getOrDefault ["payload", createHashMap];

private _token = createHashMapFromArray [
    ["id",           _id],
    ["type",         _type],
    ["subjectKind",  _subjectKind],
    ["subjectRef",   _subjectRef],
    ["confidence",   _confidence],
    ["source",       _source],
    ["scope",        _scope],
    ["discoveredAt", _discoveredAt],
    ["expiresAt",    _expiresAt],
    ["payload",      _payload]
];

// ============================================================================
// The one global write.
// ============================================================================
private _ledger = missionNamespace getVariable ["DSC_intelLedger", createHashMap];
_ledger set [_id, _token];
missionNamespace setVariable ["DSC_intelLedger", _ledger, true];

LOG_3("intelAdd - %1 (%2, conf=%3)",_id,_type,_confidence);

_id
