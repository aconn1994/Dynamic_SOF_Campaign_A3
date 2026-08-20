#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_initTestScenario
 * Description:
 *     Deterministic single-mission test harness (Tier-2). Boots ONLY the
 *     init steps a feature needs (whitelisted, dependency-ordered), forces
 *     a mission template into the real generation path, generates exactly
 *     one mission, and stops — no infinite loop, no ambient noise.
 *
 *     DESIGN CONSTRAINT: this calls the SAME generation functions the real
 *     mission loop in fnc_initServer calls (fnc_selectMission ->
 *     fnc_generateMission -> fnc_evaluateCompletion -> fnc_buildMissionOutcome).
 *     It never re-implements their bodies. It only differs in (a) which
 *     prerequisite steps boot, (b) forcing the template, (c) single-shot
 *     instead of looping, (d) player placement. See
 *     .crush/agentic-workflow-and-testing.md Part B.3.
 *
 *     Reads `DSC_testConfig` <HASHMAP>:
 *       "factionProfile" <STRING>  - Harness faction profile key. Currently
 *                                    only "vanilla" is defined (a small,
 *                                    reproducible profile owned by the
 *                                    harness itself — role sides are still
 *                                    normalized through the real
 *                                    fnc_resolveRoleSide, same as production
 *                                    init). Default: "vanilla".
 *       "steps" <ARRAY>            - Whitelist of init steps to run, in
 *                                    dependency order. Recognized keys:
 *                                      "globals"   - Step 0 equivalent
 *                                                    (session globals +
 *                                                    dynamic sim). Always
 *                                                    needed.
 *                                      "locations" - fnc_scanLocations
 *                                      "factions"  - fnc_initFactionData
 *                                      "influence" - fnc_initInfluence
 *                                      "c2"        - fnc_initC2Network
 *                                      "presence"  - fnc_initPresenceManager
 *                                      "roving"    - fnc_initRovingManager
 *                                      "bft"       - fnc_bftSnapshot
 *                                    Default: ["globals"].
 *       "missionTemplate" <HASHMAP> - Forced template passed straight to
 *                                    fnc_selectMission (same shape as
 *                                    fnc_resolveMissionConfig accepts). Its
 *                                    "location" field may be a location id
 *                                    <STRING> (resolved against the scanned
 *                                    locations) or a location <HASHMAP>
 *                                    (used as-is), or omitted entirely (auto
 *                                    selection via regionCenter/Radius or
 *                                    influence data). Default: createHashMap
 *                                    (random KILL_CAPTURE, see
 *                                    fnc_selectMission).
 *       "singleShot" <BOOL>        - true: immediately runs one debrief
 *                                    cycle (fnc_evaluateCompletion ->
 *                                    fnc_buildMissionOutcome -> publish
 *                                    DSC_lastMissionOutcome) right after
 *                                    generation, then stops. false: leaves
 *                                    the generated mission ACTIVE for a
 *                                    human to play out manually; the harness
 *                                    still never loops. Default: true.
 *       "playerSpawn" <STRING>     - "nearSite": teleports every connected
 *                                    player to ~150m from the objective
 *                                    location, random bearing. Any other
 *                                    value (or omitted): no player
 *                                    placement. Default: "".
 *       "timeOfDay" <NUMBER>       - Hour (0-24) to setDate to, applied
 *                                    BEFORE generation so the mission
 *                                    composes against fixed lighting.
 *                                    Negative/omitted: leave as-is.
 *                                    Default: -1.
 *       "freezeWeather" <BOOL>    - true: zeroes overcast/rain/fog and
 *                                    forces the change, applied BEFORE
 *                                    generation. Default: false.
 *       "extraDebug" <BOOL>        - true: logs additional TRACE detail
 *                                    about the resolved template/config.
 *                                    Default: false.
 *
 * Arguments: None (reads `DSC_testConfig` from missionNamespace)
 *
 * Return Value:
 *     <HASHMAP> - Mission outcome (from fnc_buildMissionOutcome) if
 *                 singleShot; otherwise the raw mission data hashmap from
 *                 fnc_generateMission. Empty hashmap on failure.
 *
 * Example:
 *     DSC_testConfig = createHashMapFromArray [
 *         ["factionProfile", "vanilla"],
 *         ["steps", ["globals", "locations", "factions", "influence"]],
 *         ["missionTemplate", createHashMapFromArray [
 *             ["type", "KILL_CAPTURE"],
 *             ["missionProfile", "AFO_rural"]
 *         ]],
 *         ["singleShot", true],
 *         ["playerSpawn", "nearSite"],
 *         ["timeOfDay", 6],
 *         ["freezeWeather", true]
 *     ];
 *     [] call DSC_core_fnc_initTestScenario;
 */

