// Wait until Global Server variables are initialized
waitUntil { missionNamespace getVariable ["initGlobalsComplete", false]; };

// ============================================================================
// Mission Actions (on Joint Operations Center flagpole)
// ============================================================================
jointOperationCenter addAction [
    'Debrief Mission',
    {
        private _mission = missionNamespace getVariable ["DSC_currentMission", createHashMap];
        if (_mission isEqualTo createHashMap) exitWith { hint "No active mission." };
        
        private _missionGroups = _mission getOrDefault ["groups", []];
        if (_missionGroups isEqualTo []) exitWith { hint "No mission groups found." };

        private _groupAlives = false;
        {
            if ([_x] call DSC_core_fnc_groupActive) then { _groupAlives = true };
        } forEach _missionGroups;

        if (!_groupAlives) then { 
            missionNamespace setVariable ["missionComplete", true, true]; 
        };
        missionNamespace setVariable ["missionInProgress", false, true];
    },
    [],
    6,
    false,
    true,
    "",
    "missionNamespace getVariable ['missionInProgress', false] && _target distance _this < 5"
];

// ============================================================================
// Insertion Actions
// ============================================================================
jointOperationCenter addAction [
    'HALO Jump',
    {
        openMap true;
        player onMapSingleClick {
            player onMapSingleClick "";
            
            private _jumpPos = _pos;
            
            // Create drop marker visible to all players
            private _markerName = format ["dsc_drop_%1", getPlayerUID player];
            deleteMarker _markerName;
            private _marker = createMarker [_markerName, _jumpPos];
            _marker setMarkerTypeLocal "mil_start";
            _marker setMarkerColorLocal "ColorBlue";
            _marker setMarkerText format ["%1 Drop Location", name player];
            
            // Jump all units in the player's group
            {
                private _unitOffset = _forEachIndex * 6;
                private _unitPos = [_jumpPos select 0, (_jumpPos select 1) + _unitOffset, _jumpPos select 2];
                [_x, _unitPos] spawn DSC_core_fnc_haloJump;
            } forEach units group player;
            
            openMap false;
        };
    },
    [],
    5,
    false,
    true,
    "",
    "_target distance _this < 5"
];

player addAction [
    'Request Extraction',
    {
        [player] spawn DSC_core_fnc_requestExtraction;
    },
    [],
    1,
    false,
    true,
    "",
    ""
];

// ============================================================================
// Base Recruitment Actions (on Joint Operations Center flagpole)
// ============================================================================
jointOperationCenter addAction [
    'Recruit Medic',
    {
        [player] call DSC_core_fnc_recruitMedic;
    },
    [],
    3,
    false,
    true,
    "",
    "_target distance _this < 5"
];

// ============================================================================
// Player Down/Revive System (ACE or Vanilla)
// ============================================================================
private _hasACEMedical = isClass (configFile >> "CfgPatches" >> "ace_medical");
missionNamespace setVariable ["DSC_hasACEMedical", _hasACEMedical, true];

if (_hasACEMedical) then {
    diag_log "DSC: ACE Medical detected - using ACE unconscious events";
    
    // Listen for ACE unconscious state change
    ["ace_unconscious", {
        params ["_unit", "_state"];
        if (_unit != player) exitWith {};
        if (!_state) exitWith {};
        if (_unit getVariable ["DSC_isDown", false]) exitWith {};
        
        [_unit] spawn DSC_core_fnc_handlePlayerDown;
    }] call CBA_fnc_addEventHandler;
} else {
    diag_log "DSC: Vanilla damage model - using HandleDamage EH";
    
    player addEventHandler ["HandleDamage", {
        params ["_unit", "_selection", "_damage", "_source", "_projectile", "_hitIndex", "_instigator", "_hitPoint"];
        
        if (_unit getVariable ["DSC_isDown", false]) exitWith { 0 };
        
        if (_damage >= 1 || (damage _unit) + _damage >= 1) exitWith {
            [_unit] spawn DSC_core_fnc_handlePlayerDown;
            0
        };
        
        _damage
    }];
};

// ============================================================================
// Map Draw: Faction Flag Icons for Military Installations
// ============================================================================
// Renders faction flag textures from CfgFactionClasses on the map.
// Data published by server Step 4 as DSC_baseMarkerData / DSC_outpostMarkerData.
// Each entry: [position, name, flagTexture, colorArray]

waitUntil { !(isNil { missionNamespace getVariable "DSC_baseMarkerData" }) };

((findDisplay 12) displayCtrl 51) ctrlAddEventHandler ["Draw", {
    params ["_map"];

    private _baseData = missionNamespace getVariable ["DSC_baseMarkerData", []];
    private _outpostData = missionNamespace getVariable ["DSC_outpostMarkerData", []];

    {
        _x params ["_pos", "_name", "_tex", "_color"];
        if (_tex != "") then {
            _map drawIcon [_tex, [1,1,1,1], _pos, 38, 26, 0, _name, 1, 0.04, "PuristaBold", "right"];
        };
    } forEach _baseData;

    {
        _x params ["_pos", "_name", "_tex", "_color"];
        if (_tex != "") then {
            _map drawIcon [_tex, [1,1,1,1], _pos, 26, 18, 0, _name, 1, 0.03, "PuristaMedium", "right"];
        };
    } forEach _outpostData;
}];

