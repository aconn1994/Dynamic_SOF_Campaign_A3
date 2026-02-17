#include "script_component.hpp"

/*
 * Setup guard positions at a location with static weapons and lookouts.
 * 
 * Guards are defensive units placed at strategic positions:
 * - Military locations: Static weapons or lookouts on Cargo Patrol/Tower structures
 *   - All Patrol/Tower structures get 1 guard (full perimeter coverage)
 *   - 50% chance for static weapon, 50% chance for soldier lookout
 *   - Static weapons limited to 2-3 max per base (spread across structures)
 * - Civilian locations: Checkpoints, roadblocks (placeholder for future)
 * 
 * Arguments:
 *   0: Location position <ARRAY> - Center position [x, y, z]
 *   1: Location type <STRING> - "military" or "civilian"
 *   2: Faction classname <STRING> - e.g. "OPF_F"
 *   3: Side <SIDE> - e.g. east, west, independent
 *   4: (Optional) Config overrides <HASHMAP> - Override default settings
 *      - "maxStatics": Max static weapons for location (default: 2-3)
 *      - "staticChance": Chance per structure for static vs lookout (default: 0.5)
 *      - "radius": Search radius for structures (default: 200)
 * 
 * Returns:
 *   Hashmap containing:
 *     - "units": Array of spawned units
 *     - "vehicles": Array of spawned vehicles (static weapons)
 *     - "groups": Array of created groups
 * 
 * Examples:
 *   [_locationPos, "military", "OPF_F", east] call DSC_core_fnc_setupGuards
 *   [_locationPos, "civilian", "OPF_F", east, createHashMapFromArray [["maxStatics", 1]]] call DSC_core_fnc_setupGuards
 */

params [
    ["_locationPos", [], [[]]],
    ["_locationType", "military", [""]],
    ["_faction", "OPF_F", [""]],
    ["_side", east, [east]],
    ["_configOverrides", createHashMap, [createHashMap]]
];

// Result tracking
private _result = createHashMapFromArray [
    ["units", []],
    ["vehicles", []],
    ["groups", []]
];

if (_locationPos isEqualTo []) exitWith {
    diag_log "DSC: fnc_setupGuards - No location position provided";
    _result
};

// Default config with overrides
private _maxStatics = _configOverrides getOrDefault ["maxStatics", 2 + floor random 2]; // 2-3
private _staticChance = _configOverrides getOrDefault ["staticChance", 0.5];
private _radius = _configOverrides getOrDefault ["radius", 300];

