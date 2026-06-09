#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_rovingDespawnSweep
 * Description:
 *     Sweeps active rovers and culls anything past its despawn ring or
 *     destroyed. Also frees rovers stuck at a dead/destroyed vehicle so the
 *     active list stays accurate for budget.
 *
 *     Cull rules (per type):
 *       - rotary:     distance > 5000m   OR vehicle dead/null
 *       - fixedWing:  distance > 8000m   OR vehicle dead/null
 *       - ground:     distance > 5000m   OR vehicle dead/null
 *       - foot:       distance > 2000m   OR group empty/dead (no vehicle)
 *       - boat:       distance > 3500m   OR vehicle dead/null
 *       - any:        spawnTime older than 600s (failsafe — catches frozen AI)
 *
 *     "Behind player" cone test (dot product) is intentionally NOT used in
 *     Phase 1 — the spawn pattern already routes aircraft past the player
 *     toward a far destination, so pure distance is enough and simpler. Add
 *     dot-product gating if Phase 2 testing shows pop-in artifacts.
 *
 * Arguments:
 *     None — reads DSC_rovingActive directly.
 *
 * Return Value:
 *     <NUMBER> - count of rovers despawned this sweep
 *
 * Example:
 *     [] call DSC_core_fnc_rovingDespawnSweep;
 */

private _active = missionNamespace getVariable ["DSC_rovingActive", []];
if (_active isEqualTo []) exitWith { 0 };

private _player = call CBA_fnc_currentUnit;
if (isNull _player) exitWith { 0 };
private _playerPos = getPosASL _player;

private _now = diag_tickTime;
private _killed = 0;
private _kept = [];

{
    private _record = _x;
    private _vehicle = _record getOrDefault ["vehicle", objNull];
    private _group   = _record getOrDefault ["group",   grpNull];
    private _type    = _record getOrDefault ["type",    "rotary"];
    private _spawnT  = _record getOrDefault ["spawnTime", _now];

    private _despawnRange = switch (_type) do {
        case "fixedWing": { 8000 };
        case "ground":    { 5000 }; // spawn ring is 0.8-2.5km, patrol radius local — 5km gives breathing room
        case "foot":      { 2000 }; // tighter; walkers can't outrun the player anyway
        case "boat":      { 3500 };
        default           { 5000 }; // rotary
    };
    private _age = _now - _spawnT;

    private _shouldCull = false;
    private _reason = "";

    // Foot rovers have no vehicle — measure distance from the group leader,
    // and consider them "dead" if the group has no living units.
    if (_type == "foot") then {
        private _alive = {alive _x} count units _group;
        if (isNull _group || _alive == 0) then {
            _shouldCull = true;
            _reason = "group dead";
        } else {
            private _leader = leader _group;
            private _dist = if (isNull _leader) then { _despawnRange + 1 } else { _leader distance2D _playerPos };
            if (_dist > _despawnRange) then {
                _shouldCull = true;
                _reason = format ["dist=%1m", round _dist];
            } else {
                if (_age > 600) then {
                    _shouldCull = true;
                    _reason = format ["age=%1s", round _age];
                };
            };
        };
    } else {
        if (isNull _vehicle || {!alive _vehicle}) then {
            _shouldCull = true;
            _reason = "dead";
        } else {
            private _dist = _vehicle distance2D _playerPos;
            if (_dist > _despawnRange) then {
                _shouldCull = true;
                _reason = format ["dist=%1m", round _dist];
            } else {
                if (_age > 600) then {
                    _shouldCull = true;
                    _reason = format ["age=%1s", round _age];
                };
            };
        };
    };

    if (_shouldCull) then {
        // Tear down — units first, then vehicle, then group
        {
            if (!isNull _x) then { deleteVehicle _x };
        } forEach units _group;
        if (!isNull _vehicle) then { deleteVehicle _vehicle };
        if (!isNull _group) then { deleteGroup _group };
        _killed = _killed + 1;
        diag_log format ["DSC: roving despawned [%1/%2] %3", _type, _record get "id", _reason];

        // Stats
        private _stats = missionNamespace getVariable ["DSC_rovingStats", createHashMap];
        _stats set ["despawned", (_stats getOrDefault ["despawned", 0]) + 1];
    } else {
        _kept pushBack _record;
    };
} forEach _active;

missionNamespace setVariable ["DSC_rovingActive", _kept, true];
_killed
