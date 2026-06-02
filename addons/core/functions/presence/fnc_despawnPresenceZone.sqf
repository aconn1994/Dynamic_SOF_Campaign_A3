/*
 * Function: DSC_core_fnc_despawnPresenceZone
 * Description:
 *     Dispatcher + default teardown. If the zone's registered handler
 *     supplies a "despawn" code block (non-empty), that runs instead.
 *     Otherwise the default behavior runs: delete vehicles first (releases
 *     crew), then units, then groups. Clears the zone's tracking arrays so
 *     a subsequent activation starts clean.
 *
 * Arguments:
 *     0: _zone <HASHMAP> - Zone hashmap from DSC_presenceZones
 *
 * Return Value:
 *     <NUMBER> - Total entities removed (0 if a custom handler took over)
 */

params [["_zone", createHashMap, [createHashMap]]];

private _id   = _zone get "id";
private _type = _zone get "type";

// Custom handler.despawn override?
private _registry = missionNamespace getVariable ["DSC_presenceHandlers", createHashMap];
private _handler  = _registry getOrDefault [_type, createHashMap];
private _customDespawn = _handler getOrDefault ["despawn", {}];
if (_customDespawn isNotEqualTo {}) exitWith {
    private _result = [_zone] call _customDespawn;
    diag_log format ["DSC: despawnPresenceZone [%1] - custom handler (type=%2)", _id, _type];
    _result
};

// ----- Default teardown -----
private _units    = _zone getOrDefault ["units", []];
private _vehicles = _zone getOrDefault ["vehicles", []];
private _groups   = _zone getOrDefault ["groups", []];

private _removed = 0;

{
    if (!isNull _x) then {
        { _x action ["Eject", vehicle _x] } forEach (crew _x);
        deleteVehicle _x;
        _removed = _removed + 1;
    };
} forEach _vehicles;

{
    if (!isNull _x && { alive _x || !alive _x }) then {
        deleteVehicle _x;
        _removed = _removed + 1;
    };
} forEach _units;

{
    if (!isNull _x) then {
        { deleteVehicle _x } forEach (units _x);
        deleteGroup _x;
    };
} forEach _groups;

_zone set ["units", []];
_zone set ["vehicles", []];
_zone set ["groups", []];

diag_log format ["DSC: despawnPresenceZone [%1] - removed %2 entities", _id, _removed];

_removed
