#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_createInteractionSite
 * Description:
 *     Side-effecting, server-only counterpart to
 *     `fnc_buildInteractionSiteConfig`. Rolls the actual hold duration from
 *     the config's `[min,max]` pair, registers the site into the global
 *     registry `DSC_interactionSites` (hashmap id -> site) using the same
 *     JIP-safe `missionNamespace setVariable [..., true]` broadcast idiom
 *     already used for `DSC_currentMission`/`missionState` — no new sync
 *     mechanism — and fires `DSC_interactionSite_changed` so already
 *     connected clients arm the action immediately instead of waiting on a
 *     rescan.
 *
 *     Lazily registers the ONE server-side listener for
 *     `DSC_interactionSite_fire` (client -> server "I finished the hold")
 *     on first use. This keeps the interaction-site primitive fully
 *     self-contained — no dedicated init step needs wiring into
 *     `fnc_initServer` — while guaranteeing the listener exists before any
 *     client could possibly see an ARMED site to act on.
 *
 * Arguments:
 *     0: _rawConfig <HASHMAP> - Same shape fnc_buildInteractionSiteConfig
 *        accepts (any subset of the canonical site shape).
 *
 * Return Value:
 *     <STRING> - The site's id. "" if called off the server.
 *
 * Example:
 *     private _id = [createHashMapFromArray [
 *         ["pos", getPos player],
 *         ["action", "Conduct SSE"],
 *         ["onComplete", DSC_core_fnc_interactionSiteOnCompleteIntel],
 *         ["tokenContext", createHashMapFromArray [["type", "HVT_LOCATION"]]]
 *     ]] call DSC_core_fnc_createInteractionSite;
 */

params [["_rawConfig", createHashMap, [createHashMap]]];

if (!isServer) exitWith {
    WARNING("createInteractionSite - called off the server, no-op");
    ""
};

if (isNil "DSC_interactionSiteFireHandlerRegistered") then {
    DSC_interactionSiteFireHandlerRegistered = true;
    ["DSC_interactionSite_fire", {
        params ["_firedId", ["_firedUnit", objNull, [objNull]]];
        [_firedId, _firedUnit] call DSC_core_fnc_interactionSiteFire;
    }] call CBA_fnc_addEventHandler;
    LOG("createInteractionSite - DSC_interactionSite_fire listener registered");
};

private _site = [_rawConfig] call DSC_core_fnc_buildInteractionSiteConfig;

private _durationRange = _site get "duration";
private _rolled = (_durationRange select 0) + (random ((_durationRange select 1) - (_durationRange select 0)));
_site set ["durationRolled", _rolled];

private _id = _site get "id";

private _sites = missionNamespace getVariable ["DSC_interactionSites", createHashMap];
_sites set [_id, _site];
missionNamespace setVariable ["DSC_interactionSites", _sites, true];

["DSC_interactionSite_changed", [_id, "ARMED"]] call CBA_fnc_globalEvent;

LOG_3("createInteractionSite - %1 armed at %2 (hold %3s)",_id,_site get "pos",round _rolled);

_id
