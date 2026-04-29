#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_createMissionBriefing
 * Description:
 *     Creates a task with an intel-style briefing assembled from briefing
 *     fragments + runtime context.
 *
 *     The mission's "briefingArchetype" field selects a fragment from
 *     fnc_getBriefingFragments which supplies the title prefix, objective
 *     statement, ROE, and task icon. The intel/area/threat blocks are
 *     composed at runtime from location data, AO tags, and any entity/
 *     object archetypes attached to the mission.
 *
 *     If the mission has no briefingArchetype (or one that doesn't match
 *     the registry), a generic fallback briefing is composed.
 *
 * Arguments:
 *     0: _mission <HASHMAP> - Mission data from a raid generator
 *     1: _ao <HASHMAP> - Populated AO data
 *     2: _location <HASHMAP> - Location object from scanLocations
 *
 * Return Value:
 *     <STRING> - Task ID for cleanup
 */

params [
    ["_mission", createHashMap, [createHashMap]],
    ["_ao", createHashMap, [createHashMap]],
    ["_location", createHashMap, [createHashMap]]
];

private _briefingArchetype = _mission getOrDefault ["briefingArchetype", ""];
private _locationName = _mission getOrDefault ["locationName", "Unknown"];
private _locationPos = _mission getOrDefault ["location", [0,0,0]];

// Build location tags from enriched location fields
private _locationTags = [];
if (_location getOrDefault ["isMilitary", false]) then { _locationTags pushBack "military" };
private _locType = _location getOrDefault ["locType", ""];
private _milTier = _location getOrDefault ["militaryTier", ""];
if (_milTier != "") then { _locationTags pushBack _milTier };
switch (_locType) do {
    case "NameCityCapital": { _locationTags append ["city", "urban"] };
    case "NameCity":        { _locationTags append ["city", "urban"] };
    case "NameVillage":     { _locationTags append ["settlement", "rural"] };
    case "NameLocal":       { _locationTags pushBack "isolated" };
    case "Military":        { _locationTags pushBack "military" };
};

private _defenderUnits = _ao getOrDefault ["defenderUnits", []];
private _garrisonUnits = _ao getOrDefault ["garrisonUnits", []];
private _patrolGroups = _ao getOrDefault ["patrolGroups", []];
private _aoTags = _ao getOrDefault ["tags", []];
private _totalUnits = _mission getOrDefault ["units", []];

// ============================================================================
// Resolve briefing fragment
// ============================================================================
private _fragments = call DSC_core_fnc_getBriefingFragments;
private _fragment = _fragments getOrDefault [_briefingArchetype, createHashMap];

private _titlePrefix = _fragment getOrDefault ["titlePrefix", "Mission"];
private _objective = _fragment getOrDefault ["objective", "Proceed to the area of operations and assess."];
private _roe = _fragment getOrDefault ["roe", "Exercise caution and report findings."];
private _taskIcon = _fragment getOrDefault ["taskIcon", "run"];

// ============================================================================
// Build relative location description
// ============================================================================
private _nearestNamedLoc = nearestLocation [_locationPos, ""];
private _relativeDesc = if (!isNull _nearestNamedLoc) then {
    private _locName = text _nearestNamedLoc;
    private _dist = _locationPos distance2D (locationPosition _nearestNamedLoc);
    if (_dist < 300) then {
        format ["in %1", _locName]
    } else {
        private _dir = _locationPos getDir (locationPosition _nearestNamedLoc);
        private _cardinal = switch (true) do {
            case (_dir >= 337.5 || _dir < 22.5): { "south" };
            case (_dir >= 22.5 && _dir < 67.5): { "southwest" };
            case (_dir >= 67.5 && _dir < 112.5): { "west" };
            case (_dir >= 112.5 && _dir < 157.5): { "northwest" };
            case (_dir >= 157.5 && _dir < 202.5): { "north" };
            case (_dir >= 202.5 && _dir < 247.5): { "northeast" };
            case (_dir >= 247.5 && _dir < 292.5): { "east" };
            case (_dir >= 292.5 && _dir < 337.5): { "southeast" };
            default { "" };
        };
        format ["%1 of %2", _cardinal, _locName]
    };
} else {
    format ["grid %1", mapGridPosition _locationPos]
};

// ============================================================================
// Build target description from entity/object archetypes
// ============================================================================
private _entityArchetypes = call DSC_core_fnc_getEntityArchetypes;
private _objectArchetypes = call DSC_core_fnc_getObjectArchetypes;

private _entities = _mission getOrDefault ["entities", []];
private _objectMeta = _mission getOrDefault ["objectMeta", []];

private _targetLines = [];

// Entity descriptions
{
    private _archetypeName = _x getVariable ["DSC_entityArchetype", ""];
    if (_archetypeName != "") then {
        private _archetype = _entityArchetypes getOrDefault [_archetypeName, createHashMap];
        if (_archetype isNotEqualTo createHashMap) then {
            private _entityTitle = _archetype getOrDefault ["briefingTitle", "Target"];
            private _entityDesc = _archetype getOrDefault ["briefingDesc", ""];
            _targetLines pushBack (format ["%1: %2", _entityTitle, _entityDesc]);
        };
    };
} forEach _entities;

