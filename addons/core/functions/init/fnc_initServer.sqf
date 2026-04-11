// DSC - Dynamic SOF Campaign
// Server initialization - orchestrates world scanning, faction setup, and mission loop

// ============================================================================
// STEP 0: Init Server Globals
// ============================================================================
missionNamespace setVariable ["initGlobalsComplete", false, true];

missionNamespace setVariable ["playerFaction", "BLU_F", true];
missionNamespace setVariable ["opForFaction", "OPF_F", true];
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
// STEP 3: Mission Generation Loop
// ============================================================================
while { true } do {
    diag_log "DSC: ========== Starting Mission Generation ==========";
    
    // --- Select Location ---
    // Filter to locations suitable for kill/capture (has structures to garrison)
    private _validLocations = _locations select {
        (_x get "mainCount") >= 1 && (_x get "buildingCount") >= 3
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
    private _ao = [_selectedLocation, _classifiedGroups] call DSC_core_fnc_populateAO;
    
    private _aoGroups = _ao get "groups";
    private _aoUnits = _ao get "units";
    private _aoVehicles = _ao get "vehicles";
    private _defenderUnits = _ao get "defenderUnits";
    private _patrolGroups = _ao get "patrolGroups";
    private _garrisonUnits = _ao get "garrisonUnits";
    
    // --- Place HVT ---
    private _opForSide = east;
    private _hvtUnit = objNull;
    private _hvtBuilding = objNull;
    
    // Get officer class from faction
    private _hvtClass = "O_officer_F";
    private _filterStr = format ["getNumber (_x >> 'scope') >= 2 && getText (_x >> 'faction') == '%1' && getNumber (_x >> 'isMan') == 1", _opForFaction];
    private _factionUnits = _filterStr configClasses (configFile >> "CfgVehicles");
    
    {
        private _unitName = toLower (configName _x);
        if ("officer" in _unitName || "commander" in _unitName || "leader" in _unitName) exitWith {
            _hvtClass = configName _x;
        };
    } forEach _factionUnits;
    
    // Try placing HVT with garrison bodyguards
    private _placedWithBodyguard = false;
    
    if (_garrisonUnits isNotEqualTo []) then {
        private _candidateUnits = _garrisonUnits select {
            private _building = nearestBuilding _x;
            !isNull _building && { count (_building buildingPos -1) >= 3 }
        };
        
        if (_candidateUnits isNotEqualTo []) then {
            private _bodyguard = selectRandom _candidateUnits;
            _hvtBuilding = nearestBuilding _bodyguard;
            private _buildingPositions = _hvtBuilding buildingPos -1;
            
            private _occupiedPositions = _garrisonUnits apply { getPos _x };
            private _freePositions = _buildingPositions select {
                private _pos = _x;
                (_occupiedPositions findIf { _x distance _pos < 1 }) == -1
            };
            
            if (_freePositions isNotEqualTo []) then {
                private _hvtPos = selectRandom _freePositions;
                private _hvtGroup = group _bodyguard;
                _hvtUnit = _hvtGroup createUnit [_hvtClass, _hvtPos, [], 0, "NONE"];
                _hvtUnit setPos _hvtPos;
                _hvtUnit setUnitPos "UP";
                _hvtUnit disableAI "PATH";
                _placedWithBodyguard = true;
                diag_log format ["DSC: HVT placed with bodyguards in %1", _hvtBuilding];
            };
        };
    };
    
    // Fallback: place in any location structure
    if (!_placedWithBodyguard) then {
        private _allStructures = (_selectedLocation get "mainStructures") + (_selectedLocation get "sideStructures");
        _allStructures = _allStructures select { (_x buildingPos -1) isNotEqualTo [] };
        
        private _hvtGroup = createGroup [_opForSide, true];
        
        if (_allStructures isNotEqualTo []) then {
            _hvtBuilding = selectRandom _allStructures;
            private _buildingPositions = _hvtBuilding buildingPos -1;
            private _hvtPos = selectRandom _buildingPositions;
            _hvtUnit = _hvtGroup createUnit [_hvtClass, _hvtPos, [], 0, "NONE"];
            _hvtUnit setPos _hvtPos;
            _hvtUnit setUnitPos "UP";
            diag_log format ["DSC: HVT placed alone in %1", _hvtBuilding];
        } else {
            _hvtUnit = _hvtGroup createUnit [_hvtClass, _locationPos, [], 5, "NONE"];
            diag_log "DSC: HVT spawned at location center (no buildings)";
        };
        
        _hvtGroup setBehaviour "SAFE";
        _hvtGroup setCombatMode "GREEN";
        _hvtGroup enableAttack false;
        [_hvtGroup] call DSC_core_fnc_addCombatActivation;
        _aoGroups pushBack _hvtGroup;
    };
    
    _hvtUnit setVariable ["DSC_isHVT", true, true];
    _hvtUnit setVariable ["DSC_hvtName", format ["Target %1", floor (random 1000)], true];
    _aoUnits pushBack _hvtUnit;
    
    // --- Mission Marker ---
    private _markerPos = if (!isNull _hvtBuilding) then { getPos _hvtBuilding } else { _locationPos };
    private _targetMarker = createMarker ["target_location_marker", _markerPos];
    _targetMarker setMarkerTypeLocal "hd_objective";
    _targetMarker setMarkerColorLocal "ColorRed";
    _targetMarker setMarkerText format ["HVT: %1", _locationName];
    
    // --- Configure Units ---
    {
        _x allowDamage true;
        _x setSkill ["general", 0.6];
        _x setSkill ["aimingAccuracy", 0.2];
    } forEach _aoUnits;
    
    // Add to zeus
    private _curator = (allCurators) select 0;
    if (!isNull _curator) then {
        { _curator addCuratorEditableObjects [[_x], true] } forEach allUnits;
    };
    
    // --- Build Mission Data ---
    private _mission = createHashMapFromArray [
        ["type", "KILL_CAPTURE"],
        ["location", _locationPos],
        ["locationName", _locationName],
        ["locationTags", _locationTags],
        ["entity", _hvtUnit],
        ["entityBuilding", _hvtBuilding],
        ["groups", _aoGroups],
        ["patrolGroups", _patrolGroups],
        ["defenderUnits", _defenderUnits],
        ["units", _aoUnits],
        ["vehicles", _aoVehicles],
        ["marker", _targetMarker],
        ["startTime", serverTime],
        ["status", "ACTIVE"]
    ];
    
    missionNamespace setVariable ["DSC_currentMission", _mission, true];
    
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
        hint format ["Mission SUCCESS\nHVT at %1 eliminated", _locationName];
        systemChat format ["DSC: Mission SUCCESS - HVT at %1 eliminated", _locationName];
        diag_log format ["DSC: Mission SUCCESS - HVT killed: %1", _hvtKilled];
    } else {
        hint format ["Mission INCOMPLETE\nHVT at %1 status unknown", _locationName];
        systemChat format ["DSC: Mission INCOMPLETE - %1", _locationName];
        diag_log "DSC: Mission INCOMPLETE";
    };
    
    // --- Cleanup ---
    missionNamespace setVariable ["missionState", "CLEANUP", true];
    
    [_mission] call DSC_core_fnc_cleanupMission;
    
    missionNamespace setVariable ["missionInProgress", false, true];
    missionNamespace setVariable ["missionComplete", false, true];
    missionNamespace setVariable ["missionState", "IDLE", true];
    
    diag_log "DSC: Waiting before next mission...";
    sleep 5;
};
