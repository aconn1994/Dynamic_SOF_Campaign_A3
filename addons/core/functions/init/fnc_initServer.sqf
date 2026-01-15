// DSC - Dynamic SOF Campaign

missionNamespace setVariable ["initGlobalsComplete", false, true];
// ============================================================================
// STEP 0: Init Server Globals
// ============================================================================
missionNamespace setVariable ["missionState", "IDLE", true]; // IDLE -> ACTIVE -> DEBRIEF -> CLEANUP -> IDLE
missionNamespace setVariable ["missionInProgress", false, true];
missionNamespace setVariable ["missionComplete", false, true];
private _missionCleanupInProgress = false;

missionNamespace setVariable ["initGlobalsComplete", true, true];

// ============================================================================
// STEP 1: Get Faction group data using new classification system
// ============================================================================
diag_log "=============== DSC: Initializing Faction Data =================";

// Primary OpFor faction - CSAT
private _opForFaction = "OPF_F";

// Extract and classify groups for OpFor
private _opForGroups = [_opForFaction] call DSC_core_fnc_extractGroups;
private _classifiedGroups = [_opForGroups] call DSC_core_fnc_classifyGroups;

diag_log format ["DSC: Classified %1 groups for faction %2", count _classifiedGroups, _opForFaction];

// Fallback check - if no groups found, try CSAT (same for now, but useful when testing other mods)
if (count _classifiedGroups == 0) then {
    diag_log "DSC: No groups found, falling back to OPF_F";
    _opForFaction = "OPF_F";
    _opForGroups = [_opForFaction] call DSC_core_fnc_extractGroups;
    _classifiedGroups = [_opForGroups] call DSC_core_fnc_classifyGroups;
};

// Store classified groups globally for debugging
missionNamespace setVariable ["DSC_classifiedGroups", _classifiedGroups, true];

// ============================================================================
// STEP 2: Setup While loop for continuous mission generation
// ============================================================================
while { true } do {
    diag_log "DSC: Generating group for mission...";

    // Select random group from classified pool
    private _selectedGroup = selectRandom _classifiedGroups;
    private _groupPath = _selectedGroup get "path";
    private _groupName = _selectedGroup get "groupName";
    private _doctrineTags = _selectedGroup get "doctrineTags";
    
    diag_log format ["DSC: Selected group: %1", _groupName];
    diag_log format ["DSC: Doctrine tags: %1", _doctrineTags];

    // Spawn the group at marker position
    private _spawnPos = getMarkerPos "enemy_spawn_point";
    private _spawnDir = markerDir "enemy_spawn_point";
    
    // Parse the group path and traverse config
    private _pathParts = _groupPath splitString "/";
    private _groupConfig = configFile >> "CfgGroups";
    { _groupConfig = _groupConfig >> _x } forEach _pathParts;
    
    private _spawnedGroup = [_spawnPos, east, _groupConfig] call BIS_fnc_spawnGroup;
    
    // Display doctrine tags in system chat for debugging
    private _tagString = _doctrineTags joinString ", ";
    systemChat format ["DSC: Spawned %1 [%2]", _groupName, _tagString];
    
    // Set all units to careless so they don't move or attack
    _spawnedGroup setBehaviour "CARELESS";
    private _spawnedVehicles = [];
    private _spawnedUnits = +units _spawnedGroup; // Copy array to track all units for cleanup
    {
        _x disableAI "MOVE";
        _x disableAI "TARGET";
        _x disableAI "AUTOTARGET";
        
        // Turn on engine if unit is in a vehicle and track vehicles for cleanup
        private _veh = vehicle _x;
        if (_veh != _x) then {
            _spawnedVehicles pushBackUnique _veh;
            if (driver _veh == _x) then {
                _veh engineOn true;
            };
        };
    } forEach units _spawnedGroup;

    _spawnedGroup setFormDir _spawnDir;

    // ============================================================================
    // STEP 3: Mission has begun after group has been created
    // ============================================================================
    diag_log format ["DSC: Spawned group with %1 units at %2", count units _spawnedGroup, _spawnPos];

    missionNamespace setVariable ["missionInProgress", true, true];
    missionNamespace setVariable ["missionState", "ACTIVE", true];
    
    // Store current mission data
    missionNamespace setVariable ["enemyMissionGroup", _spawnedGroup, true];
    missionNamespace setVariable ["currentMissionTags", _doctrineTags, true];

    waitUntil { !(missionNamespace getVariable ["missionInProgress", true]) };
    
    // ============================================================================
    // STEP 4: Mission Debrief and success evaluation triggered by player RTB
    // ============================================================================
    missionNamespace setVariable ["missionState", "DEBRIEF", true];

    if (missionNamespace getVariable ["missionComplete", false]) then {
        hint "Mission was successful";
        systemChat "DSC: Mission SUCCESS";
    } else {
        hint "Mission was unsuccessful";
        systemChat "DSC: Mission FAILED";
    };

    // ============================================================================
    // STEP 5: Mission is marked as finished and cleanup begins
    // ============================================================================
    missionNamespace setVariable ["missionState", "CLEANUP", true];
    _missionCleanupInProgress = true;

    diag_log "DSC: Cleanup begins...";
    
    // Delete all tracked units including dead bodies
    {
        deleteVehicle _x;
        sleep 1;
    } forEach _spawnedUnits;

    // Delete all tracked vehicles (works even if destroyed)
    {
        deleteVehicle _x;
        sleep 1;
    } forEach _spawnedVehicles;

    // Delete group after units and vehicles
    deleteGroup _spawnedGroup;

    _missionCleanupInProgress = false;
    waitUntil { !_missionCleanupInProgress };
    sleep 3;
    missionNamespace setVariable ["missionState", "IDLE", true];
    
    // ================================================================================
    // STEP 6: Once cleanup is done the next mission generation begins, back to Step 2
    // ================================================================================
    sleep 3;
};
