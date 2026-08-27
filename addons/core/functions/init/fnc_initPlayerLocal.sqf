#include "..\..\script_component.hpp"
// Wait until Global Server variables are initialized
waitUntil { missionNamespace getVariable ["initGlobalsComplete", false]; };

// ============================================================================
// Renegade protection for the player's own squad
// ============================================================================
// The player's squad is Eden-placed, so it never passes through
// fnc_applySkillProfile and gets none of the addRating protection that
// DSC-spawned AI receives.
//
// That matters more here than anywhere else. A playtest showed a squadmate at
// rating -1040 — over half of the way to the ~-2000 renegade threshold — after
// a single mission. The presence manager populates towns and compounds with
// civilians, so collateral damage in a firefight is routine, and a civilian
// kill is a large single penalty.
//
// If a squadmate crosses the threshold it becomes RENEGADE: hostile to every
// side including west, so the player's own squad turns on itself. From the
// player's chair that is inexplicable and unrecoverable, with no feedback
// pointing at the cause. Not a consequence worth modelling.
//
// Applied to the player too — a renegade player is attacked by their own AI
// and by every friendly installation on the map.
{
    if (!isNull _x) then { _x addRating 1000000 };
} forEach (units group player);

// ============================================================================
// Interaction Sites (Session 5) — client-local addAction arming
// ============================================================================
[] call DSC_core_fnc_initInteractionSites;

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
// C2 Network: report the player's weapon discharge (Sprint F.2)
// ============================================================================
// Suppressor state is classified HERE, on the machine that owns the weapon —
// muzzle accessory data is not reliably readable for remote units, so a
// server-side check would misgrade every shot in multiplayer.
//
// Throttled to one event per second per player. Without it, a 30-round burst
// would fire 30 identical noise events, each doing a full node sweep. The
// throttle costs nothing in fidelity: the network cannot be *more* alerted
// by the second bullet than the first.
//
// This catches misses, which EntityKilled cannot see. Opening fire and
// missing is still opening fire, and the enemy still heard it.
player addEventHandler ["Fired", {
    params ["_unit", "_weapon", "_muzzle"];

    private _last = _unit getVariable ["DSC_c2LastFiredReport", -99];
    if ((serverTime - _last) < 1) exitWith {};
    _unit setVariable ["DSC_c2LastFiredReport", serverTime];

    // Accessory slot 0 is the muzzle attachment.
    private _acc = _unit weaponAccessories _muzzle;
    private _suppressed = _acc isNotEqualTo [] && {(_acc select 0) != ""};

    // Launchers are never quiet regardless of what is bolted to them.
    private _isLauncher = _weapon isKindOf ["Launcher", configFile >> "CfgWeapons"];

    private _noiseType = if (_isLauncher) then {
        "EXPLOSION"
    } else {
        ["SMALL_ARMS", "SUPPRESSED"] select _suppressed
    };

    ["DSC_c2_playerFired", [getPosATL _unit, _noiseType]] call CBA_fnc_serverEvent;
}];

// ============================================================================
// C2 Network: intercepted radio chatter sink (Sprint F.4)
// ============================================================================
// The server decides what the player has earned (coverage tier, suppression
// rules, throttle — see fnc_c2IsrBroadcast) and sends a fully formatted line.
// This handler stays a dumb sink so the gating logic lives in exactly one
// place and every client renders an identical feed.
//
// `systemChat` is deliberate over `hint` or a custom RscTitles layer: it reads
// as ambient radio traffic, it does not steal focus during a firefight, and it
// scales to any volume of traffic. Recorded VO or radio SFX were considered and
// rejected — they become overwhelming the moment the network gets busy, and
// text is the only surface that stays usable at high line rates.
["DSC_c2_chatter", {
    params [["_line", "", [""]]];
    if (_line isEqualTo "") exitWith {};
    systemChat _line;
}] call CBA_fnc_addEventHandler;

// ============================================================================
// Map Draw: Faction Flag Icons for Military Installations
// ============================================================================
// Renders faction flag textures from CfgFactionClasses on the map.
// Data published by server Step 4 as DSC_baseMarkerData / DSC_outpostMarkerData.
// Each entry: [position, name, flagTexture, colorArray]

// On a dedicated server, initPlayerLocal fires before the main map display
// (display 12) exists on the client — attaching a Draw EH to a null control
// silently no-ops. Spawn a waiter that blocks on both the published data and
// the display being alive before wiring the handler.
[] spawn {
    waitUntil { !(isNil { missionNamespace getVariable "DSC_baseMarkerData" }) };
    waitUntil { sleep 0.5; !isNull (findDisplay 12) };

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
};

