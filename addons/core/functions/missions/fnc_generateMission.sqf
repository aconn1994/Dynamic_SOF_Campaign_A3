#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_generateMission
 * Description:
 *     Orchestrates mission generation from a mission config. Calls subsystems
 *     in order: populate AO → place objective → create briefing → setup QRF.
 *
 *     Currently supports KILL_CAPTURE. Architecture supports future mission types
 *     by dispatching on config "type" field.
 *
 * Arguments:
 *     0: _missionConfig <HASHMAP> - Mission config from fnc_selectMission
 *
 * Return Value:
 *     <HASHMAP> - Mission data (empty hashmap on failure):
 *        "config"          - The original mission config
 *        "ao"              - Populated AO data from fnc_populateAO
 *        "mission"         - Mission-specific data (HVT, markers, etc.)
 *        "taskId"          - Arma task ID for cleanup
 *        "status"          - "ACTIVE"
 *        "startTime"       - serverTime at creation
 *
 * Example:
 *     private _missionData = [_missionConfig] call DSC_core_fnc_generateMission;
 */

params [
    ["_missionConfig", createHashMap, [createHashMap]]
];

if (_missionConfig isEqualTo createHashMap) exitWith {
    diag_log "DSC: fnc_generateMission - No config provided";
    createHashMap
};

private _missionType = _missionConfig get "type";
private _location = _missionConfig get "location";
private _locationName = _location get "name";
private _targetFaction = _missionConfig get "targetFaction";
private _areaFaction = _missionConfig get "areaFaction";

diag_log format ["DSC: ========== Generating %1 Mission at %2 ==========", _missionType, _locationName];

// ============================================================================
// Time/Weather Randomization (commented out for now)
// ============================================================================
// private _hour = selectRandom [0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22];
// private _minute = floor random 60;
// setDate [date select 0, date select 1, date select 2, _hour, _minute];
// 0 setOvercast (random 1);
// 0 setFog ([random 0.3, 0, 0] select (random 1 > 0.7));
// 0 setRain 0;
// forceWeatherChange;
// sleep 1;
// 0 setRain (if (overcast > 0.5) then { random 0.4 } else { 0 });
// diag_log format ["DSC: Time set to %1:%2, overcast: %3", _hour, _minute, overcast];

// ============================================================================
// 1. Populate AO
// ============================================================================
private _ao = [_missionConfig] call DSC_core_fnc_populateAO;

private _aoGroups = _ao get "groups";
private _aoUnits = _ao get "units";

if (_aoUnits isEqualTo []) exitWith {
    diag_log "DSC: fnc_generateMission - AO population produced no units, aborting";
    createHashMap
};

diag_log format ["DSC: fnc_generateMission - AO populated: %1 groups, %2 units", count _aoGroups, count _aoUnits];

// ============================================================================
// 2. Place Objective (dispatch by mission type)
// ============================================================================
private _mission = createHashMap;