if (!isServer) exitWith { createHashMap };

if (isNil "DSC_testConfig") exitWith {
    ERROR("initTestScenario - DSC_testConfig is not defined, nothing to run");
    createHashMap
};

private _config = missionNamespace getVariable ["DSC_testConfig", createHashMap];
if (_config isEqualTo createHashMap) exitWith {
    ERROR("initTestScenario - DSC_testConfig is empty");
    createHashMap
};

private _factionProfileKey = _config getOrDefault ["factionProfile", "vanilla"];
private _steps             = _config getOrDefault ["steps", ["globals"]];
private _missionTemplate   = _config getOrDefault ["missionTemplate", createHashMap];
private _singleShot        = _config getOrDefault ["singleShot", true];
private _playerSpawn       = _config getOrDefault ["playerSpawn", ""];
private _timeOfDay         = _config getOrDefault ["timeOfDay", -1];
private _freezeWeather     = _config getOrDefault ["freezeWeather", false];
private _extraDebug        = _config getOrDefault ["extraDebug", false];

private _stepCount = count _steps;
INFO_1("initTestScenario - starting harness run (%1 steps)",_stepCount);

// ============================================================================
// Harness-owned faction profiles (data only). Everything the profile feeds
// into — scanLocations, initFactionData, initInfluence, resolveRoleSide,
// selectMission, generateMission, evaluateCompletion, buildMissionOutcome —
// is the real production function. Only this literal config table is
// harness-local, so a run is reproducible without depending on whichever
// faction mods happen to be loaded.
// ============================================================================
private _harnessProfileVanilla = createHashMapFromArray [
    ["bluFor", createHashMapFromArray [
        ["side", west],
        ["factions", ["BLU_F"]]
    ]],
    ["bluForPartner", createHashMapFromArray [
        ["side", independent],
        ["factions", ["IND_F"]]
    ]],
    ["opFor", createHashMapFromArray [
        ["side", east],
        ["factions", ["OPF_F", "OPF_R_F"]]
    ]],
    ["opForPartner", createHashMapFromArray [
        ["side", east],
        ["factions", ["OPF_G_F"]]
    ]],
    ["irregulars", createHashMapFromArray [
        ["side", east],
        ["factions", ["IND_C_F", "IND_L_F"]]
    ]],
    ["civilians", createHashMapFromArray [
        ["side", civilian],
        ["factions", ["CIV_F"]]
    ]],
    ["environmentalActors", createHashMapFromArray [
        ["side", civilian],
        ["factions", ["CIV_IDAP_F", "BLU_GEN_F"]]
    ]]
];

private _harnessProfiles = createHashMapFromArray [
    ["vanilla", _harnessProfileVanilla]
];

private _selectedProfile = _harnessProfiles getOrDefault [_factionProfileKey, _harnessProfileVanilla];

// Normalize role sides through the real authority, same as fnc_initServer.
{
    private _roleKey  = _x;
    private _roleData = _y;
    private _natural  = _roleData getOrDefault ["side", east];
    private _resolved = [_roleKey, _natural] call DSC_core_fnc_resolveRoleSide;
    _roleData set ["side", _resolved];
} forEach _selectedProfile;

