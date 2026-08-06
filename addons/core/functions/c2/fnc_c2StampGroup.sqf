#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_c2StampGroup
 * Description:
 *     Sprint F.1 — Provenance stamping. THE foundational primitive of the
 *     C2 Network.
 *
 *     Before this existed, nothing DSC spawned knew where it came from. A
 *     patrol was an island; killing it produced no consequence because
 *     there was no record that anyone was expecting it back. This function
 *     is what turns "five units standing in a field" into "Kilo-2, a
 *     patrol out of Zulu, due to check in at 14:35".
 *
 *     Stamped group variables (all read by F.2 signal processing):
 *
 *       DSC_c2Parent      <STRING>  owning node id
 *       DSC_c2Role        <STRING>  patrol|guard|garrison|rover|static|mission
 *       DSC_c2NextCheckIn <NUMBER>  serverTime deadline for next check-in
 *       DSC_c2RtbEta      <NUMBER>  serverTime the group is due back
 *       DSC_c2Radioman    <OBJECT>  designated radio operator
 *       DSC_c2Reported    <BOOL>    has this group already sent a contact
 *                                   report (set in F.2, read to avoid dupes)
 *
 *     Check-in cadence is PER FACTION ARCHETYPE for v1, not per role — a
 *     single number per archetype keeps the accountability model legible
 *     while tuning. Per-role cadence (recce every 30 min vs. town guard
 *     every 5) is a v2 refinement and only needs a data change here, since
 *     the deadline is already stored per group.
 *
 *     RADIOMAN DESIGNATION is what gives the player a reason to pick
 *     targets rather than just spray. Preference order:
 *       1. a unit carrying a backpack whose classname reads as a radio
 *       2. any non-leader unit (the leader is already a separate modifier)
 *       3. the leader, as a last resort
 *     Killing the radioman multiplies the contact report delay (F.2), so a
 *     group that loses theirs early may never get the report out at all.
 *
 *     Safe to call on any group at any time. No-ops quietly if the C2
 *     registry doesn't exist yet or the node id is unknown, so spawners can
 *     call it unconditionally without ordering constraints.
 *
 * Arguments:
 *     0: _group  <GROUP>  - the group to stamp
 *     1: _nodeId <STRING> - owning node id (must exist in DSC_c2Nodes)
 *     2: _role   <STRING> - provenance role (default "patrol")
 *     3: _durationOverride <NUMBER> - optional patrol duration in seconds
 *                                     for RTB (default: archetype-derived)
 *
 * Return Value:
 *     <BOOL> - true if stamped, false if no-op
 *
 * Example:
 *     [_grp, "Kavala", "patrol"] call DSC_core_fnc_c2StampGroup;
 */

params [
    ["_group",  grpNull, [grpNull]],
    ["_nodeId", "",      [""]],
    ["_role",   "patrol", [""]],
    ["_durationOverride", -1, [0]]
];

if (isNull _group) exitWith { false };
if (_nodeId isEqualTo "") exitWith { false };

private _nodes = missionNamespace getVariable ["DSC_c2Nodes", createHashMap];
if (_nodes isEqualTo createHashMap) exitWith { false };

private _node = _nodes getOrDefault [_nodeId, createHashMap];
if (_node isEqualTo createHashMap) exitWith {
    LOG_2("c2StampGroup - unknown node '%1' for role %2",_nodeId,_role);
    false
};

private _units = units _group;
if (_units isEqualTo []) exitWith { false };

// ============================================================================
// Check-in + RTB deadlines from the node's comms archetype
// ============================================================================
private _arch       = [] call DSC_core_fnc_getC2Archetypes;
private _archetypes = _arch get "archetypes";
private _archKey    = _node getOrDefault ["archetype", "irregular"];
private _archCfg    = _archetypes getOrDefault [_archKey, createHashMap];

private _interval = _archCfg getOrDefault ["checkInInterval", 600];
private _rtbMult  = _archCfg getOrDefault ["rtbMult", 1.0];

// Stagger the first check-in across the interval so a freshly activated
// zone doesn't produce a synchronized wall of check-ins one interval later.
private _firstCheckIn = serverTime + (_interval * (0.4 + random 0.6));

// ============================================================================
// RTB deadline — only for elements that actually went somewhere
// ============================================================================
// "Overdue" is meaningless for a garrison: it is not due back anywhere, it
// lives there. Setting an RTB on every stamped group made every static
// defender in a city report itself overdue exactly one duration after the
// zone activated — a ~25-signal burst that pinned the local nodes at AMBER
// permanently and drowned out real events.
//
// Only deployed elements (roving patrols, foot patrols) get an RTB clock.
// Garrisons, guards and statics get 0, which the tick reads as "no RTB".
private _deployedRoles = ["rover", "patrol"];
private _rtbEta = 0;
if (_role in _deployedRoles) then {
    private _duration = if (_durationOverride > 0) then {
        _durationOverride
    } else {
        // Default patrol life: two check-in cycles, scaled by how loose the
        // archetype's accountability is.
        _interval * 2 * _rtbMult
    };
    // Jitter so a batch spawned in one worker cycle doesn't come due together.
    _rtbEta = serverTime + (_duration * (0.8 + random 0.4));
};

// ============================================================================
// Radioman designation
// ============================================================================
private _leader = leader _group;
private _radioman = objNull;

// Pass 1 — anyone carrying something that reads as a radio backpack.
{
    if (alive _x) then {
        private _bp = backpack _x;
        if (_bp != "") then {
            private _bpLower = toLower _bp;
            private _isRadio = (_bpLower find "radio") >= 0 ||
                               {(_bpLower find "tfar") >= 0} ||
                               {(_bpLower find "acre") >= 0};
            if (_isRadio) exitWith { _radioman = _x };
        };
    };
} forEach _units;

// Pass 2 — any living non-leader.
if (isNull _radioman) then {
    private _candidates = _units select { alive _x && {_x != _leader} };
    if (_candidates isNotEqualTo []) then {
        _radioman = selectRandom _candidates;
    };
};

// Pass 3 — the leader carries it themselves.
if (isNull _radioman) then { _radioman = _leader };

// ============================================================================
// Stamp
// ============================================================================
// Public (broadcast) on parent/role because the tablet and future ISR read
// them client-side. Timers stay server-local — nothing off-server needs them
// and they churn on every check-in.
_group setVariable ["DSC_c2Parent", _nodeId, true];
_group setVariable ["DSC_c2Role", _role, true];
_group setVariable ["DSC_c2NextCheckIn", _firstCheckIn];
_group setVariable ["DSC_c2RtbEta", _rtbEta];
_group setVariable ["DSC_c2Radioman", _radioman];
_group setVariable ["DSC_c2Reported", false];

// Register on the node roster. The tick prunes dead entries, so we only
// need to guard against double-registration here.
private _roster = _node get "groups";
if !(_group in _roster) then {
    _roster pushBack _group;
};

private _stats = missionNamespace getVariable ["DSC_c2Stats", createHashMap];
_stats set ["groupsStamped", (_stats getOrDefault ["groupsStamped", 0]) + 1];

private _cs = _node get "callsign";
private _uc = count _units;
TRACE_4("c2 stamp",_cs,_role,_uc,_archKey);

true
