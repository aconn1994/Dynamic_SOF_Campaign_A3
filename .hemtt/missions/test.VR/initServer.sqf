// [] call DSC_core_fnc_initServer;
[] call DSC_core_fnc_initServerDebug;

// DSC_testConfig = createHashMapFromArray [
//     ["factionProfile", "vanilla"],
//     ["steps", ["globals", "locations", "factions", "influence"]],
//     ["missionTemplate", createHashMapFromArray [
//         ["type", "KILL_CAPTURE"],
//         ["missionProfile", "AFO_rural"],
//         ["location", "loc_replace_with_real_id"]
//         // OR, instead of a fixed id, constrain a region:
//         // ["regionCenter", [10000, 10000, 0]],
//         // ["regionRadius", 3000]
//     ]],
//     ["singleShot", true],
//     ["playerSpawn", "nearSite"],
//     ["timeOfDay", 6],
//     ["freezeWeather", true],
//     ["extraDebug", true]
// ];

// ---- Tier-1 headless test harness (see .crush/agentic-workflow-and-testing.md Part B, docs/test_harness/) ----
// fnc_initServerDebug already registers the "harness_selftest" suite. Register
// any additional DSC_testSuites entries above this line, then uncomment the
// call below and launch with `mission = "test.VR"` active in .hemtt/launch.toml
// to see PASS/FAIL/summary lines in the RPT.

// [] call DSC_core_fnc_initTestScenario; // optional — only if a suite needs booted globals
[] call DSC_core_fnc_runTests;