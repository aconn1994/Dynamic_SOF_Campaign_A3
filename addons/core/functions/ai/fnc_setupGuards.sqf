#include "script_component.hpp"

/*
 * Setup guard positions at a location with static weapons, lookouts, and overwatch.
 * 
 * Two types of guard positions:
 * 1. Dedicated structures (military) - patrol towers, guard towers, bunkers
 *    → Static weapons or lookouts, open sky check for static placement
 * 2. Overwatch positions (military + civilian) - highest positions in nearby
 *    buildings with line-of-sight to objective center
 *    → Lookout soldiers providing perimeter security
 * 
 * Works with any faction via fnc_extractAssets.
 * 
 * Arguments:
 *   0: Location position <ARRAY> - Center position [x, y, z]
 *   1: Location type <STRING> - "military" or "civilian"
 *   2: Faction classname <STRING> - e.g. "OPF_F"
 *   3: Side <SIDE> - e.g. east, west, independent
 *   4: (Optional) Config overrides <HASHMAP>
 *      - "maxStatics": Max static weapons (default: 2-3)
 *      - "staticChance": Chance per dedicated structure for static (default: 0.5)
 *      - "maxOverwatch": Max overwatch positions (default: 2-4)
 *      - "structures": Pre-scanned structures from location object
 *      - "mainStructures": Pre-classified main structures
 *      - "sideStructures": Pre-classified side structures
 *      - "assets": Pre-extracted faction assets
 * 
 * Returns:
 *   Hashmap: "units", "vehicles", "groups"
 * 
 * Examples:
 *   [_locationPos, "military", "OPF_F", east, _config] call DSC_core_fnc_setupGuards
 *   [_locationPos, "civilian", "OPF_F", east, _config] call DSC_core_fnc_setupGuards
 */

params [
    ["_locationPos", [], [[]]],
    ["_locationType", "military", [""]],
    ["_faction", "OPF_F", [""]],
    ["_side", east, [east]],
    ["_configOverrides", createHashMap, [createHashMap]]
];

private _result = createHashMapFromArray [
    ["units", []],
    ["vehicles", []],
    ["groups", []]
];

if (_locationPos isEqualTo []) exitWith {
    diag_log "DSC: fnc_setupGuards - No location position provided";
    _result
};

private _maxStatics = _configOverrides getOrDefault ["maxStatics", 2 + floor random 2];
private _staticChance = _configOverrides getOrDefault ["staticChance", 0.5];
private _maxOverwatch = _configOverrides getOrDefault ["maxOverwatch", 2 + floor random 3];

// ============================================================================
// Common Setup (faction assets, soldier class)
// ============================================================================
private _factionAssets = _configOverrides getOrDefault ["assets", createHashMap];
if (_factionAssets isEqualTo createHashMap) then {
    _factionAssets = [_faction] call DSC_core_fnc_extractAssets;
};
private _staticWeaponData = _factionAssets get "staticWeapons";
private _mgWeapons = (_staticWeaponData get "HMG") + (_staticWeaponData get "GMG");
private _launcherWeapons = (_staticWeaponData get "AT") + (_staticWeaponData get "AA");
private _allStaticWeapons = _mgWeapons + _launcherWeapons;

private _highMG = _mgWeapons select { "high" in toLower _x || "TriPod" in _x };
if (_highMG isEqualTo []) then { _highMG = _mgWeapons };

private _lookoutClass = "";
private _filterStr = format ["getNumber (_x >> 'scope') >= 2 && getText (_x >> 'faction') == '%1' && getNumber (_x >> 'isMan') == 1", _faction];
private _factionMen = _filterStr configClasses (configFile >> "CfgVehicles");
if (_factionMen isNotEqualTo []) then {
    _lookoutClass = configName (selectRandom _factionMen);
} else {
    _lookoutClass = switch (_side) do {
        case east: { "O_Soldier_F" };
        case west: { "B_Soldier_F" };
        case independent: { "I_Soldier_F" };
        default { "O_Soldier_F" };
    };
};

private _staticsSpawned = 0;
private _lookoutsSpawned = 0;
private _guardsGroup = createGroup [_side, true];

