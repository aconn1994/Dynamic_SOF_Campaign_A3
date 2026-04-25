#include "script_component.hpp"

/*
 * Setup static defenses at military locations — towers, bunkers, static weapons.
 *
 * Scans for dedicated guard structures (patrol towers, bunkers, pillboxes),
 * places static weapons or lookout soldiers at top positions. Military-only.
 *
 * Extracted from fnc_setupGuards to separate static emplacement logic
 * from entry-point guard placement.
 *
 * Arguments:
 *   0: Location position <ARRAY>
 *   1: Faction classname <STRING>
 *   2: Side <SIDE>
 *   3: Config overrides <HASHMAP>
 *      - "assets": Pre-extracted faction assets hashmap
 *      - "structures": Pre-scanned structures from location object
 *      - "maxStatics": Max static weapons to place (default: 2-3)
 *      - "staticChance": Chance per structure for static weapon vs lookout (default: 0.5)
 *      - "maxGuardsPerStructure": Max units per guard structure (default: 1)
 *      - "skillProfile": Skill profile name (default: "cqb_baseline")
 *      - "skillVariance": Per-unit skill variance (default: 0.05)
 *
 * Returns:
 *   Hashmap: "units", "vehicles", "groups"
 *
 * Example:
 *   [_locationPos, "OPF_F", east, _config] call DSC_core_fnc_setupStaticDefenses
 */

params [
    ["_locationPos", [], [[]]],
    ["_faction", "OPF_F", [""]],
    ["_side", east, [east]],
    ["_configOverrides", createHashMap, [createHashMap]]
];

// ============================================================================
// STATIC DEFENSE CONFIG
// ============================================================================
private _config = createHashMapFromArray [
    ["maxStatics", 2 + floor random 2],
    ["staticChance", 0.5],
    ["maxGuardsPerStructure", 1],
    ["skillProfile", "cqb_baseline"],
    ["skillVariance", 0.05]
];

{ _config set [_x, _y] } forEach _configOverrides;

private _result = createHashMapFromArray [
    ["units", []],
    ["vehicles", []],
    ["groups", []]
];

if (_locationPos isEqualTo []) exitWith {
    diag_log "DSC: setupStaticDefenses - No location position";
    _result
};

// ============================================================================
// ASSETS + SOLDIER CLASS
// ============================================================================
private _factionAssets = _config getOrDefault ["assets", createHashMap];
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
private _guardFaction = _config getOrDefault ["guardFaction", _faction];
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

// ============================================================================
// FIND GUARD STRUCTURES
// ============================================================================
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

private _locationStructures = _config getOrDefault ["structures", []];
if (_locationStructures isEqualTo []) then {
    _locationStructures = [_locationPos, ["House", "Building", "Strategic"], 600] call DSC_core_fnc_getMapStructures;
};

private _guardStructures = [];
{
    private _struct = _x;
    { if (_struct isKindOf _x) exitWith { _guardStructures pushBack _struct } } forEach _guardStructureTypes;
} forEach _locationStructures;

diag_log format ["DSC: setupStaticDefenses - Found %1 guard structures", count _guardStructures];

if (_guardStructures isEqualTo []) exitWith {
    diag_log "DSC: setupStaticDefenses - No guard structures found";
    _result
};

// ============================================================================
// PLACE STATIC WEAPONS + LOOKOUTS
// ============================================================================
private _maxStatics = _config get "maxStatics";
private _staticChance = _config get "staticChance";
private _maxGuardsPerStructure = _config get "maxGuardsPerStructure";
private _skillProfile = _config get "skillProfile";
private _skillVariance = _config get "skillVariance";

private _staticsSpawned = 0;
private _lookoutsSpawned = 0;
private _defenseGroup = createGroup [_side, true];

{
    private _structure = _x;
    private _buildingPositions = _structure buildingPos -1;
    if (_buildingPositions isEqualTo []) then { continue };

    // Sort by height descending — top positions first
    _buildingPositions = [_buildingPositions, [], { -(_x select 2) }, "ASCEND"] call BIS_fnc_sortBy;
    private _topPos = _buildingPositions select 0;

    // Check if position has open sky (for static weapons)
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

        private _gunner = _defenseGroup createUnit [_lookoutClass, _topPos, [], 0, "NONE"];
        _gunner allowDamage false;
        _gunner moveInGunner _static;
        [_gunner, _skillProfile, _skillVariance] call DSC_core_fnc_applySkillProfile;
        [{_this allowDamage true}, _gunner, 3] call CBA_fnc_waitAndExecute;

        (_result get "vehicles") pushBack _static;
        (_result get "units") pushBack _gunner;
        _staticsSpawned = _staticsSpawned + 1;

        diag_log format ["DSC: setupStaticDefenses - %1: Static weapon (%2)", typeOf _structure, _weaponClass];
    } else {
        private _lookout = _defenseGroup createUnit [_lookoutClass, _topPos, [], 0, "NONE"];
        _lookout allowDamage false;
        _lookout setPos _topPos;
        _lookout setDir (_locationPos getDir _topPos);
        _lookout disableAI "PATH";
        [_lookout, _skillProfile, _skillVariance] call DSC_core_fnc_applySkillProfile;
        [{_this allowDamage true}, _lookout, 3] call CBA_fnc_waitAndExecute;

        (_result get "units") pushBack _lookout;
        _lookoutsSpawned = _lookoutsSpawned + 1;

        diag_log format ["DSC: setupStaticDefenses - %1: Lookout%2", typeOf _structure, ["", " (covered)"] select (!_hasOpenSky)];
    };

    // Additional lookouts on remaining positions
    private _extraPositions = if ((count _buildingPositions) > 1) then {
        _buildingPositions select [1, (_maxGuardsPerStructure - 1) min ((count _buildingPositions) - 1)]
    } else {
        []
    };

    {
        private _extraPos = _x;
        private _lookout = _defenseGroup createUnit [_lookoutClass, _extraPos, [], 0, "NONE"];
        _lookout allowDamage false;
        _lookout setPos _extraPos;
        _lookout setDir (_locationPos getDir _extraPos);
        _lookout disableAI "PATH";
        [_lookout, _skillProfile, _skillVariance] call DSC_core_fnc_applySkillProfile;
        [{_this allowDamage true}, _lookout, 3] call CBA_fnc_waitAndExecute;

        (_result get "units") pushBack _lookout;
        _lookoutsSpawned = _lookoutsSpawned + 1;
    } forEach _extraPositions;
} forEach _guardStructures;

// ============================================================================
// FINALIZE
// ============================================================================
if ((units _defenseGroup) isNotEqualTo []) then {
    (_result get "groups") pushBack _defenseGroup;
    [_defenseGroup] call DSC_core_fnc_addCombatActivation;
} else {
    deleteGroup _defenseGroup;
};

diag_log format ["DSC: setupStaticDefenses - Complete: %1 statics, %2 lookouts",
    _staticsSpawned, _lookoutsSpawned];

_result
