#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_sweepMonitor
 * Description:
 *     The one world-sampling loop for the SWEEP archetype (Campaign
 *     Overhaul Session 6 §9 call site, spawned by fnc_generateMission's
 *     "SWEEP" case the same place the orchestrator already spawns
 *     fnc_persistentUAV). Samples players/enemies every tick, calls the
 *     PURE fnc_sweepEvaluateTick, writes the result back into
 *     DSC_currentMission's completionState (mutated in place — see the
 *     presence-manager "_q = _q - [_zone]" class of gotcha; reassigning
 *     the mission hashmap here would silently orphan every subsequent
 *     write), fires the convert hook at most once, and keeps
 *     completionState.intelGathered current every tick via
 *     fnc_resolveSweepYield + fnc_buildIntelTokenFromSite (the existing
 *     Session 5 token builder — NO direct fnc_intelAdd call here; the
 *     mission loop's existing retrofit bridge is the only writer).
 *
 *     Termination (the monitor MUST terminate on its own):
 *       - DSC_sweepRunId no longer matches the id stamped at generation
 *         (a new mission has started and orphaned this monitor).
 *       - missionInProgress is false.
 *       - DSC_missionAbortRequested is true.
 *       - Hard max-runtime elapsed (default 2400s).
 *     An orphaned monitor from mission N writing into mission N+1's
 *     completionState would be the nastiest available failure here.
 *
 *     LOS cost discipline (§10 gotcha 15): lineIntersectsSurfaces is
 *     called at most once per player per tick (the single nearest
 *     observer), never per enemy. Enemy detection uses knowsAbout (cheap)
 *     over the mission's own bounded unit list, never allUnits.
 *
 *     Accumulates from measured serverTime deltas (not the sleep
 *     constant) — uiSleep for scheduling, serverTime deltas for math, so
 *     scheduler lag / setAccTime never desyncs the dwell timer.
 *
 * Arguments:
 *     0: _ctx <HASHMAP> -
 *        "runId"          <STRING>  Stamped into DSC_sweepRunId at generation.
 *        "objectivePos"   <ARRAY>   World position of the sweep objective.
 *        "subPoints"      <ARRAY>   Array of positions (AREA_SWEPT sub-points).
 *        "sweptRadius"    <NUMBER>  Distance to count a sub-point as entered.
 *        "pidTarget"      <OBJECT>  Entity to PID (objNull if none).
 *        "pidRange"       <NUMBER>  LOS+distance radius for PID.
 *        "pidSubjectRef"  <STRING>  Subject ref for HVT_IDENTITY/HVT_LOCATION.
 *        "enemyUnits"     <ARRAY>   Mission-scoped enemy units (knowsAbout sample).
 *        "tuning"         <HASHMAP> Passed straight to fnc_sweepEvaluateTick,
 *                                   plus "exfilDistance" for the EXFIL convert.
 *        "yieldTuning"    <HASHMAP> Passed straight to fnc_resolveSweepYield.
 *        "locationId"     <STRING>  Subject ref for location-scoped tokens.
 *        "seriesId"       <STRING>  Empty string if not part of a series.
 *        "convertOn"      <STRING>  "RAID" | "EXFIL" (forwarded to fnc_sweepConvert).
 *        "exfilDistance"  <NUMBER>  Forwarded to fnc_sweepConvert.
 *        "garrisonClusters" <ARRAY> Forwarded to fnc_sweepConvert (marker reveal).
 *        "location"       <HASHMAP> Forwarded to fnc_sweepConvert (marker reveal).
 *        "maxRuntime"     <NUMBER>  Hard cap in seconds (default 2400).
 *
 * Return Value: None (spawned, runs until termination)
 *
 * Example:
 *     [_monitorCtx] spawn DSC_core_fnc_sweepMonitor;
 */

params [
    ["_ctx", createHashMap, [createHashMap]]
];

private _runId = _ctx getOrDefault ["runId", ""];
private _objectivePos = _ctx getOrDefault ["objectivePos", [0, 0, 0]];
private _subPoints = _ctx getOrDefault ["subPoints", []];
private _sweptRadius = _ctx getOrDefault ["sweptRadius", 40];
private _pidTarget = _ctx getOrDefault ["pidTarget", objNull];
private _pidRange = _ctx getOrDefault ["pidRange", 300];
private _pidSubjectRef = _ctx getOrDefault ["pidSubjectRef", ""];
private _enemyUnits = _ctx getOrDefault ["enemyUnits", []];
private _tuning = _ctx getOrDefault ["tuning", createHashMap];
private _yieldTuning = _ctx getOrDefault ["yieldTuning", createHashMap];
private _locationId = _ctx getOrDefault ["locationId", ""];
private _seriesId = _ctx getOrDefault ["seriesId", ""];
private _convertOn = _ctx getOrDefault ["convertOn", "RAID"];
private _exfilDistance = _ctx getOrDefault ["exfilDistance", 400];
private _garrisonClusters = _ctx getOrDefault ["garrisonClusters", []];
private _location = _ctx getOrDefault ["location", createHashMap];
private _maxRuntime = _ctx getOrDefault ["maxRuntime", 2400];

INFO_3("sweepMonitor - started (runId=%1, convertOn=%2, subPoints=%3)",_runId,_convertOn,count _subPoints);

private _visitedSubPoints = [];
private _state = createHashMapFromArray [
    ["observedSeconds", 0],
    ["bestProximity", 999999],
    ["compromised", false],
    ["compromiseStreak", 0],
    ["sweptPoints", 0],
    ["pidSeconds", 0],
    ["targetIdentified", false],
    ["converted", false]
];

private _lastTick = serverTime;
private _startedAt = serverTime;
private _running = true;
private _ticks = 0;

while { _running } do {
    uiSleep 2;

    private _currentRunId = missionNamespace getVariable ["DSC_sweepRunId", ""];
    private _missionActive = missionNamespace getVariable ["missionInProgress", false];
    private _aborted = missionNamespace getVariable ["DSC_missionAbortRequested", false];
    private _overtime = (serverTime - _startedAt) > _maxRuntime;

    if (_currentRunId != _runId || !_missionActive || _aborted || _overtime) then {
        if (_overtime) then {
            WARNING_1("sweepMonitor - run %1 hit max runtime, terminating",_runId);
        };
        _running = false;
    } else {
        _ticks = _ticks + 1;

        private _now = serverTime;
        private _dt = _now - _lastTick;
        _lastTick = _now;

        // ---- Sample: nearest live player + LOS (once per tick, not per enemy) ----
        private _players = allPlayers select { alive _x };
        private _observerDistance = -1;
        private _bestObserver = objNull;
        {
            private _d = _x distance2D _objectivePos;
            if (_observerDistance < 0 || { _d < _observerDistance }) then {
                _observerDistance = _d;
                _bestObserver = _x;
            };
        } forEach _players;

        private _hasLOS = false;
        if (!isNull _bestObserver) then {
            private _targetPosASL = AGLToASL [_objectivePos select 0, _objectivePos select 1, 1];
            _hasLOS = (lineIntersectsSurfaces [eyePos _bestObserver, _targetPosASL, _bestObserver, objNull, true, 1]) isEqualTo [];
        };

        // ---- Sample: enemy knowsAbout, bounded to the mission's own unit list ----
        private _maxKnowsAbout = 0;
        {
            private _enemyUnit = _x;
            if (alive _enemyUnit) then {
                {
                    _maxKnowsAbout = _maxKnowsAbout max (_enemyUnit knowsAbout _x);
                } forEach _players;
            };
        } forEach _enemyUnits;

        // ---- Sample: newly entered sub-points ----
        private _newSweptPoints = 0;
        {
            private _spIndex = _forEachIndex;
            if !(_spIndex in _visitedSubPoints) then {
                private _spPos = _x;
                private _reached = (_players findIf { (_x distance2D _spPos) <= _sweptRadius }) != -1;
                if (_reached) then {
                    _visitedSubPoints pushBack _spIndex;
                    _newSweptPoints = _newSweptPoints + 1;
                };
            };
        } forEach _subPoints;

        // ---- Sample: PID in-range + LOS ----
        private _pidInRange = false;
        if (!isNull _pidTarget && { alive _pidTarget }) then {
            private _pidObserver = _players select { (_x distance2D _pidTarget) <= _pidRange };
            if (_pidObserver isNotEqualTo []) then {
                private _po = _pidObserver select 0;
                _pidInRange = (lineIntersectsSurfaces [eyePos _po, eyePos _pidTarget, _po, _pidTarget, true, 1]) isEqualTo [];
            };
        };

        private _sample = createHashMapFromArray [
            ["dt", _dt],
            ["observerDistance", _observerDistance],
            ["hasLOS", _hasLOS],
            ["maxKnowsAbout", _maxKnowsAbout],
            ["newSweptPoints", _newSweptPoints],
            ["pidInRange", _pidInRange]
        ];

        _state = [_sample, _tuning, _state] call DSC_core_fnc_sweepEvaluateTick;

        // ---- Write back into the live mission's completionState (mutate in place) ----
        private _mission = missionNamespace getVariable ["DSC_currentMission", createHashMap];
        if (_mission isNotEqualTo createHashMap) then {
            private _cs = _mission get "completionState";
            _cs set ["observedSeconds", _state get "observedSeconds"];
            _cs set ["sweptPoints", _state get "sweptPoints"];
            _cs set ["targetIdentified", _state get "targetIdentified"];
            _cs set ["compromised", _state get "compromised"];

            // ---- Keep intelGathered current every tick (pure yield + builder reuse) ----
            private _facts = createHashMapFromArray [
                ["observedSeconds", _state get "observedSeconds"],
                ["bestProximity", _state get "bestProximity"],
                ["compromised", _state get "compromised"],
                ["sweptPoints", _state get "sweptPoints"],
                ["targetIdentified", _state get "targetIdentified"],
                ["locationId", _locationId],
                ["pidSubjectRef", _pidSubjectRef],
                ["seriesId", _seriesId]
            ];
            private _partialTokens = [_facts, _yieldTuning] call DSC_core_fnc_resolveSweepYield;
            private _syntheticSite = createHashMapFromArray [["pos", _objectivePos], ["id", _runId]];
            private _enriched = _partialTokens apply {
                [_x, _syntheticSite] call DSC_core_fnc_buildIntelTokenFromSite
            };
            _cs set ["intelGathered", _enriched];
        };

        // ---- Detection -> convert (fires at most once; fnc_sweepConvert itself
        // guards on completionState.converted, so a late duplicate is a no-op) ----
        if (_state get "convertRequested") then {
            private _convertCtx = createHashMapFromArray [
                ["runId", _runId],
                ["convertOn", _convertOn],
                ["exfilDistance", _exfilDistance],
                ["objectivePos", _objectivePos],
                ["garrisonClusters", _garrisonClusters],
                ["location", _location]
            ];
            [_convertCtx] call DSC_core_fnc_sweepConvert;
        };
    };
};

INFO_2("sweepMonitor - terminated (runId=%1, ticks=%2)",_runId,_ticks);
