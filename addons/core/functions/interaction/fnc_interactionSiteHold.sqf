#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_interactionSiteHold
 * Description:
 *     Client-local, spawned by the addAction armed in
 *     `fnc_interactionSiteArmLocal`. Runs the timed "searching..." hold
 *     (§13.3 of the session 5 spec — 20-60s for mission SSE, shorter for
 *     the universal search hook). Hold implementation (hint countdown here)
 *     is a build detail, not an architecture decision; the contract is
 *     fixed:
 *       - cancel the hold if the player dies,
 *       - cancel if the player moves outside `radius`,
 *       - cancel if the site's state changes away from ARMED mid-hold
 *         (another player finished it first, or cleanup removed it).
 *     On natural completion, fires `DSC_interactionSite_fire` — the SERVER
 *     is what actually calls `fnc_interactionSiteFire` and re-validates;
 *     this function only decides whether to ASK the server to complete it.
 *
 * Arguments:
 *     0: _id <STRING> - Site id.
 *
 * Return Value: None
 *
 * Example:
 *     ["site_12345_678"] spawn DSC_core_fnc_interactionSiteHold;
 */

params [["_id", "", [""]]];

if (_id == "") exitWith {};

private _sites = missionNamespace getVariable ["DSC_interactionSites", createHashMap];
private _site = _sites getOrDefault [_id, createHashMap];
if (_site isEqualTo createHashMap) exitWith {};

private _pos = _site get "pos";
private _radius = _site get "radius";
private _actionText = _site getOrDefault ["action", "Conduct SSE"];
private _duration = _site getOrDefault ["durationRolled", 30];

private _elapsed = 0;
private _completedHold = false;

// Loop control is an explicit flag rather than `exitWith` — `exitWith`
// inside a `while` body terminates the whole function, not just the loop
// iteration (same gotcha documented in fnc_c2ContactReport), which would
// skip the hintSilent cleanup below on every cancel path.
private _running = true;

while { _running } do {
    if (!alive player) then {
        _running = false;
    } else {
        if ((player distance _pos) > _radius) then {
            _running = false;
        } else {
            private _liveSites = missionNamespace getVariable ["DSC_interactionSites", createHashMap];
            private _liveSite = _liveSites getOrDefault [_id, createHashMap];

            if (_liveSite isEqualTo createHashMap || {(_liveSite getOrDefault ["state", ""]) != "ARMED"}) then {
                _running = false;
            } else {
                hintSilent format ["%1...\n%2s remaining", _actionText, ceil (_duration - _elapsed)];
                sleep 1;
                _elapsed = _elapsed + 1;

                if (_elapsed >= _duration) then {
                    _completedHold = true;
                    _running = false;
                };
            };
        };
    };
};

hintSilent "";

if (_completedHold) then {
    ["DSC_interactionSite_fire", [_id, player]] call CBA_fnc_serverEvent;
    LOG_1("interactionSiteHold - hold complete, requesting fire for %1",_id);
};