// ============================================================================
// STEP: globals
// ============================================================================
private _locations = [];
private _factionData = createHashMap;
private _influenceData = createHashMap;

if ("globals" in _steps) then {
    missionNamespace setVariable ["initGlobalsComplete", false, true];
    missionNamespace setVariable ["playerMainBase", "player_base_1", true];
    missionNamespace setVariable ["factionProfileConfig", _selectedProfile, true];
    missionNamespace setVariable ["missionState", "IDLE", true];
    missionNamespace setVariable ["missionInProgress", false, true];
    missionNamespace setVariable ["missionComplete", false, true];

    missionNamespace setVariable ["zeusInteriorsInstalled", false, true];
    if (isClass (configFile >> "Rsc_ZEIC_InteriorFill")) then {
        missionNamespace setVariable ["zeusInteriorsInstalled", true, true];
    };

    missionNamespace setVariable ["initGlobalsComplete", true, true];

    enableDynamicSimulationSystem true;
    "Group"        setDynamicSimulationDistance 1500;
    "Vehicle"      setDynamicSimulationDistance 2000;
    "EmptyVehicle" setDynamicSimulationDistance 500;
    "Prop"         setDynamicSimulationDistance 300;

    if (isNil { missionNamespace getVariable "DSC_missionQueue" }) then {
        missionNamespace setVariable ["DSC_missionQueue", [], true];
    };
    if (isNil { missionNamespace getVariable "DSC_missionAbortRequested" }) then {
        missionNamespace setVariable ["DSC_missionAbortRequested", false, true];
    };

    INFO("initTestScenario - STEP globals complete");
};

// ============================================================================
// STEP: locations
// ============================================================================
if ("locations" in _steps) then {
    _locations = [] call DSC_core_fnc_scanLocations;
    missionNamespace setVariable ["DSC_locations", _locations, true];
    INFO_1("initTestScenario - STEP locations complete (%1 locations)",count _locations);
};

// ============================================================================
// STEP: factions
// ============================================================================
if ("factions" in _steps) then {
    _factionData = [_selectedProfile] call DSC_core_fnc_initFactionData;
    missionNamespace setVariable ["DSC_factionData", _factionData, true];
    INFO("initTestScenario - STEP factions complete");
};

// ============================================================================
// STEP: influence
// ============================================================================
if ("influence" in _steps) then {
    _influenceData = [_locations, "offensive", _factionData] call DSC_core_fnc_initInfluence;
    missionNamespace setVariable ["DSC_influenceData", _influenceData, true];
    INFO("initTestScenario - STEP influence complete");
};

// ============================================================================
// STEP: c2 / presence / roving / bft — hooks, off by default
// ============================================================================
if ("c2" in _steps) then {
    [_influenceData, _factionData] call DSC_core_fnc_initC2Network;
    INFO("initTestScenario - STEP c2 complete");
};
if ("presence" in _steps) then {
    [_influenceData] call DSC_core_fnc_initPresenceManager;
    INFO("initTestScenario - STEP presence complete");
};
if ("roving" in _steps) then {
    [_influenceData, _factionData] call DSC_core_fnc_initRovingManager;
    INFO("initTestScenario - STEP roving complete");
};
if ("bft" in _steps) then {
    [] spawn DSC_core_fnc_bftSnapshot;
    INFO("initTestScenario - STEP bft complete");
};

// ============================================================================
// Deterministic time / weather — applied BEFORE generation
// ============================================================================
if (_timeOfDay >= 0) then {
    private _d = date;
    setDate [_d select 0, _d select 1, _d select 2, _timeOfDay, 0];
    INFO_1("initTestScenario - time of day set to %1:00",_timeOfDay);
};

