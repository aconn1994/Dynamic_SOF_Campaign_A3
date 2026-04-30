#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_initServerDebug
 * Description:
 *     Server-side debug/admin extension layer. Runs after fnc_initServer.
 *     Initializes globals and registers CBA event handlers used by the
 *     Commander's Tablet to inject mission templates and abort the active
 *     mission.
 *
 *     This is the home for any future server-side debug machinery (state
 *     dumps, scenario probes, AI inspection tooling, etc.) so the production
 *     init path stays clean.
 *
 *     Anyone may currently invoke these events. Add admin gating here later
 *     by checking _uid against an allowlist.
 *
 * Globals set:
 *     DSC_missionQueue            <ARRAY>  FIFO queue of partial templates
 *     DSC_missionAbortRequested   <BOOL>   abort flag honored by mission loop
 *
 * CBA events handled:
 *     "DSC_tablet_queueMission" [_template, _uid, _name]
 *     "DSC_tablet_abortMission" [_uid, _name]
 *
 * Arguments: none
 */

if (!isServer) exitWith {};

diag_log "DSC: ========== Initializing Server Debug Layer ==========";

// ----------------------------------------------------------------------------
// Globals (idempotent — fnc_initServer also defends these)
// ----------------------------------------------------------------------------
if (isNil { missionNamespace getVariable "DSC_missionQueue" }) then {
    missionNamespace setVariable ["DSC_missionQueue", [], true];
};
if (isNil { missionNamespace getVariable "DSC_missionAbortRequested" }) then {
    missionNamespace setVariable ["DSC_missionAbortRequested", false, true];
};

// ----------------------------------------------------------------------------
// CBA event: queue a mission template
// ----------------------------------------------------------------------------
["DSC_tablet_queueMission", {
    params [
        ["_template", createHashMap, [createHashMap]],
        ["_uid", "", [""]],
        ["_name", "", [""]]
    ];

    if (_template isEqualTo createHashMap) exitWith {
        diag_log format ["DSC: tablet queue rejected (empty template) from %1 [%2]", _name, _uid];
    };

    private _queue = missionNamespace getVariable ["DSC_missionQueue", []];
    _queue pushBack _template;
    missionNamespace setVariable ["DSC_missionQueue", _queue, true];

    diag_log format ["DSC: tablet queued mission from %1 [%2] - queue size %3 - template %4",
        _name, _uid, count _queue, _template];
}] call CBA_fnc_addEventHandler;

// ----------------------------------------------------------------------------
// CBA event: abort current mission
// ----------------------------------------------------------------------------
["DSC_tablet_abortMission", {
    params [
        ["_uid", "", [""]],
        ["_name", "", [""]]
    ];

    if (!(missionNamespace getVariable ["missionInProgress", false])) exitWith {
        diag_log format ["DSC: tablet abort ignored (no active mission) from %1 [%2]", _name, _uid];
    };

    missionNamespace setVariable ["DSC_missionAbortRequested", true, true];
    diag_log format ["DSC: tablet abort requested from %1 [%2]", _name, _uid];
}] call CBA_fnc_addEventHandler;

diag_log "DSC: Server debug layer initialized (tablet events registered)";
