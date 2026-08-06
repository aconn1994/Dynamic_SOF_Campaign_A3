#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_getC2Archetypes
 * Description:
 *     Static data for the C2 Network (Sprint F.1). Defines how different
 *     kinds of force organize their communications, how capable each node
 *     tier is, and how alert states decay.
 *
 *     Three axes combine to produce a node's behavior:
 *
 *       1. ARCHETYPE (who they are) — derived from the faction's role in
 *          factionProfileConfig. Drives link topology, link range, message
 *          reliability, check-in discipline, and contact report speed.
 *
 *       2. TIER (what the installation is) — base / outpost / camp+town.
 *          Drives response reach, decision latency, and what kinds of
 *          response the node can even field.
 *
 *       3. INFLUENCE (how strong they are there) — read live from
 *          influence data, not stored here.
 *
 *     The emergent contrast this produces is the whole point:
 *
 *       Conventional — slow to start (report -> HQ -> decision -> launch),
 *       fast to arrive (vehicles, air), long reach. The player gets a
 *       window to break contact, then a hard, competent, wide response.
 *
 *       Irregular — fast to start (everyone in the settlement heard it),
 *       no reach past ~3 km, but overwhelming numbers locally. A firefight
 *       next to a high-influence armed-civilian town is a hornets' nest
 *       within 90 seconds. Get 4 km out and it is over.
 *
 *     Result is cached in DSC_c2ArchetypeCache — this is called per node
 *     during registry build and per tick during decay evaluation.
 *
 * Arguments:
 *     None
 *
 * Return Value:
 *     <HASHMAP> with keys:
 *       "archetypes"       <HASHMAP> archetypeKey -> config
 *       "tiers"            <HASHMAP> tierKey      -> config
 *       "roleToArchetype"  <HASHMAP> factionRole  -> archetypeKey
 *       "alertDecay"       <HASHMAP> alertState   -> [seconds, nextState]
 *       "alertRank"        <HASHMAP> alertState   -> NUMBER (for comparison)
 *
 * Example:
 *     private _arch = [] call DSC_core_fnc_getC2Archetypes;
 */

private _cached = missionNamespace getVariable ["DSC_c2ArchetypeCache", createHashMap];
if (_cached isNotEqualTo createHashMap) exitWith { _cached };

// ============================================================================
// Comms archetypes — how a kind of force talks to itself
// ============================================================================
// linkRange       max distance (m) a node will link to another node
// topology        "hierarchical" (outstation -> relay -> command)
//                 "mesh"         (everyone near everyone, word of mouth)
// reliability     0..1 chance a message survives a single relay hop
// latencyMult     multiplier on the tier's base decision latency
// checkInInterval seconds between scheduled group check-ins
// checkInGrace    seconds past the deadline before MISSED_CHECKIN fires
// reportDelay     [min, max] seconds for a group in contact to get a
//                 contact report out (before leader/radioman modifiers)
// rtbMult         multiplier on patrol duration for OVERDUE_RTB
private _archetypes = createHashMapFromArray [
    ["conventional", createHashMapFromArray [
        ["label",           "Conventional"],
        ["linkRange",       12000],
        ["topology",        "hierarchical"],
        ["reliability",     0.90],
        ["latencyMult",     1.00],
        ["checkInInterval", 300],
        ["checkInGrace",    120],
        ["reportDelay",     [8, 18]],
        ["rtbMult",         1.0]
    ]],
    ["partner", createHashMapFromArray [
        ["label",           "Partner / Militia"],
        ["linkRange",       6500],
        ["topology",        "hierarchical"],
        ["reliability",     0.60],
        ["latencyMult",     1.60],
        ["checkInInterval", 600],
        ["checkInGrace",    300],
        ["reportDelay",     [18, 35]],
        ["rtbMult",         1.4]
    ]],
    ["irregular", createHashMapFromArray [
        ["label",           "Irregular"],
        ["linkRange",       4000],
        ["topology",        "mesh"],
        ["reliability",     0.35],
        ["latencyMult",     0.50],
        ["checkInInterval", 1200],
        ["checkInGrace",    600],
        ["reportDelay",     [30, 60]],
        ["rtbMult",         2.0]
    ]]
];

