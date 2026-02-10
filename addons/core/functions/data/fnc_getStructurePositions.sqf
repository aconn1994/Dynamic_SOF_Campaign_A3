#include "script_component.hpp"

/*
 * Get predefined positions for a structure type.
 * 
 * Returns position offsets for spawning units/statics on structures.
 * Positions are stored per base class and apply to all variants.
 * 
 * Arguments:
 *   0: Structure base class <STRING> - e.g. "Cargo_Tower_base_F"
 *   1: (Optional) Position type filter <STRING> - "HMG", "GMG", "AT", "AA", "LOOKOUT", etc.
 *      If omitted, returns all positions for the structure
 * 
 * Returns:
 *   Array of position definitions, each containing:
 *     [type, [offset, relDir]]
 *   Or empty array if structure not found
 * 
 * Examples:
 *   ["Cargo_Tower_base_F"] call DSC_core_fnc_getStructurePositions
 *   // Returns all positions for tower
 *   
 *   ["Cargo_Tower_base_F", "HMG"] call DSC_core_fnc_getStructurePositions
 *   // Returns only HMG positions
 */

params [
    ["_baseClass", "", [""]],
    ["_positionType", "", [""]]
];

if (_baseClass == "") exitWith {
    diag_log "DSC: fnc_getStructurePositions - No base class provided";
    []
};

// ============================================================================
// STRUCTURE POSITION DEFINITIONS
// ============================================================================
// Format: [baseClass, [[type, [offset, relDir]], ...]]
// 
// Position types:
//   - MG (HMG/GMG - interchangeable mounted guns)
//   - LAUNCHER (AT/AA - interchangeable missile systems)
//   - MORTAR (static indirect fire)
//   - LOOKOUT (infantry observation)
//   - SNIPER (elevated sniper position)
//
// Offset: [x, y, z] in model space relative to structure center
// RelDir: Direction relative to structure facing (0-360)
// ============================================================================

private _structurePositions = createHashMapFromArray [
    
    // ========================================
    // Cargo Tower (tall tower with multiple levels)
    // ========================================
    ["Cargo_Tower_base_F", [
        ["MG", [[4.67, 3.92, 4.99], 91]],
        ["MG", [[4.64, -3.06, 4.99], 95]],
        ["MG", [[-1.7, -5.11, 4.89], 180]],
        ["MG", [[-3.94, -5.32, 4.89], 178]],
        ["MG", [[-4.12, 5.38, 4.93], 360]],
        ["MG", [[-2.04, 5.43, 4.97], 360]],
        ["MG", [[-4.18, -0.98, 4.99], 270]],
        ["LAUNCHER", [[-0.5, 1.23, 7.61], 46]],
        ["LAUNCHER", [[-3.46, -1.59, 5.01], 207]]
    ]],
    
    // ========================================
    // Cargo Patrol (small patrol structure)
    // ========================================
    ["Cargo_Patrol_base_F", [
        ["MG", [[1.46, -1.07, -0.57], 89]],
        ["MG", [[-1.44, -1.16, -0.57], 181]]
    ]],
    
    // ========================================
    // Cargo HQ (medium HQ structure)
    // ========================================
    ["Cargo_HQ_base_F", [
        ["MG", [[-2.46, pi, -0.76], 0]],
        ["MG", [[-2.78, -5.02, -0.77], 271]],
        ["MG", [[-0.93, -4.82, -0.76], 182]],
        ["MG", [[5.88, 5.23, -0.79], 58]],
        ["MG", [[6.32, -1.46, -0.76], 99]],
        ["LAUNCHER", [[3.24, -0.28, -0.75], 0]],
        ["LAUNCHER", [[-1, -0.12, -0.75], 183]],
        ["LAUNCHER", [[2.96, -4.64, 1.88], 360]]
    ]]
    
    // ========================================
    // Add more structures here as needed
    // Use fnc_recordStructurePositions to capture offsets
    // ========================================
];

// Get positions for this structure
private _positions = _structurePositions getOrDefault [_baseClass, []];

if (count _positions == 0) exitWith {
    diag_log format ["DSC: fnc_getStructurePositions - No positions defined for %1", _baseClass];
    []
};

// Filter by type if specified
if (_positionType != "") then {
    _positions = _positions select { (_x select 0) == _positionType };
};

_positions
