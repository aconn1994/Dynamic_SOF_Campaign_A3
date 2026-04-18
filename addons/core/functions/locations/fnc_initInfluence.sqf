#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_initInfluence
 * Description:
 *     Initializes the influence map from scanned location anchors. Uses military
 *     tier (base/outpost/camp) from the scanner to create a tiered occupation model:
 *
 *     - Bases are occupation zones: always faction-controlled, generate influence
 *     - Outposts are satellites: controlled if near a base, contested otherwise
 *     - Camps are contention points: lightly held or neutral, prime mission targets
 *
 *     Populated areas receive influence from nearby bases/outposts.
 *     Mission sites inherit from nearest influence source.
 *
 * Arguments:
 *     0: _locations <ARRAY> - Anchor arrays from fnc_scanLocations
 *        Each: [position, name, type, isMilitary, assignedStructures, militaryTier]
 *     1: _campaignProfile <STRING> - Initial state:
 *        "offensive"  - OpFor controls most, player fights to liberate
 *        "defensive"  - BluFor controls most, OpFor is invading
 *        "contested"  - Mixed control, chaotic battlespace
 *     2: _factionData <HASHMAP> - From fnc_initFactionData
 *
 * Return Value:
 *     <HASHMAP> - Influence data:
 *       "bases"           - Array of base location hashmaps
 *       "outposts"        - Array of outpost location hashmaps
 *       "camps"           - Array of camp location hashmaps
 *       "populatedAreas"  - Array of populated area hashmaps
 *       "missionSites"    - Array of remaining small locations
 *       "influenceMap"    - Hashmap of locationId -> influence data
 *       "locations"       - All enriched location hashmaps
 *       "campaignProfile" - The profile string used
 *
 * Example:
 *     private _influence = [_locations, "offensive", _factionData] call DSC_core_fnc_initInfluence;
 */

params [
    ["_locations", [], [[]]],
    ["_campaignProfile", "offensive", [""]],
    ["_factionData", createHashMap, [createHashMap]]
];

if (_locations isEqualTo []) exitWith {
    diag_log "DSC: fnc_initInfluence - No locations provided";
    createHashMap
};

// ============================================================================
// STAGE 0: Convert anchors to rich location hashmaps
// ============================================================================
private _enrichedLocations = [];
{
    _x params ["_anchorPos", "_anchorName", "_anchorType", "_anchorIsMil", "_anchorStructs", "_milTier"];

    if (count _anchorStructs < 1) then { continue };

    private _maxDist = 0;
    {
        private _dist = _x distance2D _anchorPos;
        if (_dist > _maxDist) then { _maxDist = _dist };
    } forEach _anchorStructs;

    private _loc = createHashMapFromArray [
        ["id", format ["loc_%1", _forEachIndex]],
        ["position", _anchorPos],
        ["name", _anchorName],
        ["locType", _anchorType],
        ["isMilitary", _anchorIsMil],
        ["militaryTier", _milTier],
        ["structures", _anchorStructs],
        ["buildingCount", count _anchorStructs],
        ["radius", _maxDist max 50]
    ];

    _enrichedLocations pushBack _loc;
} forEach _locations;

diag_log format ["DSC: initInfluence - %1 anchors with structures", count _enrichedLocations];

// ============================================================================
// STAGE 1: Classify locations into strategic tiers
// ============================================================================
private _bases = [];
private _outposts = [];
private _camps = [];
private _populatedAreas = [];
private _missionSites = [];

{
    private _loc = _x;
    private _isMil = _loc get "isMilitary";
    private _locType = _loc get "locType";
    private _milTier = _loc get "militaryTier";

    if (_isMil) then {
        switch (_milTier) do {
            case "base":    { _bases pushBack _loc };
            case "outpost": { _outposts pushBack _loc };
            case "camp":    { _camps pushBack _loc };
            default         { _camps pushBack _loc };
        };
    } else {
        if (_locType in ["NameCityCapital", "NameCity", "NameVillage"]) then {
            _populatedAreas pushBack _loc;
        } else {
            _missionSites pushBack _loc;
        };
    };
} forEach _enrichedLocations;