switch (_missionType) do {
    case "KILL_CAPTURE": {
        // Build raid config for kill/capture: single OFFICER entity, no
        // objects, KILL_CAPTURE completion, compound markers. Matches the
        // pre-archetype-refactor behavior exactly.
        private _raidConfig = createHashMapFromArray [
            ["entities", [
                createHashMapFromArray [["archetype", "OFFICER"]]
            ]],
            ["objects", []],
            ["completion", "KILL_CAPTURE"],
            ["markerStyle", "compound"],
            ["briefingArchetype", "raid_kill_capture"],
            ["targetFaction", _targetFaction],
            ["targetSide", _missionConfig get "targetSide"]
        ];
        _mission = [_location, _ao, _raidConfig] call DSC_core_fnc_generateRaidMission;
    };

    case "SUPPLY_DESTROY": {
        // No HVT — destroy supply caches + outdoor weapons crates.
        private _raidConfig = createHashMapFromArray [
            ["entities", []],
            ["objects", [
                createHashMapFromArray [["archetype", "SUPPLY_CACHE"], ["count", [4, 8]]],
                createHashMapFromArray [["archetype", "WEAPONS_CRATE"], ["count", [1, 3]]]
            ]],
            ["completion", "ALL_DESTROYED"],
            ["markerStyle", "compound"],
            ["briefingArchetype", "raid_supply_destroy"],
            ["targetFaction", _targetFaction],
            ["targetSide", _missionConfig get "targetSide"]
        ];
        _mission = [_location, _ao, _raidConfig] call DSC_core_fnc_generateRaidMission;
    };

    case "INTEL_GATHER": {
        // Dryhole — no HVT, intel objects placed for player to recover.
        // Completion fires when ANY interactable is used.
        private _raidConfig = createHashMapFromArray [
            ["entities", []],
            ["objects", [
                createHashMapFromArray [["archetype", "INTEL_LAPTOP"]],
                createHashMapFromArray [["archetype", "INTEL_DOCUMENTS"], ["count", [2, 4]]]
            ]],
            ["completion", "ANY_INTERACTED"],
            ["markerStyle", "compound"],
            ["briefingArchetype", "raid_intel_gather"],
            ["targetFaction", _targetFaction],
            ["targetSide", _missionConfig get "targetSide"]
        ];
        _mission = [_location, _ao, _raidConfig] call DSC_core_fnc_generateRaidMission;
    };

    case "HOSTAGE_RESCUE": {
        // 3 hostages placed on the ground in a building; player must keep
        // them alive AND get them within 100m of extractPos (player base
        // flagpole, auto-resolved by the raid generator).
        private _raidConfig = createHashMapFromArray [
            ["entities", [
                createHashMapFromArray [["archetype", "HOSTAGE"], ["count", 3]]
            ]],
            ["objects", []],
            ["completion", "HOSTAGES_EXTRACTED"],
            ["markerStyle", "compound"],
            ["briefingArchetype", "raid_hostage_rescue"],
            ["targetFaction", _targetFaction],
            ["targetSide", _missionConfig get "targetSide"]
        ];
        _mission = [_location, _ao, _raidConfig] call DSC_core_fnc_generateRaidMission;
    };

    // Future mission types:
    // case "RECON": { ... };
    // case "SABOTAGE": { ... };
    // case "DIRECT_ACTION": { ... };
    // case "DEFEND": { ... };
    default {
        diag_log format ["DSC: fnc_generateMission - Unknown mission type: %1", _missionType];
    };
};

if (_mission isEqualTo createHashMap) exitWith {
    diag_log "DSC: fnc_generateMission - Objective placement failed, aborting";
    // Cleanup any spawned AO units
    { if (!isNull _x) then { deleteVehicle _x } } forEach _aoUnits;
    { if (!isNull _x) then { deleteGroup _x } } forEach _aoGroups;
    createHashMap
};

// ============================================================================
// 3. Create Briefing
// ============================================================================
private _taskId = [_mission, _ao, _location] call DSC_core_fnc_createMissionBriefing;

// ============================================================================
// 4. Configure Units
// ============================================================================
// Enable damage on all AO units (garrison spawns with allowDamage false)
private _allUnits = _mission getOrDefault ["units", []];
{ _x allowDamage true } forEach _allUnits;

// Apply skill profile (template override > global setting > default)
private _skillProfile = _missionConfig getOrDefault ["skillProfile", ""];
if (_skillProfile == "") then {
    _skillProfile = missionNamespace getVariable ["DSC_skillProfile", "cqb_baseline"];
};
[_allUnits, _skillProfile] call DSC_core_fnc_applySkillProfile;

// Add to zeus if curator exists
private _curator = (allCurators) select 0;
if (!isNull _curator) then {
    { _curator addCuratorEditableObjects [[_x], true] } forEach allUnits;
};

// ============================================================================
// 5. ISR Drone
// ============================================================================
private _hvtBuilding = _mission getOrDefault ["entityBuilding", objNull];
private _locationPos = _location get "position";
private _uavTargetPos = if (!isNull _hvtBuilding) then { getPos _hvtBuilding } else { _locationPos };
missionNamespace setVariable ["DSC_uavTargetPos", _uavTargetPos, true];

