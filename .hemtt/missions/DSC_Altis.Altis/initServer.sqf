[] call DSC_core_fnc_initServer;
[] call DSC_core_fnc_initServerDebug;

// [createHashMapFromArray [["debug", true]]] call DSC_core_fnc_scanLocations;

// Vanilla Altis
// private _factionProfileConfigVanilla = createHashMapFromArray [
//     ["bluFor", createHashMapFromArray [
//         ["side", west],
//         ["factions", ["BLU_F"]] // NATO
//     ]],
//     ["bluForPartner", createHashMapFromArray [
//         ["side", independent],
//         ["factions", ["IND_F", "BLU_GEN_F"]] // AAF, Gendarmerie
//     ]],
//     ["opFor", createHashMapFromArray [
//         ["side", east],
//         ["factions", ["OPF_F", "OPF_R_F"]] // CSAT, Spetsnaz
//     ]],
//     ["opForPartner", createHashMapFromArray [
//         ["side", east],
//         ["factions", ["OPF_G_F", "IND_C_F"]] // FIA, Syndikat
//     ]],
//     ["irregulars", createHashMapFromArray [
//         ["side", independent],
//         ["factions", ["IND_L_F"]] // Looters
//     ]],
//     ["civilians", createHashMapFromArray [
//         ["side", civilian],
//         ["factions", ["CIV_F"]]
//     ]],
//     ["environmentalActors", createHashMapFromArray [
//         ["side", civilian],
//         ["factions", ["CIV_IDAP_F"]] // IDAP
//     ]]
// ];

// // RHS Altis
// private _factionProfileConfigRhs = createHashMapFromArray [
//     ["bluFor", createHashMapFromArray [
//         ["side", west],
//         ["factions", [
//             "rhs_faction_socom",     // USA (SOCOM)
//             "rhs_faction_usarmy_wd", // USA (Army - W)
//             "rhs_faction_usmc_wd",   // USA (USMC - W)
//             "rhs_faction_usaf",      // USA (USAF)
//             "rhs_faction_usn"        // USA (Navy)
//         ]]
//     ]],
//     ["bluForPartner", createHashMapFromArray [
//         ["side", independent],
//         ["factions", [
//             "rhsgref_faction_cdf_ground_b", // CDF (Ground Forces)
//             "rhssaf_faction_army",           // SAF (KOV)
//             "rhssaf_faction_un"              // SAF (UN Peacekeepers)
//         ]]
//     ]],
//     ["opFor", createHashMapFromArray [
//         ["side", east],
//         ["factions", [
//             "rhs_faction_vdv", // Russia (VDV) - Airborne
//             "rhs_faction_vmf", // Russia (VMF) - Marines
//             "rhs_faction_msv", // Russia (MSV) - Motorized
//             "rhs_faction_tv"   // Russia (TV) - Mechanized
//         ]]
//     ]],
//     ["opForPartner", createHashMapFromArray [
//         ["side", east],
//         ["factions", ["rhsgref_faction_nationalist"]] // Nationalist Militia
//     ]],
//     ["irregulars", createHashMapFromArray [
//         ["side", independent],
//         ["factions", ["rhsgref_faction_chdkz"]] // ChDKZ Insurgents
//     ]],
//     ["civilians", createHashMapFromArray [
//         ["side", civilian],
//         ["factions", ["CIV_F"]] // ChDKZ (Civilian)
//     ]],
//     ["environmentalActors", createHashMapFromArray [
//         ["side", civilian],
//         ["factions", ["CIV_IDAP_F"]]
//     ]]
// ];

// // ============================================================================
// // Auto-detect faction profile: check if all RHS factions exist in CfgFactionClasses
// // ============================================================================
// private _rhsFactions = [];
// {
//     private _roleFactions = (_y getOrDefault ["factions", []]);
//     { _rhsFactions pushBackUnique _x } forEach _roleFactions;
// } forEach _factionProfileConfigRhs;

// private _allRhsPresent = true;
// {
//     if !(isClass (configFile >> "CfgFactionClasses" >> _x)) then {
//         diag_log format ["DSC: RHS faction '%1' not found - falling back to vanilla", _x];
//         _allRhsPresent = false;
//     };
// } forEach _rhsFactions;

// private _selectedProfile = if (_allRhsPresent) then {
//     diag_log "DSC: All RHS factions detected - using RHS faction profile";
//     _factionProfileConfigRhs
// } else {
//     diag_log "DSC: Using vanilla faction profile";
//     _factionProfileConfigVanilla
// };

// private _getTimeAsString = {
//     private _daytime = dayTime;
//     private _hours = floor _daytime;
//     private _minutes = floor ((_daytime - _hours) * 60);
//     private _seconds = floor ((((_daytime - _hours) * 60) - _minutes) * 60);

//     format ["%1:%2:%3", _hours, _minutes, _seconds];
// };

// // ============================================================================
// // STEP 0: Init Server Globals
// // ============================================================================
// missionNamespace setVariable ["initGlobalsComplete", false, true];

