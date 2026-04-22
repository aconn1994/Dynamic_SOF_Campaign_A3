#include "script_component.hpp"

/*
 * Setup guard positions at a location with static weapons, lookouts, and sentries.
 * 
 * Two modes based on location type:
 * 1. Military — dedicated guard structures (towers, bunkers) get static weapons
 *    or lookouts + perimeter ring around the full installation
 * 2. Civilian — compound security: sentry pairs placed tight around garrisoned
 *    building clusters, covering entrances and gaps between structures
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
 *      - "maxPerimeter": Max perimeter sentry pairs for military (default: 3-5)
 *      - "maxCompoundGuards": Max sentry pairs per building cluster for civilian (default: 2-3)
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
private _guardFaction = _configOverrides getOrDefault ["guardFaction", _faction];
private _filterStr = format ["getNumber (_x >> 'scope') >= 2 && getText (_x >> 'faction') == '%1' && getNumber (_x >> 'isMan') == 1", _guardFaction];
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

    private _maxGuardsPerStructure = _configOverrides getOrDefault ["maxGuardsPerStructure", 1];

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

        private _useStatic = (random 1 < _staticChance) && (_staticsSpawned < _maxStatics) && (_allStaticWeapons isNotEqualTo []);

        if (_useStatic && _hasOpenSky) then {
            private _weaponClass = if (_highMG isNotEqualTo [] && { random 1 > 0.3 || _launcherWeapons isEqualTo [] }) then {
                selectRandom _highMG
            } else {
                [selectRandom _highMG, selectRandom _launcherWeapons] select (_launcherWeapons isNotEqualTo [])
            };

            private _dirFromCenter = _locationPos getDir _topPos;
            private _static = createVehicle [_weaponClass, _topPos, [], 0, "NONE"];
            _static setPos _topPos;
            _static setDir _dirFromCenter;

            private _gunner = _guardsGroup createUnit [_lookoutClass, _topPos, [], 0, "NONE"];
            _gunner allowDamage false;
            _gunner moveInGunner _static;
            [{_this allowDamage true}, _gunner, 3] call CBA_fnc_waitAndExecute;

            (_result get "vehicles") pushBack _static;
            (_result get "units") pushBack _gunner;
            _staticsSpawned = _staticsSpawned + 1;
            diag_log format ["DSC: fnc_setupGuards - %1: Static weapon (%2)", typeOf _structure, _weaponClass];
        } else {
            private _lookout = _guardsGroup createUnit [_lookoutClass, _topPos, [], 0, "NONE"];
            _lookout allowDamage false;
            _lookout setPos _topPos;
            _lookout setDir (_locationPos getDir _topPos);
            _lookout disableAI "PATH";
            [{_this allowDamage true}, _lookout, 3] call CBA_fnc_waitAndExecute;

            (_result get "units") pushBack _lookout;
            _lookoutsSpawned = _lookoutsSpawned + 1;
            diag_log format ["DSC: fnc_setupGuards - %1: Lookout soldier%2", typeOf _structure, ["", " (covered)"] select (!_hasOpenSky)];
        };

        // Additional lookouts on remaining building positions
        private _extraPositions = if (count _buildingPositions > 1) then {
            _buildingPositions select [1, (_maxGuardsPerStructure - 1) min (count _buildingPositions - 1)]
        } else {
            []
        };

        {
            private _extraPos = _x;
            private _lookout = _guardsGroup createUnit [_lookoutClass, _extraPos, [], 0, "NONE"];
            _lookout allowDamage false;
            _lookout setPos _extraPos;
            _lookout setDir (_locationPos getDir _extraPos);
            _lookout disableAI "PATH";
            [{_this allowDamage true}, _lookout, 3] call CBA_fnc_waitAndExecute;

            (_result get "units") pushBack _lookout;
            _lookoutsSpawned = _lookoutsSpawned + 1;
        } forEach _extraPositions;
    } forEach _guardStructures;
};

// ============================================================================
// PHASE 2: Guard Placement (mode depends on location type)
// ============================================================================
private _mainStructures = _configOverrides getOrDefault ["mainStructures", []];
private _sideStructures = _configOverrides getOrDefault ["sideStructures", []];
private _allBuildings = _mainStructures + _sideStructures;
private _perimeterSpawned = 0;

if (_allBuildings isNotEqualTo [] && _locationType == "military") then {
    // -----------------------------------------------------------------
    // MILITARY: Perimeter ring around the full installation
    // -----------------------------------------------------------------
    private _maxPerimeter = _configOverrides getOrDefault ["maxPerimeter", 3 + floor random 3];

    private _clusterRadius = 0;
    {
        private _dist = _x distance2D _locationPos;
        if (_dist > _clusterRadius) then { _clusterRadius = _dist };
    } forEach _allBuildings;

    private _perimeterDist = (_clusterRadius + 20) max 30;
    private _numPoints = _maxPerimeter + 2;
    private _angleStep = 360 / _numPoints;
    private _startAngle = random 360;

    private _perimeterCandidates = [];

    for "_i" from 0 to (_numPoints - 1) do {
        private _angle = _startAngle + (_i * _angleStep);
        private _rawPos = _locationPos getPos [_perimeterDist, _angle];
        _rawPos set [2, 0];

        private _terrainPos = ATLToASL _rawPos;
        _rawPos = ASLToATL _terrainPos;

        private _concealmentTypes = ["TREE", "BUSH", "WALL", "FENCE", "HIDE"];
        private _nearbyConcealment = nearestTerrainObjects [_rawPos, _concealmentTypes, 20];

        private _finalPos = _rawPos;
        private _concealmentType = "open";

        if (_nearbyConcealment isNotEqualTo []) then {
            private _concealObj = _nearbyConcealment select 0;
            private _concealPos = getPos _concealObj;
            private _dirToCenter = _concealPos getDir _locationPos;
            _finalPos = _concealPos getPos [2, _dirToCenter];
            _finalPos set [2, 0];
            _concealmentType = "concealed";
        };

        if (surfaceIsWater _finalPos) then { continue };

        _perimeterCandidates pushBack [_finalPos, _concealmentType, _angle];
    };

    _perimeterCandidates = _perimeterCandidates call BIS_fnc_arrayShuffle;
    private _usedPositions = [];

    {
        if (_perimeterSpawned >= _maxPerimeter) exitWith {};

        _x params ["_sentryPos", "_concealType", "_angle"];

        private _tooClose = false;
        { if (_sentryPos distance2D _x < 20) exitWith { _tooClose = true } } forEach _usedPositions;
        if (_tooClose) then { continue };

        private _sentry1 = _guardsGroup createUnit [_lookoutClass, _sentryPos, [], 0, "NONE"];
        _sentry1 setPos _sentryPos;
        _sentry1 setDir ((_sentryPos getDir _locationPos) + 180);
        _sentry1 disableAI "PATH";
        _sentry1 setUnitPos "MIDDLE";

        private _sentry2Pos = _sentryPos getPos [3, _sentryPos getDir _locationPos];
        private _sentry2 = _guardsGroup createUnit [_lookoutClass, _sentry2Pos, [], 0, "NONE"];
        _sentry2 setPos _sentry2Pos;
        _sentry2 setDir (_sentry2Pos getDir _locationPos);
        _sentry2 disableAI "PATH";
        _sentry2 setUnitPos "MIDDLE";

        (_result get "units") pushBack _sentry1;
        (_result get "units") pushBack _sentry2;
        _usedPositions pushBack _sentryPos;
        _perimeterSpawned = _perimeterSpawned + 1;

        diag_log format ["DSC: fnc_setupGuards - Perimeter sentry pair at %1 (%2)", _sentryPos, _concealType];
    } forEach _perimeterCandidates;

} else {
    if (_allBuildings isNotEqualTo []) then {
        // -----------------------------------------------------------------
        // CIVILIAN: Compound security — sentries tight around building clusters
        // -----------------------------------------------------------------
        // Find building clusters by grouping structures within 50m of each other.
        // Place 1-2 sentry pairs per cluster, positioned at gaps/entrances
        // between structures facing outward.

        private _maxCompoundGuards = _configOverrides getOrDefault ["maxCompoundGuards", 2 + floor random 2];
        private _compoundGuardsSpawned = 0;

        // Cluster buildings by proximity (50m)
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
                } forEach _allBuildings;
            };

            if (count _cluster >= 1) then {
                _clusters pushBack _cluster;
            };
        } forEach _allBuildings;

        // Sort clusters by size descending — prioritize larger compounds
        _clusters = [_clusters, [], { -(count _x) }, "ASCEND"] call BIS_fnc_sortBy;

        diag_log format ["DSC: fnc_setupGuards - Found %1 building clusters for compound security", count _clusters];

        {
            if (_compoundGuardsSpawned >= _maxCompoundGuards) exitWith {};

            private _cluster = _x;

            // Calculate cluster center and radius
            private _sumX = 0; private _sumY = 0;
            { _sumX = _sumX + (getPos _x select 0); _sumY = _sumY + (getPos _x select 1) } forEach _cluster;
            private _clusterCenter = [_sumX / count _cluster, _sumY / count _cluster, 0];

            private _clusterRadius = 0;
            {
                private _dist = _x distance2D _clusterCenter;
                if (_dist > _clusterRadius) then { _clusterRadius = _dist };
            } forEach _cluster;

            // Guard ring tight around the cluster (5-15m outside structures)
            private _guardDist = (_clusterRadius + 8) max 12;

            // Place 1-2 sentry pairs per cluster depending on size
            private _pairsForCluster = [1, 2] select (count _cluster >= 3);

            // Generate candidate positions around this cluster
            private _numCandidates = _pairsForCluster + 2;
            private _clusterAngleStep = 360 / _numCandidates;
            private _clusterStartAngle = random 360;

            for "_j" from 0 to (_numCandidates - 1) do {
                if (_compoundGuardsSpawned >= _maxCompoundGuards) exitWith {};
                if (_pairsForCluster <= 0) exitWith {};

                private _angle = _clusterStartAngle + (_j * _clusterAngleStep);
                private _rawPos = _clusterCenter getPos [_guardDist, _angle];
                _rawPos set [2, 0];

                if (surfaceIsWater _rawPos) then { continue };

                // Search for concealment near the guard position
                private _concealmentTypes = ["TREE", "BUSH", "WALL", "FENCE", "HIDE"];
                private _nearbyConcealment = nearestTerrainObjects [_rawPos, _concealmentTypes, 12];

                private _finalPos = _rawPos;
                private _concealType = "open";

                if (_nearbyConcealment isNotEqualTo []) then {
                    private _concealObj = _nearbyConcealment select 0;
                    private _concealPos = getPos _concealObj;
                    private _dirToCluster = _concealPos getDir _clusterCenter;
                    _finalPos = _concealPos getPos [1.5, _dirToCluster];
                    _finalPos set [2, 0];
                    _concealType = "concealed";
                };

                // Sentry 1 — faces outward from cluster
                private _sentry1 = _guardsGroup createUnit [_lookoutClass, _finalPos, [], 0, "NONE"];
                _sentry1 setPos _finalPos;
                _sentry1 setDir ((_finalPos getDir _clusterCenter) + 180);
                _sentry1 disableAI "PATH";
                _sentry1 setUnitPos "MIDDLE";

                // Sentry 2 — offset slightly, faces toward cluster (covering buddy's back)
                private _sentry2Pos = _finalPos getPos [3, _finalPos getDir _clusterCenter];
                private _sentry2 = _guardsGroup createUnit [_lookoutClass, _sentry2Pos, [], 0, "NONE"];
                _sentry2 setPos _sentry2Pos;
                _sentry2 setDir (_sentry2Pos getDir _clusterCenter);
                _sentry2 disableAI "PATH";
                _sentry2 setUnitPos "MIDDLE";

                (_result get "units") pushBack _sentry1;
                (_result get "units") pushBack _sentry2;
                _compoundGuardsSpawned = _compoundGuardsSpawned + 1;
                _pairsForCluster = _pairsForCluster - 1;

                diag_log format ["DSC: fnc_setupGuards - Compound sentry pair at %1 (%2, cluster size: %3)", _finalPos, _concealType, count _cluster];
            };
        } forEach _clusters;

        _perimeterSpawned = _compoundGuardsSpawned;
    };
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

diag_log format ["DSC: fnc_setupGuards - Total: %1 statics, %2 lookouts, %3 sentry pairs (%4)",
    _staticsSpawned, _lookoutsSpawned, _perimeterSpawned, _locationType];

_result
