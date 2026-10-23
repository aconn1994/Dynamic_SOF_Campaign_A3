#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_getCompletionTypes
 * Description:
 *     Returns the completion condition registry. Conditions are pure
 *     functions over a mission state hashmap — they read state and return
 *     a bool. The raid generator's monitor calls fnc_evaluateCompletion
 *     each tick, which dispatches to the named condition's check block.
 *
 *     Each entry's "check" block receives one parameter: the state hashmap
 *     populated by the raid generator with whatever keys the condition
 *     needs (hvt, objects, hostages, defenders, intelGathered, ...).
 *
 *     Compound conditions are handled at the dispatcher level — pass an
 *     inline "completionExpr" code block to fnc_evaluateCompletion.
 *
 *     Field reference:
 *       "check"          <CODE>    Receives [_state]; returns BOOL.
 *       "successMsg"     <STRING>  Shown when check returns true on its own.
 *       "partialMsg"     <STRING>  Shown when mission ends without check
 *                                  having returned true (timeout, abort).
 *       "stateKeys"      <ARRAY>   Hashmap keys the condition expects.
 *                                  Documentation only; raid generator
 *                                  must populate them.
 *
 * Arguments: None
 *
 * Return Value:
 *     <HASHMAP> - Condition name -> condition hashmap.
 *
 * Example:
 *     private _types = call DSC_core_fnc_getCompletionTypes;
 *     private _killCapture = _types get "KILL_CAPTURE";
 */

createHashMapFromArray [

    ["KILL_CAPTURE", createHashMapFromArray [
        ["check", {
            params ["_state"];
            private _hvt = _state getOrDefault ["hvt", objNull];
            if (isNull _hvt) exitWith { false };
            !alive _hvt || { captive _hvt }
        }],
        ["successMsg", "HVT eliminated or captured"],
        ["partialMsg", "HVT escaped"],
        ["stateKeys", ["hvt"]]
    ]],

    ["ALL_DESTROYED", createHashMapFromArray [
        ["check", {
            params ["_state"];
            private _objects = _state getOrDefault ["objects", []];
            if (_objects isEqualTo []) exitWith { false };
            ({ alive _x } count _objects) == 0
        }],
        ["successMsg", "All objects destroyed"],
        ["partialMsg", "Objects remain intact"],
        ["stateKeys", ["objects"]]
    ]],

    ["ANY_INTERACTED", createHashMapFromArray [
        ["check", {
            params ["_state"];
            _state getOrDefault ["intelGathered", false]
        }],
        ["successMsg", "Intel recovered"],
        ["partialMsg", "Intel lost"],
        ["stateKeys", ["intelGathered"]]
    ]],

    ["HOSTAGES_EXTRACTED", createHashMapFromArray [
        ["check", {
            params ["_state"];
            private _hostages = _state getOrDefault ["hostages", []];
            private _extractPos = _state getOrDefault ["extractPos", []];
            if (_hostages isEqualTo [] || { _extractPos isEqualTo [] }) exitWith { false };
            // All hostages must be alive AND within 100m of extractPos
            (_hostages findIf { !alive _x }) == -1 &&
            { (_hostages findIf { _x distance2D _extractPos > 100 }) == -1 }
        }],
        ["successMsg", "All hostages extracted"],
        ["partialMsg", "Hostages lost or stranded"],
        ["stateKeys", ["hostages", "extractPos"]]
    ]],

    ["AREA_CLEAR", createHashMapFromArray [
        ["check", {
            params ["_state"];
            private _defenders = _state getOrDefault ["defenders", []];
            if (_defenders isEqualTo []) exitWith { false };
            ({ alive _x } count _defenders) < 3
        }],
        ["successMsg", "Area secured"],
        ["partialMsg", "Resistance still active"],
        ["stateKeys", ["defenders"]]
    ]],

    // Session 5 (interaction-site primitive) — N-of-M sites exploited.
    // sitesCompleted is maintained by fnc_interactionSiteFire; nothing
    // needs to poll site state directly.
    ["SITES_INTERACTED", createHashMapFromArray [
        ["check", {
            params ["_state"];
            (_state getOrDefault ["sitesCompleted", 0]) >= (_state getOrDefault ["sitesRequired", 1])
        }],
        ["successMsg", "Site(s) exploited"],
        ["partialMsg", "Site(s) not exploited"],
        ["stateKeys", ["sitesCompleted", "sitesRequired"]]
    ]],

    // Session 6 (SWEEP archetype) — player-driven accumulators only, never
    // AI state (§13.2 anti-soft-lock rule: a stuck defender can never block
    // a SWEEP). Deliberately does NOT read "compromised" — getting spotted
    // is a complication handled by fnc_sweepConvert, not a completion gate.
    ["OBSERVED", createHashMapFromArray [
        ["check", {
            params ["_state"];
            (_state getOrDefault ["observedSeconds", 0]) >= (_state getOrDefault ["observeRequired", 999999])
        }],
        ["successMsg", "Objective observed - intelligence collected"],
        ["partialMsg", "Insufficient observation time on the objective"],
        ["stateKeys", ["observedSeconds", "observeRequired"]]
    ]],

    // Proximity/movement-driven, not dwell-driven — sweeping a sector is
    // "get eyes in that treeline", not "stand here for 40 seconds". The
    // sweptRequired > 0 guard mirrors ALL_DESTROYED's empty-array guard: no
    // sub-points must never auto-complete.
    ["AREA_SWEPT", createHashMapFromArray [
        ["check", {
            params ["_state"];
            private _required = _state getOrDefault ["sweptRequired", 0];
            if (_required <= 0) exitWith { false };
            (_state getOrDefault ["sweptPoints", 0]) >= _required
        }],
        ["successMsg", "Search area swept"],
        ["partialMsg", "Search area not fully swept"],
        ["stateKeys", ["sweptPoints", "sweptRequired"]]
    ]],

    // Same shape as ANY_INTERACTED — a bool maintained outside the check,
    // latched by fnc_sweepMonitor once a player holds LOS within pidRange
    // of pidTarget for pidDwellRequired cumulative seconds.
    ["TARGET_IDENTIFIED", createHashMapFromArray [
        ["check", {
            params ["_state"];
            _state getOrDefault ["targetIdentified", false]
        }],
        ["successMsg", "Target positively identified"],
        ["partialMsg", "Target not identified"],
        ["stateKeys", ["targetIdentified"]]
    ]]
]