// ============================================================================
// MILITARY LOCATION GUARDS
// ============================================================================
if (_locationType == "military") then {
    // Guard structure types - Patrol and Tower only (HQ is for garrison)
    private _guardStructureTypes = ["Cargo_Patrol_base_F", "Cargo_Tower_base_F"];
    
    // Find guard structures in area
    private _structureCategories = ["BUILDING", "HOUSE", "BUNKER", "FORTRESS", "MILITARY"];
    private _locationStructures = nearestObjects [_locationPos, _structureCategories, _radius];
    
    private _guardStructures = [];
    {
        private _struct = _x;
        {
            if (_struct isKindOf _x) exitWith { 
                _guardStructures pushBack _struct;
            };
        } forEach _guardStructureTypes;
    } forEach _locationStructures;
    
    diag_log format ["DSC: fnc_setupGuards - Found %1 guard structures (Patrol/Tower)", count _guardStructures];
    
    if (_guardStructures isEqualTo []) exitWith {
        diag_log "DSC: fnc_setupGuards - No guard structures found at location";
        _result
    };
    
    // Get static weapons for this faction
    private _factionStaticWeapons = [_faction, "staticWeapons"] call DSC_core_fnc_getFactionAssets;
    private _mgWeapons = (_factionStaticWeapons getOrDefault ["HMG", []]) + (_factionStaticWeapons getOrDefault ["GMG", []]);
    private _launcherWeapons = (_factionStaticWeapons getOrDefault ["AT", []]) + (_factionStaticWeapons getOrDefault ["AA", []]);
    private _allStaticWeapons = _mgWeapons + _launcherWeapons;
    
    // Get default soldier class for lookouts
    private _lookoutClass = switch (_side) do {
        case east: { "O_Soldier_F" };
        case west: { "B_Soldier_F" };
        case independent: { "I_Soldier_F" };
        default { "O_Soldier_F" };
    };
    
    private _staticsSpawned = 0;
    private _lookoutsSpawned = 0;
    
    // Create single group for all guards at this location
    private _guardsGroup = createGroup [_side, true];
    
    // Process each guard structure - ALL get 1 unit for perimeter coverage
    {
        private _structure = _x;
        private _structureClass = typeOf _structure;
        
        // Determine base class for position lookup
        private _baseClass = _structureClass;
        {
            if (_structureClass isKindOf _x) exitWith { _baseClass = _x };
        } forEach _guardStructureTypes;
        
        // Get predefined positions for this structure type
        private _mgPositions = [_baseClass, "MG"] call DSC_core_fnc_getStructurePositions;
        private _launcherPositions = [_baseClass, "LAUNCHER"] call DSC_core_fnc_getStructurePositions;
        private _allPositions = _mgPositions + _launcherPositions;
        
        // Decide: static weapon or lookout soldier
        private _useStatic = random 1 < _staticChance && _staticsSpawned < _maxStatics && (count _allStaticWeapons > 0) && (count _allPositions > 0);
        
        if (_useStatic) then {
            // Spawn static weapon at random position
            private _posType = ["LAUNCHER", "MG"] select ((count _mgPositions > 0) && ((count _launcherPositions == 0) || (random 1 > 0.3)));
            private _weaponClass = if (_posType == "MG") then { selectRandom _mgWeapons } else { selectRandom _launcherWeapons };
            private _positions = [_launcherPositions, _mgPositions] select (_posType == "MG");
            private _posIndex = floor random (count _positions);
            
            private _spawnResult = [_structure, _posType, _weaponClass, _side, _posIndex, true] call DSC_core_fnc_spawnAtStructurePosition;
            private _static = _spawnResult select 0;
            private _crew = _spawnResult select 1;
            
            if (!isNull _static) then {
                (_result get "vehicles") pushBack _static;
                (_result get "units") append _crew;
                { [_x] joinSilent _guardsGroup } forEach _crew;
                _staticsSpawned = _staticsSpawned + 1;
                diag_log format ["DSC: fnc_setupGuards - %1: Static weapon (%2)", _structure, _posType];
            };
        } else {
            // Spawn lookout soldier at highest building position
            private _buildingPositions = _structure buildingPos -1;
            if (count _buildingPositions > 0) then {
                // Sort by height descending, pick highest
                _buildingPositions = [_buildingPositions, [], { -(_x select 2) }, "ASCEND"] call BIS_fnc_sortBy;
                private _lookoutPos = _buildingPositions select 0;
                
                private _lookout = _guardsGroup createUnit [_lookoutClass, _lookoutPos, [], 0, "NONE"];
                _lookout setPos _lookoutPos;
                _lookout setDir (random 360);
                _lookout disableAI "PATH";
                
                (_result get "units") pushBack _lookout;
                _lookoutsSpawned = _lookoutsSpawned + 1;
                diag_log format ["DSC: fnc_setupGuards - %1: Lookout soldier", _structure];
            };
        };
    } forEach _guardStructures;
    
    // Track group if it has units
    if (units _guardsGroup isNotEqualTo []) then {
        (_result get "groups") pushBack _guardsGroup;
        
        // Add combat activation - guards stay in place until shots fired nearby
        [_guardsGroup] call DSC_core_fnc_addCombatActivation;
    } else {
        deleteGroup _guardsGroup;
    };
    
    diag_log format ["DSC: fnc_setupGuards - Total: %1 statics, %2 lookouts", _staticsSpawned, _lookoutsSpawned];
};

// ============================================================================
// CIVILIAN LOCATION GUARDS (PLACEHOLDER)
// ============================================================================
if (_locationType == "civilian") then {
    // TODO: Implement checkpoint/roadblock logic
    // - Find road positions around location
    // - Place vehicles with mounted weapons
    // - Create infantry checkpoints at key intersections
    diag_log "DSC: fnc_setupGuards - Civilian location guard logic not yet implemented";
};

_result
