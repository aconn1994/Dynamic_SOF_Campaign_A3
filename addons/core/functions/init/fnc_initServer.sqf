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

missionNamespace setVariable ["initGlobalsComplete", true, true];

// ============================================================================
// STEP 1: Scan Map for Military Locations
// ============================================================================
private _militaryLocations = [] call DSC_core_fnc_getMilitaryLocations;

private _milBases = _militaryLocations get "bases";
private _milOutposts = _militaryLocations get "outposts";
private _milCamps = _militaryLocations get "camps";

// ============================================================================
// STEP 1b: Scan Map for Civilian Locations
// ============================================================================
private _civilianLocations = [] call DSC_core_fnc_getCivilianLocations;

private _civCities = _civilianLocations get "cities";
private _civVillages = _civilianLocations get "villages";
private _civCompounds = _civilianLocations get "compounds";
private _civMaritime = _civilianLocations get "maritime";
private _civSpecial = _civilianLocations get "special";
private _civLandmarks = _civilianLocations get "landmarks";

// ******  TODO  ******, main enemy airbase location setup will happen here.........
// ******  TODO  ******, main insurgent base location setup will happen here.........

// ============================================================================
// STEP 2: Get Faction group data using classification system
// ============================================================================
diag_log "=============== DSC: Initializing Faction Data =================";

private _opForFaction = missionNamespace getVariable ["opForFaction", "OPF_F"];
private _opForGroups = [_opForFaction] call DSC_core_fnc_extractGroups;
private _classifiedGroups = [_opForGroups] call DSC_core_fnc_classifyGroups;

diag_log format ["DSC: Classified %1 groups for faction %2", count _classifiedGroups, _opForFaction];

// Fallback check
if (count _classifiedGroups == 0) then {
    diag_log "DSC: No groups found, falling back to OPF_F";
    _opForFaction = "OPF_F";
    missionNamespace setVariable ["opForFaction", _opForFaction, true];
    _opForGroups = [_opForFaction] call DSC_core_fnc_extractGroups;
    _classifiedGroups = [_opForGroups] call DSC_core_fnc_classifyGroups;
};

// Store classified groups globally
missionNamespace setVariable ["DSC_classifiedGroups", _classifiedGroups, true];

