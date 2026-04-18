// DSC - Dynamic SOF Campaign Main Server Functionality

/*
 * Function: DSC_core_fnc_initServer
 * Description:
 *
 * Arguments:
 *     factionProfileConfig: TBD
 *
 * Return Value:
 *     Null
 *
 * Example:
 *     [] call DSC_core_fnc_initServer;
 */


// Faction Profile Configuration - Default matches BI faction setup or mod equivalent
// Eventually I want to autoscan for factions, and allow the player to decide what they want the it to look like

// Vanilla Altis
private _factionProfileConfigVanilla = createHashMapFromArray [
    ["bluFor", createHashMapFromArray [
        ["side", west],
        ["factions", ["BLU_F"]] // NATO
    ]],
    ["bluForPartner", createHashMapFromArray [
        ["side", independent],
        ["factions", ["IND_F", "BLU_GEN_F"]] // AAF, Gendarmerie
    ]],
    ["opFor", createHashMapFromArray [
        ["side", east],
        ["factions", ["OPF_F", "OPF_R_F"]] // CSAT, Spetsnaz
    ]],
    ["opForPartner", createHashMapFromArray [
        ["side", east],
        ["factions", ["OPF_G_F", "IND_C_F"]] // FIA, Syndikat
    ]],
    ["irregulars", createHashMapFromArray [
        ["side", independent],
        ["factions", ["IND_L_F"]] // Looters
    ]],
    ["civilians", createHashMapFromArray [
        ["side", civilian],
        ["factions", ["CIV_F"]]
    ]],
    ["environmentalActors", createHashMapFromArray [
        ["side", civilian],
        ["factions", ["CIV_IDAP_F"]] // IDAP
    ]]
];

// RHS Altis
private _factionProfileConfigRhs = createHashMapFromArray [
    ["bluFor", createHashMapFromArray [
        ["side", west],
        ["factions", [
            "rhs_faction_socom",     // USA (SOCOM)
            "rhs_faction_usarmy_wd", // USA (Army - W)
            "rhs_faction_usmc_wd"    // USA (USMC - W)
        ]]
    ]],
    ["bluForPartner", createHashMapFromArray [
        ["side", independent],
        ["factions", [
            "rhsgref_faction_cdf_ground_b", // CDF (Ground Forces)
            "rhssaf_faction_army",           // SAF (KOV)
            "rhssaf_faction_un"              // SAF (UN Peacekeepers)
        ]]
    ]],
    ["opFor", createHashMapFromArray [
        ["side", east],
        ["factions", [
            "rhs_faction_vdv", // Russia (VDV) - Airborne
            "rhs_faction_vmf", // Russia (VMF) - Marines
            "rhs_faction_msv", // Russia (MSV) - Motorized
            "rhs_faction_tv"   // Russia (TV) - Mechanized
        ]]
    ]],
    ["opForPartner", createHashMapFromArray [
        ["side", east],
        ["factions", ["rhsgref_faction_nationalist"]] // Nationalist Militia
    ]],
    ["irregulars", createHashMapFromArray [
        ["side", independent],
        ["factions", ["rhsgref_faction_chdkz"]] // ChDKZ Insurgents
    ]],
    ["civilians", createHashMapFromArray [
        ["side", civilian],
        ["factions", ["rhsgref_faction_chdkz_g"]] // ChDKZ (Civilian)
    ]],
    ["environmentalActors", createHashMapFromArray [
        ["side", civilian],
        ["factions", ["CIV_IDAP_F"]]
    ]]
];

private _getTimeAsString = {
    private _daytime = dayTime;
    private _hours = floor _daytime;
    private _minutes = floor ((_daytime - _hours) * 60);
    private _seconds = floor ((((_daytime - _hours) * 60) - _minutes) * 60);

    format ["%1:%2:%3", _hours, _minutes, _seconds];
};

// ============================================================================
// STEP 0: Init Server Globals
// ============================================================================
missionNamespace setVariable ["initGlobalsComplete", false, true];

missionNamespace setVariable ["playerMainBase", "player_base_0", true];
missionNamespace setVariable ["factionProfileConfig", _factionProfileConfigVanilla, true];
missionNamespace setVariable ["missionState", "IDLE", true];
missionNamespace setVariable ["missionInProgress", false, true];
missionNamespace setVariable ["missionComplete", false, true];

missionNamespace setVariable ["initGlobalsComplete", true, true];

