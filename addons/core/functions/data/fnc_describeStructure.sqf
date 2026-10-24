#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_describeStructure
 * Description:
 *     Pure. Renders a human-readable noun phrase for a structure, for use
 *     in briefings — Session 02, Ambient World Overhaul (docs/overhauls/
 *     ambient_world/session_02_location_poi_registry.md).
 *
 *     Without a location, returns the catalog's indefinite displayName
 *     verbatim ("a school"). With a location, resolves affiliation
 *     (fnc_resolveStructureAffiliation) and renders a definite, affiliation-
 *     flavored phrase ("the police barracks" vs "the barracks" vs "the
 *     derelict barracks") — Decision B25's whole point.
 *
 *     An unknown class always renders a non-empty generic string ("a
 *     building" / "the building"), never "".
 *
 * Arguments:
 *     0: _object <OBJECT, STRING> - A world object (typeOf is applied) or a
 *        bare classname.
 *     1: _location <HASHMAP> - Optional host location hashmap. Omit (or
 *        pass an empty hashmap) to get the plain catalog displayName with
 *        no affiliation flavor.
 *     2: _withGrid <BOOL> - Append " at GGG-GGG" (default false). Only
 *        applies when _object carries a resolvable position (a live object
 *        or a position array) — silently skipped for a bare classname.
 *
 * Return Value:
 *     <STRING> - e.g. "a school", "the police barracks", "the barracks at 034-112".
 *
 * Example:
 *     private _desc = [_doorObj] call DSC_core_fnc_describeStructure; // "a school"
 *     private _desc2 = [_doorObj, _location, true] call DSC_core_fnc_describeStructure; // "the police barracks at 034-112"
 */

params [
    ["_object", objNull, [objNull, "", []]],
    ["_location", createHashMap, [createHashMap]],
    ["_withGrid", false, [false]]
];

private _info = [_object] call DSC_core_fnc_resolveStructureInfo;
private _displayName = _info getOrDefault ["displayName", "a building"];
if (_displayName == "") then { _displayName = "a building" };

private _desc = _displayName;

if (count _location > 0) then {
    private _affiliation = [_info, _location] call DSC_core_fnc_resolveStructureAffiliation;

    private _adjectives = createHashMapFromArray [
        ["military", ""],
        ["law_enforcement", "police"],
        ["civil", ""],
        ["derelict", "derelict"],
        ["unknown", ""]
    ];
    private _adjective = _adjectives getOrDefault [_affiliation, ""];

    private _noun = _displayName;
    private _dnLen = count _noun;
    if (_dnLen > 2 && {(_noun select [0, 2]) == "a "}) then { _noun = _noun select [2, _dnLen - 2] };
    if (_dnLen > 3 && {(_noun select [0, 3]) == "an "}) then { _noun = _noun select [3, _dnLen - 3] };

    _desc = if (_adjective != "") then {
        format ["the %1 %2", _adjective, _noun]
    } else {
        format ["the %1", _noun]
    };
};

if (_withGrid) then {
    private _canGrid = ((_object isEqualType objNull) && {!isNull _object}) || (_object isEqualType []);
    if (_canGrid) then {
        _desc = format ["%1 at %2", _desc, mapGridPosition _object];
    };
};

_desc
