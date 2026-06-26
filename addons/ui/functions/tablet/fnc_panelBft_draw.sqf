#include "..\..\script_component.hpp"
#include "..\..\dialog\idc.hpp"
/*
 * Function: DSC_ui_fnc_panelBft_draw
 * Description:
 *     Draw event handler for the BFT map control. Pulls the unified track
 *     list (server snapshot + local squad + player + objective) from
 *     DSC_ui_fnc_panelBft_buildTracks, paints one icon per entry, then
 *     overlays a highlight ring on the currently selected track (if any).
 *
 *     Icons are drawn north-up (dir = 0) so they stay readable regardless of
 *     entity facing. The `iconType` field on each track maps to a BI marker
 *     subtype (b_inf / b_motor_inf / b_mech_inf / b_armor / b_air / b_plane /
 *     b_naval / b_uav).
 *
 *     Stays cheap on purpose: one forEach over tracks, drawIcon per entity,
 *     no per-frame allocation beyond locals. Snapshot freshness comes from
 *     the server aggregator (~2.5s) — this just paints the latest.
 *
 * Arguments:
 *     0: _map <CONTROL> - the BFT map control (passed by Draw EH)
 */

params [["_map", controlNull, [controlNull]]];
if (isNull _map) exitWith {};

// ============================================================================
// Visual constants
// ============================================================================
private _colorWest    = [0.25, 0.55, 1.00, 1.0];
private _colorGuer    = [0.20, 0.85, 0.30, 1.0];
private _colorUav     = [0.30, 0.85, 0.95, 1.0];
private _colorSquad   = [1.00, 1.00, 1.00, 1.0];
private _colorPlayer  = [0.30, 0.95, 1.00, 1.0];
private _colorObj     = [1.00, 0.85, 0.10, 1.0];
private _colorSelect  = [1.00, 0.85, 0.10, 1.0];

// BI marker subtype → texture path.
private _textureFor = {
    params ["_iconType"];
    switch (_iconType) do {
        case "inf":       { "\A3\ui_f\data\map\markers\nato\b_inf.paa" };
        case "motor_inf": { "\A3\ui_f\data\map\markers\nato\b_motor_inf.paa" };
        case "mech_inf":  { "\A3\ui_f\data\map\markers\nato\b_mech_inf.paa" };
        case "armor":     { "\A3\ui_f\data\map\markers\nato\b_armor.paa" };
        case "air":       { "\A3\ui_f\data\map\markers\nato\b_air.paa" };
        case "plane":     { "\A3\ui_f\data\map\markers\nato\b_plane.paa" };
        case "naval":     { "\A3\ui_f\data\map\markers\nato\b_naval.paa" };
        case "uav":       { "\A3\ui_f\data\map\markers\nato\b_uav.paa" };
        case "objective": { "\A3\ui_f\data\map\markers\military\objective_ca.paa" };
        default            { "\A3\ui_f\data\map\markers\nato\b_unknown.paa" };
    };
};

private _colorForTrack = {
    params ["_cat", "_iconType", "_side"];
    switch (true) do {
        case (_cat == "objective"):          { _colorObj };
        case (_cat == "player"):             { _colorPlayer };
        case (_cat == "squad"):              { _colorSquad };
        case (_iconType == "uav"):           { _colorUav };
        case (_side isEqualTo west):         { _colorWest };
        case (_side isEqualTo independent):  { _colorGuer };
        default                               { [0.70, 0.70, 0.70, 1.0] };
    };
};

private _sizeFor = {
    params ["_cat", "_iconType"];
    switch (true) do {
        case (_cat == "objective"):  { 32 };
        case (_cat == "player"):     { 26 };
        case (_cat == "squad"):      { 18 };
        case (_iconType == "uav"):   { 26 };
        default                       { 22 };
    };
};

private _textSize  = 0.030;
private _font      = "PuristaMedium";
private _iconAngle = 0;

