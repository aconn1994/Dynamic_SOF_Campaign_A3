#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_resolveMissionConfig
 * Description:
 *     Resolves a partial mission template into a complete mission config.
 *     Takes a template hashmap with optional overrides and fills in all
 *     remaining fields from influence data, faction data, and defaults.
 *
 *     Template fields are resolved in priority order:
 *       1. Explicit template values (highest priority)
 *       2. Mission profile defaults (if "missionProfile" is set)
 *       3. Auto-generated values from influence/faction data (lowest)
 *
 *     This is the core of the mission config system. All mission sources
 *     (random selection, series, player choice, intel) produce templates
 *     that flow through this resolver.
 *
 * Arguments:
 *     0: _template <HASHMAP> - Partial mission template. All fields optional:
 *        --- Core ---
 *        "type"               - Mission type (default: "KILL_CAPTURE")
 *        "missionProfile"     - Profile preset name ("AFO", "DA")
 *        "targetFaction"      - Specific faction classname
 *        "targetRoles"        - Roles to draw target from (default: all enemy)
 *        --- Location Constraints ---
 *        "location"           - Specific location hashmap (skips selection)
 *        "requiredTags"       - Location must have at least one (OR logic)
 *        "excludeTags"        - Location must have none
 *        "regionCenter"       - Position to constrain search area
 *        "regionRadius"       - Radius for region constraint (meters)
 *        "minDistance"         - Minimum distance from player base
 *        "maxDistance"         - Maximum distance from player base
 *        "minBuildingCount"   - Minimum structures at location (default: 3)
 *        --- Generation Parameters ---
 *        "density"            - "light", "medium", "heavy"
 *        "areaPresenceChance" - Base chance for area faction per slot (0-1)
 *        "qrfEnabled"         - Whether QRF can respond
 *        "qrfDelay"           - [min, max] seconds
 *        --- AO Population (passed through to populateAO) ---
 *        "garrisonAnchors"    - [min, max] garrison anchor buildings
 *        "garrisonSatellites" - [min, max] satellite buildings per anchor
 *        "guardCoverage"      - 0.0-1.0 fraction of cluster buildings that get guards
 *        "guardsPerBuilding"  - [min, max] guards at each guarded building
 *        "patrolCount"        - [min, max] target faction patrol groups
 *        "maxVehicles"        - Hard cap on parked vehicles
 *        "vehicleArmedChance" - 0.0-1.0 chance each vehicle is armed
 *
 *     1: _influenceData <HASHMAP> - From fnc_initInfluence
 *     2: _factionData <HASHMAP> - From fnc_initFactionData
 *
 * Return Value:
 *     <HASHMAP> - Complete mission config (same format as fnc_selectMission).
 *                 Empty hashmap on failure.
 *
 * Example:
 *     // Minimal — resolver generates everything
 *     private _config = [createHashMap, _influenceData, _factionData] call DSC_core_fnc_resolveMissionConfig;
 *
 *     // AFO profile — isolated target, light resistance
 *     private _tpl = createHashMapFromArray [["type", "KILL_CAPTURE"], ["missionProfile", "AFO"]];
 *     private _config = [_tpl, _influenceData, _factionData] call DSC_core_fnc_resolveMissionConfig;
 *
 *     // Specific location + faction
 *     private _tpl = createHashMapFromArray [["location", _loc], ["targetFaction", "OPF_G_F"]];
 *     private _config = [_tpl, _influenceData, _factionData] call DSC_core_fnc_resolveMissionConfig;
 */

params [
    ["_template", createHashMap, [createHashMap]],
    ["_influenceData", createHashMap, [createHashMap]],
    ["_factionData", createHashMap, [createHashMap]]
];

if (_influenceData isEqualTo createHashMap || _factionData isEqualTo createHashMap) exitWith {
    diag_log "DSC: resolveMissionConfig - Missing influence or faction data";
    createHashMap
};

// ============================================================================
// 0. Apply mission profile defaults
// ============================================================================
// Profile values fill in where the template has no explicit value.
// Template overrides always win.
private _profileName = _template getOrDefault ["missionProfile", ""];

if (_profileName != "") then {
    private _profiles = call DSC_core_fnc_getMissionProfiles;
    private _profile = _profiles getOrDefault [_profileName, createHashMap];

    if (_profile isEqualTo createHashMap) then {
        diag_log format ["DSC: resolveMissionConfig - Unknown profile: %1", _profileName];
    } else {
        {
            if !(_x in _template) then {
                _template set [_x, _y];
            };
        } forEach _profile;
        diag_log format ["DSC: resolveMissionConfig - Applied profile: %1", _profileName];
    };
};

