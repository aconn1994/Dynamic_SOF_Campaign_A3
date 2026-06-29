#include "..\..\script_component.hpp"
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
// Base Actions
// ============================================================================
["AmmoboxInit", [jointOperationCenter, true, { _this distance _target  < 6 }]] call BIS_fnc_arsenal;

if (isClass (configFile >> "CfgPatches" >> "ace_arsenal")) then {
    jointOperationCenter addAction [
        "ACE Arsenal",
        { [jointOperationCenter, player, true] call ace_arsenal_fnc_openBox; },
        [],
        5,
        false,
        true,
        "",
        "_target distance _this < 5"
    ];
};

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

if (isClass (configFile >> "CfgPatches" >> "ace_arsenal")) then {
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
};
// player addAction [
//     'Request Extraction',
//     {
//         [player] spawn DSC_core_fnc_requestExtraction;
//     },
//     [],
//     1,
//     false,
//     true,
//     "",
//     ""
// ];

// // ============================================================================
// // Base Recruitment Actions (on Joint Operations Center flagpole)
// // ============================================================================
// jointOperationCenter addAction [
//     'Recruit Medic',
//     {
//         [player] call DSC_core_fnc_recruitMedic;
//     },
//     [],
//     3,
//     false,
//     true,
//     "",
//     "_target distance _this < 5"
// ];

// ============================================================================
// Dynamic Respawn (playtest aid)
// ============================================================================
// On death, drop an invisible "respawn_west_dynamic" marker a safe distance
// from the kill site. The vanilla position-respawn template (respawn = 3)
// then respawns the player there — side-specific markers (respawn_west_*)
// override the generic base markers (respawn_*) — so play resumes near where
// the player fell instead of back at base, keeping the presence manager's
// local zones alive instead of despawning them.
//
// EntityKilled is a mission EH so it survives respawns (unlike an object EH).
// DSC_dynRespawnArmed gates out the fake death the engine fires during
// respawnOnStart at mission init — at that point the player unit sits at
// [0,0,0] (numeric, so a type check won't catch it) and a marker placed there
// would respawn the player at the map origin. We only arm once the player has
// genuinely spawned into the world with a real position.
DSC_dynRespawnArmed = false;
[] spawn {
    waitUntil { sleep 0.5; alive player && {(getPosATL player) distance2D [0, 0] > 100} };
    DSC_dynRespawnArmed = true;
    INFO("Dynamic respawn armed");
};

addMissionEventHandler ["EntityKilled", {
    params ["_killed"];
    if (_killed isEqualTo player && {DSC_dynRespawnArmed}) then {
        [_killed] call DSC_core_fnc_placeDynamicRespawn;
    };
}];

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

