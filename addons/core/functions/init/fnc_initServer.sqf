// DSC - Dynamic SOF Campaign

missionNamespace setVariable ["initGlobalsComplete", false, true];
// ============================================================================
// STEP 0: Init Server Globals
// ============================================================================
// Faction Vars
missionNamespace setVariable ["playerFaction", "BLU_F", true];
missionNamespace setVariable ["opForFaction", "OPF_F", true];

// Mission Vars
missionNamespace setVariable ["missionState", "IDLE", true]; // IDLE -> ACTIVE -> DEBRIEF -> CLEANUP -> IDLE
missionNamespace setVariable ["missionInProgress", false, true];
missionNamespace setVariable ["missionComplete", false, true];
private _missionCleanupInProgress = false;

missionNamespace setVariable ["initGlobalsComplete", true, true];

// ============================================================================
// STEP 1: Scan Map for Military Locations and setup main enemy location
// ============================================================================
private _militaryLocations = [] call DSC_core_fnc_getMilitaryLocations; // Will expand, using map locations for now

private _milBases = _militaryLocations get "bases";
private _milOutposts = _militaryLocations get "outposts";
private _milCamps = _militaryLocations get "camps";

// DEBUGGING: Map out all locations and unit positions
// [(_milBases + _milOutposts + _milCamps)] call DSC_core_fnc_mapPositionsOnMilLocations;

// Get faction flag marker type based on side
private _opForFaction = missionNamespace getVariable ["opForFaction", "OPF_F"];
private _factionCfg = configFile >> "CfgFactionClasses" >> _opForFaction;
private _factionSide = getNumber (_factionCfg >> "side");

// ******  TODO  ******, main enemy airbase location setup will happen here.........
// ******  TODO  ******, main insurgent base location setup will happen here.........

// ============================================================================
// STEP 2: Get Faction group data using new classification system
// ============================================================================
diag_log "=============== DSC: Initializing Faction Data =================";
// Extract and classify groups for OpFor
private _opForGroups = [opForFaction] call DSC_core_fnc_extractGroups;
private _classifiedGroups = [_opForGroups] call DSC_core_fnc_classifyGroups;

diag_log format ["DSC: Classified %1 groups for faction %2", count _classifiedGroups, opForFaction];

// Fallback check - if no groups found, try CSAT (same for now, but useful when testing other mods)
if (count _classifiedGroups == 0) then {
    diag_log "DSC: No groups found, falling back to OPF_F";
    opForFaction = "OPF_F";
    _opForGroups = [opForFaction] call DSC_core_fnc_extractGroups;
    _classifiedGroups = [_opForGroups] call DSC_core_fnc_classifyGroups;
};

// Store classified groups globally for debugging
missionNamespace setVariable ["DSC_classifiedGroups", _classifiedGroups, true];

// ----------- Groups (Getting them all in memory for now) ------------
// Basic Foot
private _basicInfantrySquadGroups = [_classifiedGroups, ["FOOT", "INFANTRY_SQUAD", "PATROL"], ["ELITE", "SCOUT_RECON", "AMPHIBIOUS"]] call DSC_core_fnc_getGroupsByTag;
private _basicInfantryFireteamGroups = [_classifiedGroups, ["FOOT", "FIRETEAM", "PATROL"], ["ELITE", "SCOUT_RECON", "AMPHIBIOUS"]] call DSC_core_fnc_getGroupsByTag;
private _basicRecceSquadGroups = [_classifiedGroups, ["FOOT", "INFANTRY_SQUAD", "SCOUT_RECON", "PATROL"], ["ELITE", "AMPHIBIOUS"]] call DSC_core_fnc_getGroupsByTag;
private _basicRecceFireteamGroups = [_classifiedGroups, ["FOOT", "FIRETEAM", "SCOUT_RECON", "PATROL"], ["ELITE", "AMPHIBIOUS"]] call DSC_core_fnc_getGroupsByTag;

// Elite Foot
private _eliteInfantrySquadGroups = [_classifiedGroups, ["FOOT", "INFANTRY_SQUAD", "PATROL", "ELITE"], ["SCOUT_RECON", "AMPHIBIOUS"]] call DSC_core_fnc_getGroupsByTag;
private _eliteInfantryFireteamGroups = [_classifiedGroups, ["FOOT", "FIRETEAM", "PATROL", "ELITE"], ["SCOUT_RECON", "AMPHIBIOUS"]] call DSC_core_fnc_getGroupsByTag;
private _eliteRecceSquadGroups = [_classifiedGroups, ["FOOT", "INFANTRY_SQUAD", "SCOUT_RECON", "PATROL", "ELITE"], ["AMPHIBIOUS"]] call DSC_core_fnc_getGroupsByTag;
private _eliteRecceFireteamGroups = [_classifiedGroups, ["FOOT", "FIRETEAM", "SCOUT_RECON", "PATROL", "ELITE"], ["AMPHIBIOUS"]] call DSC_core_fnc_getGroupsByTag;

// Special Foot
private _atInfantryGroups = [_classifiedGroups, ["Foot", "AT_TEAM"], ["AMPHIBIOUS"]] call DSC_core_fnc_getGroupsByTag;
private _aaInfantryGroups = [_classifiedGroups, ["Foot", "AA_TEAM"], ["AMPHIBIOUS"]] call DSC_core_fnc_getGroupsByTag;

