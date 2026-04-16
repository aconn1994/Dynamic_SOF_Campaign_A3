// DSC - Dynamic SOF Campaign
// Server initialization - orchestrates world scanning, faction setup, and mission loop

// ============================================================================
// STEP 0: Init Server Globals
// ============================================================================
missionNamespace setVariable ["initGlobalsComplete", false, true];

missionNamespace setVariable ["playerFaction", "BLU_F", true];
missionNamespace setVariable ["opForFaction", "OPF_F", true]; // rhsgref_faction_chdkz
missionNamespace setVariable ["missionState", "IDLE", true];
missionNamespace setVariable ["missionInProgress", false, true];
missionNamespace setVariable ["missionComplete", false, true];

missionNamespace setVariable ["initGlobalsComplete", true, true];

// ============================================================================
// STEP 1: Scan World - One pass, all locations with structures + tags
// ============================================================================
private _locations = [] call DSC_core_fnc_scanLocations;
missionNamespace setVariable ["DSC_locations", _locations, true];

diag_log format ["DSC: World scan complete - %1 locations indexed", count _locations];

// ============================================================================
// STEP 2: Faction Data
// ============================================================================
diag_log "=============== DSC: Initializing Faction Data =================";

private _opForFaction = missionNamespace getVariable ["opForFaction", "OPF_F"];
private _opForGroups = [_opForFaction] call DSC_core_fnc_extractGroups;
private _classifiedGroups = [_opForGroups] call DSC_core_fnc_classifyGroups;

diag_log format ["DSC: Classified %1 groups for faction %2", count _classifiedGroups, _opForFaction];

if (_classifiedGroups isEqualTo []) then {
    diag_log "DSC: No groups found, falling back to OPF_F";
    _opForFaction = "OPF_F";
    missionNamespace setVariable ["opForFaction", _opForFaction, true];
    _opForGroups = [_opForFaction] call DSC_core_fnc_extractGroups;
    _classifiedGroups = [_opForGroups] call DSC_core_fnc_classifyGroups;
};

missionNamespace setVariable ["DSC_classifiedGroups", _classifiedGroups, true];

// ============================================================================
// STEP 2b: Extract Faction Assets (vehicles, statics, aircraft)
// ============================================================================
private _opForAssets = [_opForFaction] call DSC_core_fnc_extractAssets;
missionNamespace setVariable ["DSC_opForAssets", _opForAssets, true];

