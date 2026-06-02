/*
 * Function: DSC_core_fnc_initPresenceManager
 * Description:
 *     Sprint 1 scaffolding for the world presence manager. Builds a zone
 *     registry from influence data and spawns a tick loop that drives a
 *     per-zone state machine based on player proximity. No spawning happens
 *     in this sprint — transitions are log-only so we can verify activation
 *     distances + state flow in isolation.
 *
 *     Zone registry schema (DSC_presenceZones, hashmap by zone id):
 *       "id"            <STRING>  - location/base id
 *       "type"          <STRING>  - "base" | "outpost" | "camp" | "populatedArea"
 *       "position"      <ARRAY>   - [x,y,z]
 *       "radius"        <NUMBER>  - location radius
 *       "name"          <STRING>  - display name
 *       "controlledBy"  <STRING>  - "opFor" | "bluFor" | "contested" | "neutral"
 *       "faction"       <STRING>  - cfg faction id (may be "")
 *       "influence"     <NUMBER>  - 0..1
 *       "state"         <STRING>  - "DORMANT"|"ACTIVATING"|"ACTIVE"|"DESPAWNING"|"COMBAT"
 *       "stateSince"    <NUMBER>  - server time of last state change
 *       "graceUntil"    <NUMBER>  - DESPAWNING grace deadline
 *       "combatUntil"   <NUMBER>  - COMBAT lock expires at
 *       "units"         <ARRAY>   - spawned units (sprint 2+)
 *       "vehicles"      <ARRAY>   - spawned vehicles (sprint 2+)
 *       "groups"        <ARRAY>   - spawned groups (sprint 2+)
 *
 * Arguments:
 *     0: _influenceData <HASHMAP> - from fnc_initInfluence
 *
 * Return Value:
 *     <HASHMAP> - DSC_presenceZones
 *
 * Example:
 *     [_influenceData] call DSC_core_fnc_initPresenceManager;
 */

params [
    ["_influenceData", createHashMap, [createHashMap]]
];

if (_influenceData isEqualTo createHashMap) exitWith {
    diag_log "DSC: presenceManager - No influence data, aborting";
    createHashMap
};

private _influenceMap = _influenceData getOrDefault ["influenceMap", createHashMap];
private _bases          = _influenceData getOrDefault ["bases", []];
private _outposts       = _influenceData getOrDefault ["outposts", []];
private _camps          = _influenceData getOrDefault ["camps", []];
private _populatedAreas = _influenceData getOrDefault ["populatedAreas", []];

// Exclude the player main base from presence management — it is eagerly
// populated by fnc_initBases and lives for the whole session.
private _playerMainBase = missionNamespace getVariable ["playerMainBase", ""];
private _playerBasePos  = if (_playerMainBase != "" && {(markerShape _playerMainBase) != ""}) then {
    getMarkerPos _playerMainBase
} else { [0,0,0] };

private _zones = createHashMap;

private _buildZone = {
    params ["_loc", "_zoneType"];

    private _locId = _loc get "id";
    private _locPos = _loc get "position";
    private _locName = _loc getOrDefault ["name", _locId];
    private _locRadius = _loc getOrDefault ["radius", 200];

    // Skip if this zone is the player base footprint
    if (_playerBasePos distance2D _locPos < 50) exitWith { nil };

    private _inf = _influenceMap getOrDefault [_locId, createHashMap];
    private _controlledBy = _inf getOrDefault ["controlledBy", "neutral"];
    private _faction      = _inf getOrDefault ["faction", ""];
    private _influence    = _inf getOrDefault ["influence", 0];

    private _zone = createHashMapFromArray [
        ["id",           _locId],
        ["type",         _zoneType],
        ["position",     _locPos],
        ["radius",       _locRadius],
        ["name",         _locName],
        ["controlledBy", _controlledBy],
        ["faction",      _faction],
        ["influence",    _influence],
        ["structures",   _loc getOrDefault ["structures", []]],
        ["state",        "DORMANT"],
        ["stateSince",   serverTime],
        ["graceUntil",   0],
        ["combatUntil",  0],
        ["units",        []],
        ["vehicles",     []],
        ["groups",       []]
    ];

    _zones set [_locId, _zone];
};

