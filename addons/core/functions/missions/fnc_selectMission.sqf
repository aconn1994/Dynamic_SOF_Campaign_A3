#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_selectMission
 * Description:
 *     Selects and fully configures a mission. Accepts an optional template
 *     for controlled mission generation, or generates a random template
 *     when called without one.
 *
 *     This is the primary entry point for the mission loop. It delegates
 *     all resolution logic to fnc_resolveMissionConfig.
 *
 *     Random selection (no template):
 *       Picks KILL_CAPTURE with no profile. Density, location, and factions
 *       are determined by influence data and building counts.
 *
 *     Controlled selection (with template):
 *       Template fields constrain location, faction, density, QRF, etc.
 *       Mission profiles ("AFO", "DA") apply preset defaults.
 *       See fnc_resolveMissionConfig for full template field list.
 *
 * Arguments:
 *     0: _influenceData <HASHMAP> - From fnc_initInfluence
 *     1: _factionData <HASHMAP> - From fnc_initFactionData
 *     2: _template <HASHMAP> - (Optional) Partial mission template with overrides
 *
 * Return Value:
 *     <HASHMAP> - Complete mission config (empty hashmap on failure)
 *
 * Example:
 *     // Random mission (current behavior)
 *     private _config = [_influenceData, _factionData] call DSC_core_fnc_selectMission;
 *
 *     // AFO kill/capture at an isolated location
 *     private _tpl = createHashMapFromArray [["type", "KILL_CAPTURE"], ["missionProfile", "AFO"]];
 *     private _config = [_influenceData, _factionData, _tpl] call DSC_core_fnc_selectMission;
 *
 *     // Controlled: specific region + faction
 *     private _tpl = createHashMapFromArray [
 *         ["type", "KILL_CAPTURE"],
 *         ["regionCenter", getMarkerPos "pyrgos"],
 *         ["regionRadius", 5000],
 *         ["targetFaction", "OPF_G_F"],
 *         ["density", "light"]
 *     ];
 *     private _config = [_influenceData, _factionData, _tpl] call DSC_core_fnc_selectMission;
 */

params [
    ["_influenceData", createHashMap, [createHashMap]],
    ["_factionData", createHashMap, [createHashMap]],
    ["_template", createHashMap, [createHashMap]]
];

if (_influenceData isEqualTo createHashMap || _factionData isEqualTo createHashMap) exitWith {
    diag_log "DSC: selectMission - Missing influence or faction data";
    createHashMap
};

// ============================================================================
// Build random template if none provided
// ============================================================================
if (_template isEqualTo createHashMap) then {
    _template = createHashMapFromArray [
        ["type", "KILL_CAPTURE"],
        ["missionProfile", "AFO_populated_zone"]
    ];

    diag_log "DSC: selectMission - No template provided, using random KILL_CAPTURE";
};

// ============================================================================
// Delegate to resolver
// ============================================================================
private _config = [_template, _influenceData, _factionData] call DSC_core_fnc_resolveMissionConfig;

_config