diag_log format ["DSC: initInfluence - Bases: %1, Outposts: %2, Camps: %3, Populated: %4, MissionSites: %5",
    count _bases, count _outposts, count _camps, count _populatedAreas, count _missionSites];

// ============================================================================
// STAGE 2: Assign control to bases (occupation zones)
// ============================================================================
// Only bases get direct faction assignment via campaign profile rolls.
// They are the anchor points of faction power on the map.

private _influenceMap = createHashMap;

// Player main base proximity — no opFor bases within this radius
private _playerMainBase = missionNamespace getVariable ["playerMainBase", ""];
private _playerBasePos = [0, 0, 0];
private _safeZoneRadius = 5000;

if (_playerMainBase != "") then {
    if ((markerShape _playerMainBase) != "") then {
        _playerBasePos = getMarkerPos _playerMainBase;
        diag_log format ["DSC: initInfluence - Player main base at %1, safe zone %2m", _playerBasePos, _safeZoneRadius];
    };
};

private _opForControlChance = switch (_campaignProfile) do {
    case "offensive":  { 0.80 };
    case "defensive":  { 0.25 };
    case "contested":  { 0.50 };
    default            { 0.80 };
};

private _bluForControlChance = switch (_campaignProfile) do {
    case "offensive":  { 0.10 };
    case "defensive":  { 0.65 };
    case "contested":  { 0.30 };
    default            { 0.10 };
};

{
    private _loc = _x;
    private _id = _loc get "id";
    private _locPos = _loc get "position";
    private _roll = random 1;

    private _controlledBy = "contested";
    private _influence = 0.5;
    private _assignedFaction = "";

    // Bases within safe zone of player main base cannot be opFor
    private _inSafeZone = _playerBasePos distance2D _locPos < _safeZoneRadius;

    if (!_inSafeZone && { _roll < _opForControlChance }) then {
        _controlledBy = "opFor";
        _influence = 0.7 + random 0.3;
        private _opForData = _factionData getOrDefault ["opFor", createHashMap];
        private _opForFactions = _opForData getOrDefault ["factions", []];
        if (_opForFactions isNotEqualTo []) then {
            _assignedFaction = selectRandom _opForFactions;
        };
    } else {
        if (_roll < _opForControlChance + _bluForControlChance || _inSafeZone) then {
            _controlledBy = "bluFor";
            _influence = [0.7 + random 0.3, 0.9 + random 0.1] select _inSafeZone;
            private _bluForData = _factionData getOrDefault ["bluFor", createHashMap];
            private _bluForFactions = _bluForData getOrDefault ["factions", []];
            if (_bluForFactions isNotEqualTo []) then {
                _assignedFaction = selectRandom _bluForFactions;
            };
        } else {
            _controlledBy = "contested";
            _influence = 0.3 + random 0.4;
            private _partnerData = _factionData getOrDefault ["opForPartner", createHashMap];
            private _partnerFactions = _partnerData getOrDefault ["factions", []];
            if (_partnerFactions isNotEqualTo []) then {
                _assignedFaction = selectRandom _partnerFactions;
            };
        };
    };

    _influenceMap set [_id, createHashMapFromArray [
        ["controlledBy", _controlledBy],
        ["influence", _influence],
        ["type", "base"],
        ["faction", _assignedFaction]
    ]];

    private _safeLabel = ["", " (safe zone)"] select _inSafeZone;
    diag_log format ["DSC: initInfluence - Base '%1': %2 / %3 (influence: %4)%5", _loc get "name", _controlledBy, _assignedFaction, _influence toFixed 2, _safeLabel];
} forEach _bases;

// ============================================================================
// STAGE 2.5: Assign control to outposts (satellites of nearby bases)
// ============================================================================
// Outposts inherit from the nearest base. If a base controls them, they get
// a weaker version of that control. If no base is nearby, they're contested.

private _outpostInfluenceRadius = 4000;