// ============================================================================
// STEP 3: Mission Generation Loop
// ============================================================================
while { true } do {
    diag_log "DSC: ========== Starting Mission Generation ==========";
    
    // --- Randomize Time and Weather ---
    private _hour = selectRandom [0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22];
    private _minute = floor random 60;
    setDate [date select 0, date select 1, date select 2, _hour, _minute];
    
    0 setOvercast (random 1);
    0 setFog ([random 0.3, 0, 0] select (random 1 > 0.7));
    0 setRain 0;
    forceWeatherChange;
    sleep 1;
    0 setRain (if (overcast > 0.5) then { random 0.4 } else { 0 });
    
    diag_log format ["DSC: Time set to %1:%2, overcast: %3", _hour, _minute, overcast];
    
    // --- Select Location ---
    // Filter to locations suitable for kill/capture (has structures to garrison)
    private _validLocations = _locations select {
        (_x get "mainCount") >= 1 && (_x get "buildingCount") >= 3 // && (_x get "militaryCount") >= 5
    };
    
    if (_validLocations isEqualTo []) then {
        diag_log "DSC: ERROR - No valid locations found, retrying in 30s";
        sleep 30;
        continue;
    };
    
    private _selectedLocation = selectRandom _validLocations;
    private _locationPos = _selectedLocation get "position";
    private _locationName = _selectedLocation get "name";
    private _locationTags = _selectedLocation get "tags";
    
    diag_log format ["DSC: Selected location: %1 (%2 buildings, tags: %3)", 
        _locationName, _selectedLocation get "buildingCount", _locationTags];
    
    // --- Populate AO ---
    private _ao = [_selectedLocation, _classifiedGroups, createHashMapFromArray [["assets", _opForAssets]]] call DSC_core_fnc_populateAO;
    
    // --- Generate Kill/Capture Mission ---
    private _mission = [_selectedLocation, _ao] call DSC_core_fnc_generateKillCaptureMission;
    
    if (_mission isEqualTo createHashMap) then {
        diag_log "DSC: ERROR - Mission generation failed, retrying in 10s";
        sleep 10;
        continue;
    };
    
    private _hvtUnit = _mission get "entity";
    private _aoUnits = _mission get "units";
    private _aoGroups = _mission get "groups";
    private _defenderUnits = _mission get "defenderUnits";
    private _patrolGroups = _mission get "patrolGroups";
    
    // --- Mission Briefing ---
    private _taskId = [_mission, _ao, _selectedLocation] call DSC_core_fnc_createMissionBriefing;
    
    // --- ISR Drone ---
    private _hvtBuilding = _mission get "entityBuilding";
    private _uavTargetPos = if (!isNull _hvtBuilding) then { getPos _hvtBuilding } else { _locationPos };
    missionNamespace setVariable ["DSC_uavTargetPos", _uavTargetPos, true];
    
    // Spawn UAV if none active (first mission or after shoot-down)
    private _activeUAV = missionNamespace getVariable ["DSC_activeUAV", objNull];
    if (isNull _activeUAV || !alive _activeUAV) then {
        [_uavTargetPos] spawn DSC_core_fnc_persistentUAV;
    };
    
    // --- Configure Units ---
    { _x allowDamage true } forEach _aoUnits;
    
    // Apply skill profile - change this string to test different profiles:
    // "moderate" - forgiving, casual coop
    // "hard"     - challenging, accurate AI
    // "realism"  - lethal, fast reactions
    [_aoUnits, "hard"] call DSC_core_fnc_applySkillProfile;
    
    // Add to zeus
    private _curator = (allCurators) select 0;
    if (!isNull _curator) then {
        { _curator addCuratorEditableObjects [[_x], true] } forEach allUnits;
    };
    
    // --- QRF Combat Response ---
    private _qrfDelaySeconds = 120 + random 60;
    
    private _triggerUnits = +_defenderUnits;
    if (!isNull _hvtUnit && !(_hvtUnit in _triggerUnits)) then {
        _triggerUnits pushBack _hvtUnit;
    };
    
    if (_patrolGroups isNotEqualTo [] && _triggerUnits isNotEqualTo []) then {
        {
            _x addEventHandler ["FiredNear", {
                params ["_unit", "_firer", "_distance", "_weapon", "_muzzle", "_mode", "_ammo", "_gunner"];
                
                private _isPlayerOrSquadmate = isPlayer _gunner || { isPlayer (leader group _gunner) };
                if (!_isPlayerOrSquadmate) exitWith {};
                
                private _mission = missionNamespace getVariable ["DSC_currentMission", createHashMap];
                if (_mission isEqualTo createHashMap) exitWith {};
                if (_mission getOrDefault ["combatResponseTriggered", false]) exitWith {};
                
                _mission set ["combatResponseTriggered", true];
                missionNamespace setVariable ["DSC_currentMission", _mission, true];
                
                private _patrolGroups = _mission getOrDefault ["patrolGroups", []];
                private _locationPos = _mission getOrDefault ["location", []];
                private _qrfDelay = _mission getOrDefault ["qrfDelay", 120];
                
                if (_patrolGroups isEqualTo [] || _locationPos isEqualTo []) exitWith {};
                
                diag_log format ["DSC: QRF dispatched in %1 seconds", _qrfDelay];
                
                [_patrolGroups, _locationPos, _qrfDelay] spawn {
                    params ["_patrols", "_pos", "_delay"];
                    sleep _delay;
                    
                    if (!(missionNamespace getVariable ["missionInProgress", false])) exitWith {};
                    
                    [_patrols, _pos] call DSC_core_fnc_convergePatrols;
                    systemChat "Enemy QRF is responding to the engagement!";
                    diag_log "DSC: QRF patrols converging on objective";
                };
                
                private _triggerUnits = _mission getOrDefault ["triggerUnits", []];
                { _x removeEventHandler ["FiredNear", _thisEventHandler] } forEach _triggerUnits;
            }];
        } forEach _triggerUnits;
        
        _mission set ["qrfDelay", _qrfDelaySeconds];
        _mission set ["triggerUnits", _triggerUnits];
        missionNamespace setVariable ["DSC_currentMission", _mission, true];
        
        diag_log format ["DSC: QRF EH on %1 units (delay: %2s)", count _triggerUnits, _qrfDelaySeconds];
    };
    
    // --- Mission Active ---
    missionNamespace setVariable ["missionInProgress", true, true];
    missionNamespace setVariable ["missionState", "ACTIVE", true];
    
    diag_log format ["DSC: Mission ACTIVE - Kill/Capture at %1 (%2 groups, %3 units)", 
        _locationName, count _aoGroups, count _aoUnits];
    
    // Wait for debrief (triggered by player at flagpole)
    waitUntil { 
        sleep 1;
        !(missionNamespace getVariable ["missionInProgress", true])
    };
    
    // --- Debrief ---
    missionNamespace setVariable ["missionState", "DEBRIEF", true];
    
    private _hvtKilled = !alive _hvtUnit;
    private _success = _hvtKilled || (missionNamespace getVariable ["missionComplete", false]);
    
    if (_success) then {
        [_taskId, "SUCCEEDED"] call BIS_fnc_taskSetState;
        hint format ["Mission SUCCESS\nHVT at %1 eliminated", _locationName];
        systemChat format ["DSC: Mission SUCCESS - HVT at %1 eliminated", _locationName];
        diag_log format ["DSC: Mission SUCCESS - HVT killed: %1", _hvtKilled];
    } else {
        [_taskId, "CANCELED"] call BIS_fnc_taskSetState;
        hint format ["Mission INCOMPLETE\nHVT at %1 status unknown", _locationName];
        systemChat format ["DSC: Mission INCOMPLETE - %1", _locationName];
        diag_log "DSC: Mission INCOMPLETE";
    };
    
    sleep 5;
    [_taskId] call BIS_fnc_deleteTask;
    
    // --- Cleanup ---
    missionNamespace setVariable ["missionState", "CLEANUP", true];
    
    [_mission] call DSC_core_fnc_cleanupMission;
    
    missionNamespace setVariable ["missionInProgress", false, true];
    missionNamespace setVariable ["missionComplete", false, true];
    missionNamespace setVariable ["missionState", "IDLE", true];
    
    diag_log "DSC: Waiting before next mission...";
    sleep 5;
};
