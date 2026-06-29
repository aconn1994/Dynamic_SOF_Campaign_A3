/*
 * Function: DSC_core_fnc_activatePresenceZone
 * Description:
 *     Dispatcher. Looks up the registered handler for a zone's type in
 *     DSC_presenceHandlers and invokes its "populate" code. If no handler
 *     is registered for the type, logs and returns false.
 *
 *     Handlers are registered at init by fnc_initPresenceManager via
 *     fnc_registerPresenceHandler.
 *
 * Arguments:
 *     0: _zone <HASHMAP> - Zone hashmap from DSC_presenceZones
 *
 * Return Value:
 *     <BOOL> - true if anything was spawned, false if no-op / blocked
 */

params [["_zone", createHashMap, [createHashMap]]];

#include "..\..\script_component.hpp"

private _id   = _zone get "id";
private _type = _zone get "type";

private _registry = missionNamespace getVariable ["DSC_presenceHandlers", createHashMap];
private _handler  = _registry getOrDefault [_type, createHashMap];

if (_handler isEqualTo createHashMap) exitWith {
    WARNING_2("activatePresenceZone [%1] - skip (no handler registered for type=%2)",_id,_type);
    false
};

private _populate = _handler getOrDefault ["populate", {}];
if (_populate isEqualTo {}) exitWith {
    WARNING_2("activatePresenceZone [%1] - skip (handler for type=%2 has no populate fn)",_id,_type);
    false
};

[_zone] call _populate
