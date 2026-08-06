# C2 Network + ISR — DSC Communication Simulation

*Design doc — July 2026. **Sprints F.1 + F.2 + F.3 SHIPPED** (registry,
provenance, alert decay, signals, propagation, response ladder). F.4-F.5
designed, not implemented. Sibling subsystem to the Presence Manager and
Roving Manager.*

## Implementation Status

| Sprint | Status | What exists |
|---|---|---|
| **F.1 — Provenance + registry** | **SHIPPED** | `DSC_c2Nodes` registry, link topology, callsigns, provenance stamping, alert ladder + decay tick, debug markers |
| **F.2 — Signals + propagation** | **SHIPPED** | Report timer with radioman/leader modifiers, noise events, check-in/RTB/SILENCE accountability, relay hops with reliability rolls, LKP confidence decay, radio feed buffer |
| **F.3 — Response ladder** | **SHIPPED** | Recall (redirect existing groups) + QRF (real spawn, real travel), tier×alert capability gating, decision latency, dispatch cooldown, confidence-scaled search radius, LAMBS soft dep, presence COMBAT hold |
| **F.4 — ISR + player-facing** | **SHIPPED** | ISR coverage tiers (NONE/BASIC/ENHANCED/FULL), live intercepted chatter via `systemChat`, diegetic telegraphs (illum flare on RED, headlights on dispatch), tablet **Radio Feed** page on the INTEL tab with coverage header + alerted-node strip + EARNED/ALL filter, **hostile contact fixes on the BFT** (SIGINT radio-DF + VISUAL own-force reports, aged and fading) |
| F.5 — Counterplay | designed | — |

### What F.1 actually shipped

**Functions**

| Function | Role |
|---|---|
| `fnc_getC2Archetypes` (data) | Comms archetypes, node tiers, role→archetype map, alert decay ladder, alert ranks, **signal grades, noise grades**. Cached in `DSC_c2ArchetypeCache`. |
| `fnc_initC2Network` (c2) | Builds `DSC_c2Nodes` from influence data, precomputes links, assigns callsigns, spawns the 10s tick (decay + roster hygiene + **accountability scan**) |
| `fnc_c2StampGroup` (c2) | **The foundational primitive.** Stamps provenance + check-in/RTB deadlines + radioman onto a group and registers it on a node roster |
| `fnc_c2ResolveNode` (c2) | Reach-aware "who owns this ground" lookup, influence-weighted |
| `fnc_c2RaiseAlert` (c2) | Single entry point for raising alert state. Ratchets up only; decay is the only way down. Records LKP. |
| `fnc_c2Signal` (c2) | **F.2.** Signal intake + breadth-first relay propagation. Reliability roll per hop, grade degradation per hop, LKP confidence decay. |
| `fnc_c2ContactReport` (c2) | **F.2.** The report timer. Spawned per group entering contact; 1s poll so late radioman kills still extend it. |
| `fnc_c2NoiseEvent` (c2) | **F.2.** Turns a loud event into signals at nodes in radius *and* at stamped groups that heard it. |
| `fnc_c2InitSignalSources` (c2) | **F.2.** Wires `EntityKilled` mission EH + the client-fired CBA relay. |
| `fnc_c2FeedAdd` (c2) | **F.2.** Writes the radio feed ring buffer (200 entries) that F.4's tablet page will read. |
| `fnc_c2Respond` (c2) | **F.3.** Dispatcher. Three gates: decision latency, dispatch cooldown, tier×alert capability. |
| `fnc_c2ResponseRecall` (c2) | **F.3.** Redirects existing mobile groups to the LKP. Zero spawn cost. |
| `fnc_c2ResponseQrf` (c2) | **F.3.** Real spawn at the node + real travel to the LKP. Ignores the presence budget cap. |

**Init order** — `fnc_initServer` STEP 4c, deliberately **before** presence
(4d) and roving (4e), because both stamp their groups and the registry has
to exist for those stamps to land.

**Stamping touch points** (fewer than the 11 originally scoped — see
"Dispatcher-level stamping" below):

| Site | Covers |
|---|---|
| `fnc_activatePresenceZone` | All 8 presence zone types, and any future handler automatically |
| `fnc_rovingSpawnAir` / `Ground` / `Foot` / `Boat` | All ambient rovers |
| `fnc_populateAO` | Mission AO forces |
| `fnc_cleanupMission` | Resets alert/heat/LKP/dispatch, prunes rosters, clears group accountability flags |

**Signal sources (F.2)**

| Source | Where | Catches |
|---|---|---|
| `EntityKilled` mission EH (server, 1 handler) | `fnc_c2InitSignalSources` | Deaths → noise event + immediate contact detection on the victim's group |
| `Fired` EH on player (client) → `DSC_c2_playerFired` CBA server event | `fnc_initPlayerLocal` | The player shooting **and missing**, which `EntityKilled` cannot see. Suppressor classified client-side because muzzle accessory data isn't reliable for remote units. Throttled 1/sec/player. |
| Contact backstop | C2 tick, near nodes only | Standoffs where both sides are aware but nobody has fired or died yet (`knowsAbout > 1.5` within 400 m) |
| Accountability scan | C2 tick | `MISSED_CHECKIN`, `OVERDUE_RTB`, `SILENCE` |

Deliberately built from **two** server-side handlers plus one per player
rather than per-unit `FiredNear` EHs. The existing combat-activation code
uses per-unit handlers, which is fine for a mission AO but the presence
manager can have 150 units standing at once. This scales flat.

**Group variables written by F.2**

```sqf
DSC_c2InContact          // report timer started (prevents duplicate timers)
DSC_c2Reported           // a contact report actually went out
DSC_c2SilenceScheduled   // wipe detected, SILENCE queued on the node
DSC_c2RtbRaised          // OVERDUE_RTB already raised
DSC_c2Quality            // optional report-delay multiplier (default 1.0, unset)
DSC_c2LastFiredReport    // per-player Fired throttle timestamp
```


**Globals**

```sqf
DSC_c2Nodes           // hashmap nodeId -> node hashmap
DSC_c2ArchetypeCache  // memoized archetype data
DSC_c2Stats           // session counters
DSC_c2Feed            // radio feed ring buffer (F.4 consumer)
DSC_c2TickHeartbeat   // serverTime, watchdog
```

### Design decisions made during F.1 implementation

**Dispatcher-level stamping instead of per-spawner.** The original plan
called for stamping inside all ~11 setup functions. Stamping in
`fnc_activatePresenceZone` instead collapses eight of those into one
choke point, and means a new zone type physically cannot ship without
provenance. The tradeoff is that all groups from a zone share one role
label rather than per-group patrol/guard/static granularity. v1 does not
consume role (check-in cadence is per faction archetype, per the locked
decision), so the robustness is worth more than the detail. Per-group
roles remain available as a v2 refinement.

**Civilian groups are excluded from rosters.** All four microzone
handlers and `populatedArea` append wandering civilians and indoor
civilian clusters to the same `zone.groups` array as armed groups.
Stamping those would put phantom entries on military node rosters and
make F.2's check-in scan fire `MISSED_CHECKIN` every time a farmer
wandered out of a zone.

**Nodes are resolved per side, not per zone.** A single zone can hold
opposing forces — contested zones get a west skirmish patrol from
`fnc_setupContestedSkirmish`, and neutral zones get an east irregular
overlay from `fnc_resolveIrregularOverlay`. Stamping everything to the
zone's own node would have an attacking force reporting to the
installation it is attacking. The dispatcher caches one resolved node per
side present in the zone.

**Neutral and contested locations still become nodes.** They resolve to
the `irregular` archetype when no controlling faction maps to a role. A
neutral town with a local armed population is precisely the hornets-nest
case, and the mesh topology needs those nodes to exist in order to
propagate at all.

