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
private _blackListedLocations = []; // Used for missions

// DEBUGGING: Map out all locations and unit positions
// [(_milBases + _milOutposts + _milCamps)] call DSC_core_fnc_mapPositionsOnMilLocations;

// Pick inital Enemy Base
private _mainEnemyBase = selectRandom _milBases;

// Get faction flag marker type based on side
private _opForFaction = missionNamespace getVariable ["opForFaction", "OPF_F"];
private _factionCfg = configFile >> "CfgFactionClasses" >> _opForFaction;
private _factionSide = getNumber (_factionCfg >> "side");

// Side: 0=OPFOR, 1=BLUFOR, 2=Independent, 3=Civilian
private _flagMarkerType = switch (_factionSide) do {
    case 0: { "flag_CSAT" };
    case 1: { "flag_NATO" };
    case 2: { "flag_AAF" };
    default { "flag_CSAT" };
};

private _mainEnemyBaseMarker = createMarker ["enemy_base_location", _mainEnemyBase];
_mainEnemyBaseMarker setMarkerTypeLocal _flagMarkerType;
_mainEnemyBaseMarker setMarkerTextLocal "Enemy Base";

// Create denied area marker over enemy base
private _deniedAreaMarker = createMarker ["Enemy Base Denied Area", _mainEnemyBase];
_deniedAreaMarker setMarkerShapeLocal "ELLIPSE";
_deniedAreaMarker setMarkerSizeLocal [800, 800];
_deniedAreaMarker setMarkerColorLocal "ColorRed";
_deniedAreaMarker setMarkerAlphaLocal 0.3;

// ******  TODO  ******, main base unit setup will happen here eventually.........

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

