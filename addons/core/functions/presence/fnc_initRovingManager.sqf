#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_initRovingManager
 * Description:
 *     Sprint E Phase 1 — Roving Entities Subsystem (air only).
 *
 *     Sibling system to the Presence Manager. Independent globals, independent
 *     tick + worker, independent budget. Same 8s cadence as presence but
 *     phase-offset 4s so spawn decisions don't collide on the scheduler.
 *
 *     Phase 1 spawns ambient rotary + fixed-wing air traffic biased toward
 *     military installations (bases / outposts / airbases). Aircraft transit
 *     through the player's vicinity en route to a destination hotspot and
 *     despawn behind the player at range.
 *
 *     Phase 2 (deferred): ground vehicle patrols.
 *     Phase 3 (deferred): civilian vehicles + boats.
 *
 *     Coordination with Presence Manager:
 *       - Phase-offset 4s tick so decision windows alternate
 *       - Roving uses its own budget; no shared cap
 *       - Worker yields between spawns (uiSleep) — air is cheap
 *         (~100ms per spawn) so we never block the scheduler long
 *       - Mission AO arbitration honored independently
 *
 *     Globals set:
 *       DSC_rovingHotspots          <HASHMAP>  hotspot registry
 *       DSC_rovingActive            <ARRAY>    active rover records
 *       DSC_rovingSpawnQueue        <ARRAY>    pending spawn requests
 *       DSC_rovingWorkerHeartbeat   <NUMBER>   diag_tickTime
 *       DSC_rovingStats             <HASHMAP>  session counters
 *       DSC_rovingBudgetRotary      <NUMBER>   cap (default 2)
 *       DSC_rovingBudgetFixed       <NUMBER>   cap (default 1)
 *
 * Arguments:
 *     0: _influenceData <HASHMAP>
 *     1: _factionData   <HASHMAP>
 *
 * Return Value:
 *     <NUMBER> - hotspot count
 *
 * Example:
 *     [_influenceData, _factionData] call DSC_core_fnc_initRovingManager;
 */

params [
    ["_influenceData", createHashMap, [createHashMap]],
    ["_factionData",   createHashMap, [createHashMap]]
];

// ============================================================================
// Build hotspot registry
// ============================================================================
private _hotspots = [_influenceData, _factionData] call DSC_core_fnc_resolveRovingHotspots;
missionNamespace setVariable ["DSC_rovingHotspots", _hotspots, true];

private _eastCount = count (_hotspots getOrDefault ["east", []]);
private _westCount = count (_hotspots getOrDefault ["west", []]);

if (_eastCount == 0 && _westCount == 0) exitWith {
    diag_log "DSC: rovingManager - No hotspots found, aborting (no air rovers will spawn)";
    0
};

// ============================================================================
// Globals
// ============================================================================
missionNamespace setVariable ["DSC_rovingActive", [], true];
missionNamespace setVariable ["DSC_rovingSpawnQueue", [], true];
missionNamespace setVariable ["DSC_rovingBudgetRotary", 3, true];
missionNamespace setVariable ["DSC_rovingBudgetFixed", 2, true];
missionNamespace setVariable ["DSC_rovingBudgetGround", 4, true];
missionNamespace setVariable ["DSC_rovingBudgetFoot", 2, true];
missionNamespace setVariable ["DSC_rovingBudgetBoat", 2, true];
missionNamespace setVariable ["DSC_rovingStats", createHashMapFromArray [
    ["spawned",            0],
    ["rotarySpawned",      0],
    ["fixedWingSpawned",   0],
    ["groundSpawned",      0],
    ["footSpawned",        0],
    ["boatSpawned",        0],
    ["despawned",          0],
    ["nearHotspotSpawns",  0],
    ["skippedAoOverlap",   0],
    ["skippedNoHotspot",   0],
    ["skippedBudget",      0],
    ["spawnAttempts",      0],
    ["loopStart",          diag_tickTime]
], true];
missionNamespace setVariable ["DSC_rovingWorkerHeartbeat", diag_tickTime, true];

diag_log format ["DSC: rovingManager - %1 east hotspots, %2 west hotspots registered", _eastCount, _westCount];

