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
private _missionSites   = _influenceData getOrDefault ["missionSites", []];

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
        ["mainStructures",    _loc getOrDefault ["mainStructures", []]],
        ["sideStructures",    _loc getOrDefault ["sideStructures", []]],
        ["tags",              _loc getOrDefault ["tags", []]],
        ["primaryFunction",   _loc getOrDefault ["primaryFunction", ""]],
        ["functionalProfile", _loc getOrDefault ["functionalProfile", createHashMap]],
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

diag_log format ["DSC: presenceManager - Registered %1 major zones (bases:%2 outposts:%3 camps:%4 populated:%5)",
    count _zones, count _bases, count _outposts, count _camps, count _populatedAreas];

// ============================================================================
// Microzones (Sprint D.5) — mission sites tagged with functional character
// ============================================================================
// Mission sites are the "everything else" bucket from fnc_initInfluence —
// orphan clusters, small civilian pockets, industrial sheds. They already
// carry Sprint D's tags/primaryFunction. We turn them into tag-dispatched
// microzones registered against the existing handler registry, with two
// density safeguards applied at registration time so they don't drown the
// budget or visually overlap major zones:
//
//   1. Major-zone exclusion (1200m)  — skip microzones whose center sits
//      inside a major zone's influence ring
//   2. Greedy spacing cull (600m)    — first-come-first-served between
//      accepted microzones so dense industrial complexes don't generate
//      8 overlapping clones
//
// A per-tick activation throttle in the tick loop (cap 3 microzone
// activations per tick) bounds worst-case spawn cost during fast traversal.

private _microzonesAccepted = 0;
private _microzonesRejectedNearMajor = 0;
private _microzonesRejectedSpacing   = 0;

private _majorExclusionRadius = 900;
private _microSpacing         = 600;

// Snapshot major-zone centers (only those just added above) for the
// exclusion check.
private _majorCenters = [];
{
    private _z = _zones get _x;
    _majorCenters pushBack (_z get "position");
} forEach (keys _zones);

private _classifyMicrozone = {
    params ["_tags", "_primaryFn"];
    if (("agricultural_zone" in _tags) || {_primaryFn == "agricultural"}) exitWith { "agriculturalSite" };
    if (("industrial_zone" in _tags) || {"industrial_hub" in _tags} || {_primaryFn == "industrial"}) exitWith { "industrialSite" };
    if ("infrastructure_node" in _tags) exitWith { "infrastructureNode" };
    "isolatedCompound"
};

// Build the controller-precompute candidate list once
// [pos, controlledBy, faction, influence, projRange]
private _ctrlCandidates = [];
{
    private _inf = _influenceMap getOrDefault [_x get "id", createHashMap];
    private _cb  = _inf getOrDefault ["controlledBy", "neutral"];
    if (_cb in ["opFor", "bluFor", "contested"]) then {
        _ctrlCandidates pushBack [
            _x get "position",
            _cb,
            _inf getOrDefault ["faction", ""],
            _inf getOrDefault ["influence", 0],
            4500
        ];
    };
} forEach (_bases + _outposts);
{
    private _inf = _influenceMap getOrDefault [_x get "id", createHashMap];
    private _cb  = _inf getOrDefault ["controlledBy", "neutral"];
    if (_cb in ["opFor", "bluFor", "contested"]) then {
        _ctrlCandidates pushBack [
            _x get "position",
            _cb,
            _inf getOrDefault ["faction", ""],
            _inf getOrDefault ["influence", 0],
            2500
        ];
    };
} forEach _camps;

// Map controlledBy -> engine side via factionData role lookup
private _factionDataInit = missionNamespace getVariable ["DSC_factionData", createHashMap];
private _sideForControl = {
    params ["_cb"];
    private _role = switch (_cb) do {
        case "opFor":     { "opFor" };
        case "bluFor":    { "bluFor" };
        case "contested": { "opForPartner" };
        default            { "" };
    };
    if (_role == "") exitWith { sideUnknown };
    (_factionDataInit getOrDefault [_role, createHashMap]) getOrDefault ["side", east]
};