// ============================================================================
// STEP 3: Setup While loop for continuous mission generation
// ============================================================================
while { true } do {
    diag_log "DSC: Generating group for mission...";

    // Determine Target Location
    private _randomMilLoc = selectRandom (_milCamps + _milOutposts + _milBases);
    private _radiusOuter = 400;

    private _targetMarker = createMarker ["target_location_marker", _randomMilLoc];
    _targetMarker setMarkerTypeLocal "o_installation";
    _targetMarker setMarkerColorLocal "ColorRed";
    _targetMarker setMarkerTextLocal "Target Location";

    // Setup Group/Units
    private _missionGroups = [];
    private _tagsPerGroup = [];
    private _totalUnits = [];
    private _totalVehicles = [];

    // ==================================
    // Guards (Static Weapons on Towers)
    // ==================================
    private _guardResult = [_randomMilLoc, "military", _opForFaction, east] call DSC_core_fnc_setupGuards;
    _missionGroups append (_guardResult get "groups");
    _totalUnits append (_guardResult get "units");
    _totalVehicles append (_guardResult get "vehicles");

    // ==================================
    // Garrison (Infantry in Structures)
    // ==================================
    private _garrisonGroups = _basicInfantrySquadGroups + _basicInfantryFireteamGroups + _eliteInfantrySquadGroups + _eliteInfantryFireteamGroups;
    private _garrisonResult = [_randomMilLoc, _garrisonGroups, east] call DSC_core_fnc_setupGarrison;
    _missionGroups append (_garrisonResult get "groups");
    _totalUnits append (_garrisonResult get "units");
    _tagsPerGroup append (_garrisonResult get "tags");

    // ==================================
    // Patrols (Mobile Units)
    // ==================================
    private _patrolGroups = _garrisonGroups; // Reuse infantry groups for patrols
    private _specialGroups = _atInfantryGroups + _aaInfantryGroups;
    private _patrolConfig = createHashMapFromArray [
        ["specialGroups", _specialGroups],
        ["specialChance", 0.15]
    ];
    private _patrolResult = [_randomMilLoc, _patrolGroups, east, _patrolConfig] call DSC_core_fnc_setupPatrols;
    _missionGroups append (_patrolResult get "groups");
    _totalUnits append (_patrolResult get "units");
    _tagsPerGroup append (_patrolResult get "tags");

    // ============================================================================
    // STEP 4: Mission has begun after group has been created
    // ============================================================================
    diag_log format ["DSC: Spawned %1 group at %2", count _missionGroups, _randomMilLoc];

    // Re-enable damage for all spawned units
    {
        _x allowDamage true;
    } forEach _totalUnits;

    // Add units/vehicles to zeus
    _curator = ((allCurators) select 0); // The curator object

    // Add all existing units to be editable by this curator
    {
        _curator addCuratorEditableObjects [[_x], true];
    } forEach allUnits;

    missionNamespace setVariable ["missionInProgress", true, true];
    missionNamespace setVariable ["missionState", "ACTIVE", true];
    
    // Store current mission data
    missionNamespace setVariable ["enemyMissionGroups", _missionGroups, true];
    missionNamespace setVariable ["missionGroupsTags", _tagsPerGroup, true];

    waitUntil { !(missionNamespace getVariable ["missionInProgress", true]) };
    
    // ============================================================================
    // STEP 5: Mission Debrief and success evaluation triggered by player RTB
    // ============================================================================
    missionNamespace setVariable ["missionState", "DEBRIEF", true];

    if (missionNamespace getVariable ["missionComplete", false]) then { // NEEDS FIXING, RUN HEMTT CHECK
        hint "Mission was successful";
        systemChat "DSC: Mission SUCCESS";
    } else {
        hint "Mission was unsuccessful";
        systemChat "DSC: Mission FAILED";
    };

    // ============================================================================
    // STEP 6: Mission is marked as finished and cleanup begins
    // ============================================================================
    missionNamespace setVariable ["missionState", "CLEANUP", true];
    _missionCleanupInProgress = true;

    diag_log "DSC: Cleanup begins...";
    
    // Delete all tracked units including dead bodies
    {
        deleteVehicle _x;
        sleep 0.1;
    } forEach _totalUnits;

    // Delete all tracked vehicles (works even if destroyed)
    {
        deleteVehicle _x;
        sleep 0.1;
    } forEach _totalVehicles;

    // Delete group after units and vehicles
    {
        deleteGroup _x;
    } forEach _missionGroups;

    _missionCleanupInProgress = false;
    waitUntil { !_missionCleanupInProgress };
    sleep 1;
    missionNamespace setVariable ["missionState", "IDLE", true];

    // Remove Target Markers
    deleteMarker "target_location_marker";
    deleteMarker "target_location_area_marker";
    _targetMarker = nil;
    _targetAreaMarker = nil;
    
    // ================================================================================
    // STEP 7: Once cleanup is done the next mission generation begins, back to Step 2
    // ================================================================================
    sleep 1;
};
