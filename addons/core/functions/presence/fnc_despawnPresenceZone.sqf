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

// BFT-3 protection: groups commandeered through the Blue Force Tracker
// tablet carry a role tag. fnc_bftExecuteCommand removes them from the
// zone's groups[] array on "take", but this guard keeps any survivors
// alive in case a future code path bypasses the detach.
private _protectedGroups = _groups select { (_x getVariable ["DSC_bftRole", ""]) != "" };
private _groupsToKill    = _groups - _protectedGroups;

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
        // Skip units that belong to a protected (commandeered) group
        if !((group _x) in _protectedGroups) then {
            deleteVehicle _x;
            _removed = _removed + 1;
        };
    };
} forEach _units;

{
    if (!isNull _x) then {
        { deleteVehicle _x } forEach (units _x);
        deleteGroup _x;
    };
} forEach _groupsToKill;

_zone set ["units", []];
_zone set ["vehicles", []];
_zone set ["groups", _protectedGroups];  // keep the commandeered groups attached so they don't double-process

if (_protectedGroups isNotEqualTo []) then {
    diag_log format ["DSC: despawnPresenceZone [%1] - kept %2 commandeered group(s) alive", _id, count _protectedGroups];
};

diag_log format ["DSC: despawnPresenceZone [%1] - removed %2 entities", _id, _removed];

_removed
