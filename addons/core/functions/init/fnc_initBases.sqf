/*
 * Function: DSC_core_fnc_initBases
 * Description:
 *     Orchestrates base initialization for all military installations:
 *     player base (from Eden markers), bluFor bases, and opFor bases
 *     (from influence data). Calls fnc_setupBase for each and publishes
 *     DSC_baseRegistry for downstream systems.
 *
 * Arguments:
 *     0: _influenceData <HASHMAP> - From fnc_initInfluence
 *     1: _factionData <HASHMAP> - From fnc_initFactionData
 *
 * Return Value:
 *     <HASHMAP> - DSC_baseRegistry keyed by base ID
 *
 * Example:
 *     [_influenceData, _factionData] call DSC_core_fnc_initBases;
 */

params [
    ["_influenceData", createHashMap, [createHashMap]],
    ["_factionData", createHashMap, [createHashMap]]
];

private _baseRegistry = createHashMap;

private _influenceMap = _influenceData getOrDefault ["influenceMap", createHashMap];
private _bases = _influenceData getOrDefault ["bases", []];

private _factionProfileConfig = missionNamespace getVariable ["factionProfileConfig", createHashMap];

// ============================================================================
// Helper: resolve faction + side for a role
// ============================================================================
private _getRoleData = {
    params ["_role"];
    private _roleData = _factionProfileConfig getOrDefault [_role, createHashMap];
    private _side = _roleData getOrDefault ["side", west];
    private _factions = _roleData getOrDefault ["factions", []];
    private _faction = if (_factions isNotEqualTo []) then { _factions select 0 } else { "" };
    [_side, _faction]
};

// ============================================================================
// PHASE 1: Player Base(s)
// ============================================================================
diag_log "DSC: fnc_initBases - Setting up player base(s)";

// Find all player base root markers (player_base_N but NOT player_base_N_*)
private _allPlayerBaseMarkers = allMapMarkers select { _x find "player_base" == 0 };

// Separate root markers from zone sub-markers
private _rootMarkers = [];
{
    private _marker = _x;
    // A root marker has format "player_base_N" — check it doesn't have more underscore segments
    // after removing the "player_base_" prefix
    private _suffix = _marker select [count "player_base_"];
    private _parts = _suffix splitString "_";
    // Root marker: suffix is just a number (e.g., "1")
    if (count _parts == 1) then {
        _rootMarkers pushBack _marker;
    };
} forEach _allPlayerBaseMarkers;

diag_log format ["DSC: fnc_initBases - Found %1 player base root marker(s): %2", count _rootMarkers, _rootMarkers];

// Get bluFor faction data
private _bluForData = "bluFor" call _getRoleData;
_bluForData params ["_bluForSide", "_bluForFaction"];

// Pre-extract bluFor assets once for all player bases
private _bluForAssets = createHashMap;
if (_bluForFaction != "") then {
    private _bluForRoleData = _factionData getOrDefault ["bluFor", createHashMap];
    _bluForAssets = (_bluForRoleData getOrDefault ["assets", createHashMap]) getOrDefault [_bluForFaction, createHashMap];
    if (_bluForAssets isEqualTo createHashMap) then {
        _bluForAssets = [_bluForFaction] call DSC_core_fnc_extractAssets;
    };
};

{
    private _marker = _x;
    private _markerPos = getMarkerPos _marker;

    if (_markerPos isEqualTo [0,0,0]) then {
        diag_log format ["DSC: fnc_initBases - WARNING: marker '%1' has no position, skipping", _marker];
        continue;
    };

    private _config = createHashMapFromArray [
        ["id", _marker],
        ["type", "playerBase"],
        ["position", _markerPos],
        ["side", _bluForSide],
        ["faction", _bluForFaction],
        ["name", format ["Player Base (%1)", _marker]],
        ["assets", _bluForAssets]
    ];

    private _baseEntry = [_config] call DSC_core_fnc_setupBase;
    _baseRegistry set [_marker, _baseEntry];

    diag_log format ["DSC: fnc_initBases - Player base '%1' initialized", _marker];
} forEach _rootMarkers;

// ============================================================================
// PHASE 2: BluFor Partner Bases (from influence)
// ============================================================================
diag_log "DSC: fnc_initBases - Setting up bluFor partner bases";

private _partnerData = "bluForPartner" call _getRoleData;
_partnerData params ["_partnerSide", "_partnerFaction"];