// missionNamespace setVariable ["playerMainBase", "player_base_1", true];
// missionNamespace setVariable ["factionProfileConfig", _selectedProfile, true];
// missionNamespace setVariable ["missionState", "IDLE", true];
// missionNamespace setVariable ["missionInProgress", false, true];
// missionNamespace setVariable ["missionComplete", false, true];

// missionNamespace setVariable ["initGlobalsComplete", true, true];

// // ============================================================================
// // STEP 1: Scan World - One pass, all locations with structures + tags
// // ============================================================================
// diag_log "=============== DSC: Initializing Location Data =================";
// systemChat format ["DSC - %1 - Initializing location data...", call _getTimeAsString];

// private _locations = [] call DSC_core_fnc_scanLocations;
// missionNamespace setVariable ["DSC_locations", _locations, true];

// diag_log format ["DSC: World scan complete - %1 locations indexed", count _locations];

// systemChat format ["DSC - %1 - Location data has been initialized.", call _getTimeAsString];
// // ============================================================================
// // STEP 2: Faction Data - Extract groups + assets for all factions in profile
// // ============================================================================
// diag_log "=============== DSC: Initializing Faction Data =================";
// systemChat "Initializing faction data...";

// private _factionProfileConfig = missionNamespace getVariable ["factionProfileConfig", _factionProfileConfigVanilla];
// private _factionData = [_factionProfileConfig] call DSC_core_fnc_initFactionData;
// missionNamespace setVariable ["DSC_factionData", _factionData, true];

// systemChat "Faction Data has been initialized!";
// // ============================================================================
// // STEP 3: Init Faction Influence over Map
// // ============================================================================
// diag_log "DSC: ========== Determining Map Influence ==========";
// systemChat "Initializing influence map...";

// // Campaign profiles: "offensive" (opFor dominant), "defensive" (bluFor dominant), "contested" (mixed)
// private _influenceData = [_locations, "contested", _factionData] call DSC_core_fnc_initInfluence;
// missionNamespace setVariable ["DSC_influenceData", _influenceData, true];

// systemChat "Influence map initialized!";

// // Debug: Influence markers
// // private _influenceMap = _influenceData get "influenceMap";
// // private _enrichedLocations = _influenceData get "locations";

// // {
// //     private _loc = _x;
// //     private _locId = _loc get "id";
// //     private _locPos = _loc get "position";
// //     private _locName = _loc get "name";
// //     private _locRadius = _loc get "radius";
// //     private _locInf = _influenceMap getOrDefault [_locId, createHashMap];

// //     if (_locInf isEqualTo createHashMap) then { continue };

// //     private _controlledBy = _locInf get "controlledBy";
// //     private _influence = _locInf get "influence";
// //     private _infType = _locInf get "type";
// //     private _faction = _locInf getOrDefault ["faction", ""];

// //     private _color = switch (_controlledBy) do {
// //         case "opFor":     { "ColorRed" };
// //         case "bluFor":    { "ColorBlue" };
// //         case "contested": { "ColorYellow" };
// //         default           { "ColorWhite" };
// //     };

// //     // Area marker — size and opacity scale with influence type and strength
// //     private _areaRadius = switch (_infType) do {
// //         case "base":          { (_locRadius max 200) + 300 };
// //         case "outpost":       { (_locRadius max 150) + 200 };
// //         case "camp":          { (_locRadius max 75) + 100 };
// //         case "populatedArea": { (_locRadius max 150) + 200 };
// //         default               { (_locRadius max 50) + 100 };
// //     };

// //     private _areaName = format ["dsc_inf_area_%1", _locId];
// //     private _areaMarker = createMarkerLocal [_areaName, _locPos];
// //     _areaMarker setMarkerShapeLocal "ELLIPSE";
// //     _areaMarker setMarkerSizeLocal [_areaRadius, _areaRadius];
// //     _areaMarker setMarkerColorLocal _color;
// //     _areaMarker setMarkerAlphaLocal (0.1 + (_influence * 0.25));

// //     // Point marker — icon distinguishes type
// //     private _markerIcon = switch (_infType) do {
// //         case "base":          { "hd_flag" };
// //         case "outpost":       { "mil_triangle" };
// //         case "camp":          { "mil_dot" };
// //         case "populatedArea": { "loc_Fortress" };
// //         default               { "mil_dot" };
// //     };

// //     private _factionLabel = ["", format [" (%1)", _faction]] select (_faction != "");
// //     private _markerName = format ["dsc_inf_point_%1", _locId];
// //     private _pointMarker = createMarkerLocal [_markerName, _locPos];
// //     _pointMarker setMarkerTypeLocal _markerIcon;
// //     _pointMarker setMarkerColorLocal _color;
// //     _pointMarker setMarkerTextLocal format ["%1 [%2 %3]%4", _locName, _controlledBy, _influence toFixed 1, _factionLabel];

// // } forEach _enrichedLocations;

// // diag_log "DSC: Influence debug markers created";

// diag_log "DSC: ========== Marking Military Installations ==========";