{
    private _op = _x;
    private _opId = _op get "id";
    private _opPos = _op get "position";

    private _nearestBaseId = "";
    private _nearestBaseDist = 999999;

    {
        private _basePos = _x get "position";
        private _dist = _opPos distance2D _basePos;
        if (_dist < _nearestBaseDist && _dist < _outpostInfluenceRadius) then {
            _nearestBaseDist = _dist;
            _nearestBaseId = _x get "id";
        };
    } forEach _bases;

    private _controlledBy = "contested";
    private _influence = 0.3 + random 0.2;
    private _assignedFaction = "";

    if (_nearestBaseId != "") then {
        private _baseInf = _influenceMap get _nearestBaseId;
        _controlledBy = _baseInf get "controlledBy";
        _assignedFaction = _baseInf get "faction";
        private _distFactor = 1 - (_nearestBaseDist / _outpostInfluenceRadius);
        _influence = (_baseInf get "influence") * _distFactor * 0.8;
        _influence = _influence max 0.2;
    };

    _influenceMap set [_opId, createHashMapFromArray [
        ["controlledBy", _controlledBy],
        ["influence", _influence],
        ["type", "outpost"],
        ["faction", _assignedFaction]
    ]];

    diag_log format ["DSC: initInfluence - Outpost '%1': %2 / %3 (influence: %4, nearBase: %5)",
        _op get "name", _controlledBy, _assignedFaction, _influence toFixed 2,
        ["none", "yes"] select (_nearestBaseId != "")];
} forEach _outposts;

// ============================================================================
// STAGE 2.6: Camps start neutral or lightly contested
// ============================================================================
// Camps are contention points — lightly held at best, prime mission targets.
// Small chance of light opFor presence in offensive profile.

private _campOccupyChance = switch (_campaignProfile) do {
    case "offensive":  { 0.30 };
    case "defensive":  { 0.10 };
    case "contested":  { 0.20 };
    default            { 0.30 };
};

{
    private _camp = _x;
    private _campId = _camp get "id";
    private _roll = random 1;

    private _controlledBy = "neutral";
    private _influence = 0;
    private _assignedFaction = "";

    if (_roll < _campOccupyChance) then {
        _controlledBy = "contested";
        _influence = 0.2 + random 0.2;
        private _partnerData = _factionData getOrDefault ["opForPartner", createHashMap];
        private _irregularData = _factionData getOrDefault ["irregulars", createHashMap];
        private _candidateFactions = (_partnerData getOrDefault ["factions", []]) + (_irregularData getOrDefault ["factions", []]);
        if (_candidateFactions isNotEqualTo []) then {
            _assignedFaction = selectRandom _candidateFactions;
        };
    };

    _influenceMap set [_campId, createHashMapFromArray [
        ["controlledBy", _controlledBy],
        ["influence", _influence],
        ["type", "camp"],
        ["faction", _assignedFaction]
    ]];

    diag_log format ["DSC: initInfluence - Camp '%1': %2 (influence: %3)", _camp get "name", _controlledBy, _influence toFixed 2];
} forEach _camps;

// Force locations inside player base markers to bluFor
private _playerBaseMarkers = allMapMarkers select { _x find "player_base" == 0 };
{
    private _loc = _x;
    private _locId = _loc get "id";
    private _locPos = _loc get "position";

    private _insideBase = false;
    { if (_locPos inArea _x) exitWith { _insideBase = true } } forEach _playerBaseMarkers;

    if (_insideBase) then {
        _influenceMap set [_locId, createHashMapFromArray [
            ["controlledBy", "bluFor"],
            ["influence", 1.0],
            ["type", _influenceMap getOrDefault [_locId, createHashMap] getOrDefault ["type", "base"]],
            ["faction", ""]
        ]];
        diag_log format ["DSC: initInfluence - Player base override: '%1' set to bluFor (1.0)", _loc get "name"];
    };
} forEach _enrichedLocations;

// ============================================================================
// STAGE 3: Propagate influence to populated areas from bases + outposts
// ============================================================================
private _cpInfluenceRadius = 3000;
private _influenceSources = _bases + _outposts;

