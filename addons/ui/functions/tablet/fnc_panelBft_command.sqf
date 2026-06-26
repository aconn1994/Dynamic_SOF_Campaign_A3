#include "..\..\script_component.hpp"
#include "..\..\dialog\idc.hpp"
/*
 * Function: DSC_ui_fnc_panelBft_command
 * Description:
 *     Client-side dispatcher for BFT-3 command buttons. Bound to the five
 *     buttons in the info card sidebar (TAKE / MOVE HERE / MOVE TO OBJ /
 *     SET QRF / RELEASE).
 *
 *     Responsibilities:
 *       - Resolve the currently selected track from the tablet display.
 *       - Refuse silently if no track / not commandable.
 *       - Lazy-promote the player to High Commander via BIS_fnc_addCommander
 *         the first time "take" is used in the session.
 *       - Run hcSetGroup / hcRemoveGroup locally on the calling client
 *         (HC has commander-locality), and assemble the action payload.
 *       - Hand off via CBA serverEvent "DSC_bft_command" so the server-
 *         local AI group receives its move / role-tag mutation where it's
 *         local.
 *
 * Arguments:
 *     0: _display <DISPLAY> - tablet display
 *     1: _action  <STRING>  - "take" | "moveHere" | "moveObj" | "qrf" | "release"
 */

params [
    ["_display", displayNull, [displayNull]],
    ["_action",  "",          [""]]
];

if (isNull _display) exitWith {};
if (_action == "")  exitWith {};

// ----------------------------------------------------------------------------
// Resolve selected track
// ----------------------------------------------------------------------------
private _selectedId = _display getVariable ["DSC_bftSelectedId", ""];
if (_selectedId == "") exitWith {
    systemChat "BFT: select a friendly track first";
};

private _tracks = [] call DSC_ui_fnc_panelBft_buildTracks;
private _matches = _tracks select { (_x getOrDefault ["id", ""]) == _selectedId };
if (_matches isEqualTo []) exitWith {
    systemChat "BFT: selected track no longer exists";
    [_display] call DSC_ui_fnc_panelBft_clearSelection;
};

private _track = _matches select 0;
if !(_track getOrDefault ["commandable", false]) exitWith {
    systemChat "BFT: this track can't be commanded";
};

private _grp = _track getOrDefault ["group", grpNull];
if (isNull _grp) exitWith {
    systemChat "BFT: track has no group reference";
};

// ----------------------------------------------------------------------------
// HC management — locality-bound to the commander, so do it on the client
// BEFORE firing the server event. Idempotent for repeat takes.
// ----------------------------------------------------------------------------
if (_action == "take") then {
    if (isNil "DSC_bftHcInitialized") then {
        player call BIS_fnc_addCommander;
        // Belt-and-braces: BIS_fnc_addCommander already toggles these
        // internally on most builds, but explicit calls guarantee HC
        // group icons render on the main game map + 3D world.
        setGroupIconsVisible [true, true];
        DSC_bftHcInitialized = true;
    };
    player hcSetGroup [_grp, "Bravo", ""];
};

if (_action == "release") then {
    player hcRemoveGroup _grp;
};

// ----------------------------------------------------------------------------
// Build action payload
// ----------------------------------------------------------------------------
private _params = switch (_action) do {
    case "moveHere": { [getPosWorld player] };
    case "moveObj":  {
        private _m = missionNamespace getVariable ["DSC_currentMission", createHashMap];
        private _objPos = _m getOrDefault ["location", []];
        if (_objPos isEqualType [] && {count _objPos >= 2}) then { [_objPos] } else {
            systemChat "BFT: no active mission objective";
            [getPosWorld player]
        };
    };
    case "qrf": {
        private _m = missionNamespace getVariable ["DSC_currentMission", createHashMap];
        private _objPos = _m getOrDefault ["location", []];
        if (_objPos isEqualType [] && {count _objPos >= 2}) then { [_objPos] } else {
            systemChat "BFT: no active mission objective (QRF staging at player)";
            [getPosWorld player]
        };
    };
    default { [] };
};

// ----------------------------------------------------------------------------
// Server dispatch — group orders run where the group is local (server).
// ----------------------------------------------------------------------------
[
    "DSC_bft_command",
    [netId _grp, _action, _params, getPlayerUID player, name player]
] call CBA_fnc_serverEvent;

// ----------------------------------------------------------------------------
// Optimistic local refresh — predict the role the server is about to set and
// re-populate the info card immediately, so buttons flip without waiting for
// the next snapshot broadcast (~2.5s). The Draw-EH periodic refresh in
// panelBft_draw reconciles us back to the snapshot truth shortly after.
// ----------------------------------------------------------------------------
private _expectedRole = switch (_action) do {
    case "take":     { "commanded" };
    case "moveHere": { "moving" };
    case "moveObj":  { "moving_obj" };
    case "qrf":      { "QRF" };
    case "release":  { "" };
    default          { _track getOrDefault ["role", ""] };
};

private _localTrack = +_track;
_localTrack set ["role", _expectedRole];
[_display, _localTrack] call DSC_ui_fnc_panelBft_populateInfo;

private _actionMsg = switch (_action) do {
    case "take":     { "TAKE COMMAND" };
    case "moveHere": { "MOVE HERE" };
    case "moveObj":  { "MOVE TO OBJ" };
    case "qrf":      { "SET AS QRF" };
    case "release":  { "RELEASE" };
    default          { _action };
};
systemChat format ["BFT: %1 sent to %2", _actionMsg, groupId _grp];
