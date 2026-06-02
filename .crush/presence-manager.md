# Presence Manager — DSC World Simulation

*Last updated: June 2026 — Sprints 1-8 shipped, Sprint A/B/C next*

## Overview

The Presence Manager is DSC's world simulation layer. It populates the area
around the player with civilians, military patrols, base garrisons, static
defenses, and faction overlays — and tears them down when the player moves
away. The goal is "the world feels alive" without paying full simulation cost
for the entire map.

It is **separate from the mission system**. Missions populate their own AO
through `fnc_populateAO`; the presence manager populates everything else
(towns, bases, outposts, camps). The two systems coordinate via a mission AO
arbitration rule: when a mission's AO overlaps a presence zone, the military
layer in that zone suspends to avoid double-population.

## Current State (Sprints 1-8 complete)

### Architecture

```
fnc_initPresenceManager (server)
├── Build zone registry from DSC_influenceData
│     • bases / outposts / camps / populatedAreas → presence zones
│     • Player main base excluded (handled by fnc_initBases at init)
│
├── Spawn worker scope
│     • Drains DSC_presenceActivateQueue + DSC_presenceDespawnQueue
│     • One zone per cycle, uiSleep between
│     • Heartbeat to DSC_presenceWorkerHeartbeat
│
└── Main tick loop (20s)
      ├── Sample player speed (avg + max)
      ├── Mission AO snapshot (DSC_currentMission)
      ├── Compute current budget usage from all live zones
      ├── Per-zone state machine evaluation
      ├── Candidate gathering for DORMANT → ACTIVATING
      ├── Budget gate (closest zones win)
      ├── Periodic STATS report (every 60s)
      └── Worker health check
```

### State Machine

```
                              ┌───────┐
                              │DORMANT│ ←──────────────┐
                              └───┬───┘                │
                          player  │                    │  worker
                          in range│                    │  done +
                              ▼                        │  no entities
                          ┌────────────┐               │
                          │ACTIVATING  ├───────────────┘
                          │(in queue)  │
                          └──┬──┬──────┘
            player exits     │  │  worker spawns
            BEFORE worker    │  │  units, sets
            (no entities)    │  │  zone.processed
                             │  ▼
                             │  ┌─────────┐
                             │  │ ACTIVE  │
                             │  └────┬────┘
                             │       │ player exits
                             │       │ despawn radius
                             │       ▼
                             │  ┌────────────┐
                             └─→│DESPAWNING  │
                                │(grace 60s) │
                                └─────┬──────┘
                                      │ grace expires +
                                      │ entities cleared
                                      ▼
                                  DORMANT
```

Special transitions:
- **Mission AO overlap**: military zones force-suspend to `DESPAWNING`
- **Activating + player escapes**: if worker already spawned entities, route to `DESPAWNING` instead of orphaning units (was a real bug)
- **Distance hysteresis**: `actR` to activate, `depR` to despawn — non-overlapping bands

### Zone Types and Defaults

| Type | Activation | Despawn | Spawn content |
|---|---|---|---|
| `populatedArea` | 800m | 1200m | Civilians (3-12, influence-scaled) + optional military overlay (Sprint 5) + contested skirmish opposing patrol (Sprint 8) |
| `outpost` | 1200m | 2000m | Static defenders (towers, marksmen, statics) + 1-2 small patrols + 0-1 parked vehicle |
| `base` | 1500m | 2500m | Static defenders + 2-3 patrols + 1-2 mortars + 2 parked vehicles |
| `camp` | 700m | 1100m | 1 patrol, optional 1-2 guards if structures exist, no vehicles |

### Subsystems

| Function | Role |
|---|---|
| `fnc_initPresenceManager` | Build zone registry, spawn worker + tick |
| `fnc_activatePresenceZone` | Type-dispatched populate (one big switch — refactor target) |
| `fnc_despawnPresenceZone` | Tear down all tracked entities |
| `fnc_setupCivilians` | Wandering civilian peds, CARELESS waypoints |
| `fnc_setupStaticDefenses` | Towers, statics, marksmen lookouts |
| `fnc_setupMortarEmplacement` | 1-2 mortars with crew, faction crew lookup |
| `fnc_setupContestedSkirmish` | West-side opposing patrol on contested zones |
| `fnc_filterPatrolGroups` | Restrict patrol pool to recce/fireteam (no full squads) |
| `fnc_spawnGroupYielding` | Drop-in `BIS_fnc_spawnGroup` with `uiSleep` between unit creates |
| `fnc_presenceLogTimings` | Per-zone activation timing → `DSC_presenceTimings` + cumulative totals |

