#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_c2ContactReport
 * Description:
 *     Sprint F.2 — THE core gameplay mechanic of the whole C2 layer.
 *
 *     Spawned once when a stamped group realizes it is in contact. Runs a
 *     countdown; if the group is still able to transmit when it expires, a
 *     CONTACT_REPORT signal enters the network and the region wakes up.
 *
 *     Kill the group before the timer expires and NO CONTACT REPORT GOES
 *     OUT. That is the entire point. It is what turns "shoot the enemy"
 *     into "shoot the enemy in the right order, fast, before they can talk."
 *
 *     But suppression is not immunity. The group's check-in deadline is
 *     still on the node's books, so `MISSED_CHECKIN` fires minutes later
 *     regardless (see the accountability scan in fnc_initC2Network). Speed
 *     and silence buy a window, never a free pass.
 *
 *     Delay formula:
 *
 *       reportDelay = archetypeBase                (8-18s conventional,
 *                                                   18-35s partner,
 *                                                   30-60s irregular)
 *                   x (leader alive   ? 1.0 : 1.8)
 *                   x (radioman alive ? 1.0 : 2.5)
 *                   x qualityModifier              (DSC_c2Quality, default 1)
 *
 *     The radioman multiplier is the biggest single lever, which is what
 *     gives the player a concrete reason to identify and drop a specific
 *     man rather than engaging whoever is closest. Losing both leader and
 *     radioman on a conventional patrol pushes a 13s report out past 58s —
 *     usually longer than the firefight itself.
 *
 *     Runs on a 1s poll rather than a single sleep so that killing the
 *     radioman DURING the countdown extends it retroactively. Shooting the
 *     antenna backpack twenty seconds into a fight has to still matter, or
 *     the mechanic collapses into "win the initiative roll at contact."
 *
 * Arguments:
 *     0: _group <GROUP> - the group in contact (must be C2-stamped)
 *
 * Return Value:
 *     None (spawned)
 *
 * Example:
 *     [_grp] spawn DSC_core_fnc_c2ContactReport;
 */

params [["_group", grpNull, [grpNull]]];

if (!isServer) exitWith {};
if (isNull _group) exitWith {};

private _nodeId = _group getVariable ["DSC_c2Parent", ""];
if (_nodeId isEqualTo "") exitWith {};

private _nodes = missionNamespace getVariable ["DSC_c2Nodes", createHashMap];
private _node = _nodes getOrDefault [_nodeId, createHashMap];
if (_node isEqualTo createHashMap) exitWith {};

// One timer per group, ever. Re-entering contact after a report has already
// gone out must not spam the network.
if (_group getVariable ["DSC_c2InContact", false]) exitWith {};
_group setVariable ["DSC_c2InContact", true];

private _arch = [] call DSC_core_fnc_getC2Archetypes;
private _archetypes = _arch get "archetypes";
private _archKey = _node getOrDefault ["archetype", "irregular"];
private _archCfg = _archetypes getOrDefault [_archKey, createHashMap];

private _delayRange = _archCfg getOrDefault ["reportDelay", [30, 60]];
_delayRange params [["_dMin", 30], ["_dMax", 60]];

private _baseDelay = _dMin + random (_dMax - _dMin);
private _quality = _group getVariable ["DSC_c2Quality", 1.0];
_baseDelay = _baseDelay * _quality;

private _contactPos = getPosATL (leader _group);
private _stats = missionNamespace getVariable ["DSC_c2Stats", createHashMap];
_stats set ["contactsDetected", (_stats getOrDefault ["contactsDetected", 0]) + 1];

private _startTime = serverTime;
private _groupLabel = groupId _group;

LOG_3("c2ContactReport - %1 in contact, base delay %2s (archetype %3)",_groupLabel,_baseDelay toFixed 1,_archKey);

// ============================================================================
// Countdown
// ============================================================================
// Loop control is an explicit flag rather than `exitWith`. `exitWith` inside
// a `while` body has enough ambiguity about whether it breaks the loop or
// returns from the whole function that the suppression accounting below must
// not depend on it — if it returned early, a suppressed report would never
// be logged and the mechanic would look broken while silently working.
private _sent = false;
private _wiped = false;
private _running = true;

while { _running } do {
    sleep 1;

    if (isNull _group) then {
        _wiped = true;
        _running = false;
    } else {
        private _aliveUnits = (units _group) select { alive _x };

        if (_aliveUnits isEqualTo []) then {
            _wiped = true;
            _running = false;
        } else {
            // Recompute the effective deadline every poll so late kills on
            // the leader or radioman still push the report out. Shooting the
            // antenna twenty seconds into a firefight has to still matter.
            private _leaderAlive = alive (leader _group);
            private _radioman = _group getVariable ["DSC_c2Radioman", objNull];
            private _radiomanAlive = !isNull _radioman && {alive _radioman};

            private _effective = _baseDelay;
            if (!_leaderAlive)   then { _effective = _effective * 1.8 };
            if (!_radiomanAlive) then { _effective = _effective * 2.5 };

            if ((serverTime - _startTime) >= _effective) then {
                _sent = true;
                _running = false;
            };
        };
    };
};