// Track accepted microzone positions for the spacing cull
private _acceptedMicroCenters = [];

{
    private _loc      = _x;
    private _locId    = _loc get "id";
    private _locPos   = _loc get "position";
    private _locTags  = _loc getOrDefault ["tags", []];
    private _locPrim  = _loc getOrDefault ["primaryFunction", ""];

    // Skip if inside player base
    if (_playerBasePos distance2D _locPos < 50) then { continue };

    // Major-zone exclusion
    private _nearMajor = false;
    {
        if (_locPos distance2D _x < _majorExclusionRadius) exitWith { _nearMajor = true };
    } forEach _majorCenters;
    if (_nearMajor) then {
        _microzonesRejectedNearMajor = _microzonesRejectedNearMajor + 1;
        continue
    };

    // Greedy spacing cull
    private _tooClose = false;
    {
        if (_locPos distance2D _x < _microSpacing) exitWith { _tooClose = true };
    } forEach _acceptedMicroCenters;
    if (_tooClose) then {
        _microzonesRejectedSpacing = _microzonesRejectedSpacing + 1;
        continue
    };

    private _zType = [_locTags, _locPrim] call _classifyMicrozone;

    // Build the zone hashmap (mirrors _buildZone, plus controller precompute)
    private _inf = _influenceMap getOrDefault [_locId, createHashMap];
    private _zone = createHashMapFromArray [
        ["id",           _locId],
        ["type",         _zType],
        ["position",     _locPos],
        ["radius",       _loc getOrDefault ["radius", 100]],
        ["name",         _loc getOrDefault ["name", _locId]],
        ["controlledBy", _inf getOrDefault ["controlledBy", "neutral"]],
        ["faction",      _inf getOrDefault ["faction", ""]],
        ["influence",    _inf getOrDefault ["influence", 0]],
        ["structures",        _loc getOrDefault ["structures", []]],
        ["mainStructures",    _loc getOrDefault ["mainStructures", []]],
        ["sideStructures",    _loc getOrDefault ["sideStructures", []]],
        ["tags",              _locTags],
        ["primaryFunction",   _locPrim],
        ["functionalProfile", _loc getOrDefault ["functionalProfile", createHashMap]],
        ["state",        "DORMANT"],
        ["stateSince",   serverTime],
        ["graceUntil",   0],
        ["combatUntil",  0],
        ["units",        []],
        ["vehicles",     []],
        ["groups",       []]
    ];

    // ----- Nearest-controller precompute -----
    // Pick controller maximizing strength = influence * (1 - dist/projRange)
    private _bestStrength = 0;
    private _bestDist     = 999999;
    private _bestControl  = "neutral";
    private _bestFaction  = "";
    private _bestInf      = 0;
    private _bestRange    = 0;
    {
        _x params ["_cpPos", "_cpCb", "_cpFac", "_cpInf", "_cpRange"];
        private _d = _locPos distance2D _cpPos;
        if (_d < _cpRange) then {
            private _s = _cpInf * (1 - (_d / _cpRange));
            if (_s > _bestStrength) then {
                _bestStrength = _s;
                _bestDist     = _d;
                _bestControl  = _cpCb;
                _bestFaction  = _cpFac;
                _bestInf      = _cpInf;
                _bestRange    = _cpRange;
            };
        };
    } forEach _ctrlCandidates;

    _zone set ["controllerDist",       _bestDist];
    _zone set ["controllerSide",       [_bestControl] call _sideForControl];
    _zone set ["controllerFaction",    _bestFaction];
    _zone set ["controllerInfluence",  _bestInf];
    _zone set ["controllerControl",    _bestControl];
    _zone set ["controllerProjRange",  _bestRange];

    _zones set [_locId, _zone];
    _acceptedMicroCenters pushBack _locPos;
    _microzonesAccepted = _microzonesAccepted + 1;
} forEach _missionSites;

