/*
 * Function: DSC_core_fnc_presenceLogTimings
 * Description:
 *     Aggregates per-zone activation timings into a global rolling log so
 *     stutter sources can be diagnosed without an external profiler.
 *
 *     Writes to:
 *       - RPT via diag_log (per call, single line)
 *       - DSC_presenceTimings (array, capped at 50 entries, newest last)
 *       - DSC_presenceTimingTotals (hashmap, ms summed per step across session)
 *
 *     The cumulative log is small — each entry is one hashmap. Inspect it
 *     in-game with:
 *       diag_log (missionNamespace getVariable "DSC_presenceTimings");
 *       diag_log (missionNamespace getVariable "DSC_presenceTimingTotals");
 *
 * Arguments:
 *     0: _zoneType <STRING>   - "base"|"outpost"|"camp"|"populatedArea"
 *     1: _zoneId   <STRING>
 *     2: _timings  <HASHMAP>  - step -> elapsed ms (cumulative since start of activate)
 *     3: _units    <NUMBER>
 *     4: _vehicles <NUMBER>
 */

params ["_zoneType", "_zoneId", "_timings", "_units", "_vehicles"];

#include "..\..\script_component.hpp"

private _log = missionNamespace getVariable ["DSC_presenceTimings", []];
private _totals = missionNamespace getVariable ["DSC_presenceTimingTotals", createHashMap];

// Convert cumulative ms into per-step deltas for readability
private _ordered = ["staticDefenses", "patrols", "mortars", "vehicles", "civilians", "militaryOverlay", "curator"];
private _prev = 0;
private _deltas = createHashMap;
private _totalMs = 0;
{
    if (_x in _timings) then {
        private _cum = _timings get _x;
        private _d = _cum - _prev;
        _deltas set [_x, _d];
        _prev = _cum;
        _totalMs = _cum;

        private _running = _totals getOrDefault [_x, 0];
        _totals set [_x, _running + _d];
    };
} forEach _ordered;

private _entry = createHashMapFromArray [
    ["t",        diag_tickTime],
    ["type",     _zoneType],
    ["id",       _zoneId],
    ["units",    _units],
    ["vehicles", _vehicles],
    ["totalMs",  _totalMs],
    ["steps",    _deltas]
];

_log pushBack _entry;
if (count _log > 50) then { _log deleteAt 0 };

missionNamespace setVariable ["DSC_presenceTimings", _log, true];
missionNamespace setVariable ["DSC_presenceTimingTotals", _totals, true];

// Build a compact per-step string: "guards=12.4 vehicles=8.1 ..."
private _parts = [];
{
    if (_x in _deltas) then {
        _parts pushBack format ["%1=%2", _x, (_deltas get _x) toFixed 1];
    };
} forEach _ordered;

LOG_6("presence timing [%1/%2] total=%3ms u=%4 v=%5 | %6",_zoneType,_zoneId,_totalMs toFixed 1,_units,_vehicles,_parts joinString " ");
