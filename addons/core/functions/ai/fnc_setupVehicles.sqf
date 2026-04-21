#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_setupVehicles
 * Description:
 *     Spawns parked faction vehicles near garrisoned building clusters.
 *     Armed vehicles get a gunner as a mounted sentry with combat activation.
 *     Unarmed vehicles are ambient presence (future hooks: HVT flee, player use).
 *
 * Arguments:
 *     0: _locationPos <ARRAY> - Center position [x, y, z]
 *     1: _faction <STRING> - Faction classname
 *     2: _side <SIDE> - Side for vehicle crew
 *     3: _config <HASHMAP> - Configuration:
 *        - "assets": Pre-extracted faction assets (default: extract fresh)
 *        - "structures": Structures to park near (default: [])
 *        - "density": "light", "medium", "heavy" (default: "medium")
 *        - "maxVehicles": Hard cap on total vehicles (default: 4)
 *        - "armedChance": Chance for armed vehicle per slot (default: 0.3)
 *
 * Return Value:
 *     <HASHMAP>:
 *        "vehicles"       - All spawned vehicles
 *        "units"          - All spawned crew (gunners)
 *        "groups"         - Groups containing crew
 *        "parkedVehicles" - Vehicles with their positions (for future flee logic)
 *
 * Example:
 *     private _vehResult = [_pos, "OPF_F", east, _config] call DSC_core_fnc_setupVehicles;
 */

params [
    ["_locationPos", [], [[]]],
    ["_faction", "OPF_F", [""]],
    ["_side", east, [east]],
    ["_config", createHashMap, [createHashMap]]
];

private _result = createHashMapFromArray [
    ["vehicles", []],
    ["units", []],
    ["groups", []],
    ["parkedVehicles", []]
];

if (_locationPos isEqualTo []) exitWith {
    diag_log "DSC: fnc_setupVehicles - No location position provided";
    _result
};

// ============================================================================
// Configuration
// ============================================================================
private _factionAssets = _config getOrDefault ["assets", createHashMap];
if (_factionAssets isEqualTo createHashMap) then {
    _factionAssets = [_faction] call DSC_core_fnc_extractAssets;
};

private _structures = _config getOrDefault ["structures", []];
private _density = _config getOrDefault ["density", "medium"];
private _maxVehicles = _config getOrDefault ["maxVehicles", 4];
private _armedChance = _config getOrDefault ["armedChance", 0.3];

// Build vehicle pools
private _cars = _factionAssets getOrDefault ["cars", createHashMap];
private _trucks = _factionAssets getOrDefault ["trucks", []];
private _unarmedPool = (_cars getOrDefault ["unarmed", []]) + _trucks;
private _armedPool = (_cars getOrDefault ["armed", []]) + (_cars getOrDefault ["mrap", []]);

if (_unarmedPool isEqualTo [] && _armedPool isEqualTo []) exitWith {
    diag_log format ["DSC: fnc_setupVehicles - No vehicles available for faction %1", _faction];
    _result
};

// Target vehicle count based on density
private _targetCount = switch (_density) do {
    case "light":  { 1 };
    case "medium": { 1 + floor random 2 };
    case "heavy":  { 2 + floor random 2 };
    default        { 1 };
};
_targetCount = _targetCount min _maxVehicles;

// ============================================================================
// Cluster structures for parking position search
// ============================================================================
// Group structures into clusters (same logic as guard compound clustering)
private _clustered = createHashMap;
private _clusters = [];

{
    private _struct = _x;
    private _strKey = str _struct;
    if (_strKey in _clustered) then { continue };

    private _cluster = [_struct];
    private _queue = [_struct];
    _clustered set [_strKey, true];

    while { _queue isNotEqualTo [] } do {
        private _current = _queue deleteAt 0;
        {
            private _nearKey = str _x;
            if !(_nearKey in _clustered) then {
                if (_x distance2D _current < 50) then {
                    _clustered set [_nearKey, true];
                    _cluster pushBack _x;
                    _queue pushBack _x;
                };
            };
        } forEach _structures;
    };

    _clusters pushBack _cluster;
} forEach _structures;

