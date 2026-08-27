#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_initInteractionSites
 * Description:
 *     Client-local. Called once from `fnc_initPlayerLocal`, same place the
 *     other player-local wiring lives — JIP-safe by construction since
 *     every client (including late joiners) runs `fnc_initPlayerLocal`.
 *
 *     Walks the current `DSC_interactionSites` registry (already
 *     broadcast, JIP-safe, by `fnc_createInteractionSite`) and arms one
 *     action per ARMED entry, then registers a `DSC_interactionSite_changed`
 *     CBA handler for incremental arm/disarm without a full rescan.
 *
 * Arguments: None
 *
 * Return Value: None
 *
 * Example:
 *     [] call DSC_core_fnc_initInteractionSites;
 */

if (!hasInterface) exitWith {};

player setVariable ["DSC_interactionActionIds", createHashMap];

{
    private _id = _x;
    private _site = _y;
    if ((_site getOrDefault ["state", ""]) == "ARMED") then {
        [_id] call DSC_core_fnc_interactionSiteArmLocal;
    };
} forEach (missionNamespace getVariable ["DSC_interactionSites", createHashMap]);

["DSC_interactionSite_changed", {
    params ["_id", "_state"];
    if (_state == "ARMED") then {
        [_id] call DSC_core_fnc_interactionSiteArmLocal;
    } else {
        [_id] call DSC_core_fnc_interactionSiteDisarmLocal;
    };
}] call CBA_fnc_addEventHandler;

INFO("initInteractionSites - client-local interaction site arming wired");
