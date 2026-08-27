// ============================================================================
// Tier-2 feature harness DSC_testConfig example — a single INTERACTION_SITE
// mission (SSE_INTEL archetype) at a fixed location, left ACTIVE for a human
// to walk up and trigger the "Conduct SSE" action live (singleShot: false —
// see fnc_initTestScenario's header for that flag's documented behavior).
//
// Cross-checked against fnc_resolveMissionConfig's actual accepted shape
// (Session 5 open decision #3): "completion" and "interactionSites" live
// INSIDE "raidConfig", not at the missionTemplate top level — raidConfig is
// an opaque pass-through field that fnc_generateMission's "RAID" case reads
// directly and forwards to fnc_generateRaidMission unchanged.
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
    ["steps", ["globals", "locations", "factions", "influence"]],
    ["missionTemplate", createHashMapFromArray [
        ["type", "RAID"],
        ["location", "loc_replace_with_real_id"],
        ["raidConfig", createHashMapFromArray [
            ["completion", "SITES_INTERACTED"],
            ["interactionSites", [
                createHashMapFromArray [["archetype", "SSE_INTEL"]]
            ]]
        ]]
    ]],
    ["singleShot", false],
    ["playerSpawn", "nearSite"],
    ["timeOfDay", 6],
    ["freezeWeather", true],
    ["extraDebug", true]
];

[] call DSC_core_fnc_initTestScenario;

// THIS TEST RAN SUCCESSFULLY