### Globals Exposed

```sqf
DSC_presenceZones          // hashmap zoneId -> zone hashmap
DSC_presenceActivateQueue  // FIFO of pending activations
DSC_presenceDespawnQueue   // FIFO of pending despawns
DSC_presenceBudgetUnits    // default 100
DSC_presenceBudgetVehicles // default 30
DSC_presenceTimings        // rolling 50 activation timings
DSC_presenceTimingTotals   // ms per step across session
DSC_presenceStats          // session counters (dormantToActivating, etc.)
DSC_presenceLatencies      // rolling 100 latency rows
DSC_presenceWorkerHeartbeat // diag_tickTime, watchdog
```

### Side Diplomacy Lock

At init: `east setFriend [independent, 1]` and reverse. This makes
`opForPartner` (east) and `irregulars` (independent) cooperate by default
so they don't kill each other on sight. Mission cleanup may reset this
temporarily — that's a known issue documented in the mission system.

### Mission AO Arbitration

When `DSC_currentMission` is set, every tick computes a 600m + 300m buffer
zone around the mission. Military presence zones (base/outpost/camp) whose
center falls inside force-despawn with no grace. Civilians stay (their
density already drops in opFor-controlled towns). Lifts automatically when
the mission ends.

## Performance Findings (June 2026 instrumentation pass)

We ran a 15-minute helicopter loop at sustained 60-73 m/s with full
metrics. Key numbers:

| Metric | Value | Interpretation |
|---|---|---|
| Activations | 41 | Healthy zone churn |
| Completion rate | 98-100% | Worker can keep up |
| Budget skip rate | 5% | Cap is **not** the bottleneck |
| Avg latency | 20.06s | Essentially one tick exactly |
| Max latency | 22.8s | One tick + change |
| **Abandoned (spawned but player blew past)** | **9/41 = 22%** | **One in four zones is wasted work** |

The tick interval dominates latency. The worker is fast (1-5s per zone),
but the player waits up to 20s for the next tick to promote a zone to
ACTIVE — by which time a helicopter has crossed 1400m. With a despawn
radius of 1200m on populated areas, the player exits before the zone is
even ready to be played.

### Root cause

```
Zone activates at:       800m (populatedArea)
Despawns at:             1200m
Useful engagement band:  400m
Helicopter at 70 m/s:    5.7 seconds inside band
Tick interval:           20 seconds
```

The player exits the band 14 seconds before the next tick can promote the
zone. So spawn happens, then immediately schedules despawn on the next tick.

### Performance tuning options (deferred to Sprint B)

| Option | Description | Pros | Cons |
|---|---|---|---|
| A. Cut tick interval | 20s → 8s | Single change. No behavior model change. | More state-machine work. |
| B. Speed-scaled radius | Bubble grows at speed (foot 1×, air 4×) | Foot/ground unchanged. | More simultaneous zones at speed → budget pressure. |
| C. Asymmetric hysteresis | Expand despawn radius significantly | Spawned zones survive long enough. | More units linger behind player. |
| D. Pause-instead-of-delete | Antistasi-style: disableSimulation on grace, delete after longer second grace | Re-entry is free, no `createUnit` cost | More dormant entities in memory |

We are not picking one yet. The forthcoming refactor (Sprint A below)
moves these knobs from global constants to per-handler properties, so we
can pick mix-and-match values per zone type instead of one-size-fits-all.

## Roadmap Forward

The Presence Manager will expand from "populate named locations" into
"populate everything around the player with variety." The grand vision:

- Civilian-occupied compounds in cities (garrison-style, in addition to
  wandering peds)
- Rural compounds away from named locations — farms, isolated buildings,
  abandoned structures
- Factory/warehouse/logistics sites with factory workers + light military
  guard depending on influence
- Police/military checkpoints on roads (in/near towns)
- Roving civilian vehicles
- Roving military motorized/mechanized patrols
- Static military emplacements on roads outside towns

This roughly doubles or triples the zone count (66 → 300-700 estimated)
and shrinks the average zone (3-5 units instead of 5-15). The current
architecture — single monolithic `fnc_activatePresenceZone` with a big
switch on zone type — will not scale gracefully to this many handlers.

