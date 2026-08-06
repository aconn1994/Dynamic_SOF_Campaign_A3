#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_initC2Network
 * Description:
 *     Sprint F.1 scaffolding for the C2 Network — the communication layer
 *     that gives AI forces provenance and consequence.
 *
 *     Today a patrol is an island: kill it and nothing in the world reacts
 *     beyond the local FiredNear combat activation. The C2 Network makes
 *     every spawned group belong to an installation that notices when it
 *     stops reporting.
 *
 *     F.1 IS LOG-ONLY BY DESIGN. It builds the node registry, precomputes
 *     link topology, assigns callsigns, and runs the alert decay tick. It
 *     raises no alerts on its own and dispatches no responses. This mirrors
 *     how the Presence Manager was scaffolded in its Sprint 1 — get the
 *     state machine and data flow verifiable in isolation before anything
 *     spawns. Signals land in F.2, responses in F.3.
 *
 *     Node registry schema (DSC_c2Nodes, hashmap by node id — ids are
 *     shared with DSC_presenceZones so the two systems cross-reference):
 *
 *       "id"          <STRING>  location id
 *       "tier"        <STRING>  "COMMAND" | "RELAY" | "OUTSTATION"
 *       "archetype"   <STRING>  "conventional" | "partner" | "irregular"
 *       "callsign"    <STRING>  stable per session, e.g. "ZULU-2"
 *       "faction"     <STRING>  cfg faction id (may be "")
 *       "side"        <SIDE>
 *       "controlledBy"<STRING>  "opFor"|"bluFor"|"contested"|"neutral"
 *       "position"    <ARRAY>
 *       "influence"   <NUMBER>  0..1
 *       "reach"       <NUMBER>  response projection distance (m)
 *       "reliability" <NUMBER>  0..1 per relay hop
 *       "latency"     <ARRAY>   [min,max] seconds to act
 *       "links"       <ARRAY>   [nodeId, ...] neighbors
 *       "alert"       <STRING>  "GREEN"|"AMBER"|"RED"|"BLACK"
 *       "alertSince"  <NUMBER>  serverTime of last alert change
 *       "alertSource" <STRING>  what raised it (debug/feed provenance)
 *       "groups"      <ARRAY>   live roster, pruned each tick
 *       "dispatched"  <ARRAY>   active responses (F.3)
 *       "lkp"         <HASHMAP> last known player pos + time + confidence
 *       "heat"        <NUMBER>  0..1 campaign memory (written, unread in v1)
 *       "infraLinks"  <ARRAY>   infrastructureNode ids (F.5)
 *
 *     Timebase note: this subsystem uses `serverTime` for all game-logic
 *     deadlines (alert decay, check-in) and `sleep` for the tick, so the
 *     whole thing scales coherently under setAccTime. It deliberately does
 *     NOT mix in diag_tickTime/uiSleep — see the presence manager's
 *     accelerated-time gotcha for why mixing the two makes logs unreadable.
 *
 * Arguments:
 *     0: _influenceData <HASHMAP> - from fnc_initInfluence
 *     1: _factionData   <HASHMAP> - from fnc_initFactionData
 *
 * Return Value:
 *     <HASHMAP> - DSC_c2Nodes
 *
 * Example:
 *     [_influenceData, _factionData] call DSC_core_fnc_initC2Network;
 */

params [
    ["_influenceData", createHashMap, [createHashMap]],
    ["_factionData",   createHashMap, [createHashMap]]
];

if (_influenceData isEqualTo createHashMap) exitWith {
    ERROR("c2Network - No influence data, aborting");
    createHashMap
};

private _arch            = [] call DSC_core_fnc_getC2Archetypes;
private _archetypes      = _arch get "archetypes";
private _tiers           = _arch get "tiers";
private _roleToArchetype = _arch get "roleToArchetype";

private _influenceMap   = _influenceData getOrDefault ["influenceMap", createHashMap];
private _bases          = _influenceData getOrDefault ["bases", []];
private _outposts       = _influenceData getOrDefault ["outposts", []];
private _camps          = _influenceData getOrDefault ["camps", []];
private _populatedAreas = _influenceData getOrDefault ["populatedAreas", []];