// private _influenceMap = _influenceData get "influenceMap";
// private _enrichedLocations = _influenceData get "locations";
// private _bases = _influenceData get "bases";
// private _outposts = _influenceData get "outposts";

// private _sideColor = createHashMapFromArray [
//     ["opFor", [0.8, 0, 0, 1]],
//     ["bluFor", [0, 0.3, 0.6, 1]],
//     ["contested", [0.85, 0.85, 0, 1]],
//     ["neutral", [0.7, 0.7, 0.7, 1]]
// ];

// private _sideMarkerColor = createHashMapFromArray [
//     ["opFor", "ColorEAST"],
//     ["bluFor", "ColorWEST"],
//     ["contested", "ColorYellow"],
//     ["neutral", "ColorWhite"]
// ];

// // Default flag textures per side (fallback when faction has no flag)
// private _sideFlagDefaults = createHashMapFromArray [
//     ["opFor", "\A3\Data_F\Flags\flag_CSAT_CO.paa"],
//     ["bluFor", "\A3\Data_F\Flags\flag_NATO_CO.paa"],
//     ["contested", "\A3\ui_f\data\map\markers\military\warning_CA.paa"],
//     ["neutral", "\A3\ui_f\data\map\markers\military\unknown_CA.paa"]
// ];

// // Build base marker data: [position, name, flagTexture, color] for client-side rendering
// private _baseMarkerData = [];

// {
//     private _loc = _x;
//     private _locId = _loc get "id";
//     private _locPos = _loc get "position";
//     private _locName = _loc get "name";
//     private _locInf = _influenceMap getOrDefault [_locId, createHashMap];
//     if (_locInf isEqualTo createHashMap) then { continue };

//     private _controlledBy = _locInf get "controlledBy";
//     private _faction = _locInf getOrDefault ["faction", ""];
//     private _color = _sideColor getOrDefault [_controlledBy, [0.7, 0.7, 0.7, 1]];
//     private _markerColor = _sideMarkerColor getOrDefault [_controlledBy, "ColorWhite"];

//     // Get faction flag texture from CfgFactionClasses
//     private _flagTexture = _sideFlagDefaults getOrDefault [_controlledBy, ""];
//     if (_faction != "") then {
//         private _factionFlag = getText (configFile >> "CfgFactionClasses" >> _faction >> "flag");
//         if (_factionFlag != "") then {
//             _flagTexture = _factionFlag;
//         };
//     };

//     _baseMarkerData pushBack [_locPos, _locName, _flagTexture, _color];

//     // Danger zone area marker (global, all players)
//     private _zoneName = format ["dsc_base_zone_%1", _locId];
//     private _zoneMarker = createMarker [_zoneName, _locPos];
//     _zoneMarker setMarkerShapeLocal "ELLIPSE";
//     _zoneMarker setMarkerSizeLocal [800, 800];
//     _zoneMarker setMarkerColorLocal _markerColor;
//     _zoneMarker setMarkerAlphaLocal 0.15;
//     _zoneMarker setMarkerBrush "SolidBorder";

//     diag_log format ["DSC: Marked base '%1' - %2 / %3 (flag: %4)", _locName, _controlledBy, _faction, _flagTexture];
// } forEach _bases;

// // Build outpost marker data for client-side rendering
// private _outpostMarkerData = [];

// {
//     private _loc = _x;
//     private _locId = _loc get "id";
//     private _locPos = _loc get "position";
//     private _locName = _loc get "name";
//     private _locInf = _influenceMap getOrDefault [_locId, createHashMap];
//     if (_locInf isEqualTo createHashMap) then { continue };

//     private _controlledBy = _locInf get "controlledBy";
//     private _faction = _locInf getOrDefault ["faction", ""];
//     private _color = _sideColor getOrDefault [_controlledBy, [0.7, 0.7, 0.7, 1]];

//     private _flagTexture = _sideFlagDefaults getOrDefault [_controlledBy, ""];
//     if (_faction != "") then {
//         private _factionFlag = getText (configFile >> "CfgFactionClasses" >> _faction >> "flag");
//         if (_factionFlag != "") then {
//             _flagTexture = _factionFlag;
//         };
//     };

//     _outpostMarkerData pushBack [_locPos, _locName, _flagTexture, _color];

//     diag_log format ["DSC: Marked outpost '%1' - %2 / %3", _locName, _controlledBy, _faction];
// } forEach _outposts;

// // Publish marker data for client-side map rendering
// missionNamespace setVariable ["DSC_baseMarkerData", _baseMarkerData, true];
// missionNamespace setVariable ["DSC_outpostMarkerData", _outpostMarkerData, true];

// diag_log format ["DSC: Published %1 bases and %2 outposts for map rendering", count _baseMarkerData, count _outpostMarkerData];

// // ============================================================================
// // STEP 5: Presence Manager Loop
// // ============================================================================
// diag_log "DSC: ========== Initializing Presence Manager ==========";
// [_influenceData] call DSC_core_fnc_initPresenceManager;