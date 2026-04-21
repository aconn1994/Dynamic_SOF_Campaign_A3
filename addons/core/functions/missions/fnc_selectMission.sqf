#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_selectMission
 * Description:
 *     Builds a mission config by selecting a location, target faction, and area
 *     context from the influence map and faction data. The config drives all
 *     downstream generation (population, objective, briefing, QRF).
 *
 *     Currently only generates KILL_CAPTURE missions. Architecture supports
 *     future mission types, intel-driven selection, and player choice.
 *
 * Arguments:
 *     0: _influenceData <HASHMAP> - From fnc_initInfluence
 *     1: _factionData <HASHMAP> - From fnc_initFactionData
 *
 * Return Value:
 *     <HASHMAP> - Mission config (empty hashmap on failure):
 *        "type"               - Mission type string
 *        "targetFaction"      - Faction classname for the objective
 *        "targetSide"         - Side of target faction
 *        "targetGroups"       - Classified groups for target faction
 *        "targetAssets"       - Extracted assets for target faction
 *        "location"           - Enriched location hashmap
 *        "locationType"       - Location tier string
 *        "distanceFromBase"   - Distance from player main base
 *        "areaFaction"        - Faction that controls the area
 *        "areaSide"           - Side of area faction
 *        "areaInfluence"      - Influence strength 0-1
 *        "areaGroups"         - Classified groups for area faction
 *        "areaAssets"         - Extracted assets for area faction
 *        "density"            - "light", "medium", "heavy"
 *        "areaPresenceChance" - Base chance for area faction per slot
 *        "qrfEnabled"         - Whether QRF can respond
 *        "qrfDelay"           - [min, max] seconds
 *        "campaignProfile"    - Campaign profile string
 *
 * Example:
 *     private _config = [_influenceData, _factionData] call DSC_core_fnc_selectMission;
 */

params [
    ["_influenceData", createHashMap, [createHashMap]],
    ["_factionData", createHashMap, [createHashMap]]
];

if (_influenceData isEqualTo createHashMap || _factionData isEqualTo createHashMap) exitWith {
    diag_log "DSC: fnc_selectMission - Missing influence or faction data";
    createHashMap
};

private _influenceMap = _influenceData get "influenceMap";
private _enrichedLocations = _influenceData get "locations";
private _campaignProfile = _influenceData get "campaignProfile";
private _camps = _influenceData get "camps";
private _missionSites = _influenceData get "missionSites";
private _populatedAreas = _influenceData get "populatedAreas";

// Player main base position for distance calculations
private _playerMainBase = missionNamespace getVariable ["playerMainBase", ""];
private _playerBasePos = [worldSize / 2, worldSize / 2, 0];
if (_playerMainBase != "") then {
    if ((markerShape _playerMainBase) != "") then {
        _playerBasePos = getMarkerPos _playerMainBase;
    };
};

// ============================================================================
// 1. Pick mission type
// ============================================================================
// Only KILL_CAPTURE for now. Future: weighted selection from available types
// based on intel, recent missions, location tiers.
private _missionType = "KILL_CAPTURE";

// ============================================================================
// 2. Filter valid locations for mission type
// ============================================================================
// KILL_CAPTURE → camps, missionSites, populated areas
// Exclude bluFor-controlled locations
// Require at least 3 structures (need buildings for garrison + HVT)

private _candidateLocations = (_camps + _missionSites + _populatedAreas) select {
    private _loc = _x;
    private _locId = _loc get "id";
    private _locInf = _influenceMap getOrDefault [_locId, createHashMap];
    private _controlledBy = _locInf getOrDefault ["controlledBy", "neutral"];
    private _buildingCount = _loc get "buildingCount";

    _controlledBy != "bluFor" && { _buildingCount >= 3 }
};

if (_candidateLocations isEqualTo []) exitWith {
    diag_log "DSC: fnc_selectMission - No valid locations found for KILL_CAPTURE";
    createHashMap
};

diag_log format ["DSC: fnc_selectMission - %1 candidate locations for %2", count _candidateLocations, _missionType];

// Weight by distance — farther locations are less likely but possible
// Score = 1.0 at 5km, 0.5 at 15km, 0.2 at 25km+
private _weightedLocations = _candidateLocations apply {
    private _dist = (_x get "position") distance2D _playerBasePos;
    private _weight = (1 - (_dist / 30000)) max 0.15;
    [_weight, _x]
};

// Weighted random selection
private _totalWeight = 0;
{ _totalWeight = _totalWeight + (_x select 0) } forEach _weightedLocations;

private _roll = random _totalWeight;
private _runningWeight = 0;
private _selectedLocation = (_weightedLocations select 0) select 1;

{
    _runningWeight = _runningWeight + (_x select 0);
    if (_runningWeight >= _roll) exitWith {
        _selectedLocation = _x select 1;
    };
} forEach _weightedLocations;

private _selectedId = _selectedLocation get "id";
private _selectedPos = _selectedLocation get "position";
private _selectedName = _selectedLocation get "name";
private _distanceFromBase = _selectedPos distance2D _playerBasePos;
private _locationType = _selectedLocation getOrDefault ["militaryTier", ""];
if (_locationType == "") then {
    _locationType = _selectedLocation get "locType";
};

diag_log format ["DSC: fnc_selectMission - Selected: %1 (%2, %3m from base)", _selectedName, _locationType, round _distanceFromBase];