// ============================================================================
// Worker — drains spawn queue with yields
// ============================================================================
[_factionData] spawn {
    params ["_factionData"];
    while { true } do {
        missionNamespace setVariable ["DSC_rovingWorkerHeartbeat", diag_tickTime, true];
        private _q = missionNamespace getVariable ["DSC_rovingSpawnQueue", []];
        if (_q isNotEqualTo []) then {
            private _req = _q deleteAt 0;
            _req params [["_subtype", "rotary", [""]], ["_sideKey", "auto", [""]]];
            private _hotspots = missionNamespace getVariable ["DSC_rovingHotspots", createHashMap];
            private _t0 = diag_tickTime;
            // Dispatch on subtype — both spawners derive side from the nearest
            // hotspot to the player at spawn time. The _sideKey field is
            // retained on queue items only for stats/logging.
            if (_subtype == "ground") then {
                [_hotspots, _factionData] call DSC_core_fnc_rovingSpawnGround;
            } else {
                if (_subtype == "foot") then {
                    [_hotspots, _factionData] call DSC_core_fnc_rovingSpawnFoot;
                } else {
                    if (_subtype == "boat") then {
                        [_hotspots, _factionData] call DSC_core_fnc_rovingSpawnBoat;
                    } else {
                        [_subtype, _hotspots, _factionData] call DSC_core_fnc_rovingSpawnAir;
                    };
                };
            };
            diag_log format ["DSC: roving worker BEGIN/END spawn [%1/%2] %3ms (qS=%4)",
                _subtype, _sideKey, ((diag_tickTime - _t0) * 1000) toFixed 1, count _q];
            uiSleep 1.5; // pace spawns so back-to-back ones don't stutter
        } else {
            uiSleep 1;
        };
    };
};