// ============================================================================
// Resolve current selection (for highlight ring)
// ============================================================================
private _display = uiNamespace getVariable ["DSC_TabletDisplay", displayNull];
private _selectedId = "";
if (!isNull _display) then {
    _selectedId = _display getVariable ["DSC_bftSelectedId", ""];
};

// ============================================================================
// Paint every visible track
// ============================================================================
private _tracks = [] call DSC_ui_fnc_panelBft_buildTracks;

{
    private _t        = _x;
    private _id       = _t getOrDefault ["id", ""];
    private _pos      = _t getOrDefault ["position", [0,0,0]];
    private _cat      = _t getOrDefault ["category", "unknown"];
    private _iconType = _t getOrDefault ["iconType", "inf"];
    private _side     = _t getOrDefault ["side", sideUnknown];
    private _label    = _t getOrDefault ["label", ""];
    private _str      = _t getOrDefault ["strength", 0];

    private _icon  = [_iconType] call _textureFor;
    private _color = [_cat, _iconType, _side] call _colorForTrack;
    private _size  = [_cat, _iconType] call _sizeFor;

    private _text = [_label, format ["%1 (%2)", _label, _str]] select (_str > 1);
    if (_cat == "objective") then { _text = format ["OBJ: %1", _label] };

    // BFT-vs-HC marker dedupe: commanded tracks already have a NATO type
    // icon attached by fnc_bftExecuteCommand via addGroupIcon, which the
    // engine renders on EVERY map control (including this one). Suppress
    // our own drawIcon for them so the icon doesn't double up. The
    // selection ring + QRF ring below still draw — those are BFT-only
    // decorations the HC system doesn't provide.
    if (_cat != "commanded") then {
        _map drawIcon [
            _icon, _color, _pos,
            _size, _size, _iconAngle,
            _text, 1, _textSize, _font, "right"
        ];
    };

    // Highlight ring on the selected track
    if (_id == _selectedId && {_selectedId != ""}) then {
        _map drawIcon [
            "\A3\ui_f\data\map\markers\military\circle_ca.paa",
            _colorSelect, _pos,
            _size + 20, _size + 20, _iconAngle,
            "", 0, _textSize, _font, "right"
        ];
    };

    // QRF visual highlight — yellow ring when staged, orange-red when the
    // reactor has triggered them in on contact (role "engaging" reserved
    // for future state; "QRF" is the steady-state tag).
    private _role = _t getOrDefault ["role", ""];
    if (_role == "QRF") then {
        private _ringColor = if ((_t getOrDefault ["triggered", false]) || (_role == "engaging")) then {
            [1.00, 0.40, 0.15, 0.85]
        } else {
            [1.00, 0.85, 0.10, 0.75]
        };
        _map drawIcon [
            "\A3\ui_f\data\map\markers\military\circle_ca.paa",
            _ringColor, _pos,
            _size + 10, _size + 10, _iconAngle,
            "", 0, _textSize, _font, "right"
        ];
    };
} forEach _tracks;

// ============================================================================
// Periodic info-card refresh (~1 Hz)
//
// The snapshot itself rebroadcasts every ~2.5s, so map labels and the info
// card naturally trail user actions by up to a tick. Re-populating the info
// card from the latest snapshot at 1 Hz keeps the displayed role / distance
// / position fresh without paying the cost every frame. If the selected
// track has despawned (no longer in the snapshot), drop the selection.
// ============================================================================
private _now         = diag_tickTime;
private _lastRefresh = _map getVariable ["DSC_bftLastInfoRefresh", 0];
if ((_now - _lastRefresh) >= 1.0 && {_selectedId != ""}) then {
    _map setVariable ["DSC_bftLastInfoRefresh", _now];

    private _matches = _tracks select { (_x getOrDefault ["id", ""]) == _selectedId };
    if (_matches isEqualTo []) then {
        if (!isNull _display) then {
            [_display] call DSC_ui_fnc_panelBft_clearSelection;
        };
    } else {
        if (!isNull _display) then {
            [_display, _matches select 0] call DSC_ui_fnc_panelBft_populateInfo;
        };
    };
};
