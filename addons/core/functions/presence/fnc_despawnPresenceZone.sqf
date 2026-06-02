/*
 * Function: DSC_core_fnc_despawnPresenceZone
 * Description:
 *     Tears down all entities tracked on a presence zone. Called by the
 *     state machine when a zone transitions DESPAWNING -> DORMANT after the
 *     grace window has expired and the player is still outside.
 *
 *     Deletes vehicles first (releases crew), then units, then groups. Clears
 *     the zone's tracking arrays so a subsequent activation starts clean.
 *
 * Arguments:
 *     0: _zone <HASHMAP> - Zone hashmap from DSC_presenceZones
 *
 * Return Value:
 *     <NUMBER> - Total entities removed
 */

params [["_zone", createHashMap, [createHashMap]]];

private _id = _zone get "id";

private _units    = _zone getOrDefault ["units", []];
private _vehicles = _zone getOrDefault ["vehicles", []];
private _groups   = _zone getOrDefault ["groups", []];

private _removed = 0;

// Vehicles first — also evicts/cleans crew that might be tracked separately
{
    if (!isNull _x) then {
        { _x action ["Eject", vehicle _x] } forEach (crew _x);
        deleteVehicle _x;
        _removed = _removed + 1;
    };
} forEach _vehicles;

// Units (any not already deleted by vehicle cleanup)
{
    if (!isNull _x && { alive _x || !alive _x }) then {
        deleteVehicle _x;
        _removed = _removed + 1;
    };
} forEach _units;

// Groups — delete after their units are gone
{
    if (!isNull _x) then {
        // Force-delete any leftover units in the group
        { deleteVehicle _x } forEach (units _x);
        deleteGroup _x;
    };
} forEach _groups;

// Clear tracking
_zone set ["units", []];
_zone set ["vehicles", []];
_zone set ["groups", []];

diag_log format ["DSC: despawnPresenceZone [%1] - removed %2 entities", _id, _removed];

_removed
