// ============================================================================
// Tier-2 feature harness DSC_testConfig example — forced KILL_CAPTURE at a
// fixed location, single-shot (immediate debrief, no player action needed
// to end the run), player spawned ~150m from the objective.
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
// console (`{ hint (_x get "id") } forEach (DSC_locations select { (_x get "buildingCount") > 5 })`)
// or grep the RPT's scanLocations LOG lines.
// ============================================================================

DSC_testConfig = createHashMapFromArray [
    ["factionProfile", "vanilla"],
    ["steps", ["globals", "locations", "factions", "influence"]],
    ["missionTemplate", createHashMapFromArray [
        ["type", "KILL_CAPTURE"],
        ["missionProfile", "AFO_rural"],
        ["location", "loc_replace_with_real_id"]
        // OR, instead of a fixed id, constrain a region:
        // ["regionCenter", [10000, 10000, 0]],
        // ["regionRadius", 3000]
    ]],
    ["singleShot", true],
    ["playerSpawn", "nearSite"],
    ["timeOfDay", 6],
    ["freezeWeather", true],
    ["extraDebug", true]
];

[] call DSC_core_fnc_initTestScenario;
