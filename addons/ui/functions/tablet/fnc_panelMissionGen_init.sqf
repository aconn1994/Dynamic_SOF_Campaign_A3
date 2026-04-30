#include "..\..\script_component.hpp"
#include "..\..\dialog\idc.hpp"
/*
 * Function: DSC_ui_fnc_panelMissionGen_init
 * Description:
 *     Populates Mission Gen panel combos / controls (both Standard and Advanced
 *     views). Called from the dialog's onLoad.
 *
 *     Combo entries store the canonical value via lbSetData; "(default)" /
 *     "(any)" entries store empty strings so the submit handler can treat
 *     them as "leave unset".
 *
 *     Sliders configured for 0-100 with step 10. Their value labels track via
 *     onSliderPosChanged -> DSC_ui_fnc_panelMissionGen_sliderLabel.
 *
 * Arguments:
 *     0: _display <DISPLAY> - tablet display
 */

params [["_display", displayNull, [displayNull]]];
if (isNull _display) exitWith {};

// ============================================================================
// Standard view combos
// ============================================================================

// --- Mission Type ---
private _typeCtrl = _display displayCtrl DSC_TABLET_IDC_MGEN_TYPE;
lbClear _typeCtrl;
{
    _x params ["_label", "_value"];
    private _idx = _typeCtrl lbAdd _label;
    _typeCtrl lbSetData [_idx, _value];
} forEach [
    ["Kill / Capture",   "KILL_CAPTURE"],
    ["Supply Destroy",   "SUPPLY_DESTROY"],
    ["Intel Gather",     "INTEL_GATHER"],
    ["Hostage Rescue",   "HOSTAGE_RESCUE"]
];
_typeCtrl lbSetCurSel 0;

// --- Mission Profile ---
private _profileCtrl = _display displayCtrl DSC_TABLET_IDC_MGEN_PROFILE;
lbClear _profileCtrl;
private _defaultIdx = _profileCtrl lbAdd "(profile default)";
_profileCtrl lbSetData [_defaultIdx, ""];

private _profiles = call DSC_core_fnc_getMissionProfiles;
{
    private _idx = _profileCtrl lbAdd _x;
    _profileCtrl lbSetData [_idx, _x];
} forEach (keys _profiles);
_profileCtrl lbSetCurSel 0;

// --- Density ---
private _densityCtrl = _display displayCtrl DSC_TABLET_IDC_MGEN_DENSITY;
lbClear _densityCtrl;
{
    _x params ["_label", "_value"];
    private _idx = _densityCtrl lbAdd _label;
    _densityCtrl lbSetData [_idx, _value];
} forEach [
    ["(profile default)", ""],
    ["Light",  "light"],
    ["Medium", "medium"],
    ["Heavy",  "heavy"]
];
_densityCtrl lbSetCurSel 0;

// --- Target Faction ---
private _factionCtrl = _display displayCtrl DSC_TABLET_IDC_MGEN_FACTION;
lbClear _factionCtrl;
private _anyIdx = _factionCtrl lbAdd "(weighted random)";
_factionCtrl lbSetData [_anyIdx, ""];

private _factionData = missionNamespace getVariable ["DSC_factionData", createHashMap];
private _hostileRoles = ["opFor", "opForPartner", "irregulars"];
{
    private _role = _x;
    private _roleData = _factionData getOrDefault [_role, createHashMap];
    private _factions = _roleData getOrDefault ["factions", []];
    {
        private _label = format ["[%1] %2", _role, _x];
        private _idx = _factionCtrl lbAdd _label;
        _factionCtrl lbSetData [_idx, _x];
    } forEach _factions;
} forEach _hostileRoles;
_factionCtrl lbSetCurSel 0;

// ============================================================================
// Advanced view controls
// ============================================================================

// --- AI Skill combo ---
private _skillCtrl = _display displayCtrl DSC_TABLET_IDC_MGEN_ADV_SKILL;
lbClear _skillCtrl;
{
    _x params ["_label", "_value"];
    private _idx = _skillCtrl lbAdd _label;
    _skillCtrl lbSetData [_idx, _value];
} forEach [
    ["(default)",     ""],
    ["CQB Baseline",  "cqb_baseline"],
    ["Moderate",      "moderate"],
    ["Hard",          "hard"],
    ["Realism",       "realism"]
];
_skillCtrl lbSetCurSel 0;

// --- Sliders (0-100, step 10) ---
private _setupSlider = {
    params ["_idc", "_labelIdc", "_initial"];
    private _ctrl = _display displayCtrl _idc;
    _ctrl sliderSetRange [0, 100];
    _ctrl sliderSetSpeed [10, 20];
    _ctrl sliderSetPosition _initial;
    private _lblCtrl = _display displayCtrl _labelIdc;
    _lblCtrl ctrlSetText format ["%1%2", round _initial, "%"];
};

[DSC_TABLET_IDC_MGEN_ADV_VEH_ARMED, DSC_TABLET_IDC_MGEN_ADV_VEH_ARMED_LBL, 50] call _setupSlider;
[DSC_TABLET_IDC_MGEN_ADV_AREA_PRES, DSC_TABLET_IDC_MGEN_ADV_AREA_PRES_LBL, 70] call _setupSlider;
[DSC_TABLET_IDC_MGEN_ADV_GUARD_COV, DSC_TABLET_IDC_MGEN_ADV_GUARD_COV_LBL, 40] call _setupSlider;

// ============================================================================
// Default view = Standard
// ============================================================================
[_display, "standard"] call DSC_ui_fnc_panelMissionGen_switchView;

// Initial state refresh
[_display] call DSC_ui_fnc_panelMissionGen_refreshState;