// ============================================================================
// 1. Read influence data + player base position
// ============================================================================
private _influenceMap = _influenceData get "influenceMap";
private _enrichedLocations = _influenceData get "locations";
private _campaignProfile = _influenceData get "campaignProfile";

private _playerMainBase = missionNamespace getVariable ["playerMainBase", ""];
private _playerBasePos = [worldSize / 2, worldSize / 2, 0];
if (_playerMainBase != "") then {
    if ((markerShape _playerMainBase) != "") then {
        _playerBasePos = getMarkerPos _playerMainBase;
    };
};

// ============================================================================
// 2. Resolve mission type
// ============================================================================
private _missionType = _template getOrDefault ["type", "KILL_CAPTURE"];

// ============================================================================
// 3. Resolve location
// ============================================================================
// If template provides a location, use it directly.
// Otherwise: filter enriched locations by constraints and select.
private _selectedLocation = _template getOrDefault ["location", createHashMap];
private _needsLocationSelection = _selectedLocation isEqualTo createHashMap;
private _candidateLocations = [];

if (_needsLocationSelection) then {
    // Read filter constraints (profile or template may have set these)
    private _requiredTags = _template getOrDefault ["requiredTags", []];
    private _excludeTags = _template getOrDefault ["excludeTags", ["base", "outpost"]];
    private _regionCenter = _template getOrDefault ["regionCenter", []];
    private _regionRadius = _template getOrDefault ["regionRadius", 0];
    private _minDistance = _template getOrDefault ["minDistance", 0];
    private _maxDistance = _template getOrDefault ["maxDistance", 0];
    private _minBuildingCount = _template getOrDefault ["minBuildingCount", 3];

    // Start with all enriched locations, exclude bluFor and undersized
    _candidateLocations = _enrichedLocations select {
        private _loc = _x;
        private _locId = _loc get "id";
        private _locInf = _influenceMap getOrDefault [_locId, createHashMap];
        private _controlledBy = _locInf getOrDefault ["controlledBy", "neutral"];
        private _buildingCount = _loc get "buildingCount";

        _controlledBy != "bluFor" && { _buildingCount >= _minBuildingCount }
    };

    // Filter by required tags (OR — at least one must be present)
    if (_requiredTags isNotEqualTo []) then {
        _candidateLocations = _candidateLocations select {
            private _locTags = _x get "tags";
            (_requiredTags findIf { _x in _locTags }) != -1
        };
    };

    // Filter by excluded tags (NONE can be present)
    if (_excludeTags isNotEqualTo []) then {
        _candidateLocations = _candidateLocations select {
            private _locTags = _x get "tags";
            (_excludeTags findIf { _x in _locTags }) == -1
        };
    };

    // Filter by region constraint
    if (_regionCenter isNotEqualTo [] && { _regionRadius > 0 }) then {
        _candidateLocations = _candidateLocations select {
            (_x get "position") distance2D _regionCenter < _regionRadius
        };
    };

    // Filter by distance from player base
    if (_minDistance > 0) then {
        _candidateLocations = _candidateLocations select {
            (_x get "position") distance2D _playerBasePos >= _minDistance
        };
    };
    if (_maxDistance > 0) then {
        _candidateLocations = _candidateLocations select {
            (_x get "position") distance2D _playerBasePos <= _maxDistance
        };
    };

    diag_log format ["DSC: resolveMissionConfig - %1 candidate locations (profile: %2, required: %3, excluded: %4)",
        count _candidateLocations, _profileName, _requiredTags, _excludeTags];
};

// Exit if no candidates found
if (_needsLocationSelection && { _candidateLocations isEqualTo [] }) exitWith {
    diag_log format ["DSC: resolveMissionConfig - No valid locations for %1 [%2]", _missionType, _profileName];
    createHashMap
};

// Weighted random selection by distance (closer = more likely)
if (_needsLocationSelection) then {
    private _weightedLocations = _candidateLocations apply {
        private _dist = (_x get "position") distance2D _playerBasePos;
        private _weight = (1 - (_dist / 30000)) max 0.15;
        [_weight, _x]
    };

    private _totalWeight = 0;
    { _totalWeight = _totalWeight + (_x select 0) } forEach _weightedLocations;

    private _roll = random _totalWeight;
    private _runningWeight = 0;
    _selectedLocation = (_weightedLocations select 0) select 1;

    {
        _runningWeight = _runningWeight + (_x select 0);
        if (_runningWeight >= _roll) exitWith {
            _selectedLocation = _x select 1;
        };
    } forEach _weightedLocations;
};

