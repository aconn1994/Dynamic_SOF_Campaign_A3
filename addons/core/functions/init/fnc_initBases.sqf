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
    [_side, _faction, _factions]
};

// Helper: merge assets from all factions in a role into one pooled hashmap
private _mergeAssets = {
    params ["_role", "_factionsList"];
    private _roleData = _factionData getOrDefault [_role, createHashMap];
    private _allRoleAssets = _roleData getOrDefault ["assets", createHashMap];

    private _merged = createHashMapFromArray [
        ["staticWeapons", createHashMapFromArray [["HMG",[]], ["GMG",[]], ["AT",[]], ["AA",[]], ["mortar",[]], ["cannon",[]], ["other",[]]]],
        ["cars", createHashMapFromArray [["unarmed",[]], ["armed",[]], ["mrap",[]]]],
        ["trucks", []],
        ["apcs", []],
        ["tanks", []],
        ["helicopters", createHashMapFromArray [["attack",[]], ["transport",[]]]],
        ["planes", createHashMapFromArray [["attack",[]], ["transport",[]]]],
        ["boats", []],
        ["drones", []]
    ];

    {
        private _fac = _x;
        private _facAssets = _allRoleAssets getOrDefault [_fac, createHashMap];
        if (_facAssets isEqualTo createHashMap) then {
            _facAssets = [_fac] call DSC_core_fnc_extractAssets;
        };

        // Merge each category
        {
            private _catKey = _x;
            private _src = _facAssets getOrDefault [_catKey, []];
            private _dst = _merged getOrDefault [_catKey, []];

            if (_src isEqualType createHashMap) then {
                // Sub-keyed category (staticWeapons, cars, helicopters, planes)
                {
                    private _subKey = _x;
                    private _subSrc = _src getOrDefault [_subKey, []];
                    private _subDst = _dst getOrDefault [_subKey, []];
                    _dst set [_subKey, _subDst + _subSrc];
                } forEach (keys _src);
            } else {
                _merged set [_catKey, _dst + _src];
            };
        } forEach ["staticWeapons", "cars", "trucks", "apcs", "tanks", "helicopters", "planes", "boats", "drones"];
    } forEach _factionsList;

    _merged
};

// ============================================================================
// PHASE 1: Player Base(s)
// ============================================================================
diag_log "DSC: fnc_initBases - Setting up player base(s)";

// Find the active player base marker (set in initServer Step 0)
private _playerMainBase = missionNamespace getVariable ["playerMainBase", ""];
private _allPlayerBaseMarkers = allMapMarkers select { _x find "player_base" == 0 };

// Only initialize the active player base — other player_base markers are
// reserved zones (exclusion from scanning/influence) but not populated
private _rootMarkers = [];
if (_playerMainBase != "") then {
    // Verify the marker exists
    if ((getMarkerPos _playerMainBase) isNotEqualTo [0,0,0]) then {
        _rootMarkers pushBack _playerMainBase;
    } else {
        diag_log format ["DSC: fnc_initBases - WARNING: playerMainBase '%1' marker not found", _playerMainBase];
    };
};

diag_log format ["DSC: fnc_initBases - Found %1 player base root marker(s): %2", count _rootMarkers, _rootMarkers];

// Get bluFor faction data — pool assets from ALL bluFor factions
private _bluForData = "bluFor" call _getRoleData;
_bluForData params ["_bluForSide", "_bluForFaction", "_bluForFactions"];

private _bluForAssets = ["bluFor", _bluForFactions] call _mergeAssets;
diag_log format ["DSC: fnc_initBases - Pooled bluFor assets from %1 factions", count _bluForFactions];

// Guard faction: prefer conventional (2nd faction) over SOF (1st) for base guards
private _bluForGuardFaction = if (count _bluForFactions > 1) then { _bluForFactions select 1 } else { _bluForFaction };

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
        ["assets", _bluForAssets],
        ["guardFaction", _bluForGuardFaction]
    ];

    private _baseEntry = [_config] call DSC_core_fnc_setupBase;
    _baseRegistry set [_marker, _baseEntry];

    // Style the main base marker: border-only outline visible on player maps
    _marker setMarkerBrushLocal "Border";
    _marker setMarkerColorLocal "ColorWEST";
    _marker setMarkerAlpha 1;

    // Hide all sub-zone markers (heliport, motorpool, toc, airstrip)
    private _prefix = _marker + "_";
    {
        if (_x find _prefix == 0) then {
            // _x setMarkerAlpha 0;
            _x setMarkerBrushLocal "Border";
            _x setMarkerColorLocal "ColorWEST";
            _x setMarkerAlpha 1;
        };
    } forEach _allPlayerBaseMarkers;

    diag_log format ["DSC: fnc_initBases - Player base '%1' initialized", _marker];
} forEach _rootMarkers;

// ============================================================================
// PHASE 2: BluFor Partner Bases (from influence)
// DISABLED: Will be handled by presence manager when player approaches
// ============================================================================
/*
diag_log "DSC: fnc_initBases - Setting up bluFor partner bases";

private _partnerData = "bluForPartner" call _getRoleData;
_partnerData params ["_partnerSide", "_partnerFaction", "_partnerFactions"];

private _partnerAssets = ["bluForPartner", _partnerFactions] call _mergeAssets;
diag_log format ["DSC: fnc_initBases - Pooled bluForPartner assets from %1 factions", count _partnerFactions];

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
*/

// ============================================================================
// PHASE 3: OpFor Bases (from influence)
// DISABLED: Will be handled by presence manager when player approaches
// ============================================================================
/*
diag_log "DSC: fnc_initBases - Setting up opFor bases";

private _opForData = "opFor" call _getRoleData;
_opForData params ["_opForSide", "_opForFaction", "_opForFactions"];

private _opForAssets = ["opFor", _opForFactions] call _mergeAssets;
diag_log format ["DSC: fnc_initBases - Pooled opFor assets from %1 factions", count _opForFactions];

// Guard faction: prefer conventional (2nd faction) over elite (1st) for base guards
private _opForGuardFaction = if (count _opForFactions > 1) then { _opForFactions select 1 } else { _opForFaction };

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
        ["guardFaction", _opForGuardFaction],
        ["influenceId", _locId]
    ];

    private _baseEntry = [_config] call DSC_core_fnc_setupBase;
    _baseRegistry set [_locId, _baseEntry];

    diag_log format ["DSC: fnc_initBases - OpFor base '%1' initialized", _locName];
} forEach _bases;
*/

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