// ============================================================================
// Faction -> role lookup (same pattern as fnc_presenceActivateMilitary)
// ============================================================================
private _factionProfileConfig = missionNamespace getVariable ["factionProfileConfig", createHashMap];
private _factionToRole = createHashMap;
private _factionToSide = createHashMap;
{
    private _role = _x;
    private _roleData = _y;
    private _rSide = _roleData getOrDefault ["side", east];
    {
        _factionToRole set [_x, _role];
        _factionToSide set [_x, _rSide];
    } forEach (_roleData getOrDefault ["factions", []]);
} forEach _factionProfileConfig;

// ============================================================================
// Callsign pool — stable per session so the player can learn the map
// ============================================================================
// Assigned per faction so a single force reads as one organization
// ("ZULU is the outpost north of me"). Cycles with a numeric suffix once
// the phonetic pool is exhausted rather than colliding.
// ============================================================================
// Callsign pool
// ============================================================================
// Assigned in a SECOND PASS after all nodes are built (see below), not during
// construction. The first implementation used per-faction counters, which
// produced cross-faction collisions: faction A and faction B each started at
// ALPHA, so a single session had three separate nodes called "BRAVO" and the
// radio feed printed nonsense like `BRAVO -> BRAVO "Relaying..."`.
//
// Callsigns must be GLOBALLY unique — the entire point is that the player
// learns "ZULU is the outpost north of me." Grouping by faction is preserved
// by sorting before assignment rather than by separate counters.
private _phonetic = ["ALPHA","BRAVO","CHARLIE","DELTA","ECHO","FOXTROT","GOLF",
                     "HOTEL","INDIA","JULIET","KILO","LIMA","MIKE","NOVEMBER",
                     "OSCAR","PAPA","QUEBEC","ROMEO","SIERRA","TANGO","UNIFORM",
                     "VICTOR","WHISKEY","XRAY","YANKEE","ZULU"];

// ============================================================================
// Node construction
// ============================================================================
private _nodes = createHashMap;

// Player main base is excluded — it is the player's own C2, not a
// simulated one, and fnc_initBases owns it for the whole session.
private _playerMainBase = missionNamespace getVariable ["playerMainBase", ""];
private _playerBasePos  = if (_playerMainBase != "" && {(markerShape _playerMainBase) != ""}) then {
    getMarkerPos _playerMainBase
} else { [0,0,0] };

private _skippedNoArchetype = 0;
private _skippedPlayerBase  = 0;

private _fnc_buildNode = {
    params ["_loc", "_tier"];

    private _locId  = _loc get "id";
    private _locPos = _loc get "position";

    if (_playerBasePos distance2D _locPos < 50) exitWith {
        _skippedPlayerBase = _skippedPlayerBase + 1;
    };

    private _inf          = _influenceMap getOrDefault [_locId, createHashMap];
    private _controlledBy = _inf getOrDefault ["controlledBy", "neutral"];
    private _faction      = _inf getOrDefault ["faction", ""];
    private _influence    = _inf getOrDefault ["influence", 0];

    // Resolve archetype from the controlling faction's role. Uncontrolled
    // populated areas still become irregular nodes — a neutral town with a
    // local armed population is exactly the "hornets nest" case, and the
    // mesh topology needs those nodes to exist to propagate at all.
    private _role = _factionToRole getOrDefault [_faction, ""];
    private _archetypeKey = _roleToArchetype getOrDefault [_role, ""];

    if (_archetypeKey == "") then {
        if (_controlledBy in ["neutral", "contested"]) then {
            _archetypeKey = "irregular";
        };
    };

    if (_archetypeKey == "") exitWith {
        _skippedNoArchetype = _skippedNoArchetype + 1;
    };

    private _archCfg = _archetypes getOrDefault [_archetypeKey, createHashMap];
    private _tierCfg = _tiers getOrDefault [_tier, createHashMap];

    private _side = _factionToSide getOrDefault [_faction, east];
    if (_faction == "") then {
        _side = switch (_controlledBy) do {
            case "bluFor": { west };
            case "opFor":  { east };
            default        { independent };
        };
    };

    private _node = createHashMapFromArray [
        ["id",           _locId],
        ["tier",         _tier],
        ["archetype",    _archetypeKey],
        ["callsign",     ""],
        ["faction",      _faction],
        ["side",         _side],
        ["controlledBy", _controlledBy],
        ["position",     _locPos],
        ["name",         _loc getOrDefault ["name", _locId]],
        ["influence",    _influence],
        ["reach",        _tierCfg getOrDefault ["reach", 1500]],
        ["reliability",  _archCfg getOrDefault ["reliability", 0.5]],
        ["latency",      _tierCfg getOrDefault ["latency", [30, 60]]],
        ["linkRange",    _archCfg getOrDefault ["linkRange", 4000]],
        ["topology",     _archCfg getOrDefault ["topology", "mesh"]],
        ["linkTier",     _tierCfg getOrDefault ["linkTier", 1]],
        ["links",        []],
        ["alert",        "GREEN"],
        ["alertSince",   serverTime],
        ["alertSource",  ""],
        ["groups",       []],
        ["dispatched",   []],
        ["pendingSilence", []],
        ["lkp",          createHashMap],
        ["heat",         0],
        ["infraLinks",   []]
    ];

    _nodes set [_locId, _node];
};