// ============================================================================
// Node tiers — what an installation is capable of
// ============================================================================
// reach       max distance (m) this node will project a response.
//             BEYOND REACH, NOTHING ARRIVES. Not a delayed response, not a
//             small one. This is what makes a CSAT recce patrol caught in
//             empty terrain a genuinely isolated fight, with no special case.
// latency     [min, max] seconds from receiving a signal to acting on it
// responses   what this tier can field (consumed in Sprint F.3)
// linkTier    hierarchy level for "hierarchical" topology link building
private _tiers = createHashMapFromArray [
    ["COMMAND", createHashMapFromArray [
        ["label",     "Command"],
        ["reach",     8000],
        ["latency",   [60, 120]],
        ["responses", ["qrf", "air", "mortar"]],
        ["linkTier",  3]
    ]],
    ["RELAY", createHashMapFromArray [
        ["label",     "Relay"],
        ["reach",     4000],
        ["latency",   [45, 90]],
        ["responses", ["qrf"]],
        ["linkTier",  2]
    ]],
    ["OUTSTATION", createHashMapFromArray [
        ["label",     "Outstation"],
        ["reach",     1500],
        ["latency",   [15, 45]],
        ["responses", ["foot"]],
        ["linkTier",  1]
    ]]
];

// ============================================================================
// Faction role -> comms archetype
// ============================================================================
// Roles come from factionProfileConfig. Civilians and environmental actors
// have no C2 presence and are deliberately absent.
private _roleToArchetype = createHashMapFromArray [
    ["bluFor",        "conventional"],
    ["opFor",         "conventional"],
    ["bluForPartner", "partner"],
    ["opForPartner",  "partner"],
    ["irregulars",    "irregular"]
];

// ============================================================================
// Alert decay ladder
// ============================================================================
// [secondsAtThisState, stateToDecayTo]. Evaluated on the C2 tick.
private _alertDecay = createHashMapFromArray [
    ["BLACK", [600, "RED"]],
    ["RED",   [420, "AMBER"]],
    ["AMBER", [300, "GREEN"]],
    ["GREEN", [0,   "GREEN"]]
];

// Numeric rank so escalation logic can compare states without a switch.
private _alertRank = createHashMapFromArray [
    ["GREEN", 0],
    ["AMBER", 1],
    ["RED",   2],
    ["BLACK", 3]
];

// ============================================================================
// Signal grades (Sprint F.2)
// ============================================================================
// What alert level each kind of information justifies, and how far it is
// worth passing along. Ordered here by how much the player got away with.
//
// grade    alert level raised at the origin node
// maxHops  relay depth. AMBER-grade signals never relay regardless (see
//          fnc_c2Signal) — unverified noise stays local, which is what
//          keeps the network quiet enough that a real alert means something.
// label    short human-readable form used in the radio feed
// refresh  whether a repeat at the SAME alert level restarts the decay
//          clock. TRUE for live sensory events, so sustained contact holds
//          an area hot. FALSE for accountability bookkeeping — otherwise a
//          batch of overdue patrols re-arms the timer every cycle and the
//          node can never cool back to GREEN no matter what the player does.
// echo     seconds during which a REPEAT of the same signal type at the same
//          node is treated as an echo: it still records last-known-position
//          and still writes to the radio feed, but it does not re-raise the
//          alert or re-walk the relay tree.
//
//          Without this a single firefight is catastrophic. A playtest had
//          fifteen defending groups enter contact within one second; each
//          sent its own report and each report walked four relay hops,
//          producing ~60 signals and a wall of duplicate feed lines for what
//          was one engagement HQ already knew about. Real command posts log
//          the second caller, they don't re-panic.
private _signalGrades = createHashMapFromArray [
    ["CONTACT_REPORT", createHashMapFromArray [
        ["grade",   "RED"],
        ["maxHops", 3],
        ["label",   "Contact report"],
        ["refresh", true],
        ["echo",    90]
    ]],
    ["EXPLOSION", createHashMapFromArray [
        ["grade",   "RED"],
        ["maxHops", 2],
        ["label",   "Explosion heard"],
        ["refresh", true],
        ["echo",    45]
    ]],
    ["GUNFIRE_HEARD", createHashMapFromArray [
        ["grade",   "AMBER"],
        ["maxHops", 0],
        ["label",   "Small arms heard"],
        ["refresh", true],
        ["echo",    60]
    ]],
    ["MISSED_CHECKIN", createHashMapFromArray [
        ["grade",   "AMBER"],
        ["maxHops", 0],
        ["label",   "Missed check-in"],
        ["refresh", false],
        ["echo",    0]
    ]],
    ["OVERDUE_RTB", createHashMapFromArray [
        ["grade",   "AMBER"],
        ["maxHops", 0],
        ["label",   "Patrol overdue"],
        ["refresh", false],
        ["echo",    0]
    ]],
    // An entire element going silent is materially worse than one late
    // check-in — somebody died and nobody got a word out. Never echoed:
    // each lost element is separate news.
    ["SILENCE", createHashMapFromArray [
        ["grade",   "RED"],
        ["maxHops", 2],
        ["label",   "Element lost contact"],
        ["refresh", false],
        ["echo",    0]
    ]],
    ["INSTALLATION_ATTACKED", createHashMapFromArray [
        ["grade",   "BLACK"],
        ["maxHops", 3],
        ["label",   "Installation under attack"],
        ["refresh", true],
        ["echo",    60]
    ]]
];