// ============================================================================
// 3. Read area context from influence
// ============================================================================
private _locInfluence = _influenceMap getOrDefault [_selectedId, createHashMap];
private _areaControlledBy = _locInfluence getOrDefault ["controlledBy", "opFor"];
private _areaFaction = _locInfluence getOrDefault ["faction", ""];
private _areaInfluence = _locInfluence getOrDefault ["influence", 0.5];

// Resolve area faction — if empty, pick from the controlling role's pool
if (_areaFaction == "") then {
    private _roleData = _factionData getOrDefault [_areaControlledBy, createHashMap];
    private _roleFactions = _roleData getOrDefault ["factions", []];
    if (_roleFactions isNotEqualTo []) then {
        _areaFaction = selectRandom _roleFactions;
    };
};

// Determine area side from faction data
private _areaSide = east;
{
    private _roleData = _y;
    private _roleFactions = _roleData getOrDefault ["factions", []];
    if (_areaFaction in _roleFactions) exitWith {
        _areaSide = _roleData getOrDefault ["side", east];
    };
} forEach _factionData;

diag_log format ["DSC: fnc_selectMission - Area: %1 (%2, influence: %3)", _areaFaction, _areaControlledBy, _areaInfluence toFixed 2];

// ============================================================================
// 4. Pick target faction (weighted toward different from area faction)
// ============================================================================
// Build candidate pool from enemy roles
private _targetCandidates = [];
{
    private _role = _x;
    private _roleData = _factionData getOrDefault [_role, createHashMap];
    private _roleFactions = _roleData getOrDefault ["factions", []];
    private _roleSide = _roleData getOrDefault ["side", east];
    {
        _targetCandidates pushBack [_x, _roleSide, _role];
    } forEach _roleFactions;
} forEach ["opFor", "opForPartner", "irregulars"];

if (_targetCandidates isEqualTo []) exitWith {
    diag_log "DSC: fnc_selectMission - No enemy factions available";
    createHashMap
};

// Weighted selection: 30% same as area, 70% different
private _sameAsArea = _targetCandidates select { (_x select 0) == _areaFaction };
private _differentFromArea = _targetCandidates select { (_x select 0) != _areaFaction };

private _targetEntry = [];
if (_differentFromArea isNotEqualTo [] && { random 1 < 0.7 }) then {
    _targetEntry = selectRandom _differentFromArea;
} else {
    _targetEntry = selectRandom _targetCandidates;
};

private _targetFaction = _targetEntry select 0;
private _targetSide = _targetEntry select 1;
private _targetRole = _targetEntry select 2;

diag_log format ["DSC: fnc_selectMission - Target: %1 (%2), area: %3", _targetFaction, _targetRole, _areaFaction];

// ============================================================================
// 5. Extract groups + assets for both factions
// ============================================================================
// Target faction
private _targetRoleData = _factionData getOrDefault [_targetRole, createHashMap];
private _targetGroupsAll = _targetRoleData getOrDefault ["groups", createHashMap];
private _targetGroups = _targetGroupsAll getOrDefault [_targetFaction, []];
private _targetAssetsAll = _targetRoleData getOrDefault ["assets", createHashMap];
private _targetAssets = _targetAssetsAll getOrDefault [_targetFaction, createHashMap];

// If no pre-classified groups, extract fresh
if (_targetGroups isEqualTo []) then {
    diag_log format ["DSC: fnc_selectMission - No pre-classified groups for %1, extracting fresh", _targetFaction];
    private _rawGroups = [_targetFaction] call DSC_core_fnc_extractGroups;
    _targetGroups = [_rawGroups] call DSC_core_fnc_classifyGroups;
};
if (_targetAssets isEqualTo createHashMap) then {
    _targetAssets = [_targetFaction] call DSC_core_fnc_extractAssets;
};

// Area faction (skip if same as target — populateAO will just use target for everything)
private _areaGroups = [];
private _areaAssets = createHashMap;

if (_areaFaction != _targetFaction) then {
    // Find which role the area faction belongs to
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
        diag_log format ["DSC: fnc_selectMission - No pre-classified groups for area faction %1, extracting fresh", _areaFaction];
        private _rawGroups = [_areaFaction] call DSC_core_fnc_extractGroups;
        _areaGroups = [_rawGroups] call DSC_core_fnc_classifyGroups;
    };
    if (_areaAssets isEqualTo createHashMap) then {
        _areaAssets = [_areaFaction] call DSC_core_fnc_extractAssets;
    };
};

diag_log format ["DSC: fnc_selectMission - Target groups: %1, Area groups: %2", count _targetGroups, count _areaGroups];

// ============================================================================
// 6. Determine generation parameters
// ============================================================================
private _buildingCount = _selectedLocation get "buildingCount";

private _density = switch (true) do {
    case (_buildingCount >= 30): { "heavy" };
    case (_buildingCount >= 10): { "medium" };
    default                     { "light" };
};

private _areaPresenceChance = 0.7;
private _qrfEnabled = _areaInfluence > 0.3;
private _qrfDelayMin = 120;
private _qrfDelayMax = 180;

// ============================================================================
// 7. Build and return mission config
// ============================================================================
private _config = createHashMapFromArray [
    ["type", _missionType],
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
    ["qrfDelay", [_qrfDelayMin, _qrfDelayMax]],
    ["campaignProfile", _campaignProfile]
];

diag_log format ["DSC: fnc_selectMission - Config built: %1 at %2 (target: %3, area: %4, density: %5)",
    _missionType, _selectedName, _targetFaction, _areaFaction, _density];

_config