if (_freezeWeather) then {
    0 setOvercast 0;
    0 setRain 0;
    0 setFog 0;
    forceWeatherChange;
    INFO("initTestScenario - weather frozen (clear)");
};

// ============================================================================
// Resolve forced template location (id string -> hashmap lookup)
// ============================================================================
// Shallow copy so we never mutate the caller's DSC_testConfig.missionTemplate
private _template = createHashMap;
{ _template set [_x, _y] } forEach _missionTemplate;

if ("location" in _template && { (_template get "location") isEqualType "" }) then {
    private _locId = _template get "location";
    private _enrichedLocations = if (_influenceData isEqualTo createHashMap) then { _locations } else { _influenceData get "locations" };
    private _matchIndex = _enrichedLocations findIf { (_x get "id") == _locId };

    if (_matchIndex != -1) then {
        _template set ["location", _enrichedLocations select _matchIndex];
    } else {
        WARNING_1("initTestScenario - location id '%1' not found, falling back to auto-selection",_locId);
        _template deleteAt "location";
    };
};

if (_extraDebug) then {
    TRACE_1("initTestScenario - resolved template",_template);
}; // hoisted local avoids the CBA log-macro comma-in-array trap for inline literals

// ============================================================================
// Guard: mission generation needs faction + influence data
// ============================================================================
if (_influenceData isEqualTo createHashMap || _factionData isEqualTo createHashMap) exitWith {
    ERROR("initTestScenario - cannot generate mission: 'factions' and/or 'influence' steps were not booted");
    createHashMap
};

// ============================================================================
// Select + Generate — the REAL generation path, no fork
// ============================================================================
private _missionConfig = [_influenceData, _factionData, _template] call DSC_core_fnc_selectMission;
if (_missionConfig isEqualTo createHashMap) exitWith {
    ERROR("initTestScenario - mission selection failed");
    createHashMap
};

private _missionData = [_missionConfig] call DSC_core_fnc_generateMission;
if (_missionData isEqualTo createHashMap) exitWith {
    ERROR("initTestScenario - mission generation failed");
    createHashMap
};

private _mission = _missionData get "mission";
private _location = _missionConfig get "location";
private _locationName = _location get "name";

missionNamespace setVariable ["missionInProgress", true, true];
missionNamespace setVariable ["missionState", "ACTIVE", true];
missionNamespace setVariable ["DSC_testMissionData", _missionData, true];

INFO_2("initTestScenario - mission generated (%1 at %2)",_missionConfig get "type",_locationName);

// ============================================================================
// Player placement
// ============================================================================
if (_playerSpawn == "nearSite") then {
    private _players = allPlayers;

    if (_players isNotEqualTo []) then {
        private _locPos = _location get "position";
        private _bearing = random 360;
        private _spawnPos = _locPos vectorAdd [150 * sin _bearing, 150 * cos _bearing, 0];

        { _x setPosATL _spawnPos } forEach _players;
        INFO("initTestScenario - player(s) teleported ~150m from objective");
    } else {
        WARNING("initTestScenario - playerSpawn 'nearSite' requested but no players present");
    };
};

// ============================================================================
// Single-shot debrief cycle — no loop, ever
// ============================================================================
private _outcome = _missionData;

if (_singleShot) then {
    private _completion = _mission getOrDefault ["completion", "KILL_CAPTURE"];
    private _completionState = _mission getOrDefault ["completionState", createHashMap];
    private _completionResult = [_completion, _completionState] call DSC_core_fnc_evaluateCompletion;

    _outcome = [_mission, _completionResult, createHashMap] call DSC_core_fnc_buildMissionOutcome;
    missionNamespace setVariable ["DSC_lastMissionOutcome", _outcome, true];

    INFO_1("initTestScenario - single-shot debrief complete: %1",_outcome get "message");
} else {
    INFO("initTestScenario - singleShot=false, mission left ACTIVE for manual playtest (harness still does not loop)");
};

INFO("initTestScenario - harness run complete (no loop)");

_outcome