// ============================================================================
// PHASE 1: Dedicated Guard Structures (military locations only)
// ============================================================================
if (_locationType == "military") then {
    private _guardStructureTypes = [
        "Cargo_Patrol_base_F",
        "Cargo_Tower_base_F",
        "Land_GuardTower_01_F",
        "Land_GuardTower_02_F",
        "Land_Bunker_01_small_F",
        "Land_Bunker_02_right_F",
        "Land_Bunker_02_left_F",
        "Land_Bunker_02_double_F",
        "Land_Bunker_02_light_double_F",
        "Land_Bunker_02_light_left_F",
        "Land_Bunker_02_light_right_F",
        "Land_PillboxBunker_01_big_F",
        "Land_PillboxBunker_01_rectangle_F",
        "Land_PillboxBunker_01_hex_F"
    ];
    
    private _locationStructures = _configOverrides getOrDefault ["structures", []];
    if (_locationStructures isEqualTo []) then {
        _locationStructures = [_locationPos, ["House", "Building", "Strategic"], 600] call DSC_core_fnc_getMapStructures;
    };
    
    private _guardStructures = [];
    {
        private _struct = _x;
        { if (_struct isKindOf _x) exitWith { _guardStructures pushBack _struct } } forEach _guardStructureTypes;
    } forEach _locationStructures;
    
    diag_log format ["DSC: fnc_setupGuards - Found %1 dedicated guard structures", count _guardStructures];
    
    {
        private _structure = _x;
        private _buildingPositions = _structure buildingPos -1;
        if (_buildingPositions isEqualTo []) then { continue };
        
        _buildingPositions = [_buildingPositions, [], { -(_x select 2) }, "ASCEND"] call BIS_fnc_sortBy;
        private _topPos = _buildingPositions select 0;
        
        private _checkFrom = _topPos vectorAdd [0, 0, 0.5];
        private _checkTo = _topPos vectorAdd [0, 0, 5];
        private _intersections = lineIntersectsSurfaces [_checkFrom, _checkTo, objNull, objNull, true, 1];
        private _hasOpenSky = _intersections isEqualTo [];
        
        private _useStatic = random 1 < _staticChance && _staticsSpawned < _maxStatics && _allStaticWeapons isNotEqualTo [];
        
        if (_useStatic && _hasOpenSky) then {
            private _weaponClass = if (_highMG isNotEqualTo [] && (random 1 > 0.3 || _launcherWeapons isEqualTo [])) then {
                selectRandom _highMG
            } else {
                if (_launcherWeapons isNotEqualTo []) then { selectRandom _launcherWeapons } else { selectRandom _highMG }
            };
            
            private _dirFromCenter = _locationPos getDir _topPos;
            private _static = createVehicle [_weaponClass, _topPos, [], 0, "NONE"];
            _static setPos _topPos;
            _static setDir _dirFromCenter;
            
            private _gunner = _guardsGroup createUnit [_lookoutClass, _topPos, [], 0, "NONE"];
            _gunner moveInGunner _static;
            
            (_result get "vehicles") pushBack _static;
            (_result get "units") pushBack _gunner;
            _staticsSpawned = _staticsSpawned + 1;
            diag_log format ["DSC: fnc_setupGuards - %1: Static weapon (%2)", typeOf _structure, _weaponClass];
        } else {
            private _lookout = _guardsGroup createUnit [_lookoutClass, _topPos, [], 0, "NONE"];
            _lookout setPos _topPos;
            _lookout setDir (_locationPos getDir _topPos);
            _lookout disableAI "PATH";
            
            (_result get "units") pushBack _lookout;
            _lookoutsSpawned = _lookoutsSpawned + 1;
            diag_log format ["DSC: fnc_setupGuards - %1: Lookout soldier%2", typeOf _structure, ["", " (covered)"] select (!_hasOpenSky)];
        };
    } forEach _guardStructures;
};

// ============================================================================
// PHASE 2: Perimeter Security (military AND civilian)
// ============================================================================
// Place sentries around the edge of the structure cluster facing outward.
// Search for nearby concealment (trees, walls, bushes) for natural positioning.
private _mainStructures = _configOverrides getOrDefault ["mainStructures", []];
private _sideStructures = _configOverrides getOrDefault ["sideStructures", []];
private _allBuildings = _mainStructures + _sideStructures;

private _maxPerimeter = _configOverrides getOrDefault ["maxPerimeter", 3 + floor random 3]; // 3-5
private _perimeterSpawned = 0;