// ============================================================================
// Noise grades (Sprint F.2)
// ============================================================================
// Audible radius per event class and the signal it generates. Explosions
// are deliberately the loudest thing in the game — this table is the main
// lever separating a quiet AFO posture from a loud DA posture, and it is
// what makes "hack the relay" a genuinely different choice from "blow the
// relay up."
private _noiseGrades = createHashMapFromArray [
    ["SUPPRESSED",  createHashMapFromArray [["radius",   75], ["signal", ""]]],
    ["SMALL_ARMS",  createHashMapFromArray [["radius",  800], ["signal", "GUNFIRE_HEARD"]]],
    ["EXPLOSION",   createHashMapFromArray [["radius", 2500], ["signal", "EXPLOSION"]]],
    ["VEHICLE_KILL",createHashMapFromArray [["radius", 3500], ["signal", "EXPLOSION"]]]
];

// ============================================================================
// Response ladder (Sprint F.3)
// ============================================================================
// What a node actually DOES at each alert level. Keyed by alert state; each
// entry lists response kinds in priority order plus the pacing knobs.
//
// recallRadius  how far from the node we look for existing groups to redirect
// qrfCount      how many QRF elements may be dispatched per wave
// cooldown      seconds before this node may dispatch again at this level.
//               Without it, a node sitting at RED for 7 minutes would launch
//               a fresh wave every 10s tick.
// searchSpread  base radius (m) around LKP that responders sweep. Scaled UP
//               by (1 - confidence) at dispatch time, so a stale third-hand
//               report produces a wide lazy sweep and a direct contact report
//               produces a tight dangerous one.
//
// GREEN is absent — a node at GREEN dispatches nothing, which is the point.
private _responseLadder = createHashMapFromArray [
    ["AMBER", createHashMapFromArray [
        ["responses",    ["recall"]],
        ["recallRadius", 1200],
        ["qrfCount",     0],
        ["cooldown",     240],
        ["searchSpread", 300]
    ]],
    ["RED", createHashMapFromArray [
        ["responses",    ["recall", "qrf"]],
        ["recallRadius", 2000],
        ["qrfCount",     1],
        ["cooldown",     300],
        ["searchSpread", 200]
    ]],
    ["BLACK", createHashMapFromArray [
        ["responses",    ["recall", "qrf"]],
        ["recallRadius", 3000],
        ["qrfCount",     2],
        ["cooldown",     240],
        ["searchSpread", 150]
    ]]
];

// Which response kinds each tier is physically able to field. Intersected
// with the ladder above, so an OUTSTATION at RED recalls but cannot QRF —
// a village has people to send looking, not a mounted reaction force.
// This is what makes tier matter as much as alert level.
private _tierResponses = createHashMapFromArray [
    ["COMMAND",    ["recall", "qrf"]],
    ["RELAY",      ["recall", "qrf"]],
    ["OUTSTATION", ["recall"]]
];

private _result = createHashMapFromArray [
    ["archetypes",      _archetypes],
    ["tiers",           _tiers],
    ["roleToArchetype", _roleToArchetype],
    ["alertDecay",      _alertDecay],
    ["alertRank",       _alertRank],
    ["signalGrades",    _signalGrades],
    ["noiseGrades",     _noiseGrades],
    ["responseLadder",  _responseLadder],
    ["tierResponses",   _tierResponses]
];

missionNamespace setVariable ["DSC_c2ArchetypeCache", _result];

_result
