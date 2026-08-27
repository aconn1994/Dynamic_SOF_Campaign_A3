#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_removeInteractionSite
 * Description:
 *     Deletes an entry from `DSC_interactionSites`, re-broadcasts the
 *     global, and fires `DSC_interactionSite_changed [_id, "REMOVED"]` so
 *     every client drops the associated `addAction`.
 *
 *     Idempotent — removing an id that isn't registered is not an error.
 *
 *     Callers: `fnc_interactionSiteFire` (site completed), `fnc_cleanupMission`
 *     (every mission-scoped site id, so a generated site never outlives its
 *     mission), and the universal search hook's own housekeeping.
 *
 * Arguments:
 *     0: _id <STRING> - Site id.
 *
 * Return Value:
 *     <BOOL> - false if the id was not found (no-op, not an error).
 *
 * Example:
 *     ["site_12345_678"] call DSC_core_fnc_removeInteractionSite;
 */

params [["_id", "", [""]]];

if (!isServer) exitWith { false };
if (_id == "") exitWith { false };

private _sites = missionNamespace getVariable ["DSC_interactionSites", createHashMap];
if !(_id in _sites) exitWith { false };

_sites deleteAt _id;
missionNamespace setVariable ["DSC_interactionSites", _sites, true];

["DSC_interactionSite_changed", [_id, "REMOVED"]] call CBA_fnc_globalEvent;

LOG_1("removeInteractionSite - %1 removed",_id);

true
