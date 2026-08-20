// ============================================================================
// Tier-1 headless DSC_testConfig example — runs fnc_runTests only.
// No terrain dependency. Paste above the fnc_runTests call in
// .hemtt/missions/test.VR/initServer.sqf (or any VR-style mission), then
// uncomment the fnc_runTests call already present there.
// ============================================================================

// This tier doesn't call fnc_initTestScenario at all — DSC_testConfig is
// only meaningful once fnc_initTestScenario is invoked. For a pure Tier-1
// run you only need suites registered on DSC_testSuites (see
// fnc_initServerDebug for the "harness_selftest" example) and then:
//
//     [] call DSC_core_fnc_runTests;
//
// If a future suite needs a minimal booted world (e.g. to assert against
// DSC_locations), use this config with fnc_initTestScenario first:

DSC_testConfig = createHashMapFromArray [
    ["factionProfile", "vanilla"],
    ["steps", ["globals"]],
    ["missionTemplate", createHashMap],
    ["singleShot", false],
    ["playerSpawn", ""],
    ["timeOfDay", -1],
    ["freezeWeather", false],
    ["extraDebug", true]
];

// [] call DSC_core_fnc_initTestScenario; // optional — only if a suite needs booted globals
[] call DSC_core_fnc_runTests;
