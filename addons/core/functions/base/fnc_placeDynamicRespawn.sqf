#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_placeDynamicRespawn
 * Description:
 *     Playtest aid. On player death, drops (or moves) an invisible
 *     "respawn_west_dynamic" marker a safe distance from the kill site,
 *     biased away from the nearest enemy. With vanilla base respawn
 *     (respawn = 3), side-specific markers (respawn_west_*) take
 *     precedence over the generic base markers (respawn_*), so the player
 *     respawns near where they fell instead of back at base — keeping the
 *     presence manager's local zones alive rather than despawning them.
 *
 *     The generic "respawn_*" base markers remain the spawn for the very
 *     first life (before this marker exists) and for any side without a
 *     dynamic marker.
 *
 * Arguments:
 *     0: _unit <OBJECT> - The killed player
 *
 * Return Value:
 *     None
 *
 * Example:
 *     [player] call DSC_core_fnc_placeDynamicRespawn;
 */

params [["_unit", objNull, [objNull]]];
if (isNull _unit) exitWith {};

private _deathPos = getPosATL _unit;
private _safeDist = 400;

// Guard against being called before the player has a valid world position
// (e.g. the respawnOnStart fake death at mission init). Bail rather than
// create a malformed marker that breaks respawn-template selection.
if (!(_deathPos isEqualType []) || {count _deathPos < 2}) exitWith {
    diag_log "DSC: placeDynamicRespawn skipped - invalid death position";
};
if (!((_deathPos select 0) isEqualType 0) || {!((_deathPos select 1) isEqualType 0)}) exitWith {
    diag_log "DSC: placeDynamicRespawn skipped - non-numeric death position";
};
// Reject the map-origin position the engine reports during the respawnOnStart
// fake death — placing the marker there spawns the player at [0,0,0].
if (_deathPos distance2D [0, 0] < 50) exitWith {
    diag_log "DSC: placeDynamicRespawn skipped - death position at map origin";
};

// Bias the respawn direction away from the nearest living enemy
private _dir = random 360;
private _enemies = (_deathPos nearEntities [["Man", "Car", "Tank", "Air"], 800]) select {
    alive _x && {side _x == east}
};
if (_enemies isNotEqualTo []) then {
    _enemies = [_enemies, [], { _deathPos distance2D _x }, "ASCEND"] call BIS_fnc_sortBy;
    private _threat = _enemies select 0;
    _dir = _threat getDir _unit; // points from threat toward player => away from threat
};

private _candidate = _deathPos getPos [_safeDist, _dir];

// Nudge onto safe, dry ground near the candidate. The 8th param (default
// position) is critical: without it BIS_fnc_findSafePos returns a RANDOM
// map position on failure, which is what caused the random respawns.
private _safePos = [_candidate, 0, 250, 6, 0, 0.5, 0, _candidate, 60] call BIS_fnc_findSafePos;
if ((_safePos select 0) isEqualType 0 && {(_safePos select 1) isEqualType 0}) then {
    _candidate = [_safePos select 0, _safePos select 1, 0];
};
if (!((_candidate select 0) isEqualType 0) || {!((_candidate select 1) isEqualType 0)}) exitWith {
    diag_log "DSC: placeDynamicRespawn skipped - could not resolve a valid position";
};

private _markerName = "respawn_west_dynamic";
deleteMarker _markerName;
private _m = createMarker [_markerName, _candidate];
_m setMarkerTypeLocal "Empty";
_m setMarkerAlpha 0;

diag_log format [
    "DSC: Dynamic respawn marker placed at %1 (%2m from death, dir %3)",
    _candidate, _safeDist, round _dir
];
