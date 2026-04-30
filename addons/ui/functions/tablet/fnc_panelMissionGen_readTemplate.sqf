#include "..\..\script_component.hpp"
#include "..\..\dialog\idc.hpp"
/*
 * Function: DSC_ui_fnc_panelMissionGen_readTemplate
 * Description:
 *     Reads Mission Gen panel controls and returns a partial template hashmap
 *     containing only fields the user actually set. Empty / "default" values
 *     are omitted so the resolver's profile / auto-fill cascade still applies.
 *
 *     Reads the always-visible "core" controls always; if the Advanced view
 *     is active, additionally reads location / population / mission feel
 *     fields. The Advanced view is detected via display-namespace state set
 *     by panelMissionGen_switchView.
 *
 *     Also returns the "Replace current" flag separately so the caller can
 *     decide whether to fire DSC_tablet_abortMission.
 *
 * Arguments:
 *     0: _display <DISPLAY>
 *
 * Return Value:
 *     [_template <HASHMAP>, _replace <BOOL>]
 */

params [["_display", displayNull, [displayNull]]];
if (isNull _display) exitWith { [createHashMap, false] };

private _readCombo = {
    params ["_idc"];
    private _ctrl = _display displayCtrl _idc;
    private _sel = lbCurSel _ctrl;
    if (_sel < 0) exitWith { "" };
    _ctrl lbData _sel
};

private _readEditNumber = {
    params ["_idc"];
    private _ctrl = _display displayCtrl _idc;
    private _txt = ctrlText _ctrl;
    if (_txt == "") exitWith { -1 };
    parseNumber _txt
};

private _readCheck = {
    params ["_idc"];
    private _ctrl = _display displayCtrl _idc;
    cbChecked _ctrl
};

private _readSliderPct = {
    params ["_idc"];
    private _ctrl = _display displayCtrl _idc;
    (sliderPosition _ctrl) / 100
};

private _splitTags = {
    params ["_text"];
    if (_text == "") exitWith { [] };
    // splitString with multi-char delimiter splits on ANY listed char,
    // so "isolated, low_density" -> ["isolated", "low_density"] cleanly.
    private _parts = _text splitString ", \t";
    _parts select { _x != "" }
};

private _template = createHashMap;

// ============================================================================
// CORE FIELDS (always visible)
// ============================================================================
private _type = [DSC_TABLET_IDC_MGEN_TYPE] call _readCombo;
if (_type != "") then { _template set ["type", _type] };

private _profile = [DSC_TABLET_IDC_MGEN_PROFILE] call _readCombo;
if (_profile != "") then { _template set ["missionProfile", _profile] };

private _density = [DSC_TABLET_IDC_MGEN_DENSITY] call _readCombo;
if (_density != "") then { _template set ["density", _density] };

private _faction = [DSC_TABLET_IDC_MGEN_FACTION] call _readCombo;
if (_faction != "") then { _template set ["targetFaction", _faction] };

private _qrf = [DSC_TABLET_IDC_MGEN_QRF] call _readCheck;
_template set ["qrfEnabled", _qrf];

private _minDist = [DSC_TABLET_IDC_MGEN_MIN_DIST] call _readEditNumber;
private _maxDist = [DSC_TABLET_IDC_MGEN_MAX_DIST] call _readEditNumber;
if (_minDist > 0) then { _template set ["minDistance", _minDist] };
if (_maxDist > 0) then { _template set ["maxDistance", _maxDist] };

private _atPlayer = [DSC_TABLET_IDC_MGEN_AT_PLAYER] call _readCheck;
if (_atPlayer && _maxDist > 0) then {
    _template set ["regionCenter", getPosASL player];
    _template set ["regionRadius", _maxDist];
};

private _replace = [DSC_TABLET_IDC_MGEN_REPLACE] call _readCheck;

// ============================================================================
// ADVANCED FIELDS (only if Advanced view active)
// ============================================================================
private _view = _display getVariable ["DSC_mgenView", "standard"];

if (_view == "advanced") then {

    // --- Tag filters ---
    private _reqTagsTxt = ctrlText (_display displayCtrl DSC_TABLET_IDC_MGEN_ADV_REQ_TAGS);
    private _reqTags = [_reqTagsTxt] call _splitTags;
    if (_reqTags isNotEqualTo []) then { _template set ["requiredTags", _reqTags] };

    private _excTagsTxt = ctrlText (_display displayCtrl DSC_TABLET_IDC_MGEN_ADV_EXC_TAGS);
    private _excTags = [_excTagsTxt] call _splitTags;
    if (_excTags isNotEqualTo []) then { _template set ["excludeTags", _excTags] };

    // --- Min building count ---
    private _minBldg = [DSC_TABLET_IDC_MGEN_ADV_MIN_BLDG] call _readEditNumber;
    if (_minBldg >= 0) then { _template set ["minBuildingCount", _minBldg] };

    // --- Garrison anchors [min,max] ---
    private _garMin = [DSC_TABLET_IDC_MGEN_ADV_GAR_MIN] call _readEditNumber;
    private _garMax = [DSC_TABLET_IDC_MGEN_ADV_GAR_MAX] call _readEditNumber;
    if (_garMin >= 0 && _garMax >= 0) then {
        _template set ["garrisonAnchors", [_garMin, _garMax]];
    };

    // --- Patrol count ---
    private _patrols = [DSC_TABLET_IDC_MGEN_ADV_PATROLS] call _readEditNumber;
    if (_patrols >= 0) then { _template set ["patrolCount", [_patrols, _patrols]] };

    // --- Max vehicles ---
    private _maxVeh = [DSC_TABLET_IDC_MGEN_ADV_VEHICLES] call _readEditNumber;
    if (_maxVeh >= 0) then { _template set ["maxVehicles", _maxVeh] };

    // --- Sliders ---
    _template set ["vehicleArmedChance", [DSC_TABLET_IDC_MGEN_ADV_VEH_ARMED] call _readSliderPct];
    _template set ["areaPresenceChance", [DSC_TABLET_IDC_MGEN_ADV_AREA_PRES] call _readSliderPct];
    _template set ["guardCoverage",      [DSC_TABLET_IDC_MGEN_ADV_GUARD_COV] call _readSliderPct];

    // --- AI skill ---
    private _skill = [DSC_TABLET_IDC_MGEN_ADV_SKILL] call _readCombo;
    if (_skill != "") then { _template set ["skillProfile", _skill] };

    // --- QRF delay [min,max] ---
    private _qMin = [DSC_TABLET_IDC_MGEN_ADV_QRF_MIN] call _readEditNumber;
    private _qMax = [DSC_TABLET_IDC_MGEN_ADV_QRF_MAX] call _readEditNumber;
    if (_qMin >= 0 && _qMax >= 0) then {
        _template set ["qrfDelay", [_qMin, _qMax]];
    };
};

[_template, _replace]