{ [_x, "COMMAND"]    call _fnc_buildNode } forEach _bases;
{ [_x, "RELAY"]      call _fnc_buildNode } forEach _outposts;
{ [_x, "OUTSTATION"] call _fnc_buildNode } forEach _camps;
{ [_x, "OUTSTATION"] call _fnc_buildNode } forEach _populatedAreas;

private _nodeCount = count _nodes;
INFO_4("c2Network - Registered %1 nodes (command:%2 relay:%3 outstation:%4)",_nodeCount,count _bases,count _outposts,(count _camps) + (count _populatedAreas));
if (_skippedNoArchetype > 0 || _skippedPlayerBase > 0) then {
    LOG_2("c2Network - Skipped %1 (no archetype) + %2 (player base footprint)",_skippedNoArchetype,_skippedPlayerBase);
};

if (_nodeCount == 0) exitWith {
    WARNING("c2Network - No nodes built, aborting (no comms simulation)");
    missionNamespace setVariable ["DSC_c2Nodes", createHashMap, true];
    createHashMap
};

// ============================================================================
// Callsign assignment — globally unique, grouped by faction
// ============================================================================
// Sorting by faction then tier before assignment means a single force still
// reads as one organization (its nodes get consecutive letters, command
// first), while a single running index guarantees no two nodes anywhere share
// a callsign. Beyond 26 nodes, words repeat with a numeric suffix.
private _sortKeys = [];
private _byKey = createHashMap;
{
    private _n = _nodes get _x;
    // (9 - linkTier) keeps the key a plain ascending string while still
    // ordering COMMAND(3)->6 before RELAY(2)->7 before OUTSTATION(1)->8.
    // A single string key avoids relying on mixed-type subarray comparison.
    private _tierRank = 9 - (_n get "linkTier");
    private _key = format ["%1_%2_%3", _n get "faction", _tierRank, _x];
    _sortKeys pushBack _key;
    _byKey set [_key, _x];
} forEach (keys _nodes);
_sortKeys sort true;

private _phoneticCount = count _phonetic;
{
    private _node = _nodes get (_byKey get _x);
    private _word = _phonetic select (_forEachIndex % _phoneticCount);
    private _cycle = floor (_forEachIndex / _phoneticCount);
    private _cs = [format ["%1-%2", _word, _cycle + 1], _word] select (_cycle == 0);
    _node set ["callsign", _cs];
} forEach _sortKeys;

INFO_1("c2Network - Assigned %1 unique callsigns",_nodeCount);

// ============================================================================
// Link topology — where faction character actually lives
// ============================================================================
// Hierarchical (conventional / partner): an outstation reports up to the
// nearest higher-tier node in range; relays report up to command. This is
// what makes conventional forces SLOW TO START — a contact report has to
// climb the chain before anyone with reach can act on it.
//
// Mesh (irregular): every same-side node within link range hears about it.
// No chain to climb, so irregulars are FAST TO START, but their link range
// is short so the alert never travels far.
//
// Links are stored symmetrically. Propagation in F.2 walks them with a
// reliability roll per hop, so a long chain naturally degrades.
private _nodeIds = keys _nodes;
private _linkPairs = 0;

