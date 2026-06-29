/*
 * Function: DSC_core_fnc_registerPresenceHandler
 * Description:
 *     Registers a presence zone handler with the manager. Stored in
 *     DSC_presenceHandlers (hashmap keyed by zone type) and consumed by
 *     fnc_activatePresenceZone / fnc_despawnPresenceZone and the main
 *     tick loop in fnc_initPresenceManager.
 *
 *     Handler contract (Sprint A):
 *       "type"           <STRING>   - zone type key (matches _zone "type")
 *       "activateRadius" <NUMBER>   - DORMANT -> ACTIVATING distance
 *       "despawnRadius"  <NUMBER>   - ACTIVE -> DESPAWNING distance
 *       "despawnGrace"   <NUMBER>   - seconds in DESPAWNING before delete
 *       "budgetUnits"    <NUMBER>   - pre-spawn unit estimate (budget gate)
 *       "budgetVehicles" <NUMBER>   - pre-spawn vehicle estimate
 *       "populate"       <CODE>     - fn called with [_zone] by dispatcher
 *       "despawn"        <CODE>     - optional; {} -> use default teardown
 *       "paused"         <BOOL>     - reserved for Sprint C lifecycle variants
 *
 * Arguments:
 *     0: _config <HASHMAP> - handler config; must include "type"
 *
 * Return Value:
 *     <BOOL> - true if registered, false if rejected
 */

params [["_config", createHashMap, [createHashMap]]];

#include "..\..\script_component.hpp"

private _type = _config getOrDefault ["type", ""];
if (_type == "") exitWith {
    ERROR("registerPresenceHandler - missing 'type' key, rejected");
    false
};

private _registry = missionNamespace getVariable ["DSC_presenceHandlers", createHashMap];
_registry set [_type, _config];
missionNamespace setVariable ["DSC_presenceHandlers", _registry, true];

private _actR = _config getOrDefault ["activateRadius", "?"];
private _depR = _config getOrDefault ["despawnRadius", "?"];
private _grace = _config getOrDefault ["despawnGrace", "?"];
private _budU = _config getOrDefault ["budgetUnits", "?"];
private _budV = _config getOrDefault ["budgetVehicles", "?"];
LOG_6("registerPresenceHandler - '%1' (actR=%2 depR=%3 grace=%4 budgetU=%5 budgetV=%6)",_type,_actR,_depR,_grace,_budU,_budV);

true
