#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_createMissionBriefing
 * Description:
 *     Creates a task with an intel-style briefing based on mission and AO data.
 *     Task appears in the map task list but NOT as a map icon (uses marker instead).
 *
 * Arguments:
 *     0: _mission <HASHMAP> - Mission data from generateKillCaptureMission
 *     1: _ao <HASHMAP> - Populated AO data from populateAO
 *     2: _location <HASHMAP> - Location object from scanLocations
 *
 * Return Value:
 *     <STRING> - Task ID for cleanup
 *
 * Example:
 *     private _taskId = [_mission, _ao, _location] call DSC_core_fnc_createMissionBriefing;
 */

params [
    ["_mission", createHashMap, [createHashMap]],
    ["_ao", createHashMap, [createHashMap]],
    ["_location", createHashMap, [createHashMap]]
];

private _missionType = _mission getOrDefault ["type", "UNKNOWN"];
private _locationName = _mission getOrDefault ["locationName", "Unknown"];
private _locationPos = _mission getOrDefault ["location", [0,0,0]];
private _locationTags = _location getOrDefault ["tags", []];

private _defenderUnits = _ao getOrDefault ["defenderUnits", []];
private _garrisonUnits = _ao getOrDefault ["garrisonUnits", []];
private _patrolGroups = _ao getOrDefault ["patrolGroups", []];
private _aoTags = _ao getOrDefault ["tags", []];
private _totalUnits = _mission getOrDefault ["units", []];

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
// Estimate troop strength (fuzzy intel - not exact numbers)
// ============================================================================
private _garrisonCount = count _garrisonUnits;
private _defenderCount = count _defenderUnits;
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

private _allTags = [];
{ _allTags append _x } forEach _aoTags;

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
// Compose briefing text
// ============================================================================
private _title = "";
private _description = "";

switch (_missionType) do {
    case "KILL_CAPTURE": {
        _title = format ["Eliminate HVT - %1", _locationName];
        _description = format [
            "<t size='1.2'>MISSION BRIEFING</t><br/><br/>" +
            "<t font='PuristaBold'>OBJECTIVE:</t> Locate and eliminate a high-value target.<br/><br/>" +
            "<t font='PuristaBold'>LOCATION:</t> %1, %2.<br/><br/>" +
            "<t font='PuristaBold'>AREA:</t> Target is operating from a %3, %4.<br/><br/>" +
            "<t font='PuristaBold'>INTEL:</t><br/>" +
            "- %5<br/>" +
            "- %6<br/><br/>" +
            "<t font='PuristaBold'>THREATS:</t><br/>%7<br/><br/>" +
            "<t font='PuristaBold'>RULES OF ENGAGEMENT:</t> Weapons free. Eliminate the HVT and RTB for debrief.",
            _locationName,
            _relativeDesc,
            _areaDesc,
            _strengthEstimate,
            _garrisonEstimate,
            _patrolEstimate,
            _threatText
        ];
    };
    default {
        _title = format ["Mission - %1", _locationName];
        _description = format ["Proceed to %1 %2. Exercise caution.", _locationName, _relativeDesc];
    };
};

// ============================================================================
// Create task (no map position - uses marker instead)
// ============================================================================
private _taskId = "DSC_currentTask";

[true, _taskId, [_description, _title, ""], objNull, "AUTOASSIGNED", 1, true, "kill"] call BIS_fnc_taskCreate;

diag_log format ["DSC: Mission briefing created - %1", _title];

_taskId