private _partnerAssets = createHashMap;
if (_partnerFaction != "") then {
    private _partnerRoleData = _factionData getOrDefault ["bluForPartner", createHashMap];
    _partnerAssets = (_partnerRoleData getOrDefault ["assets", createHashMap]) getOrDefault [_partnerFaction, createHashMap];
    if (_partnerAssets isEqualTo createHashMap) then {
        _partnerAssets = [_partnerFaction] call DSC_core_fnc_extractAssets;
    };
};

{
    private _loc = _x;
    private _locId = _loc get "id";
    private _locPos = _loc get "position";
    private _locName = _loc getOrDefault ["name", _locId];
    private _locRadius = _loc getOrDefault ["radius", 300];
    private _locStructures = _loc getOrDefault ["assignedStructures", []];

    private _locInf = _influenceMap getOrDefault [_locId, createHashMap];
    private _controlledBy = _locInf getOrDefault ["controlledBy", ""];

    if (_controlledBy != "bluFor") then { continue };

    // Skip if this location is inside a player base marker (already handled)
    private _insidePlayerBase = false;
    {
        if (_locPos inArea _x) exitWith { _insidePlayerBase = true };
    } forEach _rootMarkers;
    if (_insidePlayerBase) then { continue };

    private _config = createHashMapFromArray [
        ["id", _locId],
        ["type", "bluFor"],
        ["position", _locPos],
        ["side", _partnerSide],
        ["faction", _partnerFaction],
        ["name", _locName],
        ["radius", _locRadius],
        ["structures", _locStructures],
        ["assets", _partnerAssets],
        ["influenceId", _locId]
    ];

    private _baseEntry = [_config] call DSC_core_fnc_setupBase;
    _baseRegistry set [_locId, _baseEntry];

    diag_log format ["DSC: fnc_initBases - BluFor base '%1' initialized", _locName];
} forEach _bases;

// ============================================================================
// PHASE 3: OpFor Bases (from influence)
// ============================================================================
diag_log "DSC: fnc_initBases - Setting up opFor bases";

private _opForData = "opFor" call _getRoleData;
_opForData params ["_opForSide", "_opForFaction"];

private _opForAssets = createHashMap;
if (_opForFaction != "") then {
    private _opForRoleData = _factionData getOrDefault ["opFor", createHashMap];
    _opForAssets = (_opForRoleData getOrDefault ["assets", createHashMap]) getOrDefault [_opForFaction, createHashMap];
    if (_opForAssets isEqualTo createHashMap) then {
        _opForAssets = [_opForFaction] call DSC_core_fnc_extractAssets;
    };
};

{
    private _loc = _x;
    private _locId = _loc get "id";
    private _locPos = _loc get "position";
    private _locName = _loc getOrDefault ["name", _locId];
    private _locRadius = _loc getOrDefault ["radius", 300];
    private _locStructures = _loc getOrDefault ["assignedStructures", []];

    private _locInf = _influenceMap getOrDefault [_locId, createHashMap];
    private _controlledBy = _locInf getOrDefault ["controlledBy", ""];

    if (_controlledBy != "opFor") then { continue };

    private _config = createHashMapFromArray [
        ["id", _locId],
        ["type", "opFor"],
        ["position", _locPos],
        ["side", _opForSide],
        ["faction", _opForFaction],
        ["name", _locName],
        ["radius", _locRadius],
        ["structures", _locStructures],
        ["assets", _opForAssets],
        ["influenceId", _locId]
    ];

    private _baseEntry = [_config] call DSC_core_fnc_setupBase;
    _baseRegistry set [_locId, _baseEntry];

    diag_log format ["DSC: fnc_initBases - OpFor base '%1' initialized", _locName];
} forEach _bases;

// ============================================================================
// Publish Registry
// ============================================================================
private _regValues = values _baseRegistry;
private _playerCount = { (_x get "type") == "playerBase" } count _regValues;
private _bluForCount = { (_x get "type") == "bluFor" } count _regValues;
private _opForCount = { (_x get "type") == "opFor" } count _regValues;

diag_log format ["DSC: fnc_initBases - Complete: %1 total bases (%2 player, %3 bluFor, %4 opFor)",
    count _baseRegistry, _playerCount, _bluForCount, _opForCount
];

_baseRegistry
