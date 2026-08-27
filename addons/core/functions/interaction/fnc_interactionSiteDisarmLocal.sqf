#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_interactionSiteDisarmLocal
 * Description:
 *     Client-local. Removes the `addAction` armed by
 *     `fnc_interactionSiteArmLocal` for a given site id, if any. Called on
 *     a `DSC_interactionSite_changed [_id, "REMOVED"]` (or any non-ARMED)
 *     event so a completed/torn-down site doesn't leave a dangling action
 *     on the player.
 *
 *     Idempotent — a site id with no armed action is a silent no-op.
 *
 * Arguments:
 *     0: _id <STRING> - Site id.
 *
 * Return Value:
 *     <BOOL> - true if an action was removed.
 *
 * Example:
 *     ["site_12345_678"] call DSC_core_fnc_interactionSiteDisarmLocal;
 */

params [["_id", "", [""]]];

if (_id == "") exitWith { false };

private _actionIds = player getVariable ["DSC_interactionActionIds", createHashMap];
private _actionId = _actionIds getOrDefault [_id, -1];
if (_actionId == -1) exitWith { false };

player removeAction _actionId;
_actionIds deleteAt _id;
player setVariable ["DSC_interactionActionIds", _actionIds];

LOG_1("interactionSiteDisarmLocal - disarmed action for %1",_id);

true