private _selectedId = _selectedLocation get "id";
private _selectedPos = _selectedLocation get "position";
private _selectedName = _selectedLocation get "name";
private _distanceFromBase = _selectedPos distance2D _playerBasePos;
private _locationType = _selectedLocation getOrDefault ["militaryTier", ""];
if (_locationType == "") then {
    _locationType = _selectedLocation get "locType";
};

diag_log format ["DSC: resolveMissionConfig - Location: %1 (%2, %3m from base)", _selectedName, _locationType, round _distanceFromBase];

// ============================================================================
// 4. Read area context from influence
// ============================================================================
private _locInfluence = _influenceMap getOrDefault [_selectedId, createHashMap];
private _areaControlledBy = _locInfluence getOrDefault ["controlledBy", "opFor"];
private _areaFaction = _locInfluence getOrDefault ["faction", ""];
private _areaInfluence = _locInfluence getOrDefault ["influence", 0.5];

// Resolve area faction if influence map didn't assign one
if (_areaFaction == "") then {
    private _roleData = _factionData getOrDefault [_areaControlledBy, createHashMap];
    private _roleFactions = _roleData getOrDefault ["factions", []];
    if (_roleFactions isNotEqualTo []) then {
        _areaFaction = selectRandom _roleFactions;
    };
};

// Determine area side
private _areaSide = east;
{
    private _roleData = _y;
    private _roleFactions = _roleData getOrDefault ["factions", []];
    if (_areaFaction in _roleFactions) exitWith {
        _areaSide = _roleData getOrDefault ["side", east];
    };
} forEach _factionData;

diag_log format ["DSC: resolveMissionConfig - Area: %1 (%2, influence: %3)", _areaFaction, _areaControlledBy, _areaInfluence toFixed 2];

// ============================================================================
// 5. Resolve target faction
// ============================================================================
private _targetFaction = _template getOrDefault ["targetFaction", ""];
private _targetSide = east;
private _targetRole = "";

if (_targetFaction != "") then {
    // Target faction explicitly set — resolve its side and role
    {
        private _role = _x;
        private _roleData = _factionData getOrDefault [_role, createHashMap];
        private _roleFactions = _roleData getOrDefault ["factions", []];
        if (_targetFaction in _roleFactions) exitWith {
            _targetSide = _roleData getOrDefault ["side", east];
            _targetRole = _role;
        };
    } forEach ["opFor", "opForPartner", "irregulars", "bluFor", "bluForPartner"];
} else {
    // Build candidate pool from target roles (profile may have narrowed these)
    private _targetRoles = _template getOrDefault ["targetRoles", ["opFor", "opForPartner", "irregulars"]];
    private _targetCandidates = [];

    {
        private _role = _x;
        private _roleData = _factionData getOrDefault [_role, createHashMap];
        private _roleFactions = _roleData getOrDefault ["factions", []];
        private _roleSide = _roleData getOrDefault ["side", east];
        {
            _targetCandidates pushBack [_x, _roleSide, _role];
        } forEach _roleFactions;
    } forEach _targetRoles;

    if (_targetCandidates isEqualTo []) then {
        // Fallback: try all enemy roles if targeted roles produced nothing
        {
            private _role = _x;
            private _roleData = _factionData getOrDefault [_role, createHashMap];
            private _roleFactions = _roleData getOrDefault ["factions", []];
            private _roleSide = _roleData getOrDefault ["side", east];
            {
                _targetCandidates pushBack [_x, _roleSide, _role];
            } forEach _roleFactions;
        } forEach ["opFor", "opForPartner", "irregulars"];
    };

    if (_targetCandidates isNotEqualTo []) then {
        // Weighted: 30% same as area, 70% different for variety
        private _sameAsArea = _targetCandidates select { (_x select 0) == _areaFaction };
        private _differentFromArea = _targetCandidates select { (_x select 0) != _areaFaction };

        private _targetEntry = [];
        if (_differentFromArea isNotEqualTo [] && { random 1 < 0.7 }) then {
            _targetEntry = selectRandom _differentFromArea;
        } else {
            _targetEntry = selectRandom _targetCandidates;
        };

        _targetFaction = _targetEntry select 0;
        _targetSide = _targetEntry select 1;
        _targetRole = _targetEntry select 2;
    };
};

// Exit if no target faction could be resolved
if (_targetFaction == "") exitWith {
    diag_log format ["DSC: resolveMissionConfig - No enemy factions available (roles: %1)",
        _template getOrDefault ["targetRoles", ["opFor", "opForPartner", "irregulars"]]];
    createHashMap
};

