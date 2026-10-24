#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_resolveStructureInfo
 * Description:
 *     Resolves a classname or object to its structure taxonomy record —
 *     Session 01, docs/overhauls/ambient_world/session_01_structure_taxonomy.md
 *     "Approved Mini-Spec" §A2.
 *
 *     Deterministic read against the cached catalog (fnc_getStructureCatalog).
 *     An unknown class (absent from Table 2) returns a well-formed record
 *     rather than nil/error, and WARNs exactly once per distinct unknown
 *     classname (tracked in DSC_structureUnknownWarned) — the scan touches
 *     thousands of objects per call, so a per-call warning would flood the
 *     log (same precedent as fnc_resolveEntityClass's unitClassResolver).
 *
 * Arguments:
 *     0: _classOrObject <STRING, OBJECT> - A classname, or an object (typeOf
 *        is applied).
 *
 * Return Value:
 *     <HASHMAP> - {subtype, category, displayName, flags}. Unknown classes
 *     resolve to {"unknown", "unknown", "a building", []}.
 *
 * Example:
 *     private _info = ["Land_School_01_F"] call DSC_core_fnc_resolveStructureInfo;
 *     private _subtype = _info get "subtype"; // "school"
 */

params [["_classOrObject", "", [objNull, ""]]];

private _className = if (_classOrObject isEqualType objNull) then {
    typeOf _classOrObject
} else {
    _classOrObject
};

private _catalog = [] call DSC_core_fnc_getStructureCatalog;
private _byClass = _catalog get "byClass";

private _unknownSentinel = createHashMap;
private _record = _byClass getOrDefault [_className, _unknownSentinel];

if (_record isEqualTo _unknownSentinel) exitWith {
    if (isNil "DSC_structureUnknownWarned") then {
        missionNamespace setVariable ["DSC_structureUnknownWarned", createHashMap];
    };
    private _warned = missionNamespace getVariable ["DSC_structureUnknownWarned", createHashMap];

    if !(_className in _warned) then {
        WARNING_1("resolveStructureInfo - unknown structure class '%1', returning unknown record",_className);
        _warned set [_className, true];
    };

    createHashMapFromArray [
        ["subtype", "unknown"],
        ["category", "unknown"],
        ["displayName", "a building"],
        ["flags", []]
    ]
};

_record
