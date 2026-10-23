// ============================================================================
// ⏸ DEFERRED — the SWEEP "case" in fnc_generateMission.sqf is commented
// out (post-Session-6 playtest; see .crush/roadmap.md). Running this
// harness will log a WARNING and generate no mission until that case is
// re-enabled. Left in place for when the archetype is revisited.
// ============================================================================
// Tier-2 feature harness DSC_testConfig example — a forced SWEEP mission
// (SR_OBSERVE archetype, OBSERVED completion) at a fixed location, left
// ACTIVE for a human to walk up to a vantage, observe, and confirm (a)
// observedSeconds accumulates, (b) the mission completes at observeRequired,
// (c) an intel token lands in DSC_intelLedger on success.
//
// singleShot MUST be false — a single-shot debrief evaluates completion
// immediately, so observedSeconds would read 0 and the run would assert
// nothing (fnc_generateMission's "SWEEP" case WARNs if it detects
// DSC_testConfig.singleShot == true).
//
// "c2" is in steps. Without it, no node is in reach, groups are never
// C2-stamped, and the detection->convert path's "let C2 react organically"
// design has nothing to react — which reads in the RPT exactly like a
// broken convert hook (see the documented three-causes-of-C2-silence
// gotcha in AGENTS.md).
//
// playerSpawnDistance (Session 6 addition to fnc_initTestScenario) is set
// to 450m here — well inside observeMax (600) but outside observeIdeal
// (250), so the standoff/proximity dials are actually exercised instead of
// spawning the player on top of the objective at the old hardcoded 150m.
//
// Intended for a dedicated test mission following the DSC_Test.<Terrain>
// pattern (e.g. DSC_Test.Altis). That mission's initServer.sqf should call
// fnc_initTestScenario INSTEAD OF fnc_initServer:
//
//     [] call DSC_core_fnc_initTestScenario;
//     [] call DSC_core_fnc_initServerDebug; // optional, for tablet/queue globals
//
// Replace "location" below with a real location id from the terrain you're
// testing against — dump one first with steps: ["globals","locations"] and
// no "location"/"regionCenter" set, then read DSC_locations in the debug
// console, or grep the RPT's scanLocations LOG lines.
// ============================================================================

DSC_testConfig = createHashMapFromArray [
    ["factionProfile", "vanilla"],
    ["steps", ["globals", "locations", "factions", "influence", "c2"]],
    ["missionTemplate", createHashMapFromArray [
        ["type", "SWEEP"],
        ["missionProfile", "SR_rural"],
        ["location", "loc_replace_with_real_id"],
        ["sweepConfig", createHashMapFromArray [
            ["archetype", "SR_OBSERVE"],
            ["completion", "OBSERVED"],
            ["observeRequired", 90],
            ["observeMax", 600],
            ["observeIdeal", 250],
            ["compromiseThreshold", 0.6],
            ["compromiseTicks", 2],
            ["markerStyle", "search_area"]
        ]]
    ]],
    ["singleShot", false],
    ["playerSpawn", "nearSite"],
    ["playerSpawnDistance", 450],
    ["timeOfDay", 5],
    ["freezeWeather", true],
    ["extraDebug", true]
];

[] call DSC_core_fnc_initTestScenario;

// ----------------------------------------------------------------------------
// Convert-path variant — swap the sweepConfig block above for this one to
// deliberately provoke detection and confirm the mission converts to EXFIL
// (SR_OBSERVE's archetype default convertOn) instead of hard-failing:
//
//     ["sweepConfig", createHashMapFromArray [
//         ["archetype", "SR_OBSERVE"],
//         ["completion", "OBSERVED"],
//         ["observeRequired", 90],
//         ["observeMax", 600],
//         ["observeIdeal", 250],
//         ["compromiseThreshold", 0.2],
//         ["compromiseTicks", 1],
//         ["convertOn", "RAID"],
//         ["markerStyle", "search_area"]
//     ]]
//
// With compromiseThreshold this low and compromiseTicks at 1, walking into
// any ambient patrol's knowsAbout range should latch compromised within a
// couple of ticks, fire fnc_sweepConvert, reveal full compound markers, and
// swap the completion condition to the convertOn target.
// ============================================================================