// Object descriptions (one line per archetype, summarized count)
private _objectsByArchetype = createHashMap;
{
    private _archName = _x getOrDefault ["archetype", ""];
    private _objs = _x getOrDefault ["objects", []];
    if (_archName != "" && { count _objs > 0 }) then {
        private _existing = _objectsByArchetype getOrDefault [_archName, 0];
        _objectsByArchetype set [_archName, _existing + count _objs];
    };
} forEach _objectMeta;

{
    private _archName = _x;
    private _count = _y;
    private _archetype = _objectArchetypes getOrDefault [_archName, createHashMap];
    if (_archetype isNotEqualTo createHashMap) then {
        private _desc = _archetype getOrDefault ["briefingDesc", _archName];
        _targetLines pushBack (format ["%1x %2", _count, _desc]);
    };
} forEach _objectsByArchetype;

private _targetBlock = if (_targetLines isEqualTo []) then {
    ""
} else {
    "<t font='PuristaBold'>TARGETS:</t><br/>- " + (_targetLines joinString "<br/>- ") + "<br/><br/>"
};

// ============================================================================
// Estimate troop strength (fuzzy intel - not exact numbers)
// ============================================================================
private _garrisonCount = count _garrisonUnits;
private _patrolCount = count _patrolGroups;
private _totalCount = count _totalUnits;

private _garrisonEstimate = switch (true) do {
    case (_garrisonCount == 0): { "No garrison presence detected" };
    case (_garrisonCount <= 5): { "Light garrison presence (fireteam-sized)" };
    case (_garrisonCount <= 12): { "Moderate garrison presence (squad-sized)" };
    default { "Heavy garrison presence (platoon-sized)" };
};

private _patrolEstimate = switch (true) do {
    case (_patrolCount == 0): { "No patrol activity reported" };
    case (_patrolCount <= 2): { "Light patrol activity (1-2 patrols)" };
    case (_patrolCount <= 4): { "Moderate patrol activity (3-4 patrols)" };
    default { "Heavy patrol activity (5+ patrols)" };
};

private _strengthEstimate = switch (true) do {
    case (_totalCount <= 10): { "estimated light resistance" };
    case (_totalCount <= 25): { "estimated moderate resistance" };
    default { "estimated heavy resistance" };
};

// ============================================================================
// Detect special threats from AO tags
// ============================================================================
private _threats = [];
private _hasAT = false;
private _hasAA = false;
{
    if ("AT_TEAM" in _x) then { _hasAT = true };
    if ("AA_TEAM" in _x) then { _hasAA = true };
} forEach _aoTags;

if (_hasAT) then { _threats pushBack "Anti-armor teams reported in the area" };
if (_hasAA) then { _threats pushBack "Anti-air capability detected - low altitude approaches not advised" };
if ("military" in _locationTags) then { _threats pushBack "Military fortifications present - expect static weapon emplacements" };

private _threatText = if (_threats isEqualTo []) then {
    "No special threats identified."
} else {
    _threats joinString "<br/>"
};

// ============================================================================
// Build area description from tags
// ============================================================================
private _areaDesc = switch (true) do {
    case ("city" in _locationTags): { "urban area" };
    case ("town" in _locationTags): { "populated town" };
    case ("settlement" in _locationTags): { "small settlement" };
    case ("isolated" in _locationTags && "military" in _locationTags): { "isolated military position" };
    case ("isolated" in _locationTags): { "isolated compound" };
    default { "area of interest" };
};

// ============================================================================
// Compose briefing
// ============================================================================
private _title = format ["%1 - %2", _titlePrefix, _locationName];

private _description = format [
    "<t size='1.2'>MISSION BRIEFING</t><br/><br/>" +
    "<t font='PuristaBold'>OBJECTIVE:</t> %1<br/><br/>" +
    "<t font='PuristaBold'>LOCATION:</t> %2, %3.<br/><br/>" +
    "<t font='PuristaBold'>AREA:</t> Operating from a %4, %5.<br/><br/>" +
    "%6" +
    "<t font='PuristaBold'>INTEL:</t><br/>" +
    "- %7<br/>" +
    "- %8<br/><br/>" +
    "<t font='PuristaBold'>THREATS:</t><br/>%9<br/><br/>" +
    "<t font='PuristaBold'>RULES OF ENGAGEMENT:</t> %10",
    _objective,
    _locationName,
    _relativeDesc,
    _areaDesc,
    _strengthEstimate,
    _targetBlock,
    _garrisonEstimate,
    _patrolEstimate,
    _threatText,
    _roe
];

// ============================================================================
// Create task (no map position - uses marker instead)
// ============================================================================
private _taskId = "DSC_currentTask";

[true, _taskId, [_description, _title, ""], objNull, "AUTOASSIGNED", 1, true, _taskIcon] call BIS_fnc_taskCreate;

diag_log format ["DSC: Mission briefing created - %1", _title];

_taskId