// ============================================================================
// STEP 3: Mission Generation Loop
// ============================================================================
while { true } do {
    diag_log "DSC: ========== Starting Mission Generation ==========";
    
    // Generate kill/capture mission
    private _missionConfig = createHashMapFromArray [
        ["validMilTypes", ["camps", "outposts"]],
        ["validCivTypes", ["compounds", "villages", "cities"]],
        ["density", "medium"]
    ];
    
    private _mission = [
        _militaryLocations,
        _civilianLocations,
        _classifiedGroups,
        _missionConfig
    ] call DSC_core_fnc_generateKillCaptureMission;
    
    // Check if mission generated successfully
    if (count _mission == 0) then {
        diag_log "DSC: ERROR - Mission generation failed, retrying in 10s";
        sleep 10;
        continue;
    };
    
    // ============================================================================
    // STEP 4: Mission Active
    // ============================================================================
    private _hvtUnit = _mission get "entity";
    private _locationPos = _mission get "location";
    private _locationName = _mission get "locationName";
    private _missionGroups = _mission get "groups";
    private _patrolGroups = _mission get "patrolGroups";
    private _totalUnits = _mission get "units";
    
    // Re-enable damage for all spawned units
    {
        _x allowDamage true;
        _x setSkill ["general", 0.8];
        _x setSkill ["aimingAccuracy", 0.3];
    } forEach _totalUnits;
    
    // Add units to zeus
    private _curator = (allCurators) select 0;
    if (!isNull _curator) then {
        {
            _curator addCuratorEditableObjects [[_x], true];
        } forEach allUnits;
    };
    
    // ============================================================================
    // STEP 4b: Setup Combat Response - Patrols converge when defenders take fire
    // ============================================================================
    private _defenderUnits = _mission getOrDefault ["defenderUnits", []];
    private _qrfDelaySeconds = 5; // 120 + random 60; // 2-3 minute delay for QRF response
    
    // Always include HVT as trigger unit, plus any defenders
    private _triggerUnits = +_defenderUnits;
    if (!isNull _hvtUnit && !(_hvtUnit in _triggerUnits)) then {
        _triggerUnits pushBack _hvtUnit;
    };
    
    if (_patrolGroups isNotEqualTo [] && _triggerUnits isNotEqualTo []) then {
        {
            _x addEventHandler ["FiredNear", {
                params ["_unit", "_firer", "_distance", "_weapon", "_muzzle", "_mode", "_ammo", "_gunner"];
                
                // Only trigger for player or player's AI squad mates
                private _isPlayerOrSquadmate = isPlayer _gunner || { isPlayer (leader group _gunner) };
                if (!_isPlayerOrSquadmate) exitWith {};
                
                private _mission = missionNamespace getVariable ["DSC_currentMission", createHashMap];
                if (_mission isEqualTo createHashMap) exitWith {};
                
                // Check if already triggered
                if (_mission getOrDefault ["combatResponseTriggered", false]) exitWith {};
                
                // Mark as triggered immediately so other units don't re-trigger
                _mission set ["combatResponseTriggered", true];
                missionNamespace setVariable ["DSC_currentMission", _mission, true];
                
                private _patrolGroups = _mission getOrDefault ["patrolGroups", []];
                private _locationPos = _mission getOrDefault ["location", []];
                private _qrfDelay = _mission getOrDefault ["qrfDelay", 120];
                
                if (_patrolGroups isEqualTo [] || _locationPos isEqualTo []) exitWith {};
                
                diag_log format ["DSC: Combat response triggered - QRF dispatched in %1 seconds", _qrfDelay];
                
                // Delayed QRF response
                [_patrolGroups, _locationPos, _qrfDelay] spawn {
                    params ["_patrols", "_pos", "_delay"];
                    
                    sleep _delay;
                    
                    // Verify mission still active
                    private _mission = missionNamespace getVariable ["DSC_currentMission", createHashMap];
                    if (_mission isEqualTo createHashMap) exitWith {};
                    if (!(missionNamespace getVariable ["missionInProgress", false])) exitWith {};
                    
                    [_patrols, _pos] call DSC_core_fnc_convergePatrols;
                    
                    systemChat "Enemy QRF is responding to the engagement!";
                    diag_log "DSC: QRF patrols now converging on objective";
                };
                
                // Remove EH from all trigger units
                private _triggerUnits = _mission getOrDefault ["triggerUnits", []];
                {
                    _x removeEventHandler ["FiredNear", _thisEventHandler];
                } forEach _triggerUnits;
            }];
        } forEach _triggerUnits;
        
        // Store in mission for cleanup
        _mission set ["qrfDelay", _qrfDelaySeconds];
        _mission set ["triggerUnits", _triggerUnits];
        missionNamespace setVariable ["DSC_currentMission", _mission, true];
        
        diag_log format ["DSC: Combat response EH added to %1 units (QRF delay: %2s)", count _triggerUnits, _qrfDelaySeconds];
    };
    
    missionNamespace setVariable ["missionInProgress", true, true];
    missionNamespace setVariable ["missionState", "ACTIVE", true];
    
    diag_log format ["DSC: Mission ACTIVE - Kill/Capture at %1 (%2 groups, %3 units)", 
        _locationName, count _missionGroups, count _totalUnits];
    
    // Wait for mission end (triggered externally by player RTB)
    waitUntil { 
        sleep 1;
        !(missionNamespace getVariable ["missionInProgress", true])
    };
    
    // ============================================================================
    // STEP 5: Mission Debrief
    // ============================================================================
    missionNamespace setVariable ["missionState", "DEBRIEF", true];
    
    private _hvtKilled = !alive _hvtUnit;
    private _success = _hvtKilled || (missionNamespace getVariable ["missionComplete", false]);
    
    if (_success) then {
        hint format ["Mission SUCCESS\nHVT at %1 eliminated", _locationName];
        systemChat format ["DSC: Mission SUCCESS - HVT at %1 eliminated", _locationName];
        diag_log format ["DSC: Mission SUCCESS - HVT killed: %1", _hvtKilled];
    } else {
        hint format ["Mission INCOMPLETE\nHVT at %1 status unknown", _locationName];
        systemChat format ["DSC: Mission INCOMPLETE - %1", _locationName];
        diag_log "DSC: Mission INCOMPLETE";
    };
    
    // ============================================================================
    // STEP 6: Mission Cleanup
    // ============================================================================
    missionNamespace setVariable ["missionState", "CLEANUP", true];
    
    [_mission] call DSC_core_fnc_cleanupMission;
    
    missionNamespace setVariable ["missionInProgress", false, true];
    missionNamespace setVariable ["missionComplete", false, true];
    missionNamespace setVariable ["missionState", "IDLE", true];
    
    // ============================================================================
    // STEP 7: Brief pause before next mission
    // ============================================================================
    diag_log "DSC: Waiting before next mission...";
    sleep 5;
};
