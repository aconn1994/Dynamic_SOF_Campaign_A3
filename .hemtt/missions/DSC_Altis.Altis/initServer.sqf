// [] call DSC_core_fnc_initServer;
// [] call DSC_core_fnc_initServerDebug;

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