#include "script_component.hpp"

/*
 * Record position offsets of objects relative to a structure.
 * 
 * Finds all objects near a structure and calculates their position/direction
 * offset relative to the structure. Outputs formatted data ready to copy
 * into fnc_getStructurePositions.sqf.
 * 
 * Arguments:
 *   0: Structure object <OBJECT> - The reference structure
 *   1: (Optional) Search radius <NUMBER> - Radius to search for objects (default: 30)
 *   2: (Optional) Object types <ARRAY> - Types to search for (default: all units + vehicles)
 * 
 * Returns:
 *   Array of position records, each containing:
 *     - classname: Object classname
 *     - offset: [x, y, z] offset from structure in model space
 *     - relDir: Direction relative to structure facing
 * 
 * Usage:
 *   1. Place a structure in editor or Zeus
 *   2. Place units/statics at desired positions on the structure
 *   3. Run: [cursorObject] call DSC_core_fnc_recordStructurePositions
 *      (while looking at the structure)
 *   4. Check RPT log for formatted output
 *   5. Copy the data into fnc_getStructurePositions.sqf
 * 
 * Example:
 *   [cursorObject] call DSC_core_fnc_recordStructurePositions
 *   [myTower, 50, ["Man", "StaticWeapon"]] call DSC_core_fnc_recordStructurePositions
 */

params [
    ["_structure", objNull, [objNull]],
    ["_radius", 30, [0]],
    ["_objectTypes", ["Man", "StaticWeapon", "Car"], [[]]]
];

if (isNull _structure) exitWith {
    diag_log "DSC: fnc_recordStructurePositions - No structure provided";
    systemChat "ERROR: No structure provided. Look at a structure and use cursorObject.";
    []
};

private _structureClass = typeOf _structure;
private _structurePos = getPosASL _structure;
private _structureDir = getDir _structure;

// Find base class for this structure
private _baseClass = _structureClass;
{
    if (_structureClass isKindOf _x) exitWith {
        _baseClass = _x;
    };
} forEach ["Cargo_Tower_base_F", "Cargo_Patrol_base_F", "Cargo_HQ_base_F"];

diag_log format ["DSC: Recording positions for structure: %1 (base: %2)", _structureClass, _baseClass];
diag_log format ["DSC: Structure position: %1, direction: %2", _structurePos, _structureDir];

// Find all objects near structure
private _nearObjects = [];
{
    _nearObjects append ((_structure nearObjects [_x, _radius]) - [_structure]);
} forEach _objectTypes;

// Remove duplicates
_nearObjects = _nearObjects arrayIntersect _nearObjects;

if (_nearObjects isEqualTo []) exitWith {
    diag_log "DSC: No objects found near structure";
    systemChat "No objects found near structure. Place units/statics first.";
    []
};

diag_log format ["DSC: Found %1 objects near structure", count _nearObjects];

private _records = [];

{
    private _obj = _x;
    private _objClass = typeOf _obj;
    private _objPos = getPosASL _obj;
    private _objDir = getDir _obj;
    
    // Calculate offset in structure's model space
    private _offset = _structure worldToModel (ASLToAGL _objPos);
    
    // Calculate relative direction
    private _relDir = _objDir - _structureDir;
    if (_relDir < 0) then { _relDir = _relDir + 360 };
    if (_relDir >= 360) then { _relDir = _relDir - 360 };
    
    // Round values for cleaner output
    _offset = [
        (round ((_offset select 0) * 100)) / 100,
        (round ((_offset select 1) * 100)) / 100,
        (round ((_offset select 2) * 100)) / 100
    ];
    _relDir = round _relDir;
    
    private _record = createHashMapFromArray [
        ["classname", _objClass],
        ["offset", _offset],
        ["relDir", _relDir]
    ];
    
    _records pushBack _record;
    
    diag_log format ["DSC:   Object: %1", _objClass];
    diag_log format ["DSC:     Offset: %1, RelDir: %2", _offset, _relDir];
} forEach _nearObjects;

// Output formatted for copy/paste into data file
diag_log "DSC: ============ COPY THIS INTO fnc_getStructurePositions.sqf ============";
diag_log format ["DSC: [""%1"", [", _baseClass];

{
    private _record = _x;
    private _classname = _record get "classname";
    private _offset = _record get "offset";
    private _relDir = _record get "relDir";
    
    // Determine position type based on classname
    private _posType = "LOOKOUT";
    if (_classname isKindOf "StaticWeapon") then {
        if (toLower _classname find "hmg" >= 0 || toLower _classname find "gmg" >= 0) then { _posType = "MG" };
        if (toLower _classname find "_at_" >= 0 || toLower _classname find "static_at" >= 0 ||
            toLower _classname find "_aa_" >= 0 || toLower _classname find "static_aa" >= 0) then { _posType = "LAUNCHER" };
        if (toLower _classname find "mortar" >= 0) then { _posType = "MORTAR" };
    };
    
    diag_log format ["DSC:     [""%1"", [%2, %3]],", _posType, _offset, _relDir];
} forEach _records;

diag_log "DSC: ]]";
diag_log "DSC: =====================================================================";

systemChat format ["Recorded %1 positions. Check RPT log for data.", count _records];

_records
