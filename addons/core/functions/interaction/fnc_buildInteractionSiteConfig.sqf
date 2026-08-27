#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_buildInteractionSiteConfig
 * Description:
 *     PURE builder for the canonical interaction-site shape
 *     (`docs/campaign_overhaul/session_05_interaction_site.md` §1):
 *
 *         interactionSite = createHashMapFromArray [
 *             ["id",               "<uid>"],
 *             ["pos",              [x,y,z]],
 *             ["radius",           10],
 *             ["action",           "Conduct SSE"],
 *             ["duration",         [20, 60]],       // [min,max] seconds
 *             ["onComplete",       {}],              // code, [_site, _unit]
 *             ["dressing",         ""],
 *             ["tangibility",      "abstract"],       // abstract|focalProp|composition
 *             ["requireCount",     [1, 1]],           // instance-count, NOT completion count
 *             ["state",            "ARMED"],          // ARMED|COMPLETE|REMOVED
 *             ["completedBy",      objNull],
 *             ["markerLocationId", ""]
 *         ]
 *
 *     Fills in every field the caller omitted. Caller-supplied fields are
 *     copied through verbatim and never overwritten. Reads only
 *     `_rawConfig`, `diag_tickTime` and `random` for id generation — no
 *     globals are read or written, and no random hold duration is rolled
 *     here (that happens once in `fnc_createInteractionSite`, which is the
 *     side-effecting half of this split).
 *
 *     `requireCount` is intentionally the INSTANCE-count meaning (how many
 *     sites one archetype spec generates), not the completion-count
 *     meaning ("finish N of M sites") — that lives on the mission's
 *     `completionState.sitesRequired`, consumed by the `SITES_INTERACTED`
 *     completion type. See the naming-collision note in the session 5
 *     mini-spec §1.
 *
 * Arguments:
 *     0: _rawConfig <HASHMAP> - Any subset of the shape above.
 *
 * Return Value:
 *     <HASHMAP> - The canonical site config, all fields present.
 *
 * Example:
 *     private _site = [createHashMapFromArray [["pos", getPos player]]]
 *         call DSC_core_fnc_buildInteractionSiteConfig;
 */

params [["_rawConfig", createHashMap, [createHashMap]]];

private _site = createHashMap;
{ _site set [_x, _y] } forEach _rawConfig;

private _fnc_normalizePair = {
    params ["_pair", "_fallback"];
    if !(_pair isEqualType [] && {count _pair == 2}) exitWith { _fallback };
    if ((_pair select 0) > (_pair select 1)) exitWith { [_pair select 1, _pair select 0] };
    _pair
};

if !("id" in _site) then {
    _site set ["id", format ["site_%1_%2", floor (diag_tickTime * 1000), floor (random 1000000)]];
};
if !("pos" in _site) then { _site set ["pos", [0, 0, 0]] };
if !("radius" in _site) then { _site set ["radius", 10] };
if !("action" in _site) then { _site set ["action", "Conduct SSE"] };

_site set ["duration", [_site getOrDefault ["duration", [20, 60]], [20, 60]] call _fnc_normalizePair];

if !("onComplete" in _site) then { _site set ["onComplete", {}] };
if !("dressing" in _site) then { _site set ["dressing", ""] };
if !("tangibility" in _site) then { _site set ["tangibility", "abstract"] };

_site set ["requireCount", [_site getOrDefault ["requireCount", [1, 1]], [1, 1]] call _fnc_normalizePair];

if !("state" in _site) then { _site set ["state", "ARMED"] };
if !("completedBy" in _site) then { _site set ["completedBy", objNull] };
if !("markerLocationId" in _site) then { _site set ["markerLocationId", ""] };

_site