diag_log format ["DSC: resolveMissionConfig - Target: %1 (%2), area: %3", _targetFaction, _targetRole, _areaFaction];

// ============================================================================
// 6. Extract groups + assets for both factions
// ============================================================================
// Target faction
private _targetRoleData = _factionData getOrDefault [_targetRole, createHashMap];
private _targetGroupsAll = _targetRoleData getOrDefault ["groups", createHashMap];
private _targetGroups = _targetGroupsAll getOrDefault [_targetFaction, []];
private _targetAssetsAll = _targetRoleData getOrDefault ["assets", createHashMap];
private _targetAssets = _targetAssetsAll getOrDefault [_targetFaction, createHashMap];

if (_targetGroups isEqualTo []) then {
    diag_log format ["DSC: resolveMissionConfig - No pre-classified groups for %1, extracting fresh", _targetFaction];
    private _rawGroups = [_targetFaction] call DSC_core_fnc_extractGroups;
    _targetGroups = [_rawGroups] call DSC_core_fnc_classifyGroups;
};
if (_targetAssets isEqualTo createHashMap) then {
    _targetAssets = [_targetFaction] call DSC_core_fnc_extractAssets;
};

// Area faction (skip if same as target)
private _areaGroups = [];
private _areaAssets = createHashMap;

if (_areaFaction != _targetFaction) then {
    {
        private _role = _x;
        private _roleData = _factionData getOrDefault [_role, createHashMap];
        private _roleFactions = _roleData getOrDefault ["factions", []];
        if (_areaFaction in _roleFactions) exitWith {
            private _roleGroupsAll = _roleData getOrDefault ["groups", createHashMap];
            _areaGroups = _roleGroupsAll getOrDefault [_areaFaction, []];
            private _roleAssetsAll = _roleData getOrDefault ["assets", createHashMap];
            _areaAssets = _roleAssetsAll getOrDefault [_areaFaction, createHashMap];
        };
    } forEach ["opFor", "opForPartner", "irregulars"];

    if (_areaGroups isEqualTo []) then {
        diag_log format ["DSC: resolveMissionConfig - No pre-classified groups for area faction %1, extracting fresh", _areaFaction];
        private _rawGroups = [_areaFaction] call DSC_core_fnc_extractGroups;
        _areaGroups = [_rawGroups] call DSC_core_fnc_classifyGroups;
    };
    if (_areaAssets isEqualTo createHashMap) then {
        _areaAssets = [_areaFaction] call DSC_core_fnc_extractAssets;
    };
};

diag_log format ["DSC: resolveMissionConfig - Target groups: %1, Area groups: %2", count _targetGroups, count _areaGroups];

// ============================================================================
// 7. Resolve generation parameters
// ============================================================================
private _buildingCount = _selectedLocation get "buildingCount";

// Density: template/profile override, or derive from building count
private _density = _template getOrDefault ["density", ""];
if (_density == "") then {
    _density = switch (true) do {
        case (_buildingCount >= 30): { "heavy" };
        case (_buildingCount >= 10): { "medium" };
        default                     { "light" };
    };
};

private _areaPresenceChance = _template getOrDefault ["areaPresenceChance", 0.7];
private _qrfEnabled = _template getOrDefault ["qrfEnabled", _areaInfluence > 0.3];
private _qrfDelay = _template getOrDefault ["qrfDelay", [120, 180]];

// ============================================================================
// 8. Build mission config
// ============================================================================
private _config = createHashMapFromArray [
    ["type", _missionType],
    ["missionProfile", _profileName],
    ["targetFaction", _targetFaction],
    ["targetSide", _targetSide],
    ["targetGroups", _targetGroups],
    ["targetAssets", _targetAssets],
    ["location", _selectedLocation],
    ["locationType", _locationType],
    ["distanceFromBase", _distanceFromBase],
    ["areaFaction", _areaFaction],
    ["areaSide", _areaSide],
    ["areaInfluence", _areaInfluence],
    ["areaGroups", _areaGroups],
    ["areaAssets", _areaAssets],
    ["density", _density],
    ["areaPresenceChance", _areaPresenceChance],
    ["qrfEnabled", _qrfEnabled],
    ["qrfDelay", _qrfDelay],
    ["campaignProfile", _campaignProfile]
];

// Carry through extra template fields for downstream use (series state, etc.)
{
    if !(_x in _config) then {
        _config set [_x, _y];
    };
} forEach _template;

diag_log format ["DSC: resolveMissionConfig - Config built: %1 [%2] at %3 (target: %4, area: %5, density: %6)",
    _missionType, _profileName, _selectedName, _targetFaction, _areaFaction, _density];

_config
