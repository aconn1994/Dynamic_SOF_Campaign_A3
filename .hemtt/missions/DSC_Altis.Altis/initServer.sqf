// [] call DSC_core_fnc_initServer;
// [] call DSC_core_fnc_initServerDebug;

DSC_testConfig = createHashMapFromArray [
    ["factionProfile", "vanilla"],
    ["steps", ["globals", "locations", "factions", "influence", "c2", "presence", "roving"]],
    ["missionTemplate", createHashMap],
    ["singleShot", false],
    ["playerSpawn", ""],
    ["timeOfDay", 10],
    ["freezeWeather", true],
    ["extraDebug", true]
];

// PlayTest Notes
// - "Search Bodies" to "Search Body"
// - Make activation radius smaller
// - Roving should not cleanup bodies immediately - Maybe defer

// ---- Tier-1 headless test harness (see .crush/agentic-workflow-and-testing.md Part B, docs/test_harness/) ----
// fnc_initServerDebug already registers the "harness_selftest" suite. Register
// any additional DSC_testSuites entries above this line, then uncomment the
// call below and launch with `mission = "test.VR"` active in .hemtt/launch.toml
// to see PASS/FAIL/summary lines in the RPT.

[] call DSC_core_fnc_initTestScenario; // optional — only if a suite needs booted globals
// [] call DSC_core_fnc_runTests;