// Sort by size descending — park at the larger clusters
_clusters = [_clusters, [], { -(count _x) }, "ASCEND"] call BIS_fnc_sortBy;

diag_log format ["DSC: fnc_setupVehicles - %1 clusters, targeting %2 vehicles", count _clusters, _targetCount];

// ============================================================================
// Spawn vehicles at clusters
// ============================================================================
private _crewGroup = createGroup [_side, true];
private _vehiclesSpawned = 0;

{
    if (_vehiclesSpawned >= _targetCount) exitWith {};

    private _cluster = _x;

    // Calculate cluster center
    private _sumX = 0; private _sumY = 0;
    { _sumX = _sumX + (getPos _x select 0); _sumY = _sumY + (getPos _x select 1) } forEach _cluster;
    private _clusterCenter = [_sumX / count _cluster, _sumY / count _cluster, 0];

    // Find parking spots near this cluster
    private _spotsNeeded = [1, 2] select (count _cluster >= 5 && _vehiclesSpawned + 1 < _targetCount);
    private _parkingSpots = [_clusterCenter, 50, _spotsNeeded] call DSC_core_fnc_findParkingPosition;

    {
        if (_vehiclesSpawned >= _targetCount) exitWith {};

        _x params ["_parkPos", "_parkDir"];

        // Decide armed vs unarmed
        private _useArmed = random 1 < _armedChance && { _armedPool isNotEqualTo [] };
        private _vehicleClass = if (_useArmed) then {
            selectRandom _armedPool
        } else {
            if (_unarmedPool isNotEqualTo []) then {
                selectRandom _unarmedPool
            } else {
                selectRandom _armedPool
            };
        };

        // Spawn vehicle
        private _vehicle = createVehicle [_vehicleClass, _parkPos, [], 0, "NONE"];
        _vehicle setPos _parkPos;
        _vehicle setDir _parkDir;
        _vehicle setFuel (0.3 + random 0.5);
        _vehicle engineOn false;

        (_result get "vehicles") pushBack _vehicle;
        (_result get "parkedVehicles") pushBack [_vehicle, _parkPos, _parkDir];

        // If armed, add a gunner
        if (_useArmed) then {
            private _turrets = fullCrew [_vehicle, "gunner", true];
            if (_turrets isNotEqualTo []) then {
                private _lookoutClass = "";
                private _filterStr = format [
                    "getNumber (_x >> 'scope') >= 2 && getText (_x >> 'faction') == '%1' && getNumber (_x >> 'isMan') == 1",
                    _faction
                ];
                private _factionMen = _filterStr configClasses (configFile >> "CfgVehicles");
                _lookoutClass = if (_factionMen isNotEqualTo []) then {
                    configName (selectRandom _factionMen)
                } else {
                    ["O_Soldier_F", "B_Soldier_F", "I_Soldier_F"] select ([0, 1, 2] select {
                        [east, west, independent] select _x == _side
                    } select 0)
                };

                private _gunner = _crewGroup createUnit [_lookoutClass, _parkPos, [], 0, "NONE"];
                _gunner moveInGunner _vehicle;
                (_result get "units") pushBack _gunner;

                diag_log format ["DSC: fnc_setupVehicles - Armed %1 at %2 (gunner: %3)", _vehicleClass, _parkPos, _lookoutClass];
            } else {
                diag_log format ["DSC: fnc_setupVehicles - Armed %1 at %2 (no gunner turret)", _vehicleClass, _parkPos];
            };
        } else {
            diag_log format ["DSC: fnc_setupVehicles - Parked %1 at %2", _vehicleClass, _parkPos];
        };

        _vehiclesSpawned = _vehiclesSpawned + 1;
    } forEach _parkingSpots;
} forEach _clusters;

// ============================================================================
// Finalize
// ============================================================================
if (units _crewGroup isNotEqualTo []) then {
    (_result get "groups") pushBack _crewGroup;
    [_crewGroup] call DSC_core_fnc_addCombatActivation;
} else {
    deleteGroup _crewGroup;
};

diag_log format ["DSC: fnc_setupVehicles - Spawned %1 vehicles (%2 with crew)", _vehiclesSpawned, count (_result get "units")];

_result