private _fnc_link = {
    params ["_aId", "_bId"];
    if (_aId isEqualTo _bId) exitWith {};
    private _a = _nodes get _aId;
    private _b = _nodes get _bId;
    private _aLinks = _a get "links";
    private _bLinks = _b get "links";
    if !(_bId in _aLinks) then { _aLinks pushBack _bId; };
    if !(_aId in _bLinks) then { _bLinks pushBack _aId; };
};

{
    private _nodeId = _x;
    private _node   = _nodes get _nodeId;
    private _nPos   = _node get "position";
    private _nSide  = _node get "side";
    private _nRange = _node get "linkRange";
    private _nTier  = _node get "linkTier";

    if ((_node get "topology") isEqualTo "mesh") then {
        // Mesh — link to every same-side node in range, any tier.
        {
            private _otherId = _x;
            if (_otherId isNotEqualTo _nodeId) then {
                private _other = _nodes get _otherId;
                if ((_other get "side") isEqualTo _nSide) then {
                    if (((_other get "position") distance2D _nPos) <= _nRange) then {
                        [_nodeId, _otherId] call _fnc_link;
                        _linkPairs = _linkPairs + 1;
                    };
                };
            };
        } forEach _nodeIds;
    } else {
        // Hierarchical — link upward to the single nearest higher-tier
        // same-side node in range. Command nodes additionally peer with
        // each other so regional escalation can cross the map.
        private _bestUp = "";
        private _bestUpDist = 1e9;
        {
            private _otherId = _x;
            if (_otherId isNotEqualTo _nodeId) then {
                private _other = _nodes get _otherId;
                if ((_other get "side") isEqualTo _nSide) then {
                    private _d = (_other get "position") distance2D _nPos;
                    if (_d <= _nRange) then {
                        private _oTier = _other get "linkTier";
                        if (_oTier > _nTier && {_d < _bestUpDist}) then {
                            _bestUp = _otherId;
                            _bestUpDist = _d;
                        };
                        // Command-to-command peering
                        if (_nTier >= 3 && {_oTier >= 3}) then {
                            [_nodeId, _otherId] call _fnc_link;
                            _linkPairs = _linkPairs + 1;
                        };
                    };
                };
            };
        } forEach _nodeIds;

        if (_bestUp != "") then {
            [_nodeId, _bestUp] call _fnc_link;
            _linkPairs = _linkPairs + 1;
        };
    };
} forEach _nodeIds;

// Orphan report — nodes with no links can never escalate beyond themselves.
// That is legitimate (an isolated outpost genuinely is on its own) but worth
// surfacing, because a high orphan count usually means link ranges are wrong.
private _orphans = 0;
{
    private _lc = count ((_nodes get _x) get "links");
    if (_lc == 0) then { _orphans = _orphans + 1 };
} forEach _nodeIds;

INFO_2("c2Network - Link topology built (%1 link operations, %2 orphan nodes)",_linkPairs,_orphans);

missionNamespace setVariable ["DSC_c2Nodes", _nodes, true];

// ============================================================================
// Session globals
// ============================================================================
missionNamespace setVariable ["DSC_c2Stats", createHashMapFromArray [
    ["signalsRaised",   0],
    ["signalsLost",     0],
    ["signalsEchoed",   0],
    ["relaysLost",      0],
    ["alertsRaised",    0],
    ["alertsDecayed",   0],
    ["groupsStamped",   0],
    ["groupsPruned",    0],
    ["contactsDetected", 0],
    ["missedCheckIns",  0],
    ["noiseEvents",     0],
    ["reportsSent",     0],
    ["reportsSuppressed", 0],
    ["responsesDispatched", 0]
], true];

missionNamespace setVariable ["DSC_c2Feed", [], true];
missionNamespace setVariable ["DSC_c2TickHeartbeat", serverTime, true];