private _activeUAV = missionNamespace getVariable ["DSC_activeUAV", objNull];
if (isNull _activeUAV || { !alive _activeUAV }) then {
    [_uavTargetPos] spawn DSC_core_fnc_persistentUAV;
};

// ============================================================================
// 6. QRF Combat Response
// ============================================================================
// private _qrfEnabled = _missionConfig getOrDefault ["qrfEnabled", true];
// private _patrolGroups = _mission getOrDefault ["patrolGroups", []];
// private _defenderUnits = _mission getOrDefault ["defenderUnits", []];
// private _hvtUnit = _mission getOrDefault ["entity", objNull];

// if (_qrfEnabled && { _patrolGroups isNotEqualTo [] } && { _defenderUnits isNotEqualTo [] }) then {
//     private _qrfDelayRange = _missionConfig getOrDefault ["qrfDelay", [120, 180]];
//     private _qrfDelaySeconds = (_qrfDelayRange select 0) + random ((_qrfDelayRange select 1) - (_qrfDelayRange select 0));

//     private _triggerUnits = +_defenderUnits;
//     if (!isNull _hvtUnit && { !(_hvtUnit in _triggerUnits) }) then {
//         _triggerUnits pushBack _hvtUnit;
//     };

//     {
//         _x addEventHandler ["FiredNear", {
//             params ["_unit", "_firer", "_distance", "_weapon", "_muzzle", "_mode", "_ammo", "_gunner"];

//             private _isPlayerOrSquadmate = isPlayer _gunner || { isPlayer (leader group _gunner) };
//             if (!_isPlayerOrSquadmate) exitWith {};

//             private _curMission = missionNamespace getVariable ["DSC_currentMission", createHashMap];
//             if (_curMission isEqualTo createHashMap) exitWith {};
//             if (_curMission getOrDefault ["combatResponseTriggered", false]) exitWith {};

//             _curMission set ["combatResponseTriggered", true];
//             missionNamespace setVariable ["DSC_currentMission", _curMission, true];

//             private _mPatrolGroups = _curMission getOrDefault ["patrolGroups", []];
//             private _mLocationPos = _curMission getOrDefault ["location", []];
//             private _mQrfDelay = _curMission getOrDefault ["qrfDelay", 120];

//             if (_mPatrolGroups isEqualTo [] || _mLocationPos isEqualTo []) exitWith {};

//             diag_log format ["DSC: QRF dispatched in %1 seconds", _mQrfDelay];

//             [_mPatrolGroups, _mLocationPos, _mQrfDelay] spawn {
//                 params ["_patrols", "_pos", "_delay"];
//                 sleep _delay;

//                 if (!(missionNamespace getVariable ["missionInProgress", false])) exitWith {};

//                 [_patrols, _pos] call DSC_core_fnc_convergePatrols;
//                 systemChat "Enemy QRF is responding to the engagement!";
//                 diag_log "DSC: QRF patrols converging on objective";
//             };

//             private _mTriggerUnits = _curMission getOrDefault ["triggerUnits", []];
//             { _x removeEventHandler ["FiredNear", _thisEventHandler] } forEach _mTriggerUnits;
//         }];
//     } forEach _triggerUnits;

//     _mission set ["qrfDelay", _qrfDelaySeconds];
//     _mission set ["triggerUnits", _triggerUnits];
//     _mission set ["location", _locationPos];
//     _mission set ["patrolGroups", _patrolGroups];

//     diag_log format ["DSC: fnc_generateMission - QRF EH on %1 units (delay: %2s)", count _triggerUnits, _qrfDelaySeconds];
// };

// ============================================================================
// 7. Store and return
// ============================================================================
missionNamespace setVariable ["DSC_currentMission", _mission, true];

private _missionData = createHashMapFromArray [
    ["config", _missionConfig],
    ["ao", _ao],
    ["mission", _mission],
    ["taskId", _taskId],
    ["status", "ACTIVE"],
    ["startTime", serverTime]
];

diag_log format ["DSC: fnc_generateMission - %1 mission READY at %2 (target: %3, area: %4)",
    _missionType, _locationName, _targetFaction, _areaFaction];

_missionData