## Next Sprint Plan — Handler Registry Refactor + Perf

The plan is **A → B → C** in order, before any new content.

### Sprint A: Handler Registry Refactor (mechanical, no new behavior)

**Goal**: Move each zone type's populate + despawn logic into its own
handler function, registered with the manager at init. The manager loop
becomes type-agnostic; it knows only about state transitions and queue
plumbing.

**Files**:
- `addons/core/functions/presence/handlers/` (new directory)
  - `fnc_handlerPopulatedArea.sqf` — current populated-area branch
  - `fnc_handlerBase.sqf` — current base preset
  - `fnc_handlerOutpost.sqf` — current outpost preset
  - `fnc_handlerCamp.sqf` — current camp preset
- `fnc_registerPresenceHandler.sqf` (new) — adds an entry to
  `DSC_presenceHandlers` hashmap, keyed by type
- `fnc_activatePresenceZone.sqf` — becomes a thin dispatcher: look up
  handler by `_zone get "type"`, call its `populate` slot
- `fnc_despawnPresenceZone.sqf` — same, dispatches to handler's `despawn`
  slot (or falls back to default delete loop)
- `fnc_initPresenceManager.sqf` — registers builtin handlers at startup

**Handler contract** (every handler is a hashmap):
```sqf
createHashMapFromArray [
    ["type",            "populatedArea"],       // matches zone "type"
    ["activateRadius",  800],                   // override per type
    ["despawnRadius",   1200],
    ["despawnGrace",    75],
    ["budgetUnits",     8],                     // cost estimate
    ["budgetVehicles",  0],
    ["populate",        DSC_core_fnc_handlerPopulatedArea],
    ["despawn",         {}],                    // optional, defaults to entity-list delete
    ["paused",          false]                  // for Sprint C
]
```

**Acceptance**: Same test route (15-minute helicopter loop) produces
identical `DSC_presenceStats` numbers as today (or trivially close — small
ordering differences acceptable). No new zone types, no new behavior.

### Sprint B: Performance Tuning (now per-type instead of global)

With handlers in place, radii and grace periods are per-type config, not
global constants. Pick the right knob for each handler:

| Handler | Likely setting |
|---|---|
| `populatedArea` | Tick 8s + despawn 2400m (Options A + C). Civilians are cheap. |
| `outpost` | Tick 8s + despawn 3000m. Static defenders only. |
| `base` | Tick 20s, despawn 4000m. Heaviest spawn, infrequent. |
| `camp` | Tick 8s, despawn 1800m. Smallest preset. |

But really, the **tick interval is global** — it's the main loop. So Sprint
B is two parts:
1. Drop the manager tick to 8s (probably)
2. Tune each handler's `despawnRadius` + `activateRadius` independently
3. Re-run the helicopter route and read the metrics

Decide A+C mix vs. predictive lookahead based on the new numbers.

### Sprint C: Pause-Instead-of-Delete (Antistasi-style)

Add a strategy variant on the handler:

```sqf
["lifecycle", "pause"]   // disableSimulation on grace, delete after longer second grace
["lifecycle", "delete"]  // current behavior — delete on grace
```

Two-stage despawn for `pause` lifecycle:
- **Stage 1** (grace start): `{_x enableSimulation false; _x disableAI "ALL"} forEach units`. Zone state: `PAUSED` (new sub-state).
- **Stage 2** (extended grace, e.g. +120s): full delete. Zone state: `DORMANT`.
- **Re-entry during pause**: `enableSimulation true; enableAI "ALL"`. No `createUnit` cost, instant.

Roll out:
1. Populated areas first (lowest risk — civilians are passive, no combat AI)
2. Camps + outposts (medium risk — patrols can resume mid-stride)
3. Bases last (highest risk — static defenders + mortars + vehicle gunners)

**Test goal**: Player exits zone at 70 m/s, returns 30 seconds later. Units
should still be present, no spawn lag, no abandoned counter increment.

### After A/B/C → New Content (separate features)

**Sprint D — Structure-archetype data feature** (deferred, owned by user)

User has an idea for using structure archetype data stored as a function
to tag locations throughout the map. This will feed new zone types:
- Rural compounds
- Factories/warehouses
- Police/military checkpoints
- Cultural/religious sites

Once the data layer is in place, each becomes one handler registration
under the refactored architecture. No edits to the manager loop required.