// ============================================================================
// Tick loop — 8s, phase-offset 4s from presence manager
// ============================================================================
[] spawn {
    // Phase offset: presence ticks at t=0,8,16; roving starts +4s so decision
    // windows alternate. Both workers yield with uiSleep so they interleave
    // cleanly on the scheduler even when they do overlap.
    uiSleep 4;

    private _tickInterval = 8;
    private _missionAoBuffer = 800;        // meters past mission radius
    private _missionDefaultRadius = 600;

    // Spawn-roll pacing: per side, spawn-attempt cooldown so we don't burst
    // every tick. Cooldown decays over time; once elapsed, we roll for a
    // spawn. Per-tick probability stays light to keep things ambient.
    private _lastSpawnAirEast = 0;
    private _lastSpawnAirWest = 0;
    private _lastSpawnGroundEast = 0;
    private _lastSpawnGroundWest = 0;
    private _lastSpawnFoot = 0;
    private _lastSpawnBoat = 0;
    private _minIntervalAir = 45;             // seconds between same-side air spawns
    private _minIntervalGround = 60;          // seconds — ground patrols are heavier
    private _minIntervalFoot = 75;            // seconds — foot patrols are slower / longer-lived
    private _minIntervalBoat = 120;           // seconds — boats are coastal-only, rarer
    private _rollChanceAir = 0.35;            // air roll chance when air cooldown elapsed
    private _rollChanceGround = 0.30;         // ground roll chance — bumped from 0.20 to keep ground rovers more present
    private _rollChanceFoot = 0.35;           // foot roll chance
    private _rollChanceBoat = 0.30;           // boat roll chance — will silently no-op on inland maps

    private _lastStatsReport = diag_tickTime;
    private _statsReportInterval = 60;

    diag_log format ["DSC: rovingManager - Tick loop started (%1s, phase-offset 4s)", _tickInterval];

    while { true } do {
        private _now = diag_tickTime;

        // ----- Despawn sweep first (frees budget for spawn decisions) -----
        [] call DSC_core_fnc_rovingDespawnSweep;

        // ----- Mission AO arbitration (skip spawn if player is on-mission) -----
        private _missionAoActive = false;
        private _currentMission = missionNamespace getVariable ["DSC_currentMission", createHashMap];
        if (_currentMission isNotEqualTo createHashMap) then {
            // Aircraft can fly through AOs safely (high alt, ambient), but
            // we don't want a fresh rover spawning right when the mission
            // briefing fires. Pause spawn during an active mission only.
            private _state = _currentMission getOrDefault ["state", ""];
            if (_state in ["active", "briefing"]) then {
                _missionAoActive = true;
            };
        };

        // ----- Player must exist -----
        private _player = call CBA_fnc_currentUnit;
        private _hasPlayer = !isNull _player;

        // ----- Budget check per type -----
        private _active = missionNamespace getVariable ["DSC_rovingActive", []];
        private _activeRotary = count (_active select { (_x get "type") == "rotary" });
        private _activeFixed  = count (_active select { (_x get "type") == "fixedWing" });
        private _activeGround = count (_active select { (_x get "type") == "ground" });
        private _activeFoot   = count (_active select { (_x get "type") == "foot"   });
        private _activeBoat   = count (_active select { (_x get "type") == "boat"   });
        private _budgetRotary = missionNamespace getVariable ["DSC_rovingBudgetRotary", 3];
        private _budgetFixed  = missionNamespace getVariable ["DSC_rovingBudgetFixed", 2];
        private _budgetGround = missionNamespace getVariable ["DSC_rovingBudgetGround", 4];
        private _budgetFoot   = missionNamespace getVariable ["DSC_rovingBudgetFoot", 2];
        private _budgetBoat   = missionNamespace getVariable ["DSC_rovingBudgetBoat", 2];

        if (_hasPlayer && !_missionAoActive) then {
            // Try one spawn per tick, alternating side preference each cycle
            private _hotspots = missionNamespace getVariable ["DSC_rovingHotspots", createHashMap];
            private _eastAvail = count (_hotspots getOrDefault ["east", []]) > 0;
            private _westAvail = count (_hotspots getOrDefault ["west", []]) > 0;

            // ===== AIR rolls (east + west, independent) =====
            if (_eastAvail && (_now - _lastSpawnAirEast) > _minIntervalAir && random 1 < _rollChanceAir) then {
                // Pick rotary or fixed-wing — rotary far more common
                private _airType = ["fixedWing", "rotary"] select (random 1 < 0.8);
                private _cap = [_budgetFixed, _budgetRotary] select (_airType == "rotary");
                private _have = [_activeFixed, _activeRotary] select (_airType == "rotary");
                private _stats = missionNamespace getVariable ["DSC_rovingStats", createHashMap];
                _stats set ["spawnAttempts", (_stats getOrDefault ["spawnAttempts", 0]) + 1];
                // Cooldown ticks on every roll, queued or not — keeps skipBudget
                // counter honest and prevents tight re-roll loops when capped.
                _lastSpawnAirEast = _now;
                if (_have >= _cap) then {
                    _stats set ["skippedBudget", (_stats getOrDefault ["skippedBudget", 0]) + 1];
                } else {
                    (missionNamespace getVariable ["DSC_rovingSpawnQueue", []]) pushBack [_airType, "east"];
                };
            };

            if (_westAvail && (_now - _lastSpawnAirWest) > _minIntervalAir && random 1 < _rollChanceAir) then {
                private _airType = ["fixedWing", "rotary"] select (random 1 < 0.8);
                private _cap = [_budgetFixed, _budgetRotary] select (_airType == "rotary");
                private _have = [_activeFixed, _activeRotary] select (_airType == "rotary");
                private _stats = missionNamespace getVariable ["DSC_rovingStats", createHashMap];
                _stats set ["spawnAttempts", (_stats getOrDefault ["spawnAttempts", 0]) + 1];
                _lastSpawnAirWest = _now;
                if (_have >= _cap) then {
                    _stats set ["skippedBudget", (_stats getOrDefault ["skippedBudget", 0]) + 1];
                } else {
                    (missionNamespace getVariable ["DSC_rovingSpawnQueue", []]) pushBack [_airType, "west"];
                };
            };

            // ===== GROUND rolls (east + west, independent of air) =====
            if (_eastAvail && (_now - _lastSpawnGroundEast) > _minIntervalGround && random 1 < _rollChanceGround) then {
                private _stats = missionNamespace getVariable ["DSC_rovingStats", createHashMap];
                _stats set ["spawnAttempts", (_stats getOrDefault ["spawnAttempts", 0]) + 1];
                _lastSpawnGroundEast = _now;
                if (_activeGround >= _budgetGround) then {
                    _stats set ["skippedBudget", (_stats getOrDefault ["skippedBudget", 0]) + 1];
                } else {
                    (missionNamespace getVariable ["DSC_rovingSpawnQueue", []]) pushBack ["ground", "east"];
                };
            };

            if (_westAvail && (_now - _lastSpawnGroundWest) > _minIntervalGround && random 1 < _rollChanceGround) then {
                private _stats = missionNamespace getVariable ["DSC_rovingStats", createHashMap];
                _stats set ["spawnAttempts", (_stats getOrDefault ["spawnAttempts", 0]) + 1];
                _lastSpawnGroundWest = _now;
                if (_activeGround >= _budgetGround) then {
                    _stats set ["skippedBudget", (_stats getOrDefault ["skippedBudget", 0]) + 1];
                } else {
                    (missionNamespace getVariable ["DSC_rovingSpawnQueue", []]) pushBack ["ground", "west"];
                };
            };

            // ===== FOOT roll (single, side derived at spawn time) =====
            if ((_now - _lastSpawnFoot) > _minIntervalFoot && random 1 < _rollChanceFoot) then {
                private _stats = missionNamespace getVariable ["DSC_rovingStats", createHashMap];
                _stats set ["spawnAttempts", (_stats getOrDefault ["spawnAttempts", 0]) + 1];
                _lastSpawnFoot = _now;
                if (_activeFoot >= _budgetFoot) then {
                    _stats set ["skippedBudget", (_stats getOrDefault ["skippedBudget", 0]) + 1];
                } else {
                    (missionNamespace getVariable ["DSC_rovingSpawnQueue", []]) pushBack ["foot", "auto"];
                };
            };

            // ===== BOAT roll (single, side derived at spawn time) =====
            // Silently no-ops on inland maps via surfaceIsWater check in spawner.
            if ((_now - _lastSpawnBoat) > _minIntervalBoat && random 1 < _rollChanceBoat) then {
                private _stats = missionNamespace getVariable ["DSC_rovingStats", createHashMap];
                _stats set ["spawnAttempts", (_stats getOrDefault ["spawnAttempts", 0]) + 1];
                _lastSpawnBoat = _now;
                if (_activeBoat >= _budgetBoat) then {
                    _stats set ["skippedBudget", (_stats getOrDefault ["skippedBudget", 0]) + 1];
                } else {
                    (missionNamespace getVariable ["DSC_rovingSpawnQueue", []]) pushBack ["boat", "auto"];
                };
            };
        } else {
            if (_hasPlayer && _missionAoActive) then {
                private _stats = missionNamespace getVariable ["DSC_rovingStats", createHashMap];
                _stats set ["skippedAoOverlap", (_stats getOrDefault ["skippedAoOverlap", 0]) + 1];
            };
        };

        // ----- Periodic STATS report -----
        if (_now - _lastStatsReport >= _statsReportInterval) then {
            _lastStatsReport = _now;
            private _stats = missionNamespace getVariable ["DSC_rovingStats", createHashMap];
            private _runtimeMin = ((_now - (_stats getOrDefault ["loopStart", _now])) / 60) toFixed 1;
            private _activeNow = missionNamespace getVariable ["DSC_rovingActive", []];
            diag_log format ["DSC: ===== ROVING STATS (%1 min) =====", _runtimeMin];
            diag_log format ["DSC: roving - spawned=%1 (rotary=%2 fixedWing=%3 ground=%4 foot=%5 boat=%6) despawned=%7 active=%8",
                _stats getOrDefault ["spawned", 0],
                _stats getOrDefault ["rotarySpawned", 0],
                _stats getOrDefault ["fixedWingSpawned", 0],
                _stats getOrDefault ["groundSpawned", 0],
                _stats getOrDefault ["footSpawned", 0],
                _stats getOrDefault ["boatSpawned", 0],
                _stats getOrDefault ["despawned", 0],
                count _activeNow];
            diag_log format ["DSC: roving - attempts=%1 skipBudget=%2 skipAO=%3 nearHotspot=%4",
                _stats getOrDefault ["spawnAttempts", 0],
                _stats getOrDefault ["skippedBudget", 0],
                _stats getOrDefault ["skippedAoOverlap", 0],
                _stats getOrDefault ["nearHotspotSpawns", 0]];
        };

        uiSleep _tickInterval;
    };
};

count (_hotspots getOrDefault ["all", []])