// ============================================================================
// Debug markers — one icon per node, colored by alert state
// ============================================================================
#ifdef DEBUG_MODE_FULL
{
    private _node = _nodes get _x;
    private _nPos = _node get "position";
    private _mName = format ["dsc_c2_%1", _x];
    private _m = createMarker [_mName, _nPos];
    _m setMarkerTypeLocal "mil_triangle";
    _m setMarkerColorLocal "ColorGrey";
    _m setMarkerSizeLocal [0.7, 0.7];
    _m setMarkerAlphaLocal 0.85;
    private _cs = _node get "callsign";
    private _tr = _node get "tier";
    _m setMarkerTextLocal format ["%1 (%2)", _cs, _tr select [0, 3]];
} forEach _nodeIds;
INFO_1("c2Network - Created %1 debug node markers",_nodeCount);
#endif

// ============================================================================
// Signal sources (Sprint F.2)
// ============================================================================
// EntityKilled + client-fired relay. Wired once, after the registry exists.
call DSC_core_fnc_c2InitSignalSources;

// ============================================================================
// Tick loop — alert decay + roster hygiene + accountability
// ============================================================================
// 10s cadence at a third phase offset (presence 8s, roving 8s+4s) so the
// three subsystems don't stack their work on the same scheduler frames.
//
// Responsibilities:
//   - decay alert states down the ladder
//   - prune dead / deleted groups from node rosters
//   - accountability: check-in deadlines, RTB overdue, element silence
//   - contact backstop: groups that know about an enemy but haven't fired
//   - LOD split so distant nodes cost almost nothing
//   - periodic stats report
[_nodes] spawn {
    params ["_nodes"];

    private _arch       = [] call DSC_core_fnc_getC2Archetypes;
    private _alertDecay = _arch get "alertDecay";
    private _archetypes = _arch get "archetypes";

    private _stateColor = createHashMapFromArray [
        ["GREEN", "ColorGrey"],
        ["AMBER", "ColorYellow"],
        ["RED",   "ColorRed"],
        ["BLACK", "ColorBlack"]
    ];

    // Full-fidelity radius. Nodes inside tick every cycle; nodes outside
    // tick every 6th cycle (~60s) since nothing the player can observe
    // depends on their precision.
    private _lodRadius = 5000;
    private _tickInterval = 10;
    private _cycle = 0;
    private _lastReport = serverTime;

    sleep 6;  // phase offset from presence (8s) and roving (8s +4s)

    while { true } do {
        sleep _tickInterval;
        _cycle = _cycle + 1;
        missionNamespace setVariable ["DSC_c2TickHeartbeat", serverTime, true];

        private _player = call CBA_fnc_currentUnit;
        private _playerPos = if (isNull _player) then { [0,0,0] } else { getPosATL _player };

        private _stats = missionNamespace getVariable ["DSC_c2Stats", createHashMap];
        private _decayed = 0;
        private _pruned  = 0;
        private _nearCount = 0;
        private _alertedCount = 0;
        private _missed = 0;

        {
            private _nodeId = _x;
            private _node   = _nodes get _nodeId;
            if (isNil "_node") then { continue };

            private _near = ((_node get "position") distance2D _playerPos) <= _lodRadius;
            if (_near) then { _nearCount = _nearCount + 1 };

            // Lazy tick for distant nodes — 1 in 6 cycles
            if (!_near && {(_cycle % 6) != 0}) then { continue };

            private _archKey = _node getOrDefault ["archetype", "irregular"];
            private _archCfg = _archetypes getOrDefault [_archKey, createHashMap];
            private _grace   = _archCfg getOrDefault ["checkInGrace", 300];
            private _interval= _archCfg getOrDefault ["checkInInterval", 600];

            // --- Roster hygiene + accountability --------------------------
            // Both walk the same roster, so they share one pass.
            //
            // The ordering here is deliberate and load-bearing: a group that
            // died is detected as WIPED (which schedules SILENCE) rather than
            // being silently pruned. Pruning first would make a destroyed
            // patrol indistinguishable from one the presence manager
            // legitimately despawned, and the player would get away with
            // everything by simply being thorough.
            private _roster = _node get "groups";
            private _live = [];
            private _wiped = [];

            {
                private _grp = _x;
                if (isNull _grp) then { continue };

                private _units = units _grp;
                private _anyAlive = (_units findIf { alive _x }) >= 0;

                if (_anyAlive) then {
                    _live pushBack _grp;
                } else {
                    // Units still exist as objects but all are dead — that
                    // is a destroyed element, not a despawned one.
                    if (_units isNotEqualTo []) then { _wiped pushBack _grp };
                };
            } forEach _roster;

            if ((count _live) != (count _roster)) then {
                _pruned = _pruned + ((count _roster) - (count _live));
                _node set ["groups", _live];
            };

            // --- Wiped elements: BACKSTOP only ------------------------------
            // The primary scheduling path is fnc_c2ContactReport, which
            // records the pending SILENCE at the instant the group dies. That
            // is race-free; this scan is NOT, because it needs the bodies and
            // the group object to still exist and other subsystems delete them
            // on their own ticks (fnc_rovingDespawnSweep culls a wiped foot
            // rover within ~8s, well before this can classify it).
            //
            // This branch therefore only catches groups that died WITHOUT ever
            // entering contact — wiped by an explosion, or by a kill that the
            // contact detector never saw. Do not rely on it for the ordinary
            // ambush case.
            private _pending = _node getOrDefault ["pendingSilence", []];
            {
                private _grp = _x;
                if !(_grp getVariable ["DSC_c2SilenceScheduled", false]) then {
                    _grp setVariable ["DSC_c2SilenceScheduled", true];
                    private _units2 = units _grp;
                    private _lastPos = [0,0,0];
                    if (_units2 isNotEqualTo []) then { _lastPos = getPosATL (_units2 select 0) };
                    // Clamp forward — see fnc_c2ContactReport for why a
                    // past-due deadline must roll to the next cycle instead
                    // of firing SILENCE immediately.
                    private _due = _grp getVariable ["DSC_c2NextCheckIn", 0];
                    if (_due <= serverTime) then { _due = serverTime + _interval };
                    _pending pushBack [groupId _grp, _lastPos, _due];
                    private _waitFor = _due - serverTime;
                    LOG_2("c2 silence scheduled (backstop) - %1 gone, due in %2s",groupId _grp,_waitFor toFixed 0);
                };
            } forEach _wiped;
            _node set ["pendingSilence", _pending];

            // --- Pending silence coming due ---------------------------------
            private _stillPending = [];
            {
                _x params ["_pLabel", "_pPos", "_pDue"];
                if (serverTime >= _pDue) then {
                    private _payload = createHashMapFromArray [
                        ["callsign",   _pLabel],
                        ["confidence", 0.7],
                        ["detail",     format ["%1 failed to report, presumed lost", _pLabel]]
                    ];
                    INFO_2("c2 SILENCE - %1 missed its call and is gone, %2 notified",_pLabel,_node get "callsign");
                    ["SILENCE", _nodeId, _pPos, _payload] call DSC_core_fnc_c2Signal;
                } else {
                    _stillPending pushBack _x;
                };
            } forEach _pending;
            if ((count _stillPending) != (count _pending)) then {
                _node set ["pendingSilence", _stillPending];
            };

            // --- Check-in accountability ------------------------------------
            // A HEALTHY group makes its call and reschedules silently. The
            // original implementation had no success path at all, so every
            // garrison sitting safely in its own outpost raised
            // MISSED_CHECKIN forever on a 600s cycle — the accountability
            // layer generated constant noise instead of meaning something.
            //
            // A live group only FAILS its check-in if it cannot transmit,
            // which means its radioman is dead. That gives the radioman
            // weight even when the player doesn't wipe the group: kill the
            // radio and the element goes quiet on its own schedule.
            {
                private _grp = _x;

                private _nextCheckIn = _grp getVariable ["DSC_c2NextCheckIn", 0];
                if (_nextCheckIn > 0 && {serverTime > (_nextCheckIn + _grace)}) then {
                    // Reschedule first, unconditionally, so nothing re-trips
                    // on every subsequent tick.
                    _grp setVariable ["DSC_c2NextCheckIn", serverTime + _interval];

                    private _radioman = _grp getVariable ["DSC_c2Radioman", objNull];
                    private _canTransmit = !isNull _radioman && {alive _radioman};

                    // A group already in contact has reported for itself; its
                    // parent knows where it is and why it is busy.
                    private _accounted = _grp getVariable ["DSC_c2Reported", false];

                    if (_canTransmit || _accounted) then {
                        LOG_2("c2 check-in OK - %1 reported to %2",groupId _grp,_node get "callsign");
                    } else {
                        _missed = _missed + 1;
                        private _gLabel2 = groupId _grp;
                        private _gPos = getPosATL (leader _grp);
                        private _payload2 = createHashMapFromArray [
                            ["callsign",   _gLabel2],
                            ["confidence", 0.4],
                            ["detail",     format ["%1 has missed a check-in", _gLabel2]]
                        ];
                        LOG_2("c2 MISSED_CHECKIN - %1 cannot transmit (radioman down), node %2",_gLabel2,_node get "callsign");
                        ["MISSED_CHECKIN", _nodeId, _gPos, _payload2] call DSC_core_fnc_c2Signal;
                    };
                };

                // --- RTB accountability ------------------------------------
                // Only deployed elements carry a non-zero RtbEta (set in
                // fnc_c2StampGroup). Garrisons and guards read 0 here and are
                // never "overdue" — they are not due back anywhere.
                private _rtb = _grp getVariable ["DSC_c2RtbEta", 0];
                if (_rtb > 0 && {serverTime > _rtb} && {!(_grp getVariable ["DSC_c2RtbRaised", false])}) then {
                    _grp setVariable ["DSC_c2RtbRaised", true];
                    private _gLabel3 = groupId _grp;
                    private _gPos3 = getPosATL (leader _grp);
                    private _payload3 = createHashMapFromArray [
                        ["callsign",   _gLabel3],
                        ["confidence", 0.3],
                        ["detail",     format ["%1 is overdue", _gLabel3]]
                    ];
                    LOG_2("c2 OVERDUE_RTB - %1 (node %2)",_gLabel3,_node get "callsign");
                    ["OVERDUE_RTB", _nodeId, _gPos3, _payload3] call DSC_core_fnc_c2Signal;
                };

                // --- Contact backstop -------------------------------------
                // Covers the standoff case: two sides aware of each other,
                // nobody hit yet, so neither EntityKilled nor Fired has
                // produced anything. Only checked for near nodes since it
                // costs a knowsAbout call per group.
                if (_near && {!(_grp getVariable ["DSC_c2InContact", false])}) then {
                    private _ldr = leader _grp;
                    if (alive _ldr) then {
                        private _enemy = _ldr findNearestEnemy _ldr;
                        if (!isNull _enemy && {(_ldr distance2D _enemy) < 400} && {(_grp knowsAbout _enemy) > 1.5}) then {
                            [_grp] spawn DSC_core_fnc_c2ContactReport;
                        };
                    };
                };
            } forEach _live;

            // --- Dispatch record hygiene (Sprint F.3) ----------------------
            // Prune finished responses so the record doesn't grow all session
            // and so the tablet (F.4) can read "what is currently inbound"
            // without filtering corpses. Wiping a QRF is legitimate play, and
            // it must clear cleanly — the group's own C2 stamp means the wipe
            // still generates its own SILENCE through the normal path.
            private _disp = _node getOrDefault ["dispatched", []];
            if (_disp isNotEqualTo []) then {
                private _liveDisp = _disp select {
                    private _dg = _x getOrDefault ["group", grpNull];
                    !isNull _dg && {((units _dg) findIf { alive _x }) >= 0}
                };
                if ((count _liveDisp) != (count _disp)) then {
                    private _lost = (count _disp) - (count _liveDisp);
                    LOG_2("c2 [%1] - %2 dispatched element(s) no longer active",_node get "callsign",_lost);
                    _node set ["dispatched", _liveDisp];
                };
            };

            // --- Alert decay ----------------------------------------------
            private _alert = _node get "alert";
            if (_alert != "GREEN") then {
                _alertedCount = _alertedCount + 1;

                // --- Response evaluation (Sprint F.3) ----------------------
                // Runs BEFORE decay so a node that is about to cool down
                // still gets its final chance to act on what it knows.
                // Spawned rather than called: fnc_c2ResponseQrf yields
                // (uiSleep in the yielding spawner, plus a pause between
                // BLACK waves) and must not block the tick walking 32 nodes.
                [_nodeId] spawn DSC_core_fnc_c2Respond;

                private _decayCfg = _alertDecay getOrDefault [_alert, [0, "GREEN"]];
                _decayCfg params ["_holdFor", "_nextState"];
                private _elapsed = serverTime - (_node get "alertSince");
                if (_holdFor > 0 && {_elapsed >= _holdFor}) then {
                    _node set ["alert", _nextState];
                    _node set ["alertSince", serverTime];
                    _node set ["alertSource", "decay"];
                    _node set ["responseDelay", -1];
                    _decayed = _decayed + 1;
                    private _cs = _node get "callsign";
                    LOG_3("c2 decay [%1] %2 -> %3",_cs,_alert,_nextState);

                    #ifdef DEBUG_MODE_FULL
                    private _mName = format ["dsc_c2_%1", _nodeId];
                    private _col = _stateColor getOrDefault [_nextState, "ColorGrey"];
                    _mName setMarkerColorLocal _col;
                    #endif
                };
            };
        } forEach (keys _nodes);

        if (_decayed > 0) then {
            _stats set ["alertsDecayed", (_stats getOrDefault ["alertsDecayed", 0]) + _decayed];
        };
        if (_pruned > 0) then {
            _stats set ["groupsPruned", (_stats getOrDefault ["groupsPruned", 0]) + _pruned];
        };
        if (_missed > 0) then {
            _stats set ["missedCheckIns", (_stats getOrDefault ["missedCheckIns", 0]) + _missed];
        };

        // --- Periodic report ------------------------------------------------
        if ((serverTime - _lastReport) >= 60) then {
            _lastReport = serverTime;
            private _totalRostered = 0;
            {
                private _rc = count ((_nodes get _x) get "groups");
                _totalRostered = _totalRostered + _rc;
            } forEach (keys _nodes);

            private _stamped = _stats getOrDefault ["groupsStamped", 0];
            private _prunedTotal = _stats getOrDefault ["groupsPruned", 0];
            INFO_5("c2 STATS - nodes:%1 near:%2 alerted:%3 rostered:%4 (stamped:%5)",count _nodes,_nearCount,_alertedCount,_totalRostered,_stamped);
            LOG_1("c2 STATS - groups pruned this session: %1",_prunedTotal);

            // Signal accounting. `sent` vs `suppressed` is the headline
            // number for whether the report-timer mechanic is tuned right:
            // if suppressed is near zero the window is too tight to reward
            // good play, and if it dominates the network never reacts.
            private _sig  = _stats getOrDefault ["signalsRaised", 0];
            private _lost = _stats getOrDefault ["signalsLost", 0];
            private _sent = _stats getOrDefault ["reportsSent", 0];
            private _supp = _stats getOrDefault ["reportsSuppressed", 0];
            private _miss = _stats getOrDefault ["missedCheckIns", 0];
            private _noise= _stats getOrDefault ["noiseEvents", 0];
            INFO_5("c2 SIGNALS - raised:%1 lostAtIntake:%2 reportsSent:%3 suppressed:%4 missedCheckIn:%5",_sig,_lost,_sent,_supp,_miss);
            LOG_1("c2 SIGNALS - noise events: %1",_noise);

            #ifdef DEBUG_MODE_FULL
            systemChat format ["DSC C2 - nodes:%1 near:%2 alerted:%3 rostered:%4", count _nodes, _nearCount, _alertedCount, _totalRostered];
            systemChat format ["DSC C2 sig - sent:%1 suppressed:%2 lost:%3 missed:%4", _sent, _supp, _lost, _miss];
            #endif
        };
    };
};

INFO_1("c2Network - Initialized (%1 nodes, 10s tick, signals live Sprint F.2)",_nodeCount);

_nodes