{ [_x, "base"]          call _buildZone } forEach _bases;
{ [_x, "outpost"]       call _buildZone } forEach _outposts;
{ [_x, "camp"]          call _buildZone } forEach _camps;
{ [_x, "populatedArea"] call _buildZone } forEach _populatedAreas;

diag_log format ["DSC: presenceManager - Registered %1 zones (bases:%2 outposts:%3 camps:%4 populated:%5)",
    count _zones, count _bases, count _outposts, count _camps, count _populatedAreas];

missionNamespace setVariable ["DSC_presenceZones", _zones, true];

// ============================================================================
// Side diplomacy — opFor-aligned factions cooperate regardless of side
// ============================================================================
// Faction profile maps opFor/opForPartner/irregulars to potentially different
// engine sides (east vs independent). Default A3 diplomacy makes east hostile
// to independent, so partner/irregular units gun each other down on sight.
// Lock cooperation between east and independent for the whole session. Player
// (west) stays hostile to both via the default matrix.
//
// NOTE: Mission cleanup also calls setFriend to reset diplomacy. Once the
// mission system and presence coexist long-term we may need to coordinate
// these — for now mission setFriend overrides during active missions and
// presence sets a stable baseline.
east     setFriend [independent, 1];
independent setFriend [east, 1];
// Civilians stay neutral to both — no changes needed there.
diag_log "DSC: presenceManager - Locked east<->independent friendly (opFor partner cooperation)";

// ============================================================================
// Debug markers — one ELLIPSE per zone, colored by state
// ============================================================================
// State -> color mapping for at-a-glance map readout. Markers are created
// global (createMarker) so any connected client sees them.
private _stateColor = createHashMapFromArray [
    ["DORMANT",    "ColorGrey"],
    ["ACTIVATING", "ColorYellow"],
    ["ACTIVE",     "ColorGreen"],
    ["DESPAWNING", "ColorOrange"],
    ["COMBAT",     "ColorRed"]
];

{
    private _zoneId = _x;
    private _zone   = _zones get _zoneId;
    private _zPos   = _zone get "position";
    private _zType  = _zone get "type";
    private _zRad   = _zone get "radius";

    private _markerR = switch (_zType) do {
        case "base":          { (_zRad max 200) + 200 };
        case "outpost":       { (_zRad max 150) + 150 };
        case "camp":          { (_zRad max 75)  + 75  };
        case "populatedArea": { (_zRad max 150) + 100 };
        default               { 150 };
    };

    private _mName = format ["dsc_presence_%1", _zoneId];
    private _m = createMarker [_mName, _zPos];
    _m setMarkerShapeLocal "ELLIPSE";
    _m setMarkerSizeLocal [_markerR, _markerR];
    _m setMarkerBrushLocal "Solid";
    _m setMarkerColorLocal "ColorGrey";
    _m setMarkerAlphaLocal 0.25;
    _m setMarkerText format ["%1 [DORMANT]", _zone get "name"];

    _zone set ["marker", _mName];
    _zone set ["markerRadius", _markerR];
} forEach (keys _zones);

systemChat format ["DSC presence: %1 zones registered, tick loop starting (20s)", count _zones];