// ============================================================================
// Outcome
// ============================================================================
if (_wiped) then {
    _stats set ["reportsSuppressed", (_stats getOrDefault ["reportsSuppressed", 0]) + 1];
    private _elapsed = serverTime - _startTime;
    INFO_2("c2 REPORT SUPPRESSED - %1 wiped after %2s before transmitting",_groupLabel,_elapsed toFixed 1);

    // ------------------------------------------------------------------
    // Schedule the deferred SILENCE here, at the moment of the wipe.
    // ------------------------------------------------------------------
    // This MUST NOT be left to the tick's wiped-group detection. That scan
    // needs the dead bodies and the group object to still exist, and other
    // subsystems delete them first:
    //
    //   fnc_rovingDespawnSweep culls any foot rover whose group has no
    //   living units, on its own ~8s tick. A rover wiped at T is usually
    //   gone by T+5, well before the C2 tick at T+10 can classify it.
    //   The group then looks "despawned by the manager" rather than
    //   "destroyed by the player", gets pruned, and NO SILENCE EVER FIRES —
    //   the player waits for a consequence that was silently dropped.
    //
    // Scheduling at the point of death is race-free: we already know the
    // group died, and the snapshot survives the group object being deleted.
    if !(_group getVariable ["DSC_c2SilenceScheduled", false]) then {
        _group setVariable ["DSC_c2SilenceScheduled", true];

        private _lastPos = _contactPos;
        private _units3 = units _group;
        if (_units3 isNotEqualTo []) then { _lastPos = getPosATL (_units3 select 0) };

        // Clamp the deadline forward. A group whose check-in had ALREADY
        // come due when it died would otherwise schedule SILENCE in the
        // past and fire it on the very next tick — a playtest logged
        // "gone due in -61s" followed immediately by the SILENCE, which is
        // the instant-notification bug this deferral exists to prevent.
        // If they missed the window, the network waits for the one after.
        private _interval = _archCfg getOrDefault ["checkInInterval", 600];
        private _due = _group getVariable ["DSC_c2NextCheckIn", 0];
        if (_due <= serverTime) then { _due = serverTime + _interval };

        private _pending = _node getOrDefault ["pendingSilence", []];
        _pending pushBack [_groupLabel, _lastPos, _due];
        _node set ["pendingSilence", _pending];

        private _waitFor = _due - serverTime;
        INFO_2("c2 silence scheduled - %1 gone, due at check-in in %2s",_groupLabel,_waitFor toFixed 0);
    };
};

if (_sent) then {
    _stats set ["reportsSent", (_stats getOrDefault ["reportsSent", 0]) + 1];
    _group setVariable ["DSC_c2Reported", true];

    // Report the position the group is at NOW, which may have drifted from
    // where contact started. This is the LKP the enemy will act on, and its
    // inaccuracy is a feature.
    private _reportPos = _contactPos;
    if (!isNull (leader _group)) then { _reportPos = getPosATL (leader _group) };

    // ------------------------------------------------------------------
    // F.4 — the transmission is itself a detectable emission
    // ------------------------------------------------------------------
    // Registering a SIGINT fix on the TRANSMITTER (not on its LKP of the
    // player) is what lets the Blue Force Tracker show this element. This is
    // radio direction finding: you cannot see the patrol, but you can locate
    // a radio that keys up.
    //
    // Placed inside the `_sent` branch so it is bound to the report timer: a
    // group wiped before it transmits never emits, so it never gets marked.
    // That symmetry is the point — both sides pay for talking.
    //
    // GATED ON ISR COVERAGE AT THE TRANSMITTER. Direction finding needs a
    // receiver pointed at the right place; the player does not passively
    // intercept every radio on Altis. Evaluated once, at the moment of
    // emission, which is also the realistic model: you either had the coverage
    // when they keyed up or you missed it forever. ENHANCED (drone on station)
    // is the bar, matching the ISR dispatch notifications — this is a real
    // capability that should be lost with the drone.
    private _sigintTier = ([_reportPos] call DSC_core_fnc_c2IsrCoverage) select 0;
    if (_sigintTier >= 2) then {
        [_group, _reportPos, "SIGINT", _groupLabel] call DSC_core_fnc_c2ContactRegister;
    };

    // ------------------------------------------------------------------
    // Escalation: is this the installation itself being attacked?
    // ------------------------------------------------------------------
    // A garrison or guard element fighting inside its own node's footprint
    // is not "a patrol made contact somewhere" — it is the base being
    // assaulted, which is a categorically worse report and goes straight
    // to BLACK. Without this, hitting a base directly would produce the
    // same RED as ambushing one of its patrols 3 km away.
    private _role = _group getVariable ["DSC_c2Role", "patrol"];
    private _nodePos = _node get "position";
    private _atInstallation = (_role in ["garrison", "guard"]) &&
                              {(_reportPos distance2D _nodePos) < 400};

    private _signalType = ["CONTACT_REPORT", "INSTALLATION_ATTACKED"] select _atInstallation;

    private _gridRef = mapGridPosition _reportPos;
    private _detailText = if (_atInstallation) then {
        format ["We are under attack, grid %1", _gridRef]
    } else {
        format ["Contact, small arms, grid %1", _gridRef]
    };

    private _payload = createHashMapFromArray [
        ["callsign",   _groupLabel],
        ["confidence", 1.0],
        ["detail",     _detailText]
    ];

    private _elapsed2 = serverTime - _startTime;
    INFO_4("c2 REPORT SENT - %1 transmitted %2 after %3s (grid %4)",_groupLabel,_signalType,_elapsed2 toFixed 1,_gridRef);

    [_signalType, _nodeId, _reportPos, _payload] call DSC_core_fnc_c2Signal;
};