// ============================================================================
// STEP 1: Scan World - One pass, all locations with structures + tags
// ============================================================================
diag_log "=============== DSC: Initializing Location Data =================";
systemChat format ["DSC - %1 - Initializing location data...", call _getTimeAsString];

private _locations = [] call DSC_core_fnc_scanLocations;
missionNamespace setVariable ["DSC_locations", _locations, true];

diag_log format ["DSC: World scan complete - %1 locations indexed", count _locations];

systemChat format ["DSC - %1 - Location data has been initialized.", call _getTimeAsString];
// ============================================================================
// STEP 2: Faction Data - Extract groups + assets for all factions in profile
// ============================================================================
diag_log "=============== DSC: Initializing Faction Data =================";
systemChat "Initializing faction data...";

private _factionProfileConfig = missionNamespace getVariable ["factionProfileConfig", _factionProfileConfigVanilla];
private _factionData = [_factionProfileConfig] call DSC_core_fnc_initFactionData;
missionNamespace setVariable ["DSC_factionData", _factionData, true];

systemChat "Faction Data has been initialized!";
// ============================================================================
// STEP 3: Init Faction Influence over Map
// ============================================================================
diag_log "DSC: ========== Determining Map Influence ==========";
systemChat "Initializing influence map...";

// Campaign profiles: "offensive" (opFor dominant), "defensive" (bluFor dominant), "contested" (mixed)
private _influenceData = [_locations, "offensive", _factionData] call DSC_core_fnc_initInfluence;
missionNamespace setVariable ["DSC_influenceData", _influenceData, true];

systemChat "Influence map initialized!";

// Debug: Influence markers
private _influenceMap = _influenceData get "influenceMap";
private _enrichedLocations = _influenceData get "locations";

{
    private _loc = _x;
    private _locId = _loc get "id";
    private _locPos = _loc get "position";
    private _locName = _loc get "name";
    private _locRadius = _loc get "radius";
    private _locInf = _influenceMap getOrDefault [_locId, createHashMap];

    if (_locInf isEqualTo createHashMap) then { continue };

    private _controlledBy = _locInf get "controlledBy";
    private _influence = _locInf get "influence";
    private _infType = _locInf get "type";
    private _faction = _locInf getOrDefault ["faction", ""];

    private _color = switch (_controlledBy) do {
        case "opFor":     { "ColorRed" };
        case "bluFor":    { "ColorBlue" };
        case "contested": { "ColorYellow" };
        default           { "ColorWhite" };
    };

    // Area marker — size and opacity scale with influence type and strength
    private _areaRadius = switch (_infType) do {
        case "base":          { (_locRadius max 200) + 300 };
        case "outpost":       { (_locRadius max 150) + 200 };
        case "camp":          { (_locRadius max 75) + 100 };
        case "populatedArea": { (_locRadius max 150) + 200 };
        default               { (_locRadius max 50) + 100 };
    };

    private _areaName = format ["dsc_inf_area_%1", _locId];
    private _areaMarker = createMarkerLocal [_areaName, _locPos];
    _areaMarker setMarkerShapeLocal "ELLIPSE";
    _areaMarker setMarkerSizeLocal [_areaRadius, _areaRadius];
    _areaMarker setMarkerColorLocal _color;
    _areaMarker setMarkerAlphaLocal (0.1 + (_influence * 0.25));

    // Point marker — icon distinguishes type
    private _markerIcon = switch (_infType) do {
        case "base":          { "hd_flag" };
        case "outpost":       { "mil_triangle" };
        case "camp":          { "mil_dot" };
        case "populatedArea": { "loc_Fortress" };
        default               { "mil_dot" };
    };

    private _factionLabel = ["", format [" (%1)", _faction]] select (_faction != "");
    private _markerName = format ["dsc_inf_point_%1", _locId];
    private _pointMarker = createMarkerLocal [_markerName, _locPos];
    _pointMarker setMarkerTypeLocal _markerIcon;
    _pointMarker setMarkerColorLocal _color;
    _pointMarker setMarkerTextLocal format ["%1 [%2 %3]%4", _locName, _controlledBy, _influence toFixed 1, _factionLabel];

} forEach _enrichedLocations;

diag_log "DSC: Influence debug markers created";

// ============================================================================
// STEP 4: Assign Factions to Military Installations
// ============================================================================

// ============================================================================
// STEP 4: Mission Generation Loop
// ============================================================================
// while { true } do {
//     diag_log "DSC: ========== Starting Mission Generation ==========";
//     // I think this will stay very identical
// };
