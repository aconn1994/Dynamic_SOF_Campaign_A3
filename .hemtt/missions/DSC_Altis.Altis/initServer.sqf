// DSC - Dynamic SOF Campaign - Altis
// Using Aegis and RHS for now, eventually vanilla will be default and code will check for Aegis/RHS mods

// ============================================================================
// STEP 1: Get OpFor available factions from CfgFactionClasses
// ============================================================================
diag_log "=============== Groups for AFRF MSV Factions =================";
private _opForFactionGroups = ["rhs_faction_msv"] call DSC_core_fnc_factionGroupMapper;

missionNamespace setVariable ["missionInProgress", false, true];
missionNamespace setVariable ["missionComplete", false, true];
private _missionCleanupInProgress = false;

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
    
    // When player goes to debriefing (player action) missionInProgress will be set to false
    missionNamespace setVariable ["enemyMissionGroup", _spawnedGroup, true];

    waitUntil { !(missionNamespace getVariable ["missionInProgress", true]) };
    _missionCleanupInProgress = true;

    // ============================================================================
    // STEP 4: Mission is marked as finished and cleanup begins
    // ============================================================================

    if (missionComplete == true) then {
        hint "Mission was successful"
    } else {
        hint "Mission was unsuccessful"
    };

    // Logic for cleanup
    diag_log "Cleanup begins now...";
    
    // Delete all tracked vehicles (works even if destroyed)
    {
        deleteVehicle _x;
    } forEach _spawnedVehicles;
    
    // Delete all units from the mission group
    {
        deleteVehicle _x;
    } forEach units _spawnedGroup;
    deleteGroup _spawnedGroup;

    _missionCleanupInProgress = false;
    waitUntil { _missionCleanupInProgress == false; };
    // ============================================================================
    // STEP 5: Once cleanup is done the next mission generation begins
    // ============================================================================
    sleep 3;
};