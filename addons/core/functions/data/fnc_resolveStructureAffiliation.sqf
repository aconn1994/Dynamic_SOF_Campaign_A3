#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_resolveStructureAffiliation
 * Description:
 *     Resolves who occupies a structure from its HOST LOCATION context —
 *     Session 02, Ambient World Overhaul, Decision B25 (the structure
 *     catalog is context-free; affiliation is not authored). Pure.
 *
 *     A barracks on an airbase is an army barracks. The same class standing
 *     alone in a city with no military installation is a police / civil-
 *     defence / derelict barracks — the catalog has no way to know which,
 *     so it is resolved here from the location that hosts it.
 *
 *     Decision tree:
 *       - Missing location context (no "isMilitary"/"militaryTier" key —
 *         e.g. a location scanned before this existed) -> "unknown".
 *       - Not a military-flagged structure -> "derelict" if ruined, else
 *         "civil".
 *       - Military-flagged + ruined, and the location itself is not a
 *         military installation -> "derelict".
 *       - Military-flagged and the location IS a military installation
 *         (isMilitary or a non-empty militaryTier) -> "military".
 *       - Military-flagged, standing alone in a non-military location -> 
 *         "law_enforcement" if the location shows a law-enforcement
 *         presence (functionalProfile/subtypeProfile), else "civil".
 *
 * Arguments:
 *     0: _structureInfo <HASHMAP> - A record from fnc_resolveStructureInfo
 *        (or equivalent mock): {subtype, category, displayName, flags}.
 *     1: _location <HASHMAP> - The host location hashmap (or equivalent
 *        mock) from fnc_scanLocations.
 *
 * Return Value:
 *     <STRING> - One of "military", "law_enforcement", "civil", "derelict",
 *     "unknown".
 *
 * Example:
 *     private _info = ["Land_i_Barracks_V1_F"] call DSC_core_fnc_resolveStructureInfo;
 *     private _affiliation = [_info, _location] call DSC_core_fnc_resolveStructureAffiliation;
 */

params [
    ["_structureInfo", createHashMap, [createHashMap]],
    ["_location", createHashMap, [createHashMap]]
];

private _hasContext = ("isMilitary" in _location) || ("militaryTier" in _location);
if (!_hasContext) exitWith { "unknown" };

private _flags = _structureInfo getOrDefault ["flags", []];
private _isRuined = "ruined" in _flags;
private _isMilitaryClass = "military" in _flags;

if (!_isMilitaryClass) exitWith {
    ["civil", "derelict"] select _isRuined
};

private _locIsMilitary = _location getOrDefault ["isMilitary", false];
private _locMilTier = _location getOrDefault ["militaryTier", ""];
private _locIsMilitaryContext = _locIsMilitary || (_locMilTier != "");

if (_isRuined && {!_locIsMilitaryContext}) exitWith { "derelict" };

if (_locIsMilitaryContext) exitWith { "military" };

// Military-flagged class, standing alone outside any military installation.
private _functionalProfile = _location getOrDefault ["functionalProfile", createHashMap];
private _subtypeProfile = _location getOrDefault ["subtypeProfile", createHashMap];
private _lawPresence = ((_functionalProfile getOrDefault ["law_enforcement", 0]) > 0) || ("police_station" in _subtypeProfile);

if (_lawPresence) exitWith { "law_enforcement" };

"civil"
