// ============================================================================
// Tier-2 feature harness DSC_testConfig example — universal "Search" hook.
// Boots presence + roving so ambient hostile groups exist near the player;
// kill one and confirm a "Search Body" action appears at the death
// position once every unit in that group is dead, and that it yields a
// (typically low-confidence AREA) intel token on completion — with NO
// extra entities spawned to support it (§10).
//
// Unlike 03_tier2_altis_interaction_site_sse.sqf this does not force a
// specific mission — the interaction site under test comes from
// fnc_c2InitSignalSources's EntityKilled extension (Session 5), which fires
// on ANY wiped hostile group, mission-related or purely ambient. The
// harness still generates one (random) mission because
// fnc_initTestScenario's pipeline always does — ignore it and go fight
// ambient patrols/garrisons near the player base instead.
//
// Intended for a dedicated test mission following the DSC_Test.<Terrain>
// pattern. That mission's initServer.sqf should call fnc_initTestScenario
// INSTEAD OF fnc_initServer:
//
//     [] call DSC_core_fnc_initTestScenario;
//     [] call DSC_core_fnc_initServerDebug; // optional, for tablet/queue globals
// ============================================================================

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

[] call DSC_core_fnc_initTestScenario;
