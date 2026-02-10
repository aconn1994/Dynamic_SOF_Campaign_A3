#include "script_component.hpp"

/*
 * Spawn a static weapon or unit at a predefined structure position.
 * 
 * Uses offsets from fnc_getStructurePositions to place objects
 * at correct positions relative to any structure variant.
 * 
 * Arguments:
 *   0: Structure object <OBJECT> - The structure to spawn on
 *   1: Position type <STRING> - "HMG", "GMG", "AT", "AA", "LOOKOUT", etc.
 *   2: Classname to spawn <STRING> - Vehicle or unit classname
 *   3: Side <SIDE> - Side for created units/vehicles
 *   4: (Optional) Position index <NUMBER> - Which position of this type to use
 *      Default: -1 (random)
 *   5: (Optional) Create crew <BOOL> - Create gunner for static weapons
 *      Default: true
 * 
 * Returns:
 *   Array: [spawnedObject, crew] or [objNull, []] if failed
 * 
 * Examples:
 *   [myTower, "HMG", "O_HMG_01_high_F", east] call DSC_core_fnc_spawnAtStructurePosition
 *   [myTower, "LOOKOUT", "O_Soldier_F", east, 0, false] call DSC_core_fnc_spawnAtStructurePosition
 */

params [
    ["_structure", objNull, [objNull]],
    ["_positionType", "", [""]],
    ["_classname", "", [""]],
    ["_side", east, [east]],
    ["_posIndex", -1, [0]],
    ["_createCrew", true, [true]]
];

if (isNull _structure) exitWith {
    diag_log "DSC: fnc_spawnAtStructurePosition - No structure provided";
    [objNull, []]
};

if (_classname == "") exitWith {
    diag_log "DSC: fnc_spawnAtStructurePosition - No classname provided";
    [objNull, []]
};

// Determine base class of structure
private _structureClass = typeOf _structure;
private _baseClass = _structureClass;
{
    if (_structureClass isKindOf _x) exitWith {
        _baseClass = _x;
    };
} forEach ["Cargo_Tower_base_F", "Cargo_Patrol_base_F", "Cargo_HQ_base_F"];

// Get positions for this structure type
private _positions = [_baseClass, _positionType] call DSC_core_fnc_getStructurePositions;

if (count _positions == 0) exitWith {
    diag_log format ["DSC: fnc_spawnAtStructurePosition - No %1 positions for %2", _positionType, _baseClass];
    [objNull, []]
};

// Select position (random or specific index)
private _selectedPos = if (_posIndex < 0 || _posIndex >= count _positions) then {
    selectRandom _positions
} else {
    _positions select _posIndex
};

_selectedPos params ["_type", "_posData"];
_posData params ["_offset", "_relDir"];

// Calculate world position and direction
private _worldPos = _structure modelToWorld _offset;
private _worldDir = (getDir _structure) + _relDir;
if (_worldDir >= 360) then { _worldDir = _worldDir - 360 };

// Spawn the object
private _spawnedObject = objNull;
private _crew = [];

if (_classname isKindOf "Man") then {
    // Spawn infantry unit
    private _group = createGroup [_side, true];
    _spawnedObject = _group createUnit [_classname, _worldPos, [], 0, "NONE"];
    _spawnedObject setPos _worldPos;
    _spawnedObject setDir _worldDir;
    _spawnedObject disableAI "PATH";
    _crew = [_spawnedObject];
} else {
    // Spawn vehicle/static
    _spawnedObject = createVehicle [_classname, _worldPos, [], 0, "NONE"];
    _spawnedObject setPos _worldPos;
    _spawnedObject setDir _worldDir;
    
    // Create crew if requested and it's a static weapon
    if (_createCrew && _classname isKindOf "StaticWeapon") then {
        private _group = createGroup [_side, true];
        private _gunnerClass = switch (_side) do {
            case east: { "O_Soldier_F" };
            case west: { "B_Soldier_F" };
            case independent: { "I_Soldier_F" };
            default { "O_Soldier_F" };
        };
        private _gunner = _group createUnit [_gunnerClass, _worldPos, [], 0, "NONE"];
        _gunner moveInGunner _spawnedObject;
        _crew = [_gunner];
    };
};

diag_log format ["DSC: Spawned %1 at %2 (type: %3, dir: %4)", _classname, _worldPos, _positionType, _worldDir];

[_spawnedObject, _crew]
