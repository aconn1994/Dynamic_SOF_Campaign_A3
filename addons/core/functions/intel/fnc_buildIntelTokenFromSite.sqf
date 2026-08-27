#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_buildIntelTokenFromSite
 * Description:
 *     PURE. Builds a schema-valid PARTIAL intel token
 *     (`fnc_intelAdd`'s schema) from a token context plus an interaction
 *     site, for the interaction-site `onComplete` seam
 *     (`docs/campaign_overhaul/session_05_interaction_site.md` §6). Not
 *     written to the ledger here — the caller still calls `fnc_intelAdd`.
 *     Kept separate for the same reason `fnc_buildMissionOutcome` is kept
 *     separate from the retrofit bridge: a pure builder plus a thin
 *     impure caller, each independently testable.
 *
 *     Every field in `_tokenContext` is copied through verbatim,
 *     INCLUDING an out-of-range `confidence` — clamping is `fnc_intelAdd`'s
 *     job, not this function's. Only `payload` is enriched (not
 *     overwritten) with the site's position/grid/id if the caller didn't
 *     already supply them.
 *
 * Arguments:
 *     0: _tokenContext <HASHMAP> - Partial token: any subset of
 *        type/subjectKind/subjectRef/confidence/source/scope/payload (see
 *        fnc_intelAdd's header for the full schema).
 *     1: _site <HASHMAP> - The interaction site (for payload defaults —
 *        pos/grid/site id).
 *
 * Return Value:
 *     <HASHMAP> - A schema-valid partial token, NOT yet written to the
 *                 ledger.
 *
 * Example:
 *     private _token = [
 *         createHashMapFromArray [["type", "HVT_LOCATION"], ["source", "SSE"], ["confidence", 0.6]],
 *         _site
 *     ] call DSC_core_fnc_buildIntelTokenFromSite;
 *     [_token] call DSC_core_fnc_intelAdd;
 */

params [
    ["_tokenContext", createHashMap, [createHashMap]],
    ["_site", createHashMap, [createHashMap]]
];

private _sitePos = _site getOrDefault ["pos", [0, 0, 0]];
private _siteId = _site getOrDefault ["id", ""];

private _payload = _tokenContext getOrDefault ["payload", createHashMap];
private _payloadOut = createHashMap;
{ _payloadOut set [_x, _y] } forEach _payload;

if !("pos" in _payloadOut) then { _payloadOut set ["pos", _sitePos] };
if !("grid" in _payloadOut) then { _payloadOut set ["grid", mapGridPosition _sitePos] };
if !("siteId" in _payloadOut) then { _payloadOut set ["siteId", _siteId] };

private _token = createHashMap;
{ _token set [_x, _y] } forEach _tokenContext;
_token set ["payload", _payloadOut];

_token