**Sprint E — Roving Entities Subsystem** (separate from zones)

Some presence is fundamentally not zone-based:
- Civilian vehicles wandering between towns
- Military motorized/mechanized patrols on roads
- Boats along coastline

These need their own loop, their own budget, their own activation logic
(probably "spawn near a road within Nkm of the player, drive, despawn at
distance"). Built as a sibling system to the zone manager, not a new zone
type.

## Diagnostics and Tuning Tools

### Periodic STATS report (every 60s)

```
DSC: ===== PRESENCE STATS (12 min) =====
DSC: stats — activations=40 completed=38 timedOut=1 abandoned=9 (completion=95%)
DSC: stats — budget approved=40 skipped=2 (skipRate=5%)
DSC: stats — latency avg=20063ms max=22778ms (samples=38)
```

### Per-zone activation timing

```
DSC: presence timing [base/loc_94] total=4664ms u=25 v=5 |
  staticDefenses=2107 patrols=1915 mortars=270 vehicles=359 curator=13
```

### Per-zone latency

```
DSC: presence latency [loc_56/populatedArea] 20035ms (2 ticks)
  dist=1048m speed=68m/s
```

### Debug map markers

Each zone has an ellipse marker colored by state:
- DORMANT: grey (alpha 0.25)
- ACTIVATING: yellow
- ACTIVE: green
- DESPAWNING: orange
- COMBAT: red (reserved, not yet used)

Marker text shows `ZoneName [STATE]`.

### Live in-game commands

```sqf
copyToClipboard str (missionNamespace getVariable "DSC_presenceStats");
copyToClipboard str (missionNamespace getVariable "DSC_presenceLatencies");
copyToClipboard str (missionNamespace getVariable "DSC_presenceTimingTotals");
```

## Files

| File | Purpose |
|---|---|
| `addons/core/functions/presence/fnc_initPresenceManager.sqf` | Main loop, state machine, worker, instrumentation |
| `addons/core/functions/presence/fnc_activatePresenceZone.sqf` | Type-dispatched populate (will become thin dispatcher in Sprint A) |
| `addons/core/functions/presence/fnc_despawnPresenceZone.sqf` | Default entity teardown |
| `addons/core/functions/presence/fnc_presenceLogTimings.sqf` | Per-call timing aggregation |
| `addons/core/functions/ai/fnc_setupCivilians.sqf` | Civilian peds with CARELESS waypoints |
| `addons/core/functions/ai/fnc_setupStaticDefenses.sqf` | Tower + bunker defenders, marksman-preferred pool |
| `addons/core/functions/ai/fnc_setupMortarEmplacement.sqf` | Mortar tube + crew |
| `addons/core/functions/ai/fnc_setupContestedSkirmish.sqf` | West-side opposing patrol for contested zones |
| `addons/core/functions/ai/fnc_setupPatrols.sqf` | Group spawn + `taskPatrol`, supports `spawnAngle` |
| `addons/core/functions/ai/fnc_filterPatrolGroups.sqf` | Recce/fireteam filter |
| `addons/core/functions/faction/fnc_spawnGroupYielding.sqf` | Drop-in BIS_fnc_spawnGroup with yields |
| `.crush/PRESENCE_MANAGER.md` | Research/notes from Claude Web — kept for context |

## Sprints Shipped (chronological)

1. **Sprint 1** — Zone registry + tick + state machine (log-only)
2. **Sprint 2** — opFor outposts + bases activate with static defenders, mortars, parked vehicles
3. **Sprint 3** — opFor/contested camps activate with light patrol
4. **Sprint 4** — Civilians always spawn in populated areas (influence-scaled density floor)
5. **Sprint 5** — Military overlay on populated zones (single patrol from controlling side)
6. **Sprint 6** — Mission AO arbitration + global budget cap with closest-first
7. **Sprint 7** — BluFor partner ambient + bluFor bases/outposts open up
8. **Sprint 8** — Contested-zone dual-faction co-spawn (skirmishes)

## Sprints Up Next

- **Sprint A** — Handler registry refactor
- **Sprint B** — Per-handler performance tuning (tick + radii + grace)
- **Sprint C** — Pause-instead-of-delete lifecycle variant
- **Sprint D** *(separate feature)* — Structure archetype data → new zone types
- **Sprint E** *(separate subsystem)* — Roving entities (civilian vehicles, mil patrols, boats)