diag_log format ["DSC: presenceManager - Microzones: %1 accepted, %2 near-major-rejected, %3 spacing-rejected (of %4 mission sites)",
    _microzonesAccepted, _microzonesRejectedNearMajor, _microzonesRejectedSpacing, count _missionSites];

diag_log format ["DSC: presenceManager - Registered %1 zones total",
    count _zones];

missionNamespace setVariable ["DSC_presenceZones", _zones, true];

// ============================================================================
// Handler registry — one entry per zone type. Radii / grace / budget /
// populate fn live on each handler so the main loop is type-agnostic.
// Sprint A seeds today's behavior; Sprint B will tune per type.
// ============================================================================
missionNamespace setVariable ["DSC_presenceHandlers", createHashMap, true];

// Sprint B: per-type hysteresis + grace. Despawn radii are deliberately
// larger than activate radii so high-speed crossings (helicopter) stay
// inside the band long enough to be playable instead of getting abandoned
// on the next tick.
[createHashMapFromArray [
    ["type",           "base"],
    ["activateRadius", 800],
    ["despawnRadius",  1000],
    ["despawnGrace",   90],
    ["budgetUnits",    10],
    ["budgetVehicles", 2],
    ["populate",       DSC_core_fnc_presenceHandlerBase],
    ["despawn",        {}],
    ["lifecycle",      "delete"],
    ["pauseGrace",     180],
    ["paused",         false],
    ["class",          "major"]
]] call DSC_core_fnc_registerPresenceHandler;

[createHashMapFromArray [
    ["type",           "outpost"],
    ["activateRadius", 800],
    ["despawnRadius",  1000],
    ["despawnGrace",   75],
    ["budgetUnits",    8],
    ["budgetVehicles", 1],
    ["populate",       DSC_core_fnc_presenceHandlerOutpost],
    ["despawn",        {}],
    ["lifecycle",      "pause"],
    ["pauseGrace",     75],
    ["paused",         false],
    ["class",          "major"]
]] call DSC_core_fnc_registerPresenceHandler;

[createHashMapFromArray [
    ["type",           "camp"],
    ["activateRadius", 800],
    ["despawnRadius",  1000],
    ["despawnGrace",   60],
    ["budgetUnits",    4],
    ["budgetVehicles", 1],
    ["populate",       DSC_core_fnc_presenceHandlerCamp],
    ["despawn",        {}],
    ["lifecycle",      "pause"],
    ["pauseGrace",     45],
    ["paused",         false],
    ["class",          "major"]
]] call DSC_core_fnc_registerPresenceHandler;

[createHashMapFromArray [
    ["type",           "populatedArea"],
    ["activateRadius", 800],
    ["despawnRadius",  1000],
    ["despawnGrace",   60],
    ["budgetUnits",    5],
    ["budgetVehicles", 0],
    ["populate",       DSC_core_fnc_presenceHandlerPopulatedArea],
    ["despawn",        {}],
    ["lifecycle",      "pause"],
    ["pauseGrace",     60],
    ["paused",         false],
    ["class",          "major"]
]] call DSC_core_fnc_registerPresenceHandler;

// ============================================================================
// Microzone handlers (Sprint D.5)
// ============================================================================
// Small radii + lifecycle=delete so dense rural strips don't fill the budget
// with PAUSED zones the player won't revisit. typeMultiplier sets per-zone
// projection weight (infrastructure 2.0, ag 0.5, others 1.0). The shared
// fnc_resolveMicrozoneProjection helper reads these blocks at activation
// time and returns guardChance/patrolChance based on nearest-controller data
// the zone carries from init.

[createHashMapFromArray [
    ["type",           "industrialSite"],
    ["activateRadius", 600],
    ["despawnRadius",  800],
    ["despawnGrace",   30],
    ["budgetUnits",    3],
    ["budgetVehicles", 0],
    ["populate",       DSC_core_fnc_presenceHandlerIndustrialSite],
    ["despawn",        {}],
    ["lifecycle",      "delete"],
    ["pauseGrace",     0],
    ["paused",         false],
    ["class",          "micro"],
    ["military", createHashMapFromArray [
        ["typeMultiplier", 1.0],
        ["guard", createHashMapFromArray [
            ["size",              [2, 3]],
            ["radius",            40],
            ["skill",             "garrison_light"],
            ["irregularFallback", true]
        ]],
        ["patrol", createHashMapFromArray [
            ["size",   [2, 3]],
            ["radius", 250],
            ["skill",  "garrison_light"]
        ]]
    ]]
]] call DSC_core_fnc_registerPresenceHandler;

