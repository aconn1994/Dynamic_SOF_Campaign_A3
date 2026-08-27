#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_interactionSiteOnCompleteIntel
 * Description:
 *     The standard `onComplete` for an intel-granting interaction site
 *     (mission SSE archetypes and the universal search hook both use this
 *     exact function — they only differ in the `tokenContext` field they
 *     attach to the site at creation time). Reads `_site get "tokenContext"`,
 *     builds a schema-valid token via `fnc_buildIntelTokenFromSite`, and
 *     writes it with `fnc_intelAdd`.
 *
 *     Implemented as a shared global function referenced by both call
 *     sites (rather than an inline closure built per-site) so the
 *     completion behavior is a single, directly testable unit and doesn't
 *     depend on SQF closure semantics surviving from site-creation time to
 *     whenever a player actually finishes the hold — the `tokenContext` is
 *     plain data carried on the site hashmap instead.
 *
 * Arguments:
 *     0: _site <HASHMAP> - The completed interaction site. Must carry a
 *        "tokenContext" <HASHMAP> field (partial intel token, see
 *        fnc_intelAdd's schema).
 *     1: _unit <OBJECT> - The player who completed the hold (unused here,
 *        present for onComplete signature parity).
 *
 * Return Value:
 *     <STRING> - The id of the token written to the ledger.
 *
 * Example:
 *     [_site, _unit] call DSC_core_fnc_interactionSiteOnCompleteIntel;
 */

params [
    ["_site", createHashMap, [createHashMap]],
    ["_unit", objNull, [objNull]]
];

private _tokenContext = _site getOrDefault ["tokenContext", createHashMap];
private _token = [_tokenContext, _site] call DSC_core_fnc_buildIntelTokenFromSite;
private _id = [_token] call DSC_core_fnc_intelAdd;

private _siteId = _site getOrDefault ["id", ""];
LOG_2("interactionSiteOnCompleteIntel - site %1 granted intel token %2",_siteId,_id);

_id
