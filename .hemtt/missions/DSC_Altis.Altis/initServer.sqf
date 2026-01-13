// DSC - Dynamic SOF Campaign - Altis
// Using Aegis and RHS for now, eventually vanilla will be default and code will check for Aegis/RHS mods

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
// STEP 1: Get Faction group data
// ============================================================================
diag_log "=============== Get factions =================";
// private _opForFactionGroups = ["rhs_faction_msv"] call DSC_core_fnc_factionGroupMapper;
private _opForFactionGroups = ["rhs_faction_vpvo"] call DSC_core_fnc_factionGroupMapper;

// Check for null groups, fallback to base OpFor
if (
    ((count (_opForFactionGroups get "infantry")) == 0) ||
    ((count (_opForFactionGroups get "motorized")) == 0) ||
    ((count (_opForFactionGroups get "mechanized")) == 0)
) then { _opForFactionGroups = ["OPF_F"] call DSC_core_fnc_factionGroupMapper; };

// ============================================================================
// STEP 2: Setup While loop for continuous mission generation
// ============================================================================
while { true; } do {
    diag_log "Generating group for mission...";

    // Logic for spawning a group
    _groupType = selectRandom (_opForFactionGroups get (selectRandom ["infantry", "motorized", "mechanized"]));
    diag_log format ["RANDOM GROUP TYPE: %1", _groupType];

    // Spawn the group at marker position
    private _spawnPos = getMarkerPos "enemy_spawn_point";
    
    // Parse the group path and traverse config
    private _pathParts = _groupType splitString "/";
    private _groupConfig = configFile >> "CfgGroups";
    { _groupConfig = _groupConfig >> _x } forEach _pathParts;
    
    private _unitClasses = "true" configClasses _groupConfig apply {getText (_x >> "vehicle")};

    diag_log format ["Spawn Point: %1", _spawnPos];
    diag_log format ["Unit Classes Config for Group: %1", _unitClasses];
    private _spawnedGroup = [_spawnPos, east, _groupConfig] call BIS_fnc_spawnGroup;
    
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

    // ============================================================================
    // STEP 3: Mission has begun after group has been created
    // ============================================================================
    diag_log format ["Spawned group with %1 units at %2", count units _spawnedGroup, _spawnPos];

    missionNamespace setVariable ["missionInProgress", true, true];
    missionNamespace setVariable ["missionState", "ACTIVE", true];
    
    // When player goes to debriefing (player action) missionInProgress will be set to false
    missionNamespace setVariable ["enemyMissionGroup", _spawnedGroup, true];

    waitUntil { !(missionNamespace getVariable ["missionInProgress", true]) };
    // ============================================================================
    // STEP 4: Mission Debrief and success evaluation triggered by player RTB
    // ============================================================================
    missionNamespace setVariable ["missionState", "DEBRIEF", true];

    if (missionComplete == true) then {
        hint "Mission was successful"
    } else {
        hint "Mission was unsuccessful"
    };

    // ============================================================================
    // STEP 5: Mission is marked as finished and cleanup begins
    // ============================================================================
    missionNamespace setVariable ["missionState", "CLEANUP", true];
    _missionCleanupInProgress = true;

    // Logic for cleanup
    diag_log "Cleanup begins now...";
    
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
    waitUntil { _missionCleanupInProgress == false; };
    sleep 5;
    missionNamespace setVariable ["missionState", "IDLE", true];
    // ================================================================================
    // STEP 6: Once cleanup is done the next mission generation begins, back to Step 2
    // ================================================================================
    sleep 5;
};