[createHashMapFromArray [
    ["type",           "isolatedCompound"],
    ["activateRadius", 600],
    ["despawnRadius",  800],
    ["despawnGrace",   30],
    ["budgetUnits",    3],
    ["budgetVehicles", 0],
    ["populate",       DSC_core_fnc_presenceHandlerIsolatedCompound],
    ["despawn",        {}],
    ["lifecycle",      "delete"],
    ["pauseGrace",     0],
    ["paused",         false],
    ["class",          "micro"],
    ["military", createHashMapFromArray [
        ["typeMultiplier", 1.0],
        ["guard", createHashMapFromArray [
            ["size",              [2, 3]],
            ["radius",            30],
            ["skill",             "garrison_light"],
            ["irregularFallback", true]
        ]],
        ["patrol", createHashMapFromArray [
            ["size",   [2, 3]],
            ["radius", 300],
            ["skill",  "garrison_light"]
        ]]
    ]]
]] call DSC_core_fnc_registerPresenceHandler;

[createHashMapFromArray [
    ["type",           "infrastructureNode"],
    ["activateRadius", 600],
    ["despawnRadius",  800],
    ["despawnGrace",   30],
    ["budgetUnits",    3],
    ["budgetVehicles", 0],
    ["populate",       DSC_core_fnc_presenceHandlerInfrastructureNode],
    ["despawn",        {}],
    ["lifecycle",      "delete"],
    ["pauseGrace",     0],
    ["paused",         false],
    ["class",          "micro"],
    ["military", createHashMapFromArray [
        ["typeMultiplier", 2.0],
        ["guard", createHashMapFromArray [
            ["size",              [2, 3]],
            ["radius",            20],
            ["skill",             "garrison_light"],
            ["irregularFallback", false]
        ]],
        ["patrol", createHashMapFromArray [
            ["size",   [2, 3]],
            ["radius", 200],
            ["skill",  "garrison_light"]
        ]]
    ]]
]] call DSC_core_fnc_registerPresenceHandler;

[createHashMapFromArray [
    ["type",           "agriculturalSite"],
    ["activateRadius", 600],
    ["despawnRadius",  800],
    ["despawnGrace",   30],
    ["budgetUnits",    4],
    ["budgetVehicles", 0],
    ["populate",       DSC_core_fnc_presenceHandlerAgriculturalSite],
    ["despawn",        {}],
    ["lifecycle",      "delete"],
    ["pauseGrace",     0],
    ["paused",         false],
    ["class",          "micro"],
    ["military", createHashMapFromArray [
        ["typeMultiplier", 0.5]
        // no guard / patrol blocks — projection returns zero chance,
        // handler does its own 5% lone-armed-civilian roll
    ]]
]] call DSC_core_fnc_registerPresenceHandler;

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
    ["PAUSED",     "ColorBlue"],
    ["COMBAT",     "ColorRed"]
];