{
    private _area = _x;
    private _areaId = _area get "id";
    private _areaPos = _area get "position";

    private _nearbyOpFor = 0;
    private _nearbyBluFor = 0;
    private _nearbyContested = 0;
    private _totalWeight = 0;

    {
        private _cp = _x;
        private _cpPos = _cp get "position";
        private _dist = _areaPos distance2D _cpPos;

        if (_dist < _cpInfluenceRadius) then {
            private _cpId = _cp get "id";
            private _cpInfluence = _influenceMap get _cpId;
            private _cpOwner = _cpInfluence get "controlledBy";
            private _cpStrength = _cpInfluence get "influence";

            private _weight = _cpStrength * (1 - (_dist / _cpInfluenceRadius));

            switch (_cpOwner) do {
                case "opFor":     { _nearbyOpFor = _nearbyOpFor + _weight };
                case "bluFor":    { _nearbyBluFor = _nearbyBluFor + _weight };
                case "contested": { _nearbyContested = _nearbyContested + _weight };
            };
            _totalWeight = _totalWeight + _weight;
        };
    } forEach _influenceSources;

    private _controlledBy = "neutral";
    private _influence = 0;

    if (_totalWeight > 0) then {
        private _opForRatio = _nearbyOpFor / _totalWeight;
        private _bluForRatio = _nearbyBluFor / _totalWeight;

        if (_opForRatio > 0.6) then {
            _controlledBy = "opFor";
            _influence = _opForRatio;
        } else {
            if (_bluForRatio > 0.6) then {
                _controlledBy = "bluFor";
                _influence = _bluForRatio;
            } else {
                _controlledBy = "contested";
                _influence = 0.3 + random 0.3;
            };
        };
    };

    _influenceMap set [_areaId, createHashMapFromArray [
        ["controlledBy", _controlledBy],
        ["influence", _influence],
        ["type", "populatedArea"],
        ["faction", ""]
    ]];
} forEach _populatedAreas;

// Mission sites inherit from nearest influence source (base, outpost, or populated area)
{
    private _site = _x;
    private _siteId = _site get "id";
    private _sitePos = _site get "position";

    private _nearestDist = 999999;
    private _nearestInfluence = createHashMapFromArray [
        ["controlledBy", "neutral"],
        ["influence", 0],
        ["type", "missionSite"],
        ["faction", ""]
    ];

    {
        private _srcId = _x get "id";
        private _srcPos = _x get "position";
        private _dist = _sitePos distance2D _srcPos;

        if (_dist < _nearestDist) then {
            _nearestDist = _dist;
            private _srcInfluence = _influenceMap get _srcId;
            _nearestInfluence = createHashMapFromArray [
                ["controlledBy", _srcInfluence get "controlledBy"],
                ["influence", (_srcInfluence get "influence") * (0.5 max (1 - _dist / 5000))],
                ["type", "missionSite"],
                ["faction", ""]
            ];
        };
    } forEach (_influenceSources + _populatedAreas);

    _influenceMap set [_siteId, _nearestInfluence];
} forEach _missionSites;

// ============================================================================
// Summary
// ============================================================================
private _opForCount = 0;
private _bluForCount = 0;
private _contestedCount = 0;
private _neutralCount = 0;

{
    switch (_y get "controlledBy") do {
        case "opFor":     { _opForCount = _opForCount + 1 };
        case "bluFor":    { _bluForCount = _bluForCount + 1 };
        case "contested": { _contestedCount = _contestedCount + 1 };
        case "neutral":   { _neutralCount = _neutralCount + 1 };
    };
} forEach _influenceMap;

diag_log format ["DSC: initInfluence complete - OpFor: %1, BluFor: %2, Contested: %3, Neutral: %4",
    _opForCount, _bluForCount, _contestedCount, _neutralCount];

createHashMapFromArray [
    ["bases", _bases],
    ["outposts", _outposts],
    ["camps", _camps],
    ["populatedAreas", _populatedAreas],
    ["missionSites", _missionSites],
    ["influenceMap", _influenceMap],
    ["locations", _enrichedLocations],
    ["campaignProfile", _campaignProfile]
]