**Timebase.** C2 uses `serverTime` for all game-logic deadlines and
`sleep` for the tick, so the subsystem scales coherently under
`setAccTime`. It deliberately avoids mixing in `diag_tickTime`/`uiSleep`
— see the presence manager's accelerated-time gotcha for why mixing the
two makes logs unreadable. F.3 spawn code will still use `uiSleep` for
frame-spike avoidance, which is a different concern.

### Design decisions made during F.2 implementation

**AMBER-grade signals do not relay.** Unverified noise (gunfire heard,
missed check-in, overdue patrol) raises the local node and stops there.
Only a confirmed contact report, a destroyed element, or an installation
under attack is worth a regional phone call. Without this rule the network
saturates — every distant gunshot would eventually turn the whole map
AMBER and the alert state would stop carrying information.

**Grade degrades one rank per relay hop.** A relayed report is hearsay, so
a confirmed contact (RED) makes neighbours merely suspicious (AMBER)
rather than equally certain. This is also what naturally bounds
propagation: RED reaches one hop, BLACK reaches two, and nothing needs an
arbitrary distance cutoff.

**Order of operations in the accountability scan is load-bearing.** Roster
hygiene must detect *wiped* groups (all units dead but objects still
present) **before** pruning them. Pruning first would make a destroyed
patrol indistinguishable from one the presence manager legitimately
despawned, and `SILENCE` would never fire — the player would get away with
everything by simply being thorough.

**Direct attacks on an installation escalate to BLACK.** A garrison or
guard element fighting within 400 m of its own node reports
`INSTALLATION_ATTACKED`, not `CONTACT_REPORT`. Without this, assaulting a
base outright would produce the same alert grade as ambushing one of its
patrols 3 km away.

**A group that already reported does not also fail its check-in.** Its
parent knows exactly where it is and why it's busy, so raising
`MISSED_CHECKIN` on top would double-report one engagement. Suppressed
groups (wiped before transmitting) are *not* exempt — that is the entire
point of the accountability layer.

**Noise events have a 12 km player-relevance gate.** `EntityKilled` fires
for every death on the map including AI-vs-AI fights the player will never
see, and each one otherwise costs a full node sweep plus a `nearEntities`
call. 12 km is beyond the widest node reach (8 km COMMAND), so this is a
pure perf guard with no gameplay effect.

**The report timer polls at 1s instead of sleeping once.** Killing the
radioman twenty seconds into a firefight has to still extend the deadline,
or the mechanic collapses into "win the initiative roll at contact." The
timer recomputes leader/radioman multipliers every poll.

**Loop control uses an explicit flag, not `exitWith`.** `exitWith` inside
a `while` body is ambiguous enough about whether it breaks the loop or
returns from the function that the suppression accounting must not depend
on it. If it returned early, a suppressed report would never be logged and
the mechanic would look broken while silently working correctly.

### F.2 post-playtest fixes (July 2026)

First live playtest (remote outpost, patrol ambush + air strike on an MRAP
rover) validated the core mechanic and exposed three defects. All three are
fixed; the playtest log is the reference case.

**Callsigns were only unique per faction.** Counters were keyed by faction,
so faction A and faction B each began at ALPHA. One session produced three
separate nodes called `BRAVO` and the feed printed
`BRAVO -> BRAVO "Relaying..."`. Callsigns are now assigned in a **second
pass after all nodes are built**, from a single running index, sorted by
(faction, tier) so a force still reads as one organization with COMMAND
first. Uniqueness is the load-bearing property — the whole point is that
the player learns "ZULU is the outpost north of me."

**`MISSED_CHECKIN` had no success path.** Nothing ever marked a group as
having checked in, so `DSC_c2NextCheckIn` only ever came due and fired.
Every healthy garrison sitting safely in its own outpost raised
`MISSED_CHECKIN` on a permanent 600s cycle — the accountability layer
produced constant noise instead of signal, and it was what raised the first
AMBER in the playtest rather than anything the player did.

Now a live group at its deadline **checks in successfully and reschedules
silently**. A live group only *fails* if it cannot transmit, which means
its radioman is dead. This gives the radioman weight even when the player
doesn't wipe the group: kill the radio and the element goes quiet on its
own schedule, raising AMBER minutes later.

**`SILENCE` fired ~instantly, which gutted the report-timer reward.** In
the playtest: `REPORT SUPPRESSED` at 8:15:26, `SILENCE` at 8:15:28. A
clean silent wipe bought **two seconds**. The only reason the outpost
stayed GREEN was a lucky failed reliability roll on the SILENCE.

A destroyed element does not announce itself. Wiped groups are now added to
a per-node `pendingSilence` list carrying `[callsign, lastPos, dueTime]`
where `dueTime` is the group's **real check-in deadline**. `SILENCE` fires
when that deadline passes — minutes, not seconds. The snapshot means the
entry survives the group being pruned from the roster.

This is the change that makes a clean wipe actually worth executing: the
reprieve is now long enough to finish the job and move, which is what the
mechanic was always supposed to buy.

### F.2 second playtest fixes (July 2026)

Second playtest (HALO insertion near an outpost, 2-man patrol wiped in
seconds) found four more defects. The player's report — "I waited for the
SILENCE and it never came, and the outpost was already alerted before I
did anything" — was correct on both counts.

**A wiped rover's SILENCE was being dropped entirely.** The deferral fix
above scheduled `pendingSilence` from the tick's wiped-group scan, which
requires the dead bodies and the group object to still exist.
`fnc_rovingDespawnSweep` culls any foot rover whose group has no living
units on its own ~8s tick, so a rover wiped at T was deleted by T+5 — before
the C2 tick at T+10 could classify it. The group then looked *despawned by
the manager* rather than *destroyed by the player*, got pruned, and no
SILENCE was ever scheduled.

Log evidence: `REPORT SUPPRESSED` at 5:53:01, `roving despawned [foot/...]
group dead` at 5:53:06, `groups pruned: 1`, and SILENCE never appears.

Scheduling now happens in **`fnc_c2ContactReport` at the instant of the
wipe**, which is race-free — that code already knows the group died, and
the `[callsign, lastPos, dueTime]` snapshot survives deletion. The tick scan
is demoted to an explicit backstop for groups that die *without ever
entering contact* (wiped by an explosion, or a kill the detector missed).

**The player's own parachute was broadcasting a 3.5 km explosion.** A
deployed parachute is a vehicle (`ParachuteBase` → `Air` → `AllVehicles`)
and it is *destroyed*, not deleted, when the jumper lands. Ungated it
graded as `VEHICLE_KILL` and raised RED across every node in 3500 m, so
**every HALO insertion alerted the whole area before the player fired a
shot** — the exact opposite of a covert infil, and the reason the outpost
and its parent base were already lit in the playtest.

`fnc_c2InitSignalSources` now ignores `ParachuteBase` and weapon-holder
classes outright. Any future "vehicle" that is really engine bookkeeping
belongs on that list.

**Every garrison reported itself overdue.** `DSC_c2RtbEta` was stamped on
all groups, so one duration after a zone activated, every static defender
in a city fired `OVERDUE_RTB` in a single burst (~25 signals across two
nodes in the playtest, all at 6:00:03 and 6:00:23 — exactly 600 s after
their 5:50:03/5:50:15 stamps).

"Overdue" is meaningless for a garrison: it is not due back anywhere, it
lives there. RTB is now only stamped for **deployed roles** (`rover`,
`patrol`); everything else gets 0, which the tick reads as "no RTB". The
deadline also carries ±20% jitter so a batch spawned in one worker cycle
does not come due together.

**Accountability signals were preventing nodes from ever cooling down.**
`fnc_c2RaiseAlert` refreshed the decay clock on any same-level re-raise,
which is correct for sustained contact but wrong for bookkeeping. The
overdue burst above logged `alert refreshed [CHARLIE-2] holding AMBER`
twenty-plus times, re-arming the 300 s AMBER timer on every one — the node
could never return to GREEN regardless of what the player did.