if (_allBuildings isNotEqualTo []) then {
    // Calculate cluster radius from structures
    private _clusterRadius = 0;
    {
        private _dist = _x distance2D _locationPos;
        if (_dist > _clusterRadius) then { _clusterRadius = _dist };
    } forEach _allBuildings;
    
    // Perimeter ring sits just outside the structure cluster
    private _perimeterDist = (_clusterRadius + 20) max 30;
    
    // Generate evenly spaced positions around perimeter
    private _numPoints = _maxPerimeter + 2; // Generate extras for selection
    private _angleStep = 360 / _numPoints;
    private _startAngle = random 360;
    
    private _perimeterCandidates = [];
    
    for "_i" from 0 to (_numPoints - 1) do {
        private _angle = _startAngle + (_i * _angleStep);
        private _rawPos = _locationPos getPos [_perimeterDist, _angle];
        _rawPos set [2, 0];
        
        // Get terrain height at this position
        private _terrainPos = ATLToASL _rawPos;
        _rawPos = ASLToATL _terrainPos;
        
        // Search for concealment within 20m of the perimeter point
        private _concealmentTypes = ["TREE", "BUSH", "WALL", "FENCE", "HIDE"];
        private _nearbyConcealment = nearestTerrainObjects [_rawPos, _concealmentTypes, 20];
        
        private _finalPos = _rawPos;
        private _concealmentType = "open";
        
        if (_nearbyConcealment isNotEqualTo []) then {
            // Move to nearest concealment object, offset slightly toward objective
            private _concealObj = _nearbyConcealment select 0;
            private _concealPos = getPos _concealObj;
            private _dirToCenter = _concealPos getDir _locationPos;
            _finalPos = _concealPos getPos [2, _dirToCenter];
            _finalPos set [2, 0];
            _concealmentType = "concealed";
        };
        
        // Check position is not underwater or inside a building
        if (surfaceIsWater _finalPos) then { continue };
        
        _perimeterCandidates pushBack [_finalPos, _concealmentType, _angle];
    };
    
    // Shuffle and pick spread-out positions
    _perimeterCandidates = _perimeterCandidates call BIS_fnc_arrayShuffle;
    private _usedPositions = [];
    
    {
        if (_perimeterSpawned >= _maxPerimeter) exitWith {};
        
        _x params ["_sentryPos", "_concealType", "_angle"];
        
        // Don't cluster sentries
        private _tooClose = false;
        { if (_sentryPos distance2D _x < 20) exitWith { _tooClose = true } } forEach _usedPositions;
        if (_tooClose) then { continue };
        
        // Spawn sentry pair (2 units)
        private _sentry1 = _guardsGroup createUnit [_lookoutClass, _sentryPos, [], 0, "NONE"];
        _sentry1 setPos _sentryPos;
        _sentry1 setDir ((_sentryPos getDir _locationPos) + 180);
        _sentry1 disableAI "PATH";
        _sentry1 setUnitPos "MIDDLE";
        
        // Second sentry offset slightly, facing inward
        private _sentry2Pos = _sentryPos getPos [3, _sentryPos getDir _locationPos];
        private _sentry2 = _guardsGroup createUnit [_lookoutClass, _sentry2Pos, [], 0, "NONE"];
        _sentry2 setPos _sentry2Pos;
        _sentry2 setDir (_sentry2Pos getDir _locationPos); // Face inward
        _sentry2 disableAI "PATH";
        _sentry2 setUnitPos "MIDDLE";
        
        (_result get "units") pushBack _sentry1;
        (_result get "units") pushBack _sentry2;
        _usedPositions pushBack _sentryPos;
        _perimeterSpawned = _perimeterSpawned + 1;
        
        diag_log format ["DSC: fnc_setupGuards - Perimeter sentry pair at %1 (%2)", _sentryPos, _concealType];
    } forEach _perimeterCandidates;
};

// ============================================================================
// Finalize
// ============================================================================
if (units _guardsGroup isNotEqualTo []) then {
    (_result get "groups") pushBack _guardsGroup;
    [_guardsGroup] call DSC_core_fnc_addCombatActivation;
} else {
    deleteGroup _guardsGroup;
};

diag_log format ["DSC: fnc_setupGuards - Total: %1 statics, %2 lookouts, %3 perimeter pairs", _staticsSpawned, _lookoutsSpawned, _perimeterSpawned];

_result
