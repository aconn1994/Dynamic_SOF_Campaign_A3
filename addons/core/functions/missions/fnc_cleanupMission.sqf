#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_cleanupMission
 * Description:
 *     Cleans up all mission assets (units, vehicles, groups, markers).
 *
 * Arguments:
 *     0: _mission <HASHMAP> - Mission data from generateKillCaptureMission
 *
 * Return Value:
 *     <BOOL> - True if cleanup succeeded
 *
 * Example:
 *     [_mission] call DSC_core_fnc_cleanupMission
 */

params [
    ["_mission", createHashMap, [createHashMap]]
];

if (count _mission == 0) exitWith {
    ERROR("Cleanup - No mission data provided");
    false
};

INFO("Mission cleanup starting...");

private _units = _mission getOrDefault ["units", []];
private _vehicles = _mission getOrDefault ["vehicles", []];
private _objects = _mission getOrDefault ["objects", []];
private _groups = _mission getOrDefault ["groups", []];
private _marker = _mission getOrDefault ["marker", ""];

// Delete all tracked units including dead bodies
{
    if (!isNull _x) then {
        deleteVehicle _x;
    };
    sleep 0.05;
} forEach _units;

// Delete all tracked vehicles (works even if destroyed)
{
    if (!isNull _x) then {
        deleteVehicle _x;
    };
    sleep 0.05;
} forEach _vehicles;

// Delete placed mission objects (intel, supplies, equipment)
{
    if (!isNull _x) then {
        deleteVehicle _x;
    };
} forEach _objects;

// Delete groups after units and vehicles
{
    if (!isNull _x) then {
        deleteGroup _x;
    };
} forEach _groups;

// Session 5 — remove every mission-scoped interaction site so a generated
// site never outlives its mission (its addAction would stay armed on every
// client with a dangling missionScoped reference into a mission hashmap
// that's already gone).
private _interactionSites = _mission getOrDefault ["interactionSites", []];
{
    [_x] call DSC_core_fnc_removeInteractionSite;
} forEach _interactionSites;

// Delete mission marker
if (_marker isEqualType "") then {
    if (_marker != "") then {
        deleteMarker _marker;
    };
} else {
    if (!isNil "_marker") then {
        deleteMarker _marker;
    };
};

// Delete all mission markers (cluster circles, building dots, etc.)
private _markers = _mission getOrDefault ["markers", []];
{ deleteMarker _x } forEach _markers;

// Delete player drop markers
{
    deleteMarker format ["dsc_drop_%1", getPlayerUID _x];
} forEach allPlayers;

// Clear global mission variable
missionNamespace setVariable ["DSC_currentMission", nil, true];

// Diplomacy is session-wide and owned by fnc_initPresenceManager — it is
// deliberately NOT touched here. Mutating it per-mission is what previously
// left the side matrix in a different state after the first mission than it
// had at init.

// ============================================================================
// Reset C2 Network alert state (Sprint F.1)
// ============================================================================
// v1 deliberately does NOT persist alert state or campaign heat between
// missions. Persistence gives a compelling "the region is hunting you" arc,
// but it also means one sloppy mission poisons the next, and it overlaps
// with fnc_updateInfluence which already models "this region has been
// fought over." Both need a deliberate reconciliation pass before heat is
// allowed to carry — see .crush/c2-network.md.
private _c2Nodes = missionNamespace getVariable ["DSC_c2Nodes", createHashMap];
if (_c2Nodes isNotEqualTo createHashMap) then {
    private _reset = 0;
    private _qrfCleared = 0;
    {
        private _node = _c2Nodes get _x;
        if ((_node get "alert") != "GREEN") then { _reset = _reset + 1 };

        // Delete any QRF still in flight. These were spawned by
        // fnc_c2ResponseQrf outside the presence budget and are not tracked
        // by any zone, so nothing else will ever clean them up — without this
        // they survive into the next mission as orphaned hostiles.
        {
            private _dg = _x getOrDefault ["group", grpNull];
            if (!isNull _dg) then {
                private _dv = _x getOrDefault ["vehicle", objNull];
                { deleteVehicle _x } forEach (units _dg);
                if (!isNull _dv) then { deleteVehicle _dv };
                deleteGroup _dg;
                _qrfCleared = _qrfCleared + 1;
            };
        } forEach (_node getOrDefault ["dispatched", []]);

        _node set ["alert", "GREEN"];
        _node set ["alertSince", serverTime];
        _node set ["alertSource", "missionCleanup"];
        _node set ["responseDelay", -1];
        _node set ["lastDispatch", -99999];
        _node set ["dispatched", []];
        _node set ["pendingSilence", []];
        _node set ["lkp", createHashMap];
        _node set ["heat", 0];

        // Drop mission-AO groups from the roster; the units are already
        // deleted above and the tick would only prune them next cycle.
        // Surviving groups get their accountability clocks reset too —
        // otherwise a patrol that was mid-report when the mission ended
        // would fire a stale MISSED_CHECKIN into a network that has just
        // been zeroed.
        private _roster = _node get "groups";
        private _live = _roster select {
            !isNull _x && {((units _x) findIf { alive _x }) >= 0}
        };
        {
            _x setVariable ["DSC_c2InContact", false];
            _x setVariable ["DSC_c2Reported", false];
            _x setVariable ["DSC_c2SilenceScheduled", false];
            _x setVariable ["DSC_c2RtbRaised", false];
            _x setVariable ["DSC_c2RecallLkp", nil];
        } forEach _live;
        _node set ["groups", _live];

        #ifdef DEBUG_MODE_FULL
        private _mName = format ["dsc_c2_%1", _x];
        _mName setMarkerColorLocal "ColorGrey";
        #endif
    } forEach (keys _c2Nodes);

    missionNamespace setVariable ["DSC_c2Feed", [], true];

    // F.4 — clear hostile contact fixes. They reference groups that are being
    // deleted, and a marker surviving into the next mission would point at a
    // patrol that no longer exists.
    missionNamespace setVariable ["DSC_c2Contacts", [], true];

    // F.4 — reset the live-chatter throttle. serverTime keeps running between
    // missions, so a stale timestamp here is harmless, but resetting keeps the
    // first intercept of the next mission from being swallowed if cleanup
    // happens to land inside the throttle window.
    missionNamespace setVariable ["DSC_c2ChatterLastAt", -999];

    LOG_2("Cleanup - C2 network reset (%1 nodes above GREEN, %2 QRF elements cleared)",_reset,_qrfCleared);
};

INFO_4("Cleanup complete - %1 units, %2 vehicles, %3 objects, %4 groups deleted",count _units,count _vehicles,count _objects,count _groups);

true
