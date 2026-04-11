#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_populateAO
 * Description:
 *     Populates a location with enemy forces. Reads pre-classified structures
 *     directly from the location object (no re-scanning). Spawns guards,
 *     garrison, and patrols appropriate to the location's tags and size.
 *
 *     This is mission-type agnostic - it just fills an area with enemies.
 *     Mission objectives (HVT, sabotage targets, etc.) are layered on top.
 *
 * Arguments:
 *     0: _location <HASHMAP> - Location object from fnc_scanLocations
 *     1: _classifiedGroups <ARRAY> - Pre-classified group data
 *     2: _config <HASHMAP> - Optional configuration overrides
 *        - "faction": OpFor faction classname (default: from missionNamespace)
 *        - "side": OpFor side (default: east)
 *        - "density": "light", "medium", "heavy" (default: derived from location tags)
 *        - "patrolCount": [min, max] override
 *        - "garrisonDensity": override for garrison density string
 *
 * Return Value:
 *     <HASHMAP> - Populated AO data:
 *        "location"       - The original location object
 *        "groups"         - All spawned groups
 *        "units"          - All spawned units
 *        "vehicles"       - All spawned vehicles (static weapons etc.)
 *        "defenderUnits"  - Guard + garrison units (for combat response triggers)
 *        "patrolGroups"   - Patrol groups specifically (for QRF convergence)
 *        "garrisonUnits"  - Garrison units specifically (for HVT placement)
 *        "tags"           - Doctrine tags per group (parallel to groups)
 *
 * Example:
 *     private _ao = [_location, _classifiedGroups] call DSC_core_fnc_populateAO;
 */

params [
    ["_location", createHashMap, [createHashMap]],
    ["_classifiedGroups", [], [[]]],
    ["_config", createHashMap, [createHashMap]]
];

// ============================================================================
// Configuration
// ============================================================================
private _opForFaction = _config getOrDefault ["faction", missionNamespace getVariable ["opForFaction", "OPF_F"]];
private _opForSide = _config getOrDefault ["side", east];

// Read from location object
private _locationPos = _location get "position";
private _locationName = _location get "name";
private _locationRadius = _location get "radius";
private _locationTags = _location get "tags";
private _mainStructures = _location get "mainStructures";
private _sideStructures = _location get "sideStructures";
private _milCount = _location get "militaryCount";
private _buildingCount = _location get "buildingCount";

// Determine density from location tags if not overridden
private _density = _config getOrDefault ["density", ""];
if (_density == "") then {
    _density = if ("high_density" in _locationTags) then {
        "heavy"
    } else {
        ["light", "medium"] select ("medium_density" in _locationTags)
    };
};

diag_log format ["DSC: populateAO - %1 (%2 buildings, density: %3, tags: %4)", 
    _locationName, _buildingCount, _density, _locationTags];

// ============================================================================
// Result tracking
// ============================================================================
private _aoResult = createHashMapFromArray [
    ["location", _location],
    ["groups", []],
    ["units", []],
    ["vehicles", []],
    ["defenderUnits", []],
    ["patrolGroups", []],
    ["garrisonUnits", []],
    ["tags", []]
];

if (_locationPos isEqualTo []) exitWith {
    diag_log "DSC: populateAO - No location position provided";
    _aoResult
};

// ============================================================================
// Get Group Classifications
// ============================================================================
private _basicInfantrySquadGroups = [_classifiedGroups, ["FOOT", "INFANTRY_SQUAD", "PATROL"], ["ELITE", "SCOUT_RECON", "AMPHIBIOUS"]] call DSC_core_fnc_getGroupsByTag;
private _basicInfantryFireteamGroups = [_classifiedGroups, ["FOOT", "FIRETEAM", "PATROL"], ["ELITE", "SCOUT_RECON", "AMPHIBIOUS"]] call DSC_core_fnc_getGroupsByTag;
private _eliteInfantrySquadGroups = [_classifiedGroups, ["FOOT", "INFANTRY_SQUAD", "PATROL", "ELITE"], ["SCOUT_RECON", "AMPHIBIOUS"]] call DSC_core_fnc_getGroupsByTag;
private _eliteInfantryFireteamGroups = [_classifiedGroups, ["FOOT", "FIRETEAM", "PATROL", "ELITE"], ["SCOUT_RECON", "AMPHIBIOUS"]] call DSC_core_fnc_getGroupsByTag;
private _atInfantryGroups = [_classifiedGroups, ["FOOT", "AT_TEAM"], ["AMPHIBIOUS"]] call DSC_core_fnc_getGroupsByTag;
private _aaInfantryGroups = [_classifiedGroups, ["FOOT", "AA_TEAM"], ["AMPHIBIOUS"]] call DSC_core_fnc_getGroupsByTag;