// ============================================================================
// STEP 3: Setup While loop for continuous mission generation
// ============================================================================
while { true } do {
    diag_log "DSC: Generating group for mission...";

    // Determine Target Location
    private _randomMilLoc = selectRandom (_milCamps + _milOutposts);
    private _radiusOuter = 400;

    private _targetMarker = createMarker ["target_location_marker", _randomMilLoc];
    _targetMarker setMarkerTypeLocal "o_installation";
    _targetMarker setMarkerColorLocal "ColorRed";
    _targetMarker setMarkerTextLocal "Target Location";

    private _targetAreaMarker = createMarker ["target_location_area_marker", _randomMilLoc];
    _targetAreaMarker setMarkerShapeLocal "ELLIPSE";
    _targetAreaMarker setMarkerSizeLocal [400, 400];
    _targetAreaMarker setMarkerColorLocal "ColorRed";
    _targetAreaMarker setMarkerAlphaLocal 0.3;

    // Get Static Unit Positions
    private _allStaticUnitPositions = [_randomMilLoc] call DSC_core_fnc_getStaticUnitPositions;
    private _targetStructures = _allStaticUnitPositions get "locationStructures";
    private _targetGuardPosts = _allStaticUnitPositions get "guardPosts";

    // Setup Group/Units
    private _noOfGroups = selectRandom [2, 3, 4, 5];
    private _missionGroups = [];
    private _tagsPerGroup = [];
    private _totalUnits = [];
    private _totalVehicles = [];

    // Static Units (Garrison)
    for "_i" from 1 to _noOfGroups do {
        private _selectedGroup = selectRandom (_basicInfantrySquadGroups + _basicInfantryFireteamGroups + _eliteInfantrySquadGroups + _eliteInfantryFireteamGroups); // Using random infantry for now
        private _groupPath = _selectedGroup get "path";
        private _groupName = _selectedGroup get "groupName";
        private _doctrineTags = _selectedGroup get "doctrineTags";

        diag_log format ["DSC: Selected group %1: %2", _i, _groupName];
        diag_log format ["DSC: Doctrine tags: %1", _doctrineTags];

        private _groupSpawnPos = [_randomMilLoc, 0, _radiusOuter, 5, 0, 20, 0] call BIS_fnc_findSafePos; // Spawn in safe space, then move units to static spots

        // Parse the group path and traverse config
        private _pathParts = _groupPath splitString "/";
        private _groupConfig = configFile >> "CfgGroups";
        { _groupConfig = _groupConfig >> _x } forEach _pathParts;
        
        private _spawnedGroup = [_groupSpawnPos, east, _groupConfig] call BIS_fnc_spawnGroup;
        _missionGroups pushBack _spawnedGroup;
        _tagsPerGroup pushBack _doctrineTags;
        
        // Set all units to careless so they don't move or attack
        _spawnedGroup setBehaviour "CARELESS";
        private _spawnedUnits = +units _spawnedGroup; // Copy array to track all units for cleanup
        _totalUnits pushBack _spawnedUnits;
        
        // Get building positions for garrison
        private _availableStructures = +_targetStructures; // Copy array
        private _currentStructure = selectRandom _availableStructures;
        private _buildingPositions = _currentStructure buildingPos -1;
        private _posIndex = 0;

        diag_log format ["Spawning group %1 in structure %2.", _spawnedGroup, _currentStructure];


        // WILL PROBABLY RETHINK THIS LOOP.  NEEDS BETTER DISPERSION OF UNITS IN THE AREA
        // Will need to add back activation logic, maybe at a group level instead of an area level
        {
            _x disableAI "MOVE";
            _x disableAI "TARGET";
            _x disableAI "AUTOTARGET";

            // Move unit to building position
            private _veh = vehicle _x;
            if (_veh == _x) then {
                // Infantry - move to building position
                if (_posIndex < count _buildingPositions) then {
                    _x setPos (_buildingPositions select _posIndex);
                    _posIndex = _posIndex + 1;
                } else {
                    // Current building full, get next closest building
                    _availableStructures = _availableStructures - [_currentStructure];
                    if (count _availableStructures > 0) then {
                        diag_log format ["Structure %1 is out of positions. Finding alternative...", _currentStructure];
                        _availableStructures = [_availableStructures, [], { _x distance2D _currentStructure }, "ASCEND"] call BIS_fnc_sortBy;
                        _currentStructure = _availableStructures select 0;
                        diag_log format ["New structure found: %1", _currentStructure];
                        _buildingPositions = _currentStructure buildingPos -1;
                        _posIndex = 0;
                        if (count _buildingPositions > 0) then {
                            _x setPos (_buildingPositions select _posIndex);
                            _posIndex = _posIndex + 1;
                        };
                    };
                };
            } else {
                // In vehicle - track for cleanup and optionally start engine
                _totalVehicles pushBackUnique _veh;
                if (driver _veh == _x) then {
                    _veh engineOn true;
                };
            };
        } forEach units _spawnedGroup;

        sleep 1;
    };

    // for "_i" from 1 to _noOfGroups do {
    //     // Select random group from classified pool
    //     private _selectedGroup = selectRandom _classifiedGroups;
    //     private _groupPath = _selectedGroup get "path";
    //     private _groupName = _selectedGroup get "groupName";
    //     private _doctrineTags = _selectedGroup get "doctrineTags";

    //     diag_log format ["DSC: Selected group %1: %2", _i, _groupName];
    //     diag_log format ["DSC: Doctrine tags: %1", _doctrineTags];

    //     private _groupSpawnPos = [_randomMilLoc, 0, _radiusOuter, 5, 0, 20, 0] call BIS_fnc_findSafePos;

    //     // Parse the group path and traverse config
    //     private _pathParts = _groupPath splitString "/";
    //     private _groupConfig = configFile >> "CfgGroups";
    //     { _groupConfig = _groupConfig >> _x } forEach _pathParts;
        
    //     private _spawnedGroup = [_groupSpawnPos, east, _groupConfig] call BIS_fnc_spawnGroup;
    //     _missionGroups pushBack _spawnedGroup;
    //     _tagsPerGroup pushBack _doctrineTags;
        
    //     // Set all units to careless so they don't move or attack
    //     _spawnedGroup setBehaviour "CARELESS";
    //     private _spawnedUnits = +units _spawnedGroup; // Copy array to track all units for cleanup
    //     _totalUnits pushBack _spawnedUnits;
    //     {
    //         _x disableAI "MOVE";
    //         _x disableAI "TARGET";
    //         _x disableAI "AUTOTARGET";
            
    //         // Turn on engine if unit is in a vehicle and track vehicles for cleanup
    //         private _veh = vehicle _x;
    //         if (_veh != _x) then {
    //             _totalVehicles pushBackUnique _veh;
    //             if (driver _veh == _x) then {
    //                 _veh engineOn true;
    //             };
    //         };
    //     } forEach units _spawnedGroup;

    //     sleep 1;
    // };

    // ============================================================================
    // STEP 4: Mission has begun after group has been created
    // ============================================================================
    diag_log format ["DSC: Spawned %1 group at %2", count _missionGroups, _randomMilLoc];

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
        sleep 1;
    } forEach _totalUnits;

    // Delete all tracked vehicles (works even if destroyed)
    {
        deleteVehicle _x;
        sleep 1;
    } forEach _totalVehicles;

    // Delete group after units and vehicles
    {
        deleteGroup _x;
    } forEach _missionGroups;

    _missionCleanupInProgress = false;
    waitUntil { !_missionCleanupInProgress };
    sleep 3;
    missionNamespace setVariable ["missionState", "IDLE", true];

    // Remove Target Markers
    deleteMarker "target_location_marker";
    deleteMarker "target_location_area_marker";
    _targetMarker = nil;
    _targetAreaMarker = nil;
    
    // ================================================================================
    // STEP 7: Once cleanup is done the next mission generation begins, back to Step 2
    // ================================================================================
    sleep 3;
};