{
    private _zoneId = _x;
    private _zone   = _zones get _zoneId;
    private _zPos   = _zone get "position";
    private _zType  = _zone get "type";
    private _zRad   = _zone get "radius";

    private _markerR = switch (_zType) do {
        case "base":               { (_zRad max 200) + 200 };
        case "outpost":            { (_zRad max 150) + 150 };
        case "camp":               { (_zRad max 75)  + 75  };
        case "populatedArea":      { (_zRad max 150) + 100 };
        case "industrialSite":     { (_zRad max 60)  + 40  };
        case "isolatedCompound":   { (_zRad max 50)  + 30  };
        case "infrastructureNode": { (_zRad max 40)  + 30  };
        case "agriculturalSite":   { (_zRad max 50)  + 30  };
        default                    { 100 };
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

    // Handler registry — radii / grace / budget per zone type.
    // Reads are read-only; registration happens at init above.
    private _handlers = missionNamespace getVariable ["DSC_presenceHandlers", createHashMap];

    private _fnc_handlerNum = {
        params ["_zType", "_key", "_default"];
        private _h = _handlers getOrDefault [_zType, createHashMap];
        _h getOrDefault [_key, _default]
    };

    // String/value variant — handler config that's not a number (e.g. lifecycle).
    private _fnc_handlerVal = {
        params ["_zType", "_key", "_default"];
        private _h = _handlers getOrDefault [_zType, createHashMap];
        _h getOrDefault [_key, _default]
    };

    // Freeze/unfreeze helpers for the "pause" lifecycle. We disable
    // simulation and AI on everything tracked on the zone; re-entry
    // re-enables instantly with no createUnit cost.
    private _fnc_pauseZone = {
        params ["_zone"];
        {
            if (!isNull _x) then {
                _x disableAI "ALL";
                _x enableSimulation false;
            };
        } forEach (_zone getOrDefault ["units", []]);
        {
            if (!isNull _x) then {
                _x enableSimulation false;
            };
        } forEach (_zone getOrDefault ["vehicles", []]);
    };
    private _fnc_resumeZone = {
        params ["_zone"];
        {
            if (!isNull _x) then {
                _x enableSimulation true;
                _x enableAI "ALL";
            };
        } forEach (_zone getOrDefault ["units", []]);
        {
            if (!isNull _x) then {
                _x enableSimulation true;
            };
        } forEach (_zone getOrDefault ["vehicles", []]);
    };

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

    // Sprint B: tick dropped 20s -> 8s. Worker handles ~5 activations per
    // 8s easily; latency now bounded by one tick, not three.
    private _tickInterval = 8;
    diag_log format ["DSC: presenceManager - Tick loop started (%1s interval)", _tickInterval];

    // Mission AO arbitration + global entity budget
    // - When a mission is active, military zones (base/outpost/camp) whose
    //   center is within (missionRadius + buffer) of the mission AO suspend.
    //   Civilians stay (population thins naturally with influence already).
    // - Global cap on simultaneous active units/vehicles. Closest zones win.
    private _missionAoBuffer = 300;     // meters past mission radius to keep clear
    private _missionDefaultRadius = 600; // when mission doesn't expose a radius
    // Sprint B: raised from 100/30 to leave headroom for the wider despawn
    // radii (more zones simultaneously in DESPAWNING grace).
    private _budgetUnits    = 150;
    private _budgetVehicles = 40;
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
        ["pausedTotal",          0],   // ACTIVE -> PAUSED transitions
        ["resumedFromPause",     0],   // PAUSED -> ACTIVE (re-entry, instant)
        ["pauseExpired",         0],   // PAUSED -> DORMANT (extended grace ran out, entities deleted)
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
        private _ticks = floor ((_now - _dormantExit) / _tickInterval) + 1; // approx tick count

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
        sleep _tickInterval;

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
            // DESPAWNING zones are condemned — the worker will free their
            // units within the next cycle. Counting them in the budget cap
            // creates artificial scarcity (60%+ skipRate observed in flight
            // tests where 10+ zones sat DESPAWNING simultaneously after a
            // helicopter sprint). Exclude them so closer candidates can
            // activate while the worker drains the despawn queue.
            if (_zs in ["ACTIVE", "ACTIVATING", "PAUSED"]) then {
                _curUnits    = _curUnits + count (_z get "units");
                _curVehicles = _curVehicles + count (_z get "vehicles");
            };
        } forEach (keys _zones);

        private _activated = 0;
        private _despawned = 0;
        private _dormant   = 0;
        private _activatingCt = 0;
        private _pausedCt  = 0;
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

            private _actR = [_zType, "activateRadius", 1000] call _fnc_handlerNum;
            private _depR = [_zType, "despawnRadius",  1800] call _fnc_handlerNum;

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
                        // Force despawn with no grace — mission needs this zone clear.
                        // Bypasses pause lifecycle: mission AO always means delete.
                        _newState = "DESPAWNING";
                        _zone set ["graceUntil", serverTime];
                        _suspended = _suspended + 1;
                        ["forcedSuspended"] call _fnc_bumpStat;
                        diag_log format ["DSC: presence active-duration [%1/%2] %3s (forced by mission AO)",
                            _zoneId, _zType, round (serverTime - (_zone getOrDefault ["stateSince", serverTime]))];
                    } else {
                        if (_minDist > _depR) then {
                            private _lifecycle = [_zType, "lifecycle", "delete"] call _fnc_handlerVal;
                            private _activeFor = round (serverTime - (_zone getOrDefault ["stateSince", serverTime]));
                            // Speed-aware: if the player blew past at >35 m/s
                            // (~125 km/h), they're not coming back. Skip pause
                            // lifecycle and route straight to DESPAWNING so the
                            // budget isn't consumed by zones that will never
                            // resume. resumeRate=0% in helicopter sprints proved
                            // pause is dead weight under sustained motion.
                            if (_lifecycle == "pause" && _avgPlayerSpeed > 35) then {
                                _lifecycle = "delete";
                                ["pauseSkippedFast"] call _fnc_bumpStat;
                            };
                            if (_lifecycle == "pause") then {
                                // Freeze instead of delete. Re-entry within pauseGrace
                                // wakes the zone instantly. Beyond pauseGrace, fall
                                // through to actual delete via PAUSED -> DORMANT.
                                [_zone] call _fnc_pauseZone;
                                _newState = "PAUSED";
                                _zone set ["graceUntil", serverTime + ([_zType, "pauseGrace", 120] call _fnc_handlerNum)];
                                ["pausedTotal"] call _fnc_bumpStat;
                                diag_log format ["DSC: presence active-duration [%1/%2] %3s (paused, dist=%4m, %5u/%6v frozen)",
                                    _zoneId, _zType, _activeFor, round _minDist,
                                    count (_zone get "units"), count (_zone get "vehicles")];
                            } else {
                                _newState = "DESPAWNING";
                                _zone set ["graceUntil", serverTime + ([_zType, "despawnGrace", 45] call _fnc_handlerNum)];
                                diag_log format ["DSC: presence active-duration [%1/%2] %3s (player left, dist=%4m)",
                                    _zoneId, _zType, _activeFor, round _minDist];
                            };
                        };
                    };
                };
                case "PAUSED": {
                    // Re-entry is instant: unfreeze and go straight to ACTIVE.
                    // Mission AO forces actual delete via despawn queue.
                    // Grace expiry transitions to DORMANT (entities deleted).
                    if (_missionOverlap) then {
                        if !(_zone in _despawnQueue) then {
                            _despawnQueue pushBack _zone;
                        };
                        _newState = "DESPAWNING";
                        _zone set ["graceUntil", serverTime];
                        _suspended = _suspended + 1;
                        ["forcedSuspended"] call _fnc_bumpStat;
                        diag_log format ["DSC: presence pause-forced [%1/%2] (mission AO, deleting)", _zoneId, _zType];
                    } else {
                        if (_minDist <= _actR) then {
                            [_zone] call _fnc_resumeZone;
                            _newState = "ACTIVE";
                            private _pausedFor = round (serverTime - (_zone getOrDefault ["stateSince", serverTime]));
                            ["resumedFromPause"] call _fnc_bumpStat;
                            diag_log format ["DSC: presence resumed [%1/%2] (paused for %3s, dist=%4m, %5u/%6v unfrozen)",
                                _zoneId, _zType, _pausedFor, round _minDist,
                                count (_zone get "units"), count (_zone get "vehicles")];
                        } else {
                            if (serverTime >= (_zone get "graceUntil")) then {
                                // Pause grace expired — actually delete now.
                                if !(_zone in _despawnQueue) then {
                                    _despawnQueue pushBack _zone;
                                };
                                _newState = "DESPAWNING";
                                _zone set ["graceUntil", serverTime];
                                ["pauseExpired"] call _fnc_bumpStat;
                                diag_log format ["DSC: presence pause-expired [%1/%2] (deleting %3u/%4v)",
                                    _zoneId, _zType, count (_zone get "units"), count (_zone get "vehicles")];
                            };
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
                case "PAUSED":     { _pausedCt = _pausedCt + 1 };
                case "DORMANT":    { _dormant   = _dormant + 1 };
                default {};
            };
        } forEach (keys _zones);

        // ----- Apply budget to candidates ----------------------------------
        // Sort by distance ascending; enqueue while we have unit/vehicle headroom.
        // Skipped candidates stay DORMANT — the next tick gives them another chance
        // once active zones despawn and free budget.
        //
        // Microzone throttle (Sprint D.5): cap NEW microzone activations per
        // tick. Microzones are cheap individually, but a fast traversal across
        // a dense rural strip can land 10+ candidates in one tick — yielding
        // spawns inside the worker still adds up. Major zones bypass the
        // throttle so they always win when both are competing for budget.
        private _maxMicrosPerTick = 4;
        private _microsThisTick   = 0;
        _candidates sort true;
        private _approved = 0;
        private _budgetSkipped = 0;
        private _microSkippedThrottle = 0;
        {
            _x params ["_d", "_zone"];
            // Estimate cost from the registered handler — kept conservative
            // so spikes don't blow past the cap before activations resolve.
            private _zt = _zone get "type";
            private _estU = [_zt, "budgetUnits",    5] call _fnc_handlerNum;
            private _estV = [_zt, "budgetVehicles", 0] call _fnc_handlerNum;
            private _zClass = [_zt, "class", "major"] call _fnc_handlerVal;

            if (_zClass == "micro" && {_microsThisTick >= _maxMicrosPerTick}) then {
                _microSkippedThrottle = _microSkippedThrottle + 1;
                // Stay DORMANT — next tick gets another shot.
            } else {
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
                if (_zClass == "micro") then { _microsThisTick = _microsThisTick + 1 };
                ["dormantToActivating"] call _fnc_bumpStat;
                ["budgetApproved"] call _fnc_bumpStat;
                // Promote counter
                _dormant = _dormant - 1;
                _activatingCt = _activatingCt + 1;
                };
            };
        } forEach _candidates;

        if (_budgetSkipped > 0 || _microSkippedThrottle > 0) then {
            diag_log format ["DSC: presence — budget gate: %1 candidates approved, %2 budget-skipped, %3 micro-throttled (cap %4u/%5v, used %6u/%7v, %8/%9 micros this tick)",
                _approved, _budgetSkipped, _microSkippedThrottle,
                _budgetUnits, _budgetVehicles, _curUnits, _curVehicles,
                _microsThisTick, _maxMicrosPerTick];
        };

        private _missionLabel = if (_hasMission) then {
            format [" | mission r=%1", _missionAoRadius]
        } else { "" };

        diag_log format ["DSC: presence tick — active:%1 activating:%2 paused:%3 despawning:%4 dormant:%5 sus:%6 (of %7) | qA=%8 qD=%9 | used %10u/%11v of %12u/%13v | speed avg=%14 max=%15%16",
            _activated, _activatingCt, _pausedCt, _despawned, _dormant, _suspended, count _zones,
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
            private _paused    = _stats getOrDefault ["pausedTotal", 0];
            private _resumed   = _stats getOrDefault ["resumedFromPause", 0];
            private _pauseExp  = _stats getOrDefault ["pauseExpired", 0];
            private _resumeRate = if (_paused > 0) then { 100 * _resumed / _paused } else { 0 };
            diag_log format ["DSC: stats — paused=%1 resumed=%2 expired=%3 (resumeRate=%4%%, save=%5 spawns avoided)",
                _paused, _resumed, _pauseExp, round _resumeRate, _resumed];
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
