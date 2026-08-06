/*
 * Function: DSC_core_fnc_activatePresenceZone
 * Description:
 *     Dispatcher. Looks up the registered handler for a zone's type in
 *     DSC_presenceHandlers and invokes its "populate" code. If no handler
 *     is registered for the type, logs and returns false.
 *
 *     Handlers are registered at init by fnc_initPresenceManager via
 *     fnc_registerPresenceHandler.
 *
 * Arguments:
 *     0: _zone <HASHMAP> - Zone hashmap from DSC_presenceZones
 *
 * Return Value:
 *     <BOOL> - true if anything was spawned, false if no-op / blocked
 */

params [["_zone", createHashMap, [createHashMap]]];

#include "..\..\script_component.hpp"

private _id   = _zone get "id";
private _type = _zone get "type";

private _registry = missionNamespace getVariable ["DSC_presenceHandlers", createHashMap];
private _handler  = _registry getOrDefault [_type, createHashMap];

if (_handler isEqualTo createHashMap) exitWith {
    WARNING_2("activatePresenceZone [%1] - skip (no handler registered for type=%2)",_id,_type);
    false
};

private _populate = _handler getOrDefault ["populate", {}];
if (_populate isEqualTo {}) exitWith {
    WARNING_2("activatePresenceZone [%1] - skip (handler for type=%2 has no populate fn)",_id,_type);
    false
};

private _result = [_zone] call _populate;

// ============================================================================
// C2 provenance stamping (Sprint F.1)
// ============================================================================
// Stamped here at the dispatcher rather than inside each setup function.
// One choke point covers all eight zone types and any future handler for
// free, and it is impossible for a new zone type to silently ship without
// provenance. The tradeoff is that every group from a zone shares one role
// label instead of per-group patrol/guard/static granularity — v1 doesn't
// consume role (check-in cadence is per faction archetype), so the
// robustness is worth more than the detail. Per-group roles are a v2
// refinement inside the setup family.
//
// Major zones share ids with C2 nodes directly. Microzones are not nodes
// of their own — they resolve to whichever installation projects into
// them, which is the same "controlling faction reaches outward" model
// fnc_resolveMicrozoneProjection already uses for spawn chance.
private _groups = _zone getOrDefault ["groups", []];

// Civilian-side groups are excluded. Several handlers (all four microzone
// types, populatedArea) append wandering civilians and indoor civilian
// clusters to the same zone roster as armed groups. Civilians have no
// reporting obligation, so stamping them would put phantom entries on a
// military node's roster and make F.2's check-in scan raise MISSED_CHECKIN
// every time a farmer wanders out of the zone.
private _armedGroups = _groups select { !isNull _x && {(side _x) != civilian} };

// TEMPORARY DIAGNOSTIC (August 2026) — remove with the faction overhaul.
// Presence zones near the player base were spawning hostiles in the rear area.
// This dumps the REAL side of every armed group a zone produced, alongside the
// control/faction the zone believed it was populating for, so a mismatch
// between "ctrl=bluFor" and "side=EAST" is visible at the dispatcher instead of
// having to be inferred from a handler's summary line.
if (_armedGroups isNotEqualTo []) then {
    private _diagSides = [];
    {
        private _s = str (side _x);
        if !(_s in _diagSides) then { _diagSides pushBack _s };
    } forEach _armedGroups;
    private _diagUnitCt = 0;
    { _diagUnitCt = _diagUnitCt + count (units _x) } forEach _armedGroups;
    private _diagCtrl = _zone getOrDefault ["controlledBy", "?"];
    private _diagFac  = _zone getOrDefault ["faction", "?"];
    diag_log format [
        "DSCDIAG [presenceZone] %1 type=%2 ctrl=%3 faction=%4 -> %5 armed groups, %6 units, sides=%7",
        _id, _type, _diagCtrl, _diagFac, count _armedGroups, _diagUnitCt, _diagSides
    ];
};

if (_armedGroups isNotEqualTo []) then {
    private _nodes = missionNamespace getVariable ["DSC_c2Nodes", createHashMap];

    if (_nodes isNotEqualTo createHashMap) then {
        private _zPos = _zone get "position";

        private _role = switch (_type) do {
            case "base";
            case "outpost";
            case "camp":          { "garrison" };
            case "populatedArea": { "garrison" };
            default                { "guard" };
        };

        // Resolve a node PER SIDE rather than once for the whole zone.
        // A single zone can hold groups from opposing forces: contested
        // zones get a west skirmish patrol via fnc_setupContestedSkirmish,
        // and neutral zones get an east irregular overlay. Stamping every
        // group to the zone's own node would have the attacking force
        // reporting to the installation it is attacking.
        private _sideNodeCache = createHashMap;
        private _stamped = 0;
        private _isolated = 0;

        {
            private _grp = _x;
            private _gSide = side _grp;
            private _sideKey = str _gSide;

            private _nodeId = _sideNodeCache getOrDefault [_sideKey, "?"];
            if (_nodeId isEqualTo "?") then {
                // The zone's own node only claims groups of its own side.
                private _own = _nodes getOrDefault [_id, createHashMap];
                if (_own isNotEqualTo createHashMap && {(_own get "side") isEqualTo _gSide}) then {
                    _nodeId = _id;
                } else {
                    _nodeId = [_zPos, _gSide] call DSC_core_fnc_c2ResolveNode;
                };
                _sideNodeCache set [_sideKey, _nodeId];
            };

            if (_nodeId != "") then {
                if ([_grp, _nodeId, _role] call DSC_core_fnc_c2StampGroup) then {
                    _stamped = _stamped + 1;
                };
            } else {
                _isolated = _isolated + 1;
            };
        } forEach _armedGroups;

        LOG_3("activatePresenceZone [%1] - C2 stamped %2 groups (%3 isolated)",_id,_stamped,_isolated);
    };
};

_result