// ============================================================================
// Tick loop — spawned, runs forever
// ============================================================================
[_zones, _stateColor] spawn {
    params ["_zones", "_stateColor"];

    // Activation/despawn radii per zone type (Sprint 1 — log only)
    private _activateRadius = createHashMapFromArray [
        ["base",          800],
        ["outpost",       1000],
        ["camp",          1200],
        ["populatedArea", 2000]
    ];
    private _despawnRadius = createHashMapFromArray [
        ["base",          800],
        ["outpost",       1000],
        ["camp",          1200],
        ["populatedArea", 2000]
    ];
    private _despawnGrace = 45; // seconds in DESPAWNING before going DORMANT

    // Activation throttle: zones that reach ACTIVATING are queued and processed
    // by a worker loop, max one zone per worker cycle, with a yield between.
    // This prevents the main tick from running createUnit/createVehicle bursts
    // for several zones back-to-back (the source of activation stutter).
    private _activateQueue = [];   // zone hashmaps awaiting spawn
    private _despawnQueue  = [];   // zone hashmaps awaiting cleanup
    missionNamespace setVariable ["DSC_presenceActivateQueue", _activateQueue, true];
    missionNamespace setVariable ["DSC_presenceDespawnQueue",  _despawnQueue,  true];

    // Worker scope — drains the activate + despawn queues with yields between.
    // No `continue` inside `then` blocks; structure is explicit if/else with a
    // heartbeat timestamp so we can detect a dead worker from outside.
    missionNamespace setVariable ["DSC_presenceWorkerHeartbeat", diag_tickTime, true];
    missionNamespace setVariable ["DSC_presenceWorkerIterations", 0, true];

    [_activateQueue, _despawnQueue] spawn {
        params ["_aq", "_dq"];
        private _iter = 0;

        while { true } do {
            _iter = _iter + 1;
            missionNamespace setVariable ["DSC_presenceWorkerHeartbeat", diag_tickTime, true];
            missionNamespace setVariable ["DSC_presenceWorkerIterations", _iter, true];

            if (_dq isNotEqualTo []) then {
                private _zone = _dq deleteAt 0;
                private _id = _zone get "id";
                private _t0 = diag_tickTime;
                diag_log format ["DSC: presence worker[%1] BEGIN despawn [%2] (qD=%3 qA=%4)",
                    _iter, _id, count _dq, count _aq];
                [_zone] call DSC_core_fnc_despawnPresenceZone;
                _zone set ["processed", false];
                diag_log format ["DSC: presence worker[%1] END despawn [%2] %3ms",
                    _iter, _id, ((diag_tickTime - _t0) * 1000) toFixed 1];
                sleep 0.5;
            } else {
                if (_aq isNotEqualTo []) then {
                    private _zone = _aq deleteAt 0;
                    private _id = _zone get "id";
                    private _t0 = diag_tickTime;
                    diag_log format ["DSC: presence worker[%1] BEGIN activate [%2] (qA=%3 qD=%4)",
                        _iter, _id, count _aq, count _dq];
                    [_zone] call DSC_core_fnc_activatePresenceZone;
                    // Always mark processed so the state machine can promote
                    // ACTIVATING -> ACTIVE even if activate returned false (skip).
                    _zone set ["processed", true];
                    diag_log format ["DSC: presence worker[%1] END activate [%2] %3ms",
                        _iter, _id, ((diag_tickTime - _t0) * 1000) toFixed 1];
                    sleep 1.5;
                } else {
                    sleep 1; // both queues empty — back off
                };
            };
        };
    };

    diag_log "DSC: presenceManager - Tick loop started (20s interval, log-only)";

    // Mission AO arbitration + global entity budget
    // - When a mission is active, military zones (base/outpost/camp) whose
    //   center is within (missionRadius + buffer) of the mission AO suspend.
    //   Civilians stay (population thins naturally with influence already).
    // - Global cap on simultaneous active units/vehicles. Closest zones win.
    private _missionAoBuffer = 300;     // meters past mission radius to keep clear
    private _missionDefaultRadius = 600; // when mission doesn't expose a radius
    private _budgetUnits    = 100;
    private _budgetVehicles = 30;
    missionNamespace setVariable ["DSC_presenceBudgetUnits", _budgetUnits, true];
    missionNamespace setVariable ["DSC_presenceBudgetVehicles", _budgetVehicles, true];

    // ============================================================================
    // Instrumentation — for measuring helicopter / vehicle behavior.
    //   DSC_presenceLatencies — rolling array of activation events:
    //     [zoneId, zoneType, distM, ticksToActive, msToActive, playerSpeed]
    //   DSC_presenceStats — cumulative session counters
    // ============================================================================
    missionNamespace setVariable ["DSC_presenceLatencies", [], true];
    missionNamespace setVariable ["DSC_presenceStats", createHashMapFromArray [
        ["dormantToActivating",  0],   // zones approved per session
        ["activatingToActive",   0],   // zones that reached ACTIVE
        ["activatingTimedOut",   0],   // ACTIVATING -> DORMANT (player left before spawn finished)
        ["activatingAbandoned",  0],   // ACTIVATING -> DESPAWNING (player blew past, entities present)
        ["budgetSkipped",        0],   // candidates skipped because of cap
        ["budgetApproved",       0],   // candidates that passed the cap
        ["forcedSuspended",      0],   // suspended for mission AO
        ["totalActivated",       0],   // delta zones that fully spawned
        ["totalDespawned",       0],   // delta zones that fully cleaned up
        ["loopStart",            diag_tickTime]
    ], true];

    private _statsReportInterval = 60; // seconds between STATS summary lines
    private _lastStatsReport = diag_tickTime;

    private _fnc_logLatency = {
        params ["_zone", "_distAtActivating", "_speed"];
        private _dormantExit = _zone getOrDefault ["dormantExitTime", 0];
        if (_dormantExit <= 0) exitWith {};
        private _now = diag_tickTime;
        private _elapsedMs = (_now - _dormantExit) * 1000;
        private _ticks = floor ((_now - _dormantExit) / 20) + 1; // approx tick count

        private _row = [
            _zone get "id",
            _zone get "type",
            round _distAtActivating,
            _ticks,
            round _elapsedMs,
            round _speed
        ];
        private _log = missionNamespace getVariable ["DSC_presenceLatencies", []];
        _log pushBack _row;
        if (count _log > 100) then { _log deleteAt 0 };
        missionNamespace setVariable ["DSC_presenceLatencies", _log, true];

        diag_log format ["DSC: presence latency [%1/%2] %3ms (%4 ticks) dist=%5m speed=%6m/s",
            _zone get "id", _zone get "type", round _elapsedMs, _ticks,
            round _distAtActivating, round _speed];
    };

    private _fnc_bumpStat = {
        params ["_key", ["_delta", 1]];
        private _stats = missionNamespace getVariable ["DSC_presenceStats", createHashMap];
        _stats set [_key, (_stats getOrDefault [_key, 0]) + _delta];
    };

    while { true } do {
        sleep 20;

        private _players = call BIS_fnc_listPlayers;
        if (_players isEqualTo []) then { _players = allPlayers - entities "HeadlessClient_F" };
        if (_players isEqualTo []) then { continue };

        // ----- Player speed sampling (instrumentation) ---------------------------
        // Average + max player speed this tick. We track this alongside latency
        // so we can correlate "how fast was the player when this activation
        // started" against "how long until it became ACTIVE".
        private _maxPlayerSpeed = 0;
        private _avgPlayerSpeed = 0;
        {
            private _vel = velocity (vehicle _x);
            private _s = vectorMagnitude _vel;
            _avgPlayerSpeed = _avgPlayerSpeed + _s;
            if (_s > _maxPlayerSpeed) then { _maxPlayerSpeed = _s };
        } forEach _players;
        _avgPlayerSpeed = _avgPlayerSpeed / (count _players);

        // ----- Mission AO snapshot (arbitration) -------------------------------
        private _missionAoPos    = [];
        private _missionAoRadius = 0;
        private _currentMission = missionNamespace getVariable ["DSC_currentMission", createHashMap];
        if (_currentMission isNotEqualTo createHashMap) then {
            _missionAoPos = _currentMission getOrDefault ["location", []];
            _missionAoRadius = _currentMission getOrDefault ["radius", _missionDefaultRadius];
        };
        private _hasMission = _missionAoPos isNotEqualTo [];

        // ----- Current budget usage --------------------------------------------
        private _curUnits = 0;
        private _curVehicles = 0;
        {
            private _z = _zones get _x;
            private _zs = _z get "state";
            if (_zs in ["ACTIVE", "ACTIVATING", "DESPAWNING"]) then {
                _curUnits    = _curUnits + count (_z get "units");
                _curVehicles = _curVehicles + count (_z get "vehicles");
            };
        } forEach (keys _zones);

        private _activated = 0;
        private _despawned = 0;
        private _dormant   = 0;
        private _activatingCt = 0;
        private _suspended = 0;
        private _transitions = [];

        // ----- Eligible-for-activation list (closest first) --------------------
        // We collect candidates this tick, then enqueue in distance order so
        // when the budget is tight the closest zones get the limited slots.
        private _candidates = [];

        {
            private _zoneId = _x;
            private _zone   = _zones get _zoneId;
            private _zType  = _zone get "type";
            private _zPos   = _zone get "position";
            private _state  = _zone get "state";

            // Nearest-player distance
            private _minDist = 1e9;
            {
                private _d = _x distance2D _zPos;
                if (_d < _minDist) then { _minDist = _d };
            } forEach _players;

            private _actR = _activateRadius getOrDefault [_zType, 1000];
            private _depR = _despawnRadius  getOrDefault [_zType, 1800];

            // Mission AO arbitration — military zones overlapping the active
            // mission AO are forced to suspend. Civilian-only populated areas
            // are exempt (mission generator owns its garrison; presence civs
            // stay around the edges).
            private _isMilitary = _zType in ["base", "outpost", "camp"];
            private _missionOverlap = false;
            if (_hasMission && _isMilitary) then {
                private _md = _zPos distance2D _missionAoPos;
                if (_md < (_missionAoRadius + _missionAoBuffer)) then {
                    _missionOverlap = true;
                };
            };

            private _newState = _state;

            switch (_state) do {
                case "DORMANT": {
                    if (!_missionOverlap && {_minDist <= _actR}) then {
                        // Defer the actual enqueue — collect candidate first so
                        // budget can be applied in distance order below.
                        _candidates pushBack [_minDist, _zone];
                    };
                };
                case "ACTIVATING": {
                    // Helper — clean up if the worker already spawned entities
                    // while we were in ACTIVATING. Without this we orphan units
                    // when the player blows past the despawn radius (helicopter
                    // crossing a town in <20s) before we ever reach ACTIVE.
                    private _hasEntities = (count (_zone get "units")) > 0
                                        || (count (_zone get "vehicles")) > 0;

                    if (_missionOverlap) then {
                        // Mission AO appeared while we were queued — pull out
                        // in-place so the worker (which holds the same array
                        // reference) sees the removal.
                        private _idx = _activateQueue find _zone;
                        if (_idx >= 0) then { _activateQueue deleteAt _idx };
                        if (_hasEntities && !(_zone in _despawnQueue)) then {
                            _despawnQueue pushBack _zone;
                            _newState = "DESPAWNING";
                            _zone set ["graceUntil", serverTime];
                            _suspended = _suspended + 1;
                            ["forcedSuspended"] call _fnc_bumpStat;
                        } else {
                            _newState = "DORMANT";
                            ["activatingTimedOut"] call _fnc_bumpStat;
                        };
                    } else {
                        if (_zone getOrDefault ["processed", false]) then {
                            _newState = "ACTIVE";
                            [_zone, _zone getOrDefault ["distAtActivating", _minDist], _avgPlayerSpeed] call _fnc_logLatency;
                            ["activatingToActive"] call _fnc_bumpStat;
                            ["totalActivated"] call _fnc_bumpStat;
                        };
                        if (_minDist > _depR) then {
                            private _idx = _activateQueue find _zone;
                            if (_idx >= 0) then { _activateQueue deleteAt _idx };
                            if (_hasEntities) then {
                                // Worker already spawned — schedule cleanup,
                                // don't drop straight to DORMANT and orphan units.
                                if !(_zone in _despawnQueue) then {
                                    _despawnQueue pushBack _zone;
                                };
                                _newState = "DESPAWNING";
                                _zone set ["graceUntil", serverTime];
                                ["activatingAbandoned"] call _fnc_bumpStat;
                            } else {
                                _newState = "DORMANT";
                                ["activatingTimedOut"] call _fnc_bumpStat;
                            };
                        };
                    };
                };
                case "ACTIVE": {
                    if (_missionOverlap) then {
                        // Force despawn with no grace — mission needs this zone clear
                        _newState = "DESPAWNING";
                        _zone set ["graceUntil", serverTime];
                        _suspended = _suspended + 1;
                        ["forcedSuspended"] call _fnc_bumpStat;
                    } else {
                        if (_minDist > _depR) then {
                            _newState = "DESPAWNING";
                            _zone set ["graceUntil", serverTime + _despawnGrace];
                        };
                    };
                };
                case "DESPAWNING": {
                    if (_missionOverlap) then {
                        // Don't let the player walk into the AO and rescue this zone
                        if (serverTime >= (_zone get "graceUntil")) then {
                            if !(_zone in _despawnQueue) then {
                                _despawnQueue pushBack _zone;
                            };
                            if (!(_zone getOrDefault ["processed", true])
                                && {(count (_zone get "units")) == 0}
                                && {(count (_zone get "vehicles")) == 0}
                            ) then {
                                _newState = "DORMANT";
                                ["totalDespawned"] call _fnc_bumpStat;
                            };
                        };
                    } else {
                        if (_minDist <= _actR) then {
                            _newState = "ACTIVE";
                        } else {
                            if (serverTime >= (_zone get "graceUntil")) then {
                                if !(_zone in _despawnQueue) then {
                                    _despawnQueue pushBack _zone;
                                };
                                if (!(_zone getOrDefault ["processed", true])
                                    && {(count (_zone get "units")) == 0}
                                    && {(count (_zone get "vehicles")) == 0}
                                ) then {
                                    _newState = "DORMANT";
                                    ["totalDespawned"] call _fnc_bumpStat;
                                };
                            };
                        };
                    };
                };
                case "COMBAT": {
                    // Sprint 1: nothing puts us into COMBAT yet
                    if (serverTime >= (_zone get "combatUntil")) then {
                        _newState = ["ACTIVE", "DESPAWNING"] select (_minDist > _depR);
                    };
                };
                default {};
            };

            if (_newState != _state) then {
                _zone set ["state", _newState];
                _zone set ["stateSince", serverTime];

                // Update map marker color + label
                private _mName = _zone get "marker";
                if (!isNil "_mName") then {
                    private _color = _stateColor getOrDefault [_newState, "ColorGrey"];
                    _mName setMarkerColorLocal _color;
                    _mName setMarkerAlphaLocal ([0.25, 0.45] select (_newState != "DORMANT"));
                    _mName setMarkerText format ["%1 [%2]", _zone get "name", _newState];
                };

                _transitions pushBack format ["%1 %2->%3 (%4m)", _zone get "name", _state, _newState, round _minDist];

                diag_log format ["DSC: presence [%1] %2 -> %3 (type=%4 ctrl=%5 inf=%6 dist=%7m)",
                    _zoneId, _state, _newState,
                    _zType, _zone get "controlledBy", (_zone get "influence") toFixed 2, round _minDist
                ];
            };

            switch (_newState) do {
                case "ACTIVE":     { _activated = _activated + 1 };
                case "ACTIVATING": { _activatingCt = _activatingCt + 1 };
                case "DESPAWNING": { _despawned = _despawned + 1 };
                case "DORMANT":    { _dormant   = _dormant + 1 };
                default {};
            };
        } forEach (keys _zones);

        // ----- Apply budget to candidates ----------------------------------
        // Sort by distance ascending; enqueue while we have unit/vehicle headroom.
        // Skipped candidates stay DORMANT — the next tick gives them another chance
        // once active zones despawn and free budget.
        _candidates sort true;
        private _approved = 0;
        private _budgetSkipped = 0;
        {
            _x params ["_d", "_zone"];
            // Estimate cost — we don't know exactly what a zone will spawn until
            // activate runs, so use type-based heuristics. Conservative bias keeps
            // us under cap even when activations spike.
            private _zt = _zone get "type";
            private _estU = switch (_zt) do {
                case "base":          { 20 };
                case "outpost":       { 8  };
                case "camp":          { 4  };
                case "populatedArea": { 8  };
                default               { 5  };
            };
            private _estV = switch (_zt) do {
                case "base":    { 3 };
                case "outpost": { 1 };
                default         { 0 };
            };

            if ((_curUnits + _estU > _budgetUnits) || (_curVehicles + _estV > _budgetVehicles)) then {
                _budgetSkipped = _budgetSkipped + 1;
                ["budgetSkipped"] call _fnc_bumpStat;
            } else {
                _zone set ["processed", false];
                _zone set ["dormantExitTime", diag_tickTime];
                _zone set ["distAtActivating", _d];
                _activateQueue pushBack _zone;
                _zone set ["state", "ACTIVATING"];
                _zone set ["stateSince", serverTime];

                private _mName = _zone get "marker";
                if (!isNil "_mName") then {
                    private _color = _stateColor getOrDefault ["ACTIVATING", "ColorYellow"];
                    _mName setMarkerColorLocal _color;
                    _mName setMarkerAlphaLocal 0.45;
                    _mName setMarkerText format ["%1 [ACTIVATING]", _zone get "name"];
                };

                _transitions pushBack format ["%1 DORMANT->ACTIVATING (%2m)", _zone get "name", round _d];
                diag_log format ["DSC: presence [%1] DORMANT -> ACTIVATING (type=%2 dist=%3m speed=%4m/s budget=%5u/%6v est=%7u/%8v)",
                    _zone get "id", _zt, round _d, round _avgPlayerSpeed,
                    _curUnits, _curVehicles, _estU, _estV
                ];

                _curUnits    = _curUnits + _estU;
                _curVehicles = _curVehicles + _estV;
                _approved = _approved + 1;
                ["dormantToActivating"] call _fnc_bumpStat;
                ["budgetApproved"] call _fnc_bumpStat;
                // Promote counter
                _dormant = _dormant - 1;
                _activatingCt = _activatingCt + 1;
            };
        } forEach _candidates;

        if (_budgetSkipped > 0) then {
            diag_log format ["DSC: presence — budget gate: %1 candidates approved, %2 skipped (cap %3u/%4v, used %5u/%6v)",
                _approved, _budgetSkipped, _budgetUnits, _budgetVehicles, _curUnits, _curVehicles];
        };

        private _missionLabel = if (_hasMission) then {
            format [" | mission r=%1", _missionAoRadius]
        } else { "" };

        diag_log format ["DSC: presence tick — active:%1 activating:%2 despawning:%3 dormant:%4 sus:%5 (of %6) | qA=%7 qD=%8 | used %9u/%10v of %11u/%12v | speed avg=%13 max=%14%15",
            _activated, _activatingCt, _despawned, _dormant, _suspended, count _zones,
            count _activateQueue, count _despawnQueue,
            _curUnits, _curVehicles, _budgetUnits, _budgetVehicles,
            round _avgPlayerSpeed, round _maxPlayerSpeed,
            _missionLabel];

        // ----- Periodic STATS report -----
        if ((diag_tickTime - _lastStatsReport) >= _statsReportInterval) then {
            private _stats = missionNamespace getVariable ["DSC_presenceStats", createHashMap];
            private _elapsed = diag_tickTime - (_stats getOrDefault ["loopStart", diag_tickTime]);
            private _activations    = _stats getOrDefault ["dormantToActivating", 0];
            private _completions    = _stats getOrDefault ["activatingToActive", 0];
            private _timedOut       = _stats getOrDefault ["activatingTimedOut", 0];
            private _abandoned      = _stats getOrDefault ["activatingAbandoned", 0];
            private _budgetSkippedT = _stats getOrDefault ["budgetSkipped", 0];
            private _budgetApprovedT = _stats getOrDefault ["budgetApproved", 0];

            // Latency stats from the rolling log
            private _latLog = missionNamespace getVariable ["DSC_presenceLatencies", []];
            private _avgMs = 0;
            private _maxMs = 0;
            if (_latLog isNotEqualTo []) then {
                private _sum = 0;
                {
                    private _ms = _x select 4;
                    _sum = _sum + _ms;
                    if (_ms > _maxMs) then { _maxMs = _ms };
                } forEach _latLog;
                _avgMs = _sum / (count _latLog);
            };

            private _completionRate = if (_activations > 0) then {
                100 * _completions / _activations
            } else { 0 };
            private _budgetSkipRate = if (_budgetApprovedT + _budgetSkippedT > 0) then {
                100 * _budgetSkippedT / (_budgetApprovedT + _budgetSkippedT)
            } else { 0 };

            diag_log format ["DSC: ===== PRESENCE STATS (%1 min) =====", round (_elapsed / 60)];
            diag_log format ["DSC: stats — activations=%1 completed=%2 timedOut=%3 abandoned=%4 (completion=%5%%)",
                _activations, _completions, _timedOut, _abandoned, round _completionRate];
            diag_log format ["DSC: stats — budget approved=%1 skipped=%2 (skipRate=%3%%)",
                _budgetApprovedT, _budgetSkippedT, round _budgetSkipRate];
            diag_log format ["DSC: stats — latency avg=%1ms max=%2ms (samples=%3)",
                round _avgMs, round _maxMs, count _latLog];
            (format ["DSC stats: act=%1 done=%2 timed=%3 aband=%4 skip%%=%5 lat=%6ms",
                _activations, _completions, _timedOut, _abandoned, round _budgetSkipRate, round _avgMs]
            ) remoteExec ["systemChat", 0];

            _lastStatsReport = diag_tickTime;
        };

        // Worker health check — if heartbeat is stale, the worker scope died
        // (likely a scripted error). Log loudly so we notice immediately.
        private _hb = missionNamespace getVariable ["DSC_presenceWorkerHeartbeat", 0];
        private _stale = diag_tickTime - _hb;
        if (_stale > 30 && {count _activateQueue + count _despawnQueue > 0}) then {
            diag_log format ["DSC: presence WORKER STALE — heartbeat %1s old, queues qA=%2 qD=%3 (worker likely dead)",
                _stale toFixed 1, count _activateQueue, count _despawnQueue];
            (format ["DSC presence: WORKER STALE %1s qA=%2 qD=%3",
                _stale toFixed 0, count _activateQueue, count _despawnQueue]
            ) remoteExec ["systemChat", 0];
        };

        // Per-tick systemChat summary so testers can see activity without RPT
        (format ["DSC presence: A:%1 ~A:%2 D-:%3 Z:%4 sus:%5 (of %6) %7u/%8v",
            _activated, _activatingCt, _despawned, _dormant, _suspended, count _zones,
            _curUnits, _curVehicles]
        ) remoteExec ["systemChat", 0];

        // Announce each transition this tick (capped to avoid spam)
        if (_transitions isNotEqualTo []) then {
            private _show = _transitions select [0, 6];
            {
                (format ["DSC presence: %1", _x]) remoteExec ["systemChat", 0];
            } forEach _show;
            if (count _transitions > 6) then {
                (format ["DSC presence: +%1 more transitions", (count _transitions) - 6]) remoteExec ["systemChat", 0];
            };
        };
    };
};

_zones
