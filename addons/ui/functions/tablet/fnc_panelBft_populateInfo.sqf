#include "..\..\script_component.hpp"
#include "..\..\dialog\idc.hpp"
/*
 * Function: DSC_ui_fnc_panelBft_populateInfo
 * Description:
 *     Writes a selected BFT track's details into the info card's value
 *     labels (one ctrlSetText per row) and reveals every info card control
 *     (chrome + 7 key labels + 7 value labels). Plain RscText labels are
 *     used — no parseText / RscStructuredText — so every field renders
 *     predictably.
 *
 *     Body fields:
 *       Category    e.g. "Ground patrol", "Garrison", "ISR drone", "Self"
 *       Side        NATO / OPFOR / Partner / Civilian
 *       Faction     factionClass (if known)
 *       Strength    alive unit count
 *       Vehicle     vehicle displayName (if mounted)
 *       Distance    metres from player
 *       To Obj      metres from active mission objective (if any)
 *
 * Arguments:
 *     0: _display <DISPLAY>  - tablet display
 *     1: _track   <HASHMAP>  - track entry from panelBft_buildTracks
 */

params [
    ["_display", displayNull,   [displayNull]],
    ["_track",   createHashMap, [createHashMap]]
];

if (isNull _display) exitWith {};
if (_track isEqualTo createHashMap) exitWith {};

// ----------------------------------------------------------------------------
// Derived field values
// ----------------------------------------------------------------------------
private _label = _track getOrDefault ["label", ""];
private _cat   = _track getOrDefault ["category", ""];

private _catLabel = switch (toLower _cat) do {
    case "garrison":  { "Garrison" };
    case "ground":    { "Ground patrol" };
    case "air":       { "Air patrol" };
    case "foot":      { "Foot patrol" };
    case "boat":      { "Boat patrol" };
    case "uav":       { "ISR drone" };
    case "mission":   { "Attached" };
    case "squad":     { "Squad member" };
    case "player":    { "Self" };
    case "objective": { "Objective" };
    default            { _cat };
};

private _side    = _track getOrDefault ["side", sideUnknown];
private _sideLbl = switch (true) do {
    case (_side isEqualTo west):        { "NATO (west)" };
    case (_side isEqualTo east):        { "OPFOR (east)" };
    case (_side isEqualTo independent): { "Partner (independent)" };
    case (_side isEqualTo civilian):    { "Civilian" };
    default                              { "—" };
};

private _faction    = _track getOrDefault ["faction", ""];
private _factionLbl = [_faction, "—"] select (_faction == "");

private _strength = _track getOrDefault ["strength", 0];
private _strLbl   = [format ["%1 alive", _strength], "—"] select (_strength <= 0);

private _veh    = _track getOrDefault ["vehicle", objNull];
private _vehLbl = "—";
if (!isNull _veh && {alive _veh}) then {
    private _displayName = getText (configOf _veh >> "displayName");
    _vehLbl = [_displayName, typeOf _veh] select (_displayName == "");
};

private _pos        = _track getOrDefault ["position", [0,0,0]];
private _distPlayer = format ["%1 m", round (player distance2D _pos)];

private _mission = missionNamespace getVariable ["DSC_currentMission", createHashMap];
private _objPos  = _mission getOrDefault ["location", []];
private _distObj = "—";
if (_objPos isEqualType [] && {count _objPos >= 2} && {_cat != "objective"}) then {
    _distObj = format ["%1 m", round (_pos distance2D _objPos)];
};

// ----------------------------------------------------------------------------
// Write each value into its label. The sidebar itself is always visible
// while the BFT tab is active (switchPanel manages that); we only update
// content here. Null-guarded so a missing IDC degrades that one row
// instead of bailing the whole card.
// ----------------------------------------------------------------------------
private _setText = {
    params ["_idc", "_text"];
    private _c = _display displayCtrl _idc;
    if (!isNull _c) then { _c ctrlSetText _text };
};

[DSC_TABLET_IDC_BFT_INFO_TITLE,        toUpper _label] call _setText;
[DSC_TABLET_IDC_BFT_INFO_VAL_CATEGORY, _catLabel]      call _setText;
[DSC_TABLET_IDC_BFT_INFO_VAL_SIDE,     _sideLbl]       call _setText;
[DSC_TABLET_IDC_BFT_INFO_VAL_FACTION,  _factionLbl]    call _setText;
[DSC_TABLET_IDC_BFT_INFO_VAL_STRENGTH, _strLbl]        call _setText;
[DSC_TABLET_IDC_BFT_INFO_VAL_VEHICLE,  _vehLbl]        call _setText;
[DSC_TABLET_IDC_BFT_INFO_VAL_DIST,     _distPlayer]    call _setText;
[DSC_TABLET_IDC_BFT_INFO_VAL_DIST_OBJ, _distObj]       call _setText;

// ----------------------------------------------------------------------------
// Configure the BFT-3 command buttons based on the selected track's state.
//
//   commandable = false (player/squad/UAV/objective) → everything disabled
//   commandable = true,  role == ""                  → TAKE only
//   commandable = true,  role != ""                  → MOVE / QRF / RELEASE
//
// MOVE TO OBJ and SET AS QRF additionally require an active mission
// objective; without one their target is undefined.
// ----------------------------------------------------------------------------
private _commandable = _track getOrDefault ["commandable", false];
private _role        = _track getOrDefault ["role", ""];
private _taken       = _role != "";
private _hasObj      = _objPos isEqualType [] && {count _objPos >= 2};

private _setEnabled = {
    params ["_idc", "_enabled"];
    private _c = _display displayCtrl _idc;
    if (!isNull _c) then { _c ctrlEnable _enabled };
};

[DSC_TABLET_IDC_BFT_CMD_TAKE,      _commandable && !_taken]              call _setEnabled;
[DSC_TABLET_IDC_BFT_CMD_MOVE_HERE, _commandable &&  _taken]              call _setEnabled;
[DSC_TABLET_IDC_BFT_CMD_MOVE_OBJ,  _commandable &&  _taken && _hasObj]   call _setEnabled;
[DSC_TABLET_IDC_BFT_CMD_QRF,       _commandable &&  _taken && _hasObj]   call _setEnabled;
[DSC_TABLET_IDC_BFT_CMD_RELEASE,   _commandable &&  _taken]              call _setEnabled;
