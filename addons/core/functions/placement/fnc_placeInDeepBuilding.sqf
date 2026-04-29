#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_placeInDeepBuilding
 * Description:
 *     Placement strategy: spawn a single unit deep inside a building, ideally
 *     surrounded by existing garrison defenders.
 *
 *     Tries three paths in order:
 *       1. Bodyguard path - join an existing garrison unit's group inside a
 *          building with enough free positions. HVT inherits group behavior.
 *       2. Structure path - pick any structure at the location with usable
 *          buildingPos slots, create a fresh group, place inside.
 *       3. Center fallback - spawn at the location centerpoint in a fresh
 *          group. Used only when no buildings have positions at all.
 *
 *     Placement is the only concern. Behavior wiring (SAFE/GREEN, combat
 *     activation, mission bookkeeping, classname resolution) belongs to the
 *     caller.
 *
 * Arguments:
 *     0: _archetype <HASHMAP> - Placement parameters:
 *        "unitClass"     <STRING>  Resolved classname to spawn (required)
 *        "side"          <SIDE>    Side for fresh groups (default: east)
 *        "hasBodyguards" <BOOL>    Try bodyguard path first (default: true)
 *        "minPositions"  <NUMBER>  Min buildingPos slots required for the
 *                                  bodyguard-host building (default: 3)
 *     1: _location <HASHMAP> - Location object from fnc_scanLocations
 *     2: _ao <HASHMAP> - Populated AO data from fnc_populateAO
 *
 * Return Value:
 *     <HASHMAP>:
 *        "unit"           <OBJECT>  The placed unit (objNull on total failure)
 *        "building"       <OBJECT>  Building used (objNull for "center" path)
 *        "position"       <ARRAY>   World position used
 *        "group"          <GROUP>   Group the unit ended up in
 *        "withBodyguards" <BOOL>    True iff bodyguard path succeeded
 *        "fallback"       <STRING>  "bodyguard" | "structure" | "center"
 *
 * Example:
 *     private _placement = [
 *         createHashMapFromArray [["unitClass", "O_officer_F"], ["side", east]],
 *         _location,
 *         _ao
 *     ] call DSC_core_fnc_placeInDeepBuilding;
 *     private _hvt = _placement get "unit";
 */

params [
    ["_archetype", createHashMap, [createHashMap]],
    ["_location", createHashMap, [createHashMap]],
    ["_ao", createHashMap, [createHashMap]]
];

private _unitClass = _archetype getOrDefault ["unitClass", ""];
private _side = _archetype getOrDefault ["side", east];
private _hasBodyguards = _archetype getOrDefault ["hasBodyguards", true];
private _minPositions = _archetype getOrDefault ["minPositions", 3];

if (_unitClass isEqualTo "") exitWith {
    diag_log "DSC: placeInDeepBuilding called without unitClass";
    createHashMapFromArray [
        ["unit", objNull],
        ["building", objNull],
        ["position", [0,0,0]],
        ["group", grpNull],
        ["withBodyguards", false],
        ["fallback", "none"]
    ]
};

private _locationPos = _location get "position";
private _garrisonUnits = _ao getOrDefault ["garrisonUnits", []];

private _unit = objNull;
private _building = objNull;
private _pos = [0,0,0];
private _group = grpNull;
private _withBodyguards = false;
private _fallback = "";

// ----------------------------------------------------------------------------
// Path 1: bodyguard host
// ----------------------------------------------------------------------------
if (_hasBodyguards && { _garrisonUnits isNotEqualTo [] }) then {
    private _candidateUnits = _garrisonUnits select {
        private _b = nearestBuilding _x;
        !isNull _b && { count (_b buildingPos -1) >= _minPositions }
    };

    if (_candidateUnits isNotEqualTo []) then {
        private _bodyguard = selectRandom _candidateUnits;
        private _hostBuilding = nearestBuilding _bodyguard;
        private _buildingPositions = _hostBuilding buildingPos -1;

        private _occupiedPositions = _garrisonUnits apply { getPos _x };
        private _freePositions = _buildingPositions select {
            private _p = _x;
            (_occupiedPositions findIf { _x distance _p < 1 }) == -1
        };

        if (_freePositions isNotEqualTo []) then {
            _pos = selectRandom _freePositions;
            _group = group _bodyguard;
            _unit = _group createUnit [_unitClass, _pos, [], 0, "NONE"];
            _unit setPos _pos;
            _unit setUnitPos "UP";
            _unit disableAI "PATH";
            _building = _hostBuilding;
            _withBodyguards = true;
            _fallback = "bodyguard";
            diag_log format ["DSC: placeInDeepBuilding - bodyguard path in %1", _building];
        };
    };
};

// ----------------------------------------------------------------------------
// Path 2: any structure with positions
// ----------------------------------------------------------------------------
if (isNull _unit) then {
    private _allStructures = _location getOrDefault ["structures", []];
    _allStructures = _allStructures select { (_x buildingPos -1) isNotEqualTo [] };

    if (_allStructures isNotEqualTo []) then {
        _group = createGroup [_side, true];
        _building = selectRandom _allStructures;
        private _buildingPositions = _building buildingPos -1;
        _pos = selectRandom _buildingPositions;
        _unit = _group createUnit [_unitClass, _pos, [], 0, "NONE"];
        _unit setPos _pos;
        _unit setUnitPos "UP";
        _fallback = "structure";
        diag_log format ["DSC: placeInDeepBuilding - structure path in %1", _building];
    };
};

// ----------------------------------------------------------------------------
// Path 3: location center fallback
// ----------------------------------------------------------------------------
if (isNull _unit) then {
    _group = createGroup [_side, true];
    _pos = _locationPos;
    _unit = _group createUnit [_unitClass, _pos, [], 5, "NONE"];
    _fallback = "center";
    diag_log "DSC: placeInDeepBuilding - center fallback (no buildings with positions)";
};

createHashMapFromArray [
    ["unit", _unit],
    ["building", _building],
    ["position", _pos],
    ["group", _group],
    ["withBodyguards", _withBodyguards],
    ["fallback", _fallback]
]