private _garrisonTemplates = _basicInfantrySquadGroups + _basicInfantryFireteamGroups + _eliteInfantrySquadGroups + _eliteInfantryFireteamGroups;
private _specialGroups = _atInfantryGroups + _aaInfantryGroups;

// ============================================================================
// GUARDS (Static weapons on towers - military locations only)
// ============================================================================
if ("military" in _locationTags) then {
    private _guardResult = [_locationPos, "military", _opForFaction, _opForSide] call DSC_core_fnc_setupGuards;
    
    private _guardGroups = _guardResult get "groups";
    private _guardUnits = _guardResult get "units";
    private _guardVehicles = _guardResult get "vehicles";
    
    (_aoResult get "groups") append _guardGroups;
    (_aoResult get "units") append _guardUnits;
    (_aoResult get "vehicles") append _guardVehicles;
    (_aoResult get "defenderUnits") append _guardUnits;
    
    diag_log format ["DSC: populateAO - Guards: %1 units, %2 vehicles", count _guardUnits, count _guardVehicles];
};

// ============================================================================
// GARRISON (Infantry in structures)
// ============================================================================
if (_garrisonTemplates isNotEqualTo [] && _mainStructures isNotEqualTo []) then {
    private _garrisonConfig = createHashMapFromArray [
        ["density", _config getOrDefault ["garrisonDensity", _density]],
        ["mainStructures", _mainStructures],
        ["sideStructures", _sideStructures]
    ];
    
    private _garrisonResult = [_locationPos, _garrisonTemplates, _opForSide, _garrisonConfig] call DSC_core_fnc_setupGarrison;
    
    private _garrisonGroups = _garrisonResult get "groups";
    private _garrisonUnits = _garrisonResult get "units";
    private _garrisonTags = _garrisonResult get "tags";
    
    (_aoResult get "groups") append _garrisonGroups;
    (_aoResult get "units") append _garrisonUnits;
    (_aoResult get "defenderUnits") append _garrisonUnits;
    (_aoResult get "garrisonUnits") append _garrisonUnits;
    (_aoResult get "tags") append _garrisonTags;
    
    diag_log format ["DSC: populateAO - Garrison: %1 units in %2 groups", count _garrisonUnits, count _garrisonGroups];
} else {
    if (_mainStructures isEqualTo []) then {
        diag_log "DSC: populateAO - No main structures, skipping garrison";
    };
};

// ============================================================================
// PATROLS (Mobile units around perimeter)
// ============================================================================
private _patrolTemplates = _garrisonTemplates;
if (_patrolTemplates isNotEqualTo []) then {
    // Scale patrol count to location size
    private _patrolCount = _config getOrDefault ["patrolCount", []];
    if (_patrolCount isEqualTo []) then {
        _patrolCount = switch (_density) do {
            case "light": { [1, 1] };
            case "medium": { [1, 2] };
            case "heavy": { [2, 3] };
            default { [1, 2] };
        };
    };
    
    // Scale patrol radius to location radius
    private _patrolSpawnMin = (_locationRadius max 100) min 300;
    private _patrolSpawnMax = (_patrolSpawnMin + 200) min 400;
    private _patrolWaypointMin = _patrolSpawnMin + 50;
    private _patrolWaypointMax = _patrolSpawnMax + 100;
    
    private _patrolConfig = createHashMapFromArray [
        ["patrolCount", _patrolCount],
        ["spawnRadius", [_patrolSpawnMin, _patrolSpawnMax]],
        ["patrolRadius", [_patrolWaypointMin, _patrolWaypointMax]],
        ["specialGroups", _specialGroups],
        ["specialChance", 0.15]
    ];
    
    private _patrolResult = [_locationPos, _patrolTemplates, _opForSide, _patrolConfig] call DSC_core_fnc_setupPatrols;
    
    private _patrolGroupsSpawned = _patrolResult get "groups";
    private _patrolUnits = _patrolResult get "units";
    private _patrolTags = _patrolResult get "tags";
    
    (_aoResult get "groups") append _patrolGroupsSpawned;
    (_aoResult get "units") append _patrolUnits;
    (_aoResult get "patrolGroups") append _patrolGroupsSpawned;
    (_aoResult get "tags") append _patrolTags;
    
    diag_log format ["DSC: populateAO - Patrols: %1 units in %2 groups", count _patrolUnits, count _patrolGroupsSpawned];
};

// ============================================================================
// Summary
// ============================================================================
private _totalGroups = count (_aoResult get "groups");
private _totalUnits = count (_aoResult get "units");
private _totalVehicles = count (_aoResult get "vehicles");

diag_log format ["DSC: populateAO - Complete: %1 groups, %2 units, %3 vehicles at %4",
    _totalGroups, _totalUnits, _totalVehicles, _locationName];

_aoResult