Signal grades now carry a `refresh` flag: `true` for live sensory events
(contact report, explosion, gunfire, installation attacked) so sustained
fighting holds an area hot, `false` for accountability
(`MISSED_CHECKIN`, `OVERDUE_RTB`, `SILENCE`). Absorbed signals still record
LKP and still log — they just don't touch the clock.

**Cosmetic:** the group-relay feed line hardcoded "We have gunfire to our
%1" for every noise type, producing "gunfire" for a vehicle brewing up
3 km away. It now reads the noise class ("an explosion", "a vehicle
burning", "gunfire").

### Design decisions made during F.3 implementation

**Capability is `ladder ∩ tier`, not alert level alone.** The alert state
says what a node *wants* to do; `tierResponses` says what the installation
actually *has*. An OUTSTATION at RED recalls but cannot QRF — a village has
people to send looking, not a mounted reaction force. This is what makes
tier matter as much as alert level, and it means the "hornets nest near a
high-influence town vs. long wait in empty terrain" contrast falls out of
data rather than special cases.

**Decision latency is rolled once per alert episode, not per tick.** Stored
on the node as `responseDelay` and cleared whenever the alert level changes
or decays. Re-rolling every tick would have averaged out to the midpoint of
the range and erased the variance that makes response timing feel uncertain.

**Dispatch cooldown is mandatory.** A node sitting at RED for its full
7-minute decay would otherwise launch a fresh wave on every 10s tick — 40+
groups. Cooldowns are per alert level (RED 300s, BLACK 240s).

**Search radius scales from LKP confidence, not from truth.**
`searchSpread × (1 + (1 - confidence) × 2)`. A direct contact report sends
responders to a tight box on the right spot; a third-hand relay sends them
sweeping nearly triple the area around a stale position. The enemy acts on
what it was told.

**Only mobile roles are recalled.** Garrisons hold their buildings and
statics hold their towers. Pulling them out to sweep a treeline would strip
the installation the player may be about to hit, and it looks absurd in
game.

**Responders get their combat AI back.** Roving spawns deliberately
`disableAI` AUTOCOMBAT/TARGET/AUTOTARGET to stay ambient. A recalled or
dispatched element is no longer ambient, so those are re-enabled — without
this a QRF would drive to the LKP and refuse to engage.

**Mounted elements never get `taskHunt`.** LAMBS `taskHunt` starts a search
pattern immediately, which makes a vehicle mill around near its spawn
instead of covering ground. Mounted QRF and mounted recalls get a plain
move-and-engage order so they actually travel — which is also what lets the
player see a response coming down a road and react to it. Foot elements get
`taskHunt` where LAMBS is present.

**`taskHunt`'s position argument is index 4, not 2.** Signature is
`[_group, _radius, _cycle, _area, _pos, _onlyPlayers, ...]`. Passing the LKP
as arg 2 silently sets the cycle time to an array and leaves the search
centred on the group. Called with `spawn`, since it suspends.

**Mounted QRF must use `BIS_fnc_spawnGroup`, not the yielding spawner.**
`fnc_spawnGroupYielding` creates units via `createUnit` and cannot create
vehicles — a MOTORIZED CfgGroups entry lists its transport as a unit slot,
and `createUnit` on a vehicle class does not produce a crewed vehicle. The
single-frame burst is accepted for the same reason `fnc_setupVehiclePatrol`
accepts it: a QRF is a rare player-triggered event, not a per-tick cost.
Foot QRF still uses the yielding spawner.

**QRF groups are themselves C2-stamped.** A QRF can be ambushed and wiped
before it reports, with exactly the same report-timer mechanics as anything
else. Killing the response is legitimate play, not an exception.

**Dispatched QRFs must be deleted at mission cleanup.** They are spawned
outside the presence budget and are not tracked by any zone, so nothing
else would ever clean them up — they would survive into the next mission as
orphaned hostiles.

**Presence `COMBAT` hold is bounded, never a leak.** `fnc_c2Respond` sets
`combatUntil = serverTime + 300` on the owning zone; the presence tick
refuses `ACTIVE → DESPAWNING` while that is in the future. Because the
deadline expires on its own, this can only ever *delay* teardown by a known
window. Stat counter: `combatHeld`.

### F.3 post-playtest fixes (July 2026)

First F.3 playtest (AFO mission sited between an opFor and a bluFor base)
produced "everything in the area got alerted and I lost control." The log
showed four distinct defects, three in C2 and one much older in the faction
layer.

**Decision latency re-rolled on every incoming report, so nodes could never
act.** The gate compared elapsed-time-since-`alertSince` against a stored
delay, and both were reset whenever a fresh signal refreshed the alert. Under
sustained contact the deadline receded faster than the clock advanced. The
log is unambiguous:

```
8:29:46  c2Respond [ALPHA-2] - still deciding (5s of 119s)
8:31:16  c2Respond [ALPHA-2] - still deciding (3s of 90s)
8:32:28  c2Respond [ALPHA-2] - still deciding (75s of 90s)
```

ALPHA-2 went RED at 8:28:20 and did not dispatch until 8:32:48 — four and a
half minutes, because every report pushed the deadline back. Latency is now
an **absolute deadline** (`responseDueAt`) set once per escalation and
cleared only on a genuine alert-level change, never on refresh.

**One firefight produced one full propagation pass per defending group.** At
8:36:29 fifteen groups entered contact within a single second; each ran its
own report timer, each report raised its node and walked four relay hops.
Session totals hit `raised:59` from `reportsSent:24`. That is the "everything
got alerted" the player felt, and it is not a tuning problem — it is missing
deduplication.

Signal grades now carry an `echo` window (CONTACT_REPORT 90s, GUNFIRE_HEARD
60s, EXPLOSION 45s). A repeat of the same signal type at the same node inside
that window still records LKP and still writes to the radio feed, but does
not re-raise the alert or re-walk relays. Real command posts log the second
caller; they don't re-panic. `SILENCE` and the accountability signals are
never echoed — each lost element is separate news. Stat: `signalsEchoed`.

**Deferred SILENCE fired instantly when the check-in deadline had already
passed.** A group that dies shortly *after* its check-in came due scheduled
SILENCE in the past:

```
8:28:46  c2 silence scheduled (backstop) - Alpha 1-2 gone due in -61s
8:28:46  c2 SILENCE - Alpha 1-2 missed its call and is gone
```

Same tick — the exact instant-notification behaviour the deferral exists to
prevent, arriving through a new path. Past-due deadlines now roll forward to
the next check-in cycle at both scheduling sites.

**Failed dispatches retried every tick.** `c2Recall - no mobile groups within
1200m of LKP` repeated for four nodes on every 10s tick for minutes, because
`lastDispatch` was only stamped on success. A partial (90s) backoff is now
applied when nothing could be launched, and the per-tick "still deciding"
line was replaced with a single "will act in Ns" at roll time.

### Design decisions made during F.4 implementation

**Broadcast hooks at `fnc_c2FeedAdd`, not at each call site.** Every C2 line
already flows through that one function, so hooking `fnc_c2IsrBroadcast` at its
tail made all six existing feed writers (`c2Signal` ×4, `c2ResponseQrf`,
`c2ResponseRecall`) player-facing with zero edits, and any future signal type is
covered automatically. Same reasoning as stamping C2 provenance at the presence
dispatcher rather than inside each setup function.

**Coverage is evaluated at READ time, in two places, against the same rule.**
`DSC_c2Feed` records everything the enemy said, including lines the player never
earned. The live chat surface filters in `fnc_c2IsrBroadcast`; the tablet
scrollback filters in `fnc_panelRadio_refresh`. Both call
`fnc_c2IsrCoverage` with the node's position and compare against the entry's
`grade`, so the two surfaces can never disagree about what the player earned.
Writing two filtered buffers instead would have made an omniscient debug view
impossible.

**`LOST` lines are never shown to the player.** A transmission that did not
arrive is exactly the information the player must not have — "did they get a
report out before we killed them?" is the central tension of the report timer.
Surfacing `(not received)` would confirm the player got away with it, which is
the *reward* for good play, not a status readout. They stay in the buffer and
are visible under the tablet's `ALL (DEBUG)` filter.

**Corroborating echo lines are buffer-only.** Fifteen groups in one firefight
generate a lot of "small arms heard (corroborating)". Useful in the RPT, spam
on screen.

**Live chatter is throttled to one line per 2.5 s.** `systemChat` has no rate
limit and a busy network will bury the player's own squad reports and mission
feedback. The dropped lines are still in the scrollback, which is precisely the
problem the Radio Feed page exists to solve.

**Text only — no VO, no radio SFX.** Recorded audio becomes overwhelming the
moment the network gets busy, and text is the only surface that stays usable at
high line rates. `systemChat` specifically (not `hint`, not a custom RscTitles
layer) because it reads as ambient traffic and does not steal focus mid-firefight.

**Telegraphs are diegetic and ungated.** If the player needed a drone to
understand why they were being flanked, then without a drone the system may as
well not exist. Two always-available cues:

- **Illum flare** when a node transitions to RED (confirmed contact). Fires on
  the transition only — a node holding RED through a long firefight must not
  keep launching flares.
- **Vehicle headlights** forced on when a QRF departs. The AI often decides to
  run dark, which silently removes the cue.

Both are night-only (`sunOrMoon > 0.35` aborts) and gated to 3 km of a player.
Fired unconditionally they would light up the whole terrain, since the network
raises alerts across dozens of nodes continuously.

**Night carries no ISR penalty.** Fog and rain shrink the drone's effective
orbit; darkness does not. Radio intercept does not care about light, and
punishing the player's preferred infil window would be backwards for a SOF mod.

**Dispatch notifications are gated at ENHANCED, everything else at BASIC.**
BASIC is the player's own presence (800 m — things they could plausibly notice),
so assaulting a compound surfaces its traffic with no assets at all. QRF and
recall notifications — bearing, element type, ETA — require the drone on
station. That gate is the entire reason keeping the drone alive matters.

**Radio Feed lives on the existing INTEL tab.** Intercepted enemy traffic *is*
intelligence, and that tab was a "not implemented yet" stub. Avoided adding a
sixth tab for the same content.

**The panel shows a coverage header and an alerted-node strip.** A feed that
goes quiet with no explanation is indistinguishable from a feed that is broken,
so the header always states the current tier, why, and the drone's status
(amber when coverage is NONE). The node strip answers "who is hot right now",
which is the actionable counterpart to the transcript.

**Enemy contact markers on the BFT are fixes, not tracking.** Adding hostile
markers is a step toward a wallhack, so each source had to map to a real
capability, and every fix had to decay.

Two sources, both genuine:

| Source | Capability | Gate | TTL |
|---|---|---|---|
| `SIGINT` | **Radio direction finding.** A group that transmits a contact report is a radio emitting from a known position. You cannot see the patrol; you can locate the transmitter. | ENHANCED (drone on station), evaluated **once at the moment of emission** | 240s |
| `VISUAL` | **Own-force contact reports.** Something on the player's side has actually seen it. The most ordinary BFT function there is. | engine `knowsAbout >= 0.5`, 1500m | 90s, refreshed while observed |

What keeps it honest:

- **Fixes are snapshots.** The marker sits where the element *was*. Enemies move; the marker does not.
- **The label states the age** — `ALPHA 1-3 SIGINT 2m`. That is the single most important fact about an enemy marker, and without it the marker implies live tracking.
- **Icon is `o_unknown`**, not a NATO type symbol. A radio fix tells you something transmitted there, not whether it was infantry or a command post. The ambiguity is the honest representation.
- **Alpha fades to 0.35** across the TTL, so staleness is visible before the marker disappears.
- **Silent, unobserved enemies are completely invisible.** Most of the world stays dark.
- VISUAL supersedes SIGINT for the same group (seeing beats inferring), but a stale radio burst cannot overwrite a fresh visual contact.

**The mechanically interesting consequence:** this makes the report timer legible
*spatially*. Kill a patrol before it transmits and it never appears on your map
at all. Let it report and you learn roughly where it was — but the enemy
simultaneously learns where you are. Both sides pay for talking, and the player
can now *see* that trade on the map.

Positions carry no jitter, deliberately. The inaccuracy is **temporal** (the
marker is old) rather than spatial, which reads as honest rather than buggy — a
player looking at a 3-minute-old fix understands why nothing is there.

Cleared at mission cleanup with the rest of C2 state; the fixes reference groups
that are about to be deleted.

### The side-allocation bug (faction layer, older than C2) — ✅ RESOLVED

C2 did not cause this, but C2 surfaced it: every AI death fires real signals,
so a self-destructing garrison flooded the network and made it untestable.

**Root cause was not sides at all — it was `group createUnit`.** That command
leaves the new unit on the side of its `CfgFactionClasses` faction rather than
the group's side, so a Syndikat class (native GUER) spawned into
`createGroup [east]` produced `side _unit == GUER` inside `side _grp == EAST`.
Since AI hostility is evaluated **observer-group-side vs target-unit-side**,
every fighter read its own squadmates as enemy independents and opened fire.

Fixed with `[_unit] joinSilent _group` at all 11 `createUnit` sites.

Three earlier diagnoses each found and fixed a *different* real bug (side
normalization, side-blind microzone projection, and the rating/renegade
threshold), none of which was this one. Full write-up, including the
instrumentation that finally isolated it, is in `.crush/faction-overhaul.md`.

**C2-relevant detail:** `fnc_initC2Network` resolves node sides from the faction
profile, and those sides feed `fnc_c2ResolveNode`'s matching. If node sides and
spawn sides ever disagree again, groups resolve to no node and C2 provenance
drops **silently, with no error**. Role sides are now normalized once in
`fnc_initServer` before the profile is published, which keeps both consistent by
construction.


## Premise

A military patrol doesn't just exist. It belongs to something, it reports
to something, and when it stops reporting, somebody notices.

Today DSC spawns patrols, guards, garrisons and rovers as independent
islands. Killing one has no consequence beyond the local `FiredNear`
combat activation. The C2 Network adds the missing layer: **provenance,
reporting, and consequence**.

The design goal is the same as the rest of the mod — realism over
convenience. If the player wants to avoid a regional response, the answer
is tradecraft (speed, silence, leader targeting, timing), not a difficulty
slider.

## The Unifying Idea

> **ISR is the player's read-access to the enemy C2 network.**

One layer, two consumers. The enemy uses the network to find the player;
the player taps into it to stay ahead. This reframing does a lot of work:

- ISR becomes a *consumer* of C2 data, not a separate parallel system
- "hack the radio station" vs "blow up the radio station" becomes a real
  decision with opposite payoffs
- Intel-as-currency (already on the roadmap) gets a concrete mechanism
- The player's Blue Force Tracker and the enemy's C2 net are the same
  machinery pointed in opposite directions

## Design Decisions (locked)

| Question | Decision |
|---|---|
| Response travel | **Real spawn + real travel** when the responding node is within range. Arma firefights are long; a 5-8 minute QRF transit is a feature, not dead time. |
| Player visibility | **Middle ground** — telegraphs always visible, detail gated behind ISR/SIGINT |
| Persistence | **Reset on mission cleanup** for v1. `heat` field exists in the schema and is written but never read, so persistence can be switched on later without a migration. |
| Scope | **Ambient from the start.** Ambushing a roving patrol 5 km from any mission produces a real response. |
| Factions | **All of them**, including `bluForPartner`. A partner patrol in a contested zone gets a response too. |
| Difficulty | **Emergent** from node tier + distance + influence + faction archetype. No global difficulty knob for v1. |
| Counterplay / ISR depth | **Surface level for v1**, architected for expansion |
| Reaction budget | **QRF may exceed the presence cap.** Consequence must never be silently cancelled by a busy world. See "Reaction Budget" below. |
| Chatter delivery | **Text only.** Real-time subtitles + a scrollable, timestamped **Radio Feed** page on the Commander's Tablet. No audio. |
| `bluForPartner` responses | **Simplified** — partner calls it in, a partner QRF arrives. No full node hierarchy for v1. |
| Check-in cadence | **Per faction archetype** for v1, not per role. |

## Prerequisite: Provenance

**Nothing currently spawned knows who it belongs to.** This is the one
foundational change that blocks everything else, and it is mechanical.

Every spawner stamps its groups:

```sqf
_grp setVariable ["DSC_c2Parent",      _nodeId, true];
_grp setVariable ["DSC_c2Role",        "patrol"];   // patrol|guard|garrison|rover|static
_grp setVariable ["DSC_c2NextCheckIn", serverTime + _interval];
_grp setVariable ["DSC_c2RtbEta",      serverTime + _duration];
_grp setVariable ["DSC_c2Radioman",    _unit];      // designated, antenna backpack
```

Touch points:
- `fnc_setupPatrols`, `fnc_setupGuards`, `fnc_setupGarrison`
- `fnc_setupAnchoredPatrol`, `fnc_setupAnchoredGuard`
- `fnc_setupVehiclePatrol`, `fnc_setupStaticDefenses`
- `fnc_rovingSpawnAir` / `Ground` / `Foot` / `Boat`
- `fnc_populateAO` (mission AO becomes a node — see below)

Rovers resolve their parent from the nearest hotspot, which
`fnc_resolveRovingHotspots` already computes.

## Node Registry (`DSC_c2Nodes`)

Built at init from `DSC_influenceData`, alongside the presence zone
registry. **Alert state lives on the node, not on units** — this is
critical. The presence manager despawns everything when the player
leaves; if alert state lived on units, the war would forget it happened.

```
"id"           <STRING>  location/base id (shared with presence zone id)
"tier"         <STRING>  "COMMAND" | "RELAY" | "OUTSTATION"
"faction"      <STRING>
"side"         <SIDE>
"position"     <ARRAY>
"alert"        <STRING>  "GREEN" | "AMBER" | "RED" | "BLACK"
"alertUntil"   <NUMBER>  decay deadline
"links"        <ARRAY>   [nodeId, ...] precomputed neighbors
"reliability"  <NUMBER>  0..1 chance a message gets through per hop
"latency"      <NUMBER>  seconds from receipt to acting
"reach"        <NUMBER>  max response projection distance (m)
"dispatched"   <ARRAY>   active response records
"lkp"          <HASHMAP> last known player position + time + confidence
"heat"         <NUMBER>  0..1 campaign memory (written, unread in v1)
"infraLinks"   <ARRAY>   infrastructureNode ids this node depends on
```

### Tier capability

| Tier | Source | Reach | Latency | Response ceiling |
|---|---|---|---|---|
| COMMAND | base | 8000 m | 60-120 s | QRF waves, air, mortars |
| RELAY | outpost | 4000 m | 45-90 s | Motorized QRF |
| OUTSTATION | camp, populatedArea | 1500 m | 15-45 s | Foot / technicals |

**Beyond reach, nothing arrives.** This is what makes a CSAT long-range
recce patrol in empty terrain a genuinely isolated fight, and it requires
no special casing.

### Faction archetype

Topology is where faction character lives.

| Archetype | Topology | Link range | Latency | Reliability | Response |
|---|---|---|---|---|---|
| Conventional (`opFor`, `bluFor`) | Hierarchical: outstation → relay → command | 8-15 km | 30-90 s | 0.85-0.95 | Motorized QRF, air, mortars |
| Partner / militia (`opForPartner`, `bluForPartner`) | Hierarchical but sparse | 5-8 km | 90-180 s | 0.6 | Motorized QRF, no air |
| Irregulars (`irregulars`) | **Mesh** between adjacent settlements, word of mouth | 3-5 km | 20-60 s local | 0.35 regional | Locals swarming, foot + civ vehicles |

### Check-in cadence

Per **faction archetype** for v1, not per role. A single number per
archetype keeps the accountability model legible while tuning:

| Archetype | Check-in interval | Grace before `MISSED_CHECKIN` |
|---|---|---|
| Conventional | 5 min | 2 min |
| Partner / militia | 10 min | 5 min |
| Irregulars | 20 min | 10 min |

Per-role cadence (recce every 30 min vs. town guard every 5) is a
deliberate v2 refinement — the field is per-group already
(`DSC_c2NextCheckIn`), so it's a data change, not a rework.

### `bluForPartner` responses (simplified)

Partner forces get **reporting and a response, but no node hierarchy**
in v1. A partner group in contact calls it in, and a partner QRF is
dispatched from the nearest partner-held installation within reach.
No relay hops, no alert-state propagation, no BLACK escalation.

This is enough to satisfy "a partner patrol in a contested zone gets a
real response" without doubling the state machine's surface area. The
node schema is side-agnostic, so promoting partners to full parity later
is a registration change rather than a redesign.


### The emergent contrast (the payoff)

This table produces the behavioral split without special-casing it:

- **Conventional** — *slow to start* (contact report → HQ → decision →
  launch), *fast to arrive* (vehicles, air), *long reach*. You get a
  window to break contact, then a hard, competent, wide-ranging response.
- **Irregular** — *fast to start* (everyone in the settlement heard it),
  *no reach past ~3 km*, but **overwhelming numbers locally**. A firefight
  next to a high-influence armed-civilian town is a hornets' nest within
  90 seconds. Get 4 km out and it's over.

Response scaling reuses the exact gradient already implemented in
`fnc_resolveMicrozoneProjection`:

```
responseStrength = nodeCapability(tier)
                 × influence
                 × distanceFalloff(dist / reach)
                 × archetypeMultiplier
```

C2 applies the same "controlling faction projects outward" math to
*reaction* instead of *spawn chance*.

## Signals

Five sources, ordered by how much the player got away with.

| Signal | Source | Alert | Notes |
|---|---|---|---|
| `CONTACT_REPORT` | Group in contact survives its report timer | RED | The core mechanic |
| `GUNFIRE_HEARD` | Noise event, radius by weapon | AMBER | Unverified — triggers investigation, not QRF |
| `EXPLOSION` | Demo / vehicle brew-up | RED | Big radius, skips the "unverified" step |
| `MISSED_CHECKIN` | Node tick finds group past `nextCheckIn` | AMBER | Catches "killed too fast to report" |
| `OVERDUE_RTB` / `SILENCE` | Group past `rtbEta`, or whole element lost | AMBER → RED | Slow, coarse, inevitable |

### Report timer — the heart of it

When a group enters contact, start a countdown:

```
reportDelay = base(factionArchetype)
            × (leader alive   ? 1.0 : 1.8)
            × (radioman alive ? 1.0 : 2.5)
            × qualityModifier          // ELITE fast, CONSCRIPTS slow
```

Wipe the group before it expires → **no contact report**. But
`MISSED_CHECKIN` still fires 3-10 minutes later.

**Speed and silence buy a window, never immunity.** This is the single
mechanic that makes SOF tradecraft mechanically real rather than
cosmetic, and it gives the designated radioman a reason to exist as a
priority target.

### Noise draw

Explosions are deliberately the loudest signal — it is the main lever
separating a quiet AFO posture from a loud DA posture.

| Event | Radius | Alert |
|---|---|---|
| Suppressed shot | 75 m | — |
| Unsuppressed small arms | 800 m | AMBER |
| Explosion / demolition | 2500 m | **RED** |
| Vehicle destruction / secondary | 3500 m | RED |
| Installation destroyed | regional | **BLACK** |

Implementation note: one server-side `EntityKilled` mission EH plus a
`Fired` EH on the player (suppressor check via muzzle attachment) — not
per-unit event handlers.

## Propagation

```
signal raised at position P by group G
   ↓ resolve owning node via G's DSC_c2Parent (fallback: nearest hotspot)
   ↓ roll reliability — failure = message lost / garbled / dismissed
   ↓ node latency delay
   ↓ node alert raises; LKP recorded with confidence
   ↓ relay to linked nodes — each hop costs latency + reliability roll
   ↓ LKP confidence decays per hop and over time
   ↓ node evaluates response ladder against reach + capability
```

**LKP, not omniscience.** The node knows where the *report* came from, not
where the player is. Responses move to the LKP and search outward from
there. Confidence decay means a stale report produces a wider, lazier,
less accurate search. This is nearly free (hashmap math) and is where most
of the immersion payoff lives.

## Response Ladder

| Alert | Node behavior | Player-visible effect |
|---|---|---|
| **GREEN** | Normal ambient | — |
| **AMBER** (unverified) | Wake local garrison, recall nearby patrols toward LKP, dispatch one recon element | Patrols stop wandering and start moving somewhere |
| **RED** (confirmed) | Dispatch QRF, converge rovers in range, mortars if in range, static defenses alert | Vehicles inbound, illum at night |
| **BLACK** (installation attacked / sustained) | Multiple QRF waves, air search, adjacent nodes → AMBER, regional density bump | The area becomes untenable — extract |

Decay: BLACK → RED → AMBER → GREEN on 5-20 minute timers.

### Reuse

The response primitives mostly exist:

| Need | Existing function |
|---|---|
| Recall / converge patrols | `fnc_convergePatrols` |
| QRF road transit from base | `fnc_buildRoadRoute` |
| Vehicle response group | `fnc_setupVehiclePatrol` (combat interrupt already wired) |
| Air search | `fnc_rovingSpawnAir` patterns |
| Frame-safe spawning | `fnc_spawnGroupYielding` + `uiSleep` |
| Reaction loop shape | `fnc_bftQrfReact` (mirror it for AI) |

### Real spawn vs. abstract

Per the locked decision: if the responding node is **within reach**, the
QRF spawns *at the node* and travels for real. Arma firefights are long
— a 5-8 minute transit is tension, not dead time, especially with
LAMBS_Danger driving the contact.

Beyond reach: **no response**. Not a delayed one, not a small one. This
is what makes operating far from installations meaningfully safer.

### Reaction Budget

C2 responses draw from a **separate budget that may exceed the presence
manager's 150u/40v cap**. The reasoning is that a QRF is *earned
consequence* — if the player kicks off a major engagement and a busy
ambient world silently cancels the response, the entire system fails at
the exact moment it should matter most.

**Combat substitution.** This is not purely a cost — it can be a net
saving. When a C2 response is active in an area, the QRF *is* the world
density. Ambient presence has no narrative job to do while a firefight
and a converging reaction force are the main event, so:

- Presence zones inside an active response radius throttle ambient
  spawning (skip new activations, let existing zones ride)
- The reserved `COMBAT` zone state is the natural mechanism — a zone in
  COMBAT suppresses despawn for its existing entities but stops
  *acquiring* new ambient population
- Net effect: units shift from ambient-scattered to
  concentrated-and-relevant, at similar or lower total cost

This keeps the frame budget roughly flat during the moments the player
cares about most. Worth instrumenting in F.3 to confirm the substitution
actually nets out — if it doesn't, the presence cap gets tuned down
during active responses rather than capping the QRF.

Reaction spawns still obey the frame-spike convention
(`fnc_spawnGroupYielding`, `uiSleep` between creates). Exceeding the cap
is about *total standing units*, never about spawning them in one frame.

### LAMBS soft dependency

LAMBS_Danger.fsm is not currently wired (`ao_populous_overhaul.md` item
5) but is planned and is in the playtest loadout. `lambs_wp_fnc_taskHunt`
is a dramatically better "search toward last known position" behavior
than a SAD waypoint. Design for optional detection:

```sqf
if (isClass (configFile >> "CfgPatches" >> "lambs_wp")) then {
    [_grp, _lkpPos, _radius] call lambs_wp_fnc_taskHunt;
} else {
    [[_grp], _lkpPos, _cfg] call DSC_core_fnc_convergePatrols;
};
```

## ISR Module

The player-side counterpart. Same machinery, opposite direction.

### Concept

An ISR operator is an information layer that reads actual world state and
reports to the player with fidelity determined by **coverage**.

| Coverage source | Provides |
|---|---|
| Persistent UAV (exists) | Live contact picture within its orbit |
| Partner-force reports | `bluForPartner` nodes report what they observe |
| SIGINT (hacked infra / captured radios) | **Read access to enemy node alert states and dispatch table** |
| Satellite pass windows | Periodic wide-area snapshot, low fidelity |

### Balance

The force multiplier is **decision quality, not target data**. When the
player is in contact, ISR reports *what is responding to them*:

> "Be advised, QRF dispatched from the north. Four vehicles. ETA six mikes."

Knowing a response was launched, its bearing and its ETA lets a good
player break contact, reposition, or set an ambush. That is a genuine
advantage against a matched or larger force, earned through good
decisions — and it is not a wallhack.

Degraders keep it honest: night, weather, terrain masking, UAV must be
alive and on-station, and a request cadence rather than a constant feed.

### Middle-ground visibility

- **Always visible** — telegraphs. A radio burst cue when a group reports.
  Headlights leaving a base at night. Illum going up. Cause and effect
  must be legible or the system may as well not exist.
- **ISR-gated** — chatter transcripts, node alert states on the tablet,
  dispatch ETAs, LKP confidence, Radio Feed history.

### Delivery — text only, two surfaces

No audio. Recorded VO / radio SFX would get overwhelming fast once the
network is busy, and text scales to any volume of traffic.

**1. Real-time subtitles.** Chatter appears as it happens, using the
subtitle/`systemChat` surface so it reads as ambient radio traffic
without stealing focus during a firefight.

**2. Radio Feed page (Commander's Tablet).** A scrollable, timestamped
history of everything the player's ISR coverage has picked up. Solves
the core problem with real-time-only chatter: during a contact the
player is busy and will miss lines that mattered.

```
[14:32:07] (INTERCEPT) KILO-2  → ZULU  "Contact, small arms, grid 034-112"
[14:32:41] (INTERCEPT) ZULU    → KILO-2 "Say again your location"
[14:33:15] (ISR)       QRF dispatched — Ostatny outpost, 4 vehicles, bearing 340
[14:38:02] (INTERCEPT) ZULU    → HQ    "Kilo-2 not responding, sending a section"
```

Feed entry schema (ring buffer, capped ~200 entries, cleared on mission
cleanup with the rest of C2 state):

```
"time"      <NUMBER>  serverTime
"stamp"     <STRING>  formatted HH:MM:SS
"source"    <STRING>  "INTERCEPT" | "ISR" | "PARTNER" | "COMMAND"
"from"/"to" <STRING>  callsigns
"text"      <STRING>
"nodeId"    <STRING>  for map cross-reference
"grade"     <STRING>  fidelity tier the player earned this line at
```

Callsigns should be generated per node at registry build time and stay
stable for the session, so the player can learn "Zulu is the outpost
north of me" organically.

Fits the tablet's existing panel architecture directly (`fnc_switchPanel`
already dispatches mission/supports/bft/squad/intel — Radio Feed is one
more tab).

## Counterplay (surface level for v1)

| Vector | Effect |
|---|---|
| **Kill the radioman / leader first** | Extends the report window (1.8× / 2.5×). Radioman visually identifiable via antenna backpack. |
| **Destroy comms infrastructure** | Severs `links` for a region — isolates nodes for N minutes. Makes the existing `infrastructureNode` microzone gameplay-relevant. |
| **Hack comms infrastructure** | Grants SIGINT read on that region. No alert. |
| **Jamming** | UAV/ECM support asset — temporary reliability crush over an area. |
| **Timing** | Hit during a check-in gap. |
| **Body concealment** | Delays `SILENCE` escalation. |

### Infrastructure archetypes

Data-driven, matching the existing archetype convention
(`fnc_getEntityArchetypes`, `fnc_getObjectArchetypes`). New:
`fnc_getC2InfraArchetypes`.

| Archetype | Quiet disable | Destroy |
|---|---|---|
| `RADIO_RELAY` | Links severed ~10 min, AMBER at next check-in | Links severed long, **BLACK regionally** |
| `CELL_TOWER` | Node reliability −40% | Reliability −70%, RED |
| `POWER_SUBSTATION` | Lights out, nearby populatedArea irregular overlay chance up | Same + **BLACK**, settlement becomes an armed-civilian nightmare |

The power substation case is the clearest expression of the AFO-vs-loud
tradeoff: if you are operating in an area long term, you do *not* want to
knock out the grid, because the response is disproportionate to the
tactical gain.

Street lights can be killed cheaply via `nearestObjects` on lamp classes
plus `switchLight "OFF"`.

## Integration Notes

- **Presence `COMBAT` state** — `fnc_initPresenceManager`'s zone schema
  already reserves `"COMBAT"` and `combatUntil` but never uses them. C2
  alert state is the natural driver: a RED/BLACK node forces its presence
  zone into COMBAT, which should suppress despawn while the fight is live.
- **Mission AO becomes a node.** `fnc_generateMission` has a vestigial,
  commented-out `qrfEnabled` block (line ~209). Rather than reviving it,
  register the mission AO as a C2 node so QRF is an *emergent output of
  the network* instead of a bespoke mission feature.
- **Node LOD** — nodes within ~5 km of the player tick at full fidelity;
  distant nodes tick lazily (60 s) and resolve responses abstractly with
  no spawns, so campaign state advances at near-zero cost.
- **Separate reaction budget** — a QRF must never be starved by the
  presence budget cap. Reaction spawns still obey the frame-spike
  convention (`fnc_spawnGroupYielding`, `uiSleep` between creates).
- **Tick phasing** — presence ticks at 8 s, roving at 8 s offset 4 s. C2
  should tick ~10 s at a third phase offset to avoid stacking spikes.
- **Mission cleanup** resets all node alert to GREEN, clears dispatch
  records and `heat`.

## Proposed Phasing

| Sprint | Content | Acceptance |
|---|---|---|
| **F.1 — Provenance + registry** (SHIPPED) | `DSC_c2Nodes` built at init, links precomputed, provenance stamped at the presence dispatcher + rovers + mission AO, node tick with alert state + decay. Log-only, no behavior change. | Node registry populates; debug markers show alert states; zero gameplay delta |
| **F.2 — Signals + propagation** (SHIPPED) | Report timer, noise events, check-in / RTB / SILENCE accountability, relay hops, LKP with confidence decay, radio feed buffer. Still no responses. | Killing a patrol quietly vs. loudly produces visibly different node alert traces in the log |
| **F.3 — Response ladder** (SHIPPED) | Recall/converge, QRF dispatch with real travel, tier×alert capability gating, decision latency, cooldown, confidence-scaled search. LAMBS soft dependency. | A firefight near an outpost produces a QRF that arrives and fights |
| **F.4 — ISR + player-facing** | Telegraphs, real-time subtitle chatter, tablet **Radio Feed** page + C2/ISR panel, UAV/SIGINT coverage model | Player can tell *why* a response is inbound, and can scroll back to find the line they missed mid-firefight |
| **F.5 — Counterplay** | Radioman targeting, infra archetypes (sever/hack/destroy), jamming, campaign `heat` persistence | Hack vs. destroy produce measurably different regional outcomes |

F.1 and F.2 are deliberately log-only, mirroring how the Presence
Manager was scaffolded in its Sprint 1 — get the state machine and the
data flow verifiable in isolation before anything spawns.

### Validating F.1 in game

F.1 raises no alerts on its own, so validation is registry + roster
correctness plus a manual exercise of the alert ladder.

Set `DEBUG_MODE_FULL` in `addons/main/script_mod.hpp` for node markers
and the per-minute stats systemChat, then check:

1. **Registry** — RPT shows `c2Network - Registered N nodes` with a
   sensible command/relay/outstation split, and
   `Link topology built (... M orphan nodes)`. A high orphan count means
   link ranges need tuning.
2. **Rosters fill** — the `c2 STATS` line's `rostered` count should climb
   as presence zones activate around the player and fall as they despawn.
   `stamped` is cumulative and should only ever increase.
3. **No civilians on rosters** — rostered count tracks armed groups only;
   a town full of civilians should not inflate it.
4. **Alert ladder + decay**, from the debug console:
   ```sqf
   private _id = (keys DSC_c2Nodes) select 0;
   [_id, "RED", "manual test"] call DSC_core_fnc_c2RaiseAlert;
   ```
   Expect an `ALERT [CALLSIGN] GREEN -> RED` line, the node's map marker
   turning red, a `decay RED -> AMBER` line ~7 minutes later, then
   `AMBER -> GREEN` ~5 minutes after that.
5. **Ratchet behavior** — raising AMBER on a node already at RED should
   log `alert absorbed`, not downgrade it.
6. **Cleanup reset** — finishing or aborting a mission should log
   `C2 network reset (N nodes were above GREEN)`.

### Validating F.2 in game

F.2 still dispatches nothing, so all output is log + alert state + feed.
The headline test is that **identical kills produce different consequences
depending on how you do them.**

New per-minute log lines:
```
c2 SIGNALS - raised:N lostAtIntake:N reportsSent:N suppressed:N missedCheckIn:N
```

**Test 1 — the report timer (the core mechanic).**
Find an isolated conventional patrol near an opFor outpost.
- *Ambush fast, kill all 5 within ~13s* → expect
  `c2 REPORT SUPPRESSED - <grp> wiped after Ns before transmitting`,
  and the node stays GREEN. Then wait: `c2 SILENCE` should fire on the next
  tick (element destroyed), and the node goes RED anyway. Speed bought a
  delay, not immunity.
- *Engage slowly, let them fight back for 30s* → expect
  `c2 REPORT SENT - <grp> transmitted CONTACT_REPORT after Ns (grid XXX)`
  and the node goes RED immediately.

**Test 2 — radioman targeting.**
Same patrol. Shoot the unit whose `DSC_c2Radioman` you can identify (dump
it from the console, or look for the antenna backpack) *first*, then the
rest at leisure. The effective deadline multiplies 2.5×; a 13s report
becomes ~33s, and 58s if the leader also drops. Confirm the elapsed time in
the `REPORT SENT`/`SUPPRESSED` line reflects it.

**Test 3 — suppressor economics.**
Fire an unsuppressed rifle in empty terrain 600 m from a town → the town
goes AMBER (`GUNFIRE_HEARD`). Repeat suppressed → nothing at all.
Then detonate any explosive ~2 km from a base → RED (`EXPLOSION`), and
because RED relays, its linked relay/command node should go AMBER.

**Test 4 — relay chain and reliability.**
Trigger a `CONTACT_REPORT` at a camp/town (OUTSTATION) that has links. Watch
for `Relaying:` feed lines and `relay to [CALLSIGN] failed reliability roll`.
Against irregulars (0.35 reliability) most relays should fail — that is
correct, not a bug. Against conventional (0.90) most should succeed.

**Test 5 — the feed.**
After an engagement, dump the conversation:
```sqf
{ systemChat format ["[%1] (%2) %3 -> %4  %5",
    _x get "stamp", _x get "source", _x get "from", _x get "to", _x get "text"]
} forEach (DSC_c2Feed select [(count DSC_c2Feed) - 10, 10]);
```
Expect a legible sequence including `(LOST)` entries for messages that
never arrived. This is the raw material F.4's tablet page will render.

**Test 6 — installation escalation.**
Attack an outpost's garrison directly. Expect
`transmitted INSTALLATION_ATTACKED` and the node going **BLACK**, with
neighbours pulled to RED rather than AMBER.

**Tuning signal.** `reportsSent` vs `reportsSuppressed` is the number to
watch. If suppressed is near zero the window is too tight to reward good
play; if it dominates, the network never reacts. Roughly 1:2 to 1:4
suppressed:sent across a session is the target band.

### Validating F.3 in game

F.3 is the first sprint where the network *does* something, so validation is
behavioural rather than log-reading.

**Test 1 — recall at AMBER (the common case).**
Fire an unsuppressed shot ~600 m from an opFor town, then withdraw and
observe. Expect `c2 ALERT ... AMBER (GUNFIRE_HEARD)`, then after the
outstation's 15-45 s decision delay:
```
c2 RECALL [KILO] - N groups searching r=Xm (conf=0.70)
c2Recall - search driver: LAMBS taskHunt
```
Patrols that were wandering should converge on where you fired. Nothing
spawns — this rung is free.

**Test 2 — QRF at RED, and the reach gate.**
Ambush a patrol *within* ~4 km of an outpost and let them report:
```
c2 QRF DISPATCHED [CHARLIE] - 5 mounted units toward LKP 2100m out (bearing 340 from target)
```
Then watch them actually drive to you. Repeat >4 km from any node and expect
`LKP Xm beyond reach Ym, no response` — nothing arrives at all, which is the
reward for operating deep.

**Test 3 — tier capability.**
Trigger RED at a camp or town (OUTSTATION) rather than an outpost. Expect
recall but **no** QRF, or `OUTSTATION at RED has no capable response` if it
has nothing mobile to recall either.

**Test 4 — confidence widening the search.**
Compare `r=Xm` in the RECALL line between a direct contact report
(confidence 1.0) and a two-hop relay (~0.56). The second should be visibly
wider — responders sweeping a vague area instead of walking onto you.

**Test 5 — cooldown.**
Stay in contact near an outpost for several minutes. QRF should dispatch
once per cooldown window (RED = 300 s), not once per tick.

**Test 6 — combat hold.**
Trigger a QRF then move outside the zone's despawn radius. Presence stats
should show `combatHeld` rather than tearing the zone down, and the QRF
should still find you.

**Test 7 — kill the QRF.**
Ambush the response itself. It is C2-stamped, so expect a normal
`REPORT SUPPRESSED`/`REPORT SENT` from the QRF group and
`N dispatched element(s) no longer active` next tick.

### Validating F.4 in game

F.4 is presentation, so validation is mostly "look at the screen" — but the
coverage gate has real logic behind it and is worth exercising deliberately.

**Test 1 — BASIC coverage with no assets.**
Walk into a compound and open fire. Intercepted chatter should appear in
`systemChat` within a couple of seconds (`[12:04:11] ALPHA 1-2 >> WHISKEY:
Contact, small arms, grid ...`). Open the tablet (Ctrl+Shift+T) → **INTEL** tab:
the header should read `COVERAGE: BASIC (local)` and the transcript should show
the same lines. This proves the system is legible with no drone.

**Test 2 — coverage drop.**
Move more than ~800 m from any alerted node with no drone up. The header should
go amber and read `COVERAGE: NONE (no coverage)`, and the list should show
`-- no intercepts at current coverage (N lines withheld) --`. The withheld count
proves lines are still being buffered, just not earned.

**Test 3 — ENHANCED and the dispatch payoff.**
With the ISR drone alive and on station, trigger a QRF (loud contact near an
outpost). Expect an `ISR` line in cyan:
`QRF dispatched from WHISKEY - mounted element, bearing 214, approx 4 min out`.
Header should read `COVERAGE: ENHANCED (ISR drone)`. This is the line the whole
sprint exists to deliver — confirm the bearing points at the node and the ETA is
roughly right.

**Test 4 — the drone matters.**
Shoot down or let the drone die, then trigger another QRF. The `COMMAND` and
`INTERCEPT` lines may still appear if you are close, but the `ISR` dispatch
notification must NOT. Header should read `drone lost`.

**Test 5 — LOST stays hidden.**
Wipe a group before its report timer expires. The RPT will log
`REPORT SUPPRESSED`, and a `LOST` entry goes into the buffer — but it must not
appear in the feed under `EARNED`. Toggle the filter to `ALL (DEBUG)` and it
should appear, dimmed. If a `LOST` line is ever visible under `EARNED`, the
report-timer mechanic is broken.

**Test 6 — telegraphs at night.**
Run a night mission. When a node hits RED, an illum flare should go up over it
(within 3 km). When a QRF departs, its vehicles should have headlights on. Both
should be absent in daylight.

**Test 7 — throttle under load.**
Start a large firefight near a populated area. Chatter should stay readable at
roughly one line per 2.5 s and must not bury squad/mission systemChat. The
tablet scrollback should contain the lines that were dropped from the live
surface — that gap is exactly what the page exists for.

**Test 8 — node strip.**
With two or more nodes alerted, the strip under the list should read
`ALERTED: WHISKEY RED (1.4km)   CHARLIE-2 AMBER (3.1km)`. All quiet should read
green.

**Test 9 — SIGINT contact markers (BFT).**
With the drone alive, let an enemy group transmit a contact report
(`REPORT SENT` in the RPT). Open the BFT tab: a red `o_unknown` marker should
appear at the transmitter's position labelled e.g. `Alpha 1-3 SIGINT 5s`, and
the age should climb as you watch. Now **wipe a group before its timer expires**
(`REPORT SUPPRESSED`) — that group must NOT produce a marker. That contrast is
the whole mechanic.

**Test 10 — SIGINT requires the drone.**
Kill the drone, then let another group transmit. No new SIGINT marker should
appear. Existing ones continue ageing out normally.

**Test 11 — VISUAL contact markers.**
Walk up on an enemy patrol until your squad has eyes on. A red marker should
appear tagged `SEEN` and stay accurate while observed. Break line of sight and
move away: it should freeze in place, fade over ~90s, and vanish. It must not
follow the patrol.

**Test 12 — markers respect the MINE filter and mission cleanup.**
Toggle the BFT filter to `MINE` — hostile contacts should disappear (that view
is the player's own assets). Finish or abort the mission — all contact markers
should clear.

## Open Questions

All v1 scoping questions are resolved (see "Design Decisions"). Callsign
generation was settled during F.1 (per-faction phonetic pool, stable for
the session, numeric suffix on wrap). Remaining items are
implementation-time calls, not design blockers:

1. **Subtitle vs. `systemChat`** for real-time chatter — subtitle reads
   better as radio traffic but competes with ACE and other mods for the
   surface. May need a config toggle.
2. **Combat-substitution measurement** — F.3 must instrument whether
   throttling ambient presence during an active response actually nets
   out flat. If it doesn't, tune the presence cap down during responses
   rather than capping the QRF.
3. **`heat` persistence** — the schema field exists and is written but
   unread in v1. Turning it on later interacts with
   `fnc_updateInfluence`, since both model "this region has been fought
   over." Needs a deliberate pass so they don't double-count.
4. **Link range tuning** — F.1 ships conventional 12 km / partner 6.5 km
   / irregular 4 km. The orphan-node count in the init log is the signal
   for whether these are right on a given map.
