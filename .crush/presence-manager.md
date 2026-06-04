# Presence Manager — DSC World Simulation

*Last updated: June 2026 — Sprints 1-8 + A/B/C/D + Stutter Pass shipped, real-mission shakedown next, Sprint E after*

## Overview

The Presence Manager is DSC's world simulation layer. It populates the area
around the player with civilians, military patrols, base garrisons, static
defenses, and faction overlays — and tears them down (or freezes them) when
the player moves away. The goal is "the world feels alive" without paying
full simulation cost for the entire map.

It is **separate from the mission system**. Missions populate their own AO
through `fnc_populateAO`; the presence manager populates everything else
(towns, bases, outposts, camps). The two systems coordinate via a mission AO
arbitration rule: when a mission's AO overlaps a presence zone, the military
layer in that zone suspends to avoid double-population.

## Current State

### Architecture

```
fnc_initPresenceManager (server)
├── Build zone registry from DSC_influenceData
│     • bases / outposts / camps / populatedAreas → presence zones
│     • Player main base excluded (handled by fnc_initBases at init)
│
├── Register builtin handlers (Sprint A)
│     • DSC_presenceHandlers hashmap keyed by zone type
│     • Each handler: actR / depR / grace / budgetU/V / populate fn /
│       lifecycle (delete|pause) / pauseGrace
│     • Built-ins: base, outpost, camp, populatedArea
│
├── Spawn worker scope
│     • Drains DSC_presenceActivateQueue + DSC_presenceDespawnQueue
│     • One zone per cycle, uiSleep between
│     • Heartbeat to DSC_presenceWorkerHeartbeat
│
└── Main tick loop (8s)
      ├── Sample player speed (avg + max)
      ├── Mission AO snapshot (DSC_currentMission)
      ├── Compute current budget usage (counts PAUSED at full cost)
      ├── Per-zone state machine evaluation (reads radii/grace from handler)
      ├── Candidate gathering for DORMANT → ACTIVATING
      ├── Budget gate (closest zones win; estimates from handler config)
      ├── Periodic STATS report (every 60s; includes pause/resume metrics)
      └── Worker health check
```

The activate dispatcher (`fnc_activatePresenceZone`) looks up
`DSC_presenceHandlers[zone.type].populate` and calls it. Type-specific
spawn logic lives in handler files (`fnc_presenceHandler{Base,Outpost,
Camp,PopulatedArea}.sqf`), all of which delegate to either
`fnc_presenceActivateMilitary` (shared role-resolve + static defenses +
patrols + mortars + vehicles pipeline) or, for populated areas, an inline
civilians-plus-overlay sequence.

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
                             │  │ ACTIVE  │←──────────┐
                             │  └────┬────┘           │
                             │       │ player exits   │ player re-enters
                             │       │ despawn radius │ actR (instant
                             │       │                │  unfreeze)
                             │       ▼                │
                             │  lifecycle==pause?     │
                             │   yes ┴── no          │
                             │       │   │           │
                             │       ▼   ▼           │
                             │  ┌──────┐ ┌──────────┐│
                             │  │PAUSED├─┤DESPAWNING││
                             │  │(freeze)│(grace)   ││
                             │  └──┬───┘ └────┬─────┘│
                             │     │          │      │
                             │     │ pauseGrace      │
                             │     │ expired         │
                             │     └────► queues actual delete
                             │                │
                             └────────────────▼ grace expires +
                                              │ entities cleared
                                              ▼
                                          DORMANT
```

Special transitions:
- **Mission AO overlap**: military zones (and PAUSED zones) force-suspend
  to `DESPAWNING` and actually delete, bypassing pause lifecycle
- **Activating + player escapes**: if worker already spawned entities,
  route to `DESPAWNING` instead of orphaning units
- **Distance hysteresis**: `actR` to activate, `depR` to despawn — wide
  non-overlapping bands tuned per type (see table below)
- **Pause re-entry**: instant unfreeze inline (no worker spawn cost, no
  `DORMANT → ACTIVATING` increment)

### Zone Types and Defaults (post-Sprint B/C)

| Type | actR | depR | grace | budgetU/V | lifecycle | pauseGrace | Spawn content |
|---|---|---|---|---|---|---|---|
| `base` | 1500 | 4000 | 90s | 20 / 3 | delete | (180s configured, not used) | Static defenders + 2-3 patrols + 1-2 mortars + 2 parked vehicles |
| `outpost` | 1200 | 3000 | 75s | 8 / 1 | pause | 75s | Static defenders (towers, marksmen, statics) + 1-2 small patrols + 0-1 parked vehicle |
| `camp` | 900 | 1800 | 60s | 4 / 1 | pause | 45s | 1 patrol if controlled; armed-civilian patrol if `controlledBy=neutral` |
| `populatedArea` | 1500 | 2400 | 60s | 8 / 0 | pause | 60s | Civilians (3-12, influence-scaled) + optional military overlay + contested skirmish opposing patrol + irregular overlay on neutral zones |

Tick interval: 8s (global). Budget cap: 150 units / 40 vehicles.

**Speed-aware pause skip** (June 2026 post-flight-test tuning) — when the
player's average tick speed exceeds 35 m/s (~125 km/h), the `ACTIVE → exit`
decision forces `lifecycle=delete` regardless of registered config. This
prevents helicopter sprints from filling the budget cap with PAUSED zones
the player will never return to. Stat counter: `pauseSkippedFast`.

**Budget excludes DESPAWNING** (June 2026 second pass) — condemned zones
are no longer counted against the unit/vehicle cap. Previously a wave of
zones in DESPAWNING (waiting for the worker to drain them) artificially
exhausted the budget and forced new candidates to skip. Counting only
`ACTIVE + ACTIVATING + PAUSED` aligns the cap with zones that actually
consume resources for more than a worker cycle.

**Note on testing with `setAccTime`**: don't tune from logs captured at
accelerated sim time. The presence manager mixes real-time (`uiSleep`,
`diag_tickTime`, worker yields) with sim-time (`sleep`, `serverTime`,
`velocity`). Under 4× sim time: ticks fire 4× faster, grace counters
expire 4× faster, but per-unit spawn cost stays at real-time, making
the worker look stalled and latencies look catastrophic. Always validate
perf changes at 1× speed.

### Subsystems

| Function | Role |
|---|---|
| `fnc_initPresenceManager` | Build zone registry, register handlers, spawn worker + tick |
| `fnc_registerPresenceHandler` | Adds a handler config to `DSC_presenceHandlers` |
| `fnc_activatePresenceZone` | Dispatcher — looks up `DSC_presenceHandlers[type].populate` |
| `fnc_despawnPresenceZone` | Dispatcher + default teardown (delete vehicles → units → groups) |
| `fnc_presenceHandlerBase` / `Outpost` / `Camp` / `PopulatedArea` | Per-type populate logic; military handlers delegate to `fnc_presenceActivateMilitary` |
| `fnc_presenceActivateMilitary` | Shared role-resolve + static defenses + patrols + mortars + vehicles for base/outpost/camp |
| `fnc_setupCivilians` | Wandering civilian peds, CARELESS waypoints |
| `fnc_setupStaticDefenses` | Towers, statics, marksmen lookouts |
| `fnc_setupMortarEmplacement` | 1-2 mortars with crew, faction crew lookup |
| `fnc_setupContestedSkirmish` | West-side opposing patrol on contested zones |
| `fnc_resolveIrregularOverlay` | East-side armed-civilian patrol for neutral zones (populated areas + camps) |
| `fnc_filterPatrolGroups` | Restrict patrol pool to recce/fireteam (no full squads) |
| `fnc_spawnGroupYielding` | Drop-in `BIS_fnc_spawnGroup` with `uiSleep` between unit creates |
| `fnc_presenceLogTimings` | Per-zone activation timing → `DSC_presenceTimings` + cumulative totals |

### Globals Exposed

```sqf
DSC_presenceZones          // hashmap zoneId -> zone hashmap
DSC_presenceHandlers       // hashmap type -> handler config (Sprint A)
DSC_presenceActivateQueue  // FIFO of pending activations
DSC_presenceDespawnQueue   // FIFO of pending despawns
DSC_presenceBudgetUnits    // 150 (post-Sprint B)
DSC_presenceBudgetVehicles // 40  (post-Sprint B)
DSC_presenceTimings        // rolling 50 activation timings
DSC_presenceTimingTotals   // ms per step across session
DSC_presenceStats          // session counters — includes pausedTotal,
                           //   resumedFromPause, pauseExpired (Sprint C)
DSC_presenceLatencies      // rolling 100 latency rows
DSC_presenceWorkerHeartbeat // diag_tickTime, watchdog
```

### Side Diplomacy Lock

At init: `east setFriend [independent, 1]` and reverse. This makes
`opForPartner` (east) and `irregulars` (independent) cooperate by default
so they don't kill each other on sight. Mission cleanup may reset this
temporarily — that's a known issue documented in the mission system.

The irregular overlay (`fnc_resolveIrregularOverlay`) spawns its patrols
on **east side** regardless of the source faction's natural side. This
gives clean hostility-to-player (west↔east hostile by default) and
aligns the armed civilians with the rest of the east bloc.

### Mission AO Arbitration

When `DSC_currentMission` is set, every tick computes a 600m + 300m buffer
zone around the mission. Military presence zones (base/outpost/camp) whose
center falls inside force-despawn with no grace. PAUSED zones inside the
buffer also force-delete (bypassing pause lifecycle — the mission needs
the area clear). Civilians stay (their density already drops in
opFor-controlled towns). Lifts automatically when the mission ends.

## Performance — Pre-Tuning Baseline (June 2026, historical)

Before Sprint B, we ran a 15-minute helicopter loop at sustained 60-73 m/s
with full metrics. Key numbers:

| Metric | Pre-tuning | Post Sprint B | Post Sprint C | Post Stutter Pass (June '26) |
|---|---|---|---|---|
| Activations (9-min loop) | 41 | 24 | 9 | 21 |
| Completion rate | 98-100% | 100% | 100% | 100% |
| Budget skip rate | 5% | 0% | 0% | **0%** (was 60% before fix) |
| Avg latency | 20.06s | 8.7s | 8.0s | 15s (heavier per-zone work post-Sprint D) |
| **Abandoned (spawned but player blew past)** | **22%** | **0%** | **0%** | **0%** |
| Active duration (avg) | ~25s | ~50-80s | ~60-100s | 40-180s |
| Pause/resume saves | n/a | n/a | 3 of 7 paused zones resumed (43%) | 0 (speed-skip routes sprints to delete) |
| Active zones during sprint (cruise) | n/a | n/a | 1-3 | **4-6** |
| Peak budget usage | n/a | n/a | 163u/150u (over) | 143u/150u (under) |

### Original root cause (now resolved)

```
Zone activates at:       800m (populatedArea, pre-B)
Despawns at:             1200m
Useful engagement band:  400m
Helicopter at 70 m/s:    5.7 seconds inside band
Tick interval:           20 seconds
```

The player exited the band 14 seconds before the next tick could promote
the zone. Sprint B's asymmetric hysteresis (despawn radii 2-3× larger
than activate radii) + 8s tick eliminated the abandonment problem.
Sprint C's pause lifecycle made re-entry instant.

### Tuning options surveyed (Sprint B planning, historical)

| Option | Description | Status |
|---|---|---|
| A. Cut tick interval | 20s → 8s | Shipped |
| B. Speed-scaled radius | Bubble grows at speed | Not needed |
| C. Asymmetric hysteresis | Wider despawn than activate | Shipped |
| D. Pause-instead-of-delete | Freeze on grace, delete after extended grace | Shipped (Sprint C) |

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
and shrinks the average zone (3-5 units instead of 5-15). The Sprint A
handler registry refactor is what makes adding these zone types a
one-handler registration each, rather than a switch-statement bloat.

## Sprint Change Log — Handler Registry + Perf + Pause Lifecycle

A → B → C shipped in order; tangent followed before Sprint D.

### Sprint A: Handler Registry Refactor (SHIPPED June 2026)

**Goal**: Move each zone type's populate + despawn logic into its own
handler function, registered with the manager at init. The manager loop
becomes type-agnostic; it knows only about state transitions and queue
plumbing.

**Files (as shipped)**:
- `fnc_registerPresenceHandler.sqf` — adds entries to `DSC_presenceHandlers`
- `fnc_presenceHandlerPopulatedArea.sqf` — civilians + military overlay + skirmish (verbatim from pre-refactor)
- `fnc_presenceHandlerBase.sqf` — base preset, delegates to military helper
- `fnc_presenceHandlerOutpost.sqf` — outpost preset, delegates to military helper
- `fnc_presenceHandlerCamp.sqf` — camp preset, delegates to military helper
- `fnc_presenceActivateMilitary.sqf` — shared military activation body (role resolve + foot groups + static defenses + patrols + mortars + vehicles)
- `fnc_activatePresenceZone.sqf` — thin dispatcher: reads `DSC_presenceHandlers[zone.type].populate`, calls it
- `fnc_despawnPresenceZone.sqf` — dispatcher + default teardown; runs `handler.despawn` if non-empty
- `fnc_initPresenceManager.sqf` — registers four builtin handlers at startup; tick loop reads radii/grace/budget from registry via `_fnc_handlerNum`

**Handler contract** (as registered):
```sqf
createHashMapFromArray [
    ["type",            "populatedArea"],       // matches zone "type"
    ["activateRadius",  2000],                  // seeded to today's value
    ["despawnRadius",   2000],
    ["despawnGrace",    45],
    ["budgetUnits",     8],                     // pre-spawn estimate (budget gate)
    ["budgetVehicles",  0],
    ["populate",        DSC_core_fnc_presenceHandlerPopulatedArea],
    ["despawn",         {}],                    // empty -> default teardown
    ["paused",          false]                  // reserved for Sprint C
]
```

Seeded values per type (preserve pre-refactor behavior):

| Type | actR | depR | grace | budgetU | budgetV |
|---|---|---|---|---|---|
| base | 800 | 800 | 45 | 20 | 3 |
| outpost | 1000 | 1000 | 45 | 8 | 1 |
| camp | 1200 | 1200 | 45 | 4 | 0 |
| populatedArea | 2000 | 2000 | 45 | 8 | 0 |

(The doc's earlier "Zone Types and Defaults" table did not match the
shipped code radii — code is authoritative. Sprint B will retune.)

### Sprint B: Performance Tuning (SHIPPED June 2026)

Per-handler hysteresis bands + tick drop + budget bump, plus an
active-duration log on `ACTIVE → DESPAWNING` so we can see how long
zones stay playable.

**Changes**:

1. **Tick interval**: 20s → 8s (single global). Drives the state machine
   and the per-zone "approx ticks to ACTIVE" latency counter. Worker
   cycle (1.5s sleep per activate) easily keeps up.
2. **Per-handler radii + grace** (asymmetric hysteresis is the main lever
   for the abandoned-zone problem):

   | Type | actR | depR | grace | band | budgetU | budgetV |
   |---|---|---|---|---|---|---|
   | base | 1500 | 4000 | 90 | 2500m | 20 | 3 |
   | outpost | 1200 | 3000 | 75 | 1800m | 8 | 1 |
   | camp | 900 | 1800 | 60 | 900m | 4 | 1 |
   | populatedArea | 1500 | 2400 | 60 | 900m | 8 | 0 |

3. **Budget cap**: 100u/30v → **150u/40v** to leave headroom for the
   wider despawn radii (more zones simultaneously in DESPAWNING).
4. **New instrumentation**: `DSC: presence active-duration [id/type] Ns
   (player left, dist=Xm)` on every `ACTIVE → DESPAWNING` transition.
   Also covers the mission-AO forced-suspend path. Read it to see if a
   zone was playable for a real engagement window or got steamrolled.

**Acceptance criteria** (15-min helicopter loop at sustained speed):
- Abandoned rate < 8% (was 22% pre-Sprint A / 16% post-Sprint A)
- Completion rate ≥ 95%
- Avg latency ~8-10s (one tick under new interval)
- Budget skip rate ≤ 20%

**Out of scope** (deferred to later sprints): speed-scaled radii,
predictive lookahead, pause-instead-of-delete (Sprint C).

### Sprint C: Pause-Instead-of-Delete (SHIPPED June 2026)

Adds `PAUSED` as a first-class state. Pause-lifecycle zones freeze
simulation + AI on grace start instead of deleting. Re-entry within
`pauseGrace` wakes the zone instantly with zero `createUnit` cost.
Beyond `pauseGrace`, the zone falls through to actual deletion.

**Handler config additions**:
```sqf
["lifecycle",  "pause"]   // freeze on grace, delete after pauseGrace
["lifecycle",  "delete"]  // current behavior — delete on grace (default)
["pauseGrace", 120]       // seconds in PAUSED before actual delete
```

**State machine additions**:
- `ACTIVE → PAUSED` (pause-lifecycle, player exits depR): freeze inline,
  set `graceUntil = now + pauseGrace`
- `PAUSED → ACTIVE` (player re-enters actR): unfreeze inline, instant
- `PAUSED → DESPAWNING` (pauseGrace expired OR mission AO overlap):
  queue actual delete
- Budget tracking now counts PAUSED entities at full cost

**Rollout (as shipped)**:

| Type | lifecycle | pauseGrace |
|---|---|---|
| populatedArea | pause | 120s |
| camp | pause | 120s |
| outpost | pause | 150s |
| base | delete | 180s (config present, lifecycle still delete — flip later if rollout stays clean) |

`pauseGrace=180` is registered on `base` so flipping to `pause` later is
a one-field edit, not a redesign.

**New stats counters**: `pausedTotal`, `resumedFromPause`, `pauseExpired`.

**New log lines**:
- `presence active-duration [...] (paused, dist=Xm, Nu/Mv frozen)` — on `ACTIVE → PAUSED`
- `presence resumed [...] (paused for Ns, dist=Xm, Nu/Mv unfrozen)` — on `PAUSED → ACTIVE`
- `presence pause-expired [...] (deleting Nu/Mv)` — on `PAUSED → DESPAWNING` (grace expired)
- `presence pause-forced [...] (mission AO, deleting)` — on `PAUSED → DESPAWNING` (mission overlap)
- Periodic STATS report adds: `paused=N resumed=M expired=K (resumeRate=%, save=M spawns avoided)`

**Per-tick summary** now reads:
`active:N activating:N paused:N despawning:N dormant:N sus:N (of total)`

**Acceptance criteria** (15-min loop, mix of helicopter sprints + lingering):
- `resumeRate` ≥ 30% (depends on flight pattern — show that re-entry is non-zero)
- No abandoned-rate regression (still 0% from Sprint B)
- No completion-rate regression (still 100%)
- Average latency unchanged (~8-10s for fresh spawns)
- Paused zones survive `pauseGrace` and visibly resume on re-entry (verify in log)

**Out of scope**: paused-budget discount (counted at full for safety),
auto-flip base to pause (manual after testing).

### After A/B/C → New Content (separate features)

**Sprint D — Functional location tagging + civilian flavor (SHIPPED June 2026)**

Two-parter laying the data foundation for future variety:

**Part 1 — Scanner enrichment** (`fnc_scanLocations.sqf`).
The functional categories already produced by `fnc_getStructureTypes`
(residential / commercial / industrial / agricultural / medical / religious /
infrastructure / port / airport / law_enforcement) are now distilled into
character tags on each location:

| Tag | Trigger |
|---|---|
| `industrial_zone` | industrial count ≥ 2 |
| `industrial_hub`  | industrial count ≥ 5 |
| `commercial_hub`  | commercial count ≥ 3 |
| `agricultural_zone` | agricultural count ≥ 2 |
| `medical_zone`    | any medical structure |
| `religious_site`  | any religious structure |
| `port_zone`       | any port structure |
| `airport_civilian`| any civilian airport structure |
| `law_enforcement_present` | any law_enforcement structure |
| `infrastructure_node` | infrastructure ≥ 1 AND buildingCount < 10 |
| `residential_zone` | residential ≥ 8 AND primary = residential |
| `mixed_use`       | 3+ categories each with ≥ 2 structures |

Plus a new `primaryFunction` field on the location hashmap: the dominant
category iff it represents ≥ 40% of the categorized structures AND has at
least 2 entries. Empty string when no clear dominant.

**Part 2 — Civilian flavor by location character.** The presence manager
now propagates `tags`, `primaryFunction`, and `functionalProfile` from the
location into every zone hashmap (all four zone types — keeps the data
available for future handlers). The `populatedArea` handler runs the new
helper `fnc_resolveCivilianMix` to build a weighted resolver-key mix and
passes it as `classMix` to `fnc_setupCivilians`.

Populated areas (cities/towns/settlements) intentionally lean heavy on
casual civilians with specialty types only sprinkled in (~5-15% per tag).
A town with factories *occasionally* shows a worker — it doesn't read as
a worker convention. Future dedicated zone types (industrial sites, ports,
farms) will reuse the same helper but pass denser specialty tag sets,
naturally producing specialty-heavy mixes:

```sqf
// Industrial town example (specialty sprinkle on 20-baseline)
[["civilian", 20], ["civilian_worker", 3]]
// Commercial hub with church (mild suit lean)
[["civilian", 20], ["civilian_suit", 3]]
// Dedicated industrial site (planned Sprint E-ish handler) — denser tags
[["civilian", 20], ["civilian_worker", 12]]  // ~38% workers
```

Each civilian rolls a resolver key by weight, then resolves to a concrete
classname via `fnc_resolveEntityClass`. New resolver key
`civilian_worker` was added (keywords: worker, construction, utility,
laborer, hunter, fisher, farmer) alongside existing `civilian`,
`civilian_suit`, `civilian_labcoat`.

Backwards compatible — when no tags trigger flavor, the mix degrades to
just `[["civilian", 4]]` and behavior matches pre-D. Resolver itself falls
back to a random civilian if no keyword matches the faction's manPool, so
limited-civilian mods still work.

**Files**:
- `addons/core/functions/locations/fnc_scanLocations.sqf` — character tag + primaryFunction derivation
- `addons/core/functions/presence/fnc_initPresenceManager.sqf` — zone hashmap carries `tags`/`primaryFunction`/`functionalProfile`
- `addons/core/functions/ai/fnc_resolveCivilianMix.sqf` — tag → resolver-key weighted mix (new)
- `addons/core/functions/ai/fnc_setupCivilians.sqf` — accepts `classMix` config
- `addons/core/functions/faction/fnc_resolveEntityClass.sqf` — `civilian_worker` resolver
- `addons/core/functions/presence/fnc_presenceHandlerPopulatedArea.sqf` — calls resolveCivilianMix, passes classMix

**Future hooks for the same data layer**: missions can filter location
candidates by character tag (e.g. "supply cache at an industrial site"),
new handler types can register against `industrial_zone` or `port_zone` for
specialized population, and the resolver can grow new keys
(`civilian_dockworker`, `civilian_youth`, etc.) without touching the
scanner.

**Part 3 — Indoor garrison layer (populated areas).** On top of the
wandering civilian pass, the populatedArea handler now places multiple
*indoor* clusters of armed units using `fnc_setupGarrison` + a new
wrapper:

- `fnc_setupLightMilitaryGarrison` — armed garrison cluster from the
  controlling side's foot-infantry pool. Uses combat activation
  (FiredNear EH) and the new `garrison_light` skill profile (softer than
  `cqb_baseline` — slow reactions, wide spread). Tuned to **mission
  density** (caps + satellites match `fnc_populateAO`):

  | sizeTier | bldg count | anchors | mainCap / sideCap | satellite range | sat radius |
  |---|---|---|---|---|---|
  | isolated   | <5    | 1     | 4 / 2 | 1-2 | 50m |
  | settlement | 5-14  | 1-2   | 4 / 2 | 1-3 | 50m |
  | town       | 15-49 | 1-2   | 4 / 2 | 1-3 | 50m |
  | city       | 50+   | 1-3   | 4 / 2 | 1-3 | 50m |

  Each cluster = 1 anchor (up to 4 units) + 1-3 satellites within 50m
  (up to 2 units each) → **6-10 units per occupied compound**.

The handler runs **two independent garrison passes** per zone:

1. **Controlling-faction garrison** — gated by `controlledBy ∈ {opFor,
   bluFor, contested}` AND `influence ≥ 0.3`. The handler decides total
   cluster count by sizeTier (isolated 1, settlement/town 1-2, city
   1-3), then per-cluster engagement roll (70% across all three controls)
   determines how many actually spawn. Contested side is re-rolled per
   call — opFor *or* bluFor partner.

2. **Irregular garrison** — runs on *any* populated zone regardless of
   control or influence. Represents the armed civilian populace, so it
   shouldn't depend on faction control. Always 1 cluster, force-east
   side for player hostility (same trick used by the wandering
   irregular overlay + contested skirmish). Sources from `irregulars`
   role, falls back to `opForPartner`.

   | Control | Irregular garrison chance |
   |---|---|
   | neutral   | 40% |
   | contested | 40% |
   | opFor     | 20% |
   | bluFor    | 25% |

   Higher on neutral/contested (the populace is the only armed
   presence); lower on opFor/bluFor (controlling garrison already
   provides combat encounters there). opFor towns can stack both
   garrison passes — rare, but creates dense compound encounters.

A civilian indoor garrison variant (`fnc_setupGarrisonCivilians`) was
also built but is currently **disabled** — wandering civilians already
carry the "alive" feel without the extra budget cost. The wrapper is
kept as a dormant utility, easy to re-enable from the handler if
revisited later.

**Camp / base / outpost zones**: no indoor garrison. Camps already have
their light patrol or irregular overlay; bases and outposts are
deterrent territory players are meant to *avoid*, not clear room by
room.

**Files added/changed**:
- `addons/core/functions/ai/fnc_setupGarrison.sqf` — `unitPoolOverride`
  config branch (skips CfgGroups walk when supplied)
- `addons/core/functions/ai/fnc_setupGarrisonCivilians.sqf` — new
  wrapper, classMix-driven pool, CARELESS post-processing (currently
  unused)
- `addons/core/functions/ai/fnc_setupLightMilitaryGarrison.sqf` — new
  wrapper, combat-activation, `garrison_light` skill profile,
  mission-density satellite/cap settings
- `addons/core/functions/ai/fnc_getSkillProfile.sqf` — added
  `garrison_light` profile
- `addons/core/functions/presence/fnc_initPresenceManager.sqf` — zone
  hashmap now carries `mainStructures` / `sideStructures` (anchor
  selection needs them)
- `addons/core/functions/presence/fnc_presenceHandlerPopulatedArea.sqf`
  — controlling-faction garrison + always-on irregular garrison pass
- `addons/core/functions/presence/fnc_presenceHandlerCamp.sqf` —
  unchanged content (civilian-garrison variant trialed and removed)

**Budget impact**: With mission-density tuning, an active opFor town can
add up to ~12-20 indoor units (controlling cluster + irregular cluster)
on top of wandering civilians and the existing military overlay. The
combined per-cluster + irregular spawn rolls keep most activations
lighter, but worst-case populated zones now sit around 25-35u (vs ~10u
pre-Sprint-D). Sprint B's 150u global budget cap absorbs this; if perf
shows pressure, the first lever is the controlling-faction per-cluster
engagement roll (currently 0.70 across all three controls).

### Sprint D.5 — Microzones (PLANNED)

The named-location / military-tier passes covered by Sprints 1-D handle
~40-66 major zones on Altis. Between them — and especially across rural
stretches a few km from any town — `fnc_initInfluence` produces a fifth
bucket the presence manager currently ignores: `_missionSites`. Every
scanned location that isn't a NameCity/NameVillage/NameCityCapital and
isn't military lands here:

- Orphan-recovery clusters from `fnc_scanLocations` Stage 3.5
  (flood-filled building groups beyond 500m of any named location,
  named by grid reference)
- Small `NameLocal` pockets and isolated farms
- Industrial-shed clusters (`Land_i_Shed_Ind_F` complexes etc.)

All of these already carry Sprint D's `tags`, `primaryFunction`, and
`functionalProfile` data. D.5 turns them into a new family of zone
types registered against the existing handler registry — same tick
loop, same worker, same state machine, same budget gate, same mission
AO arbitration. No second loop, no second worker.

**Design principles**

- Reuse Sprint A's registry verbatim. Every new microzone type is a
  one-file handler + `registerPresenceHandler` call. Tick loop stays
  type-agnostic.
- Small radii + `lifecycle=delete`. Pausing 200 microzones would torch
  the 150u budget cap; they're so cheap that re-spawning on re-entry
  is cheaper than carrying frozen entities.
- Density caps at registration time so dense rural strips don't
  generate 30 overlapping microzones at one stretch of map.
- Per-tick activation throttle so a fast traverse never pays more than
  a few microzone spawns in a single tick.

**Microzone defaults**

| Property | Major zones (today) | Microzones |
|---|---|---|
| actR / depR | 900-1500 / 1800-4000 | 400-700 / 800-1200 |
| Grace | 60-90s | 30s |
| Lifecycle | pause | **delete** |
| budgetU/V | 4-20 / 0-3 | 2-6 / 0-1 |
| Estimated count (Altis) | ~40-66 | 100-300 |
| Spawn content | civilians + garrison + patrols + statics | one small flavor pass |

**Initial zone types** (tag-driven dispatch from `_missionSites`)

| Type | Trigger | Civilian content | Military projection multiplier |
|---|---|---|---|
| `industrialSite` | `industrial_zone` ∈ tags OR `primaryFunction=industrial` | 1-3 `civilian_worker` | 1.0× |
| `agriculturalSite` | `agricultural_zone` OR `primaryFunction=agricultural` | 1-2 `civilian_worker`, CARELESS | 0.5× (low-value, militaries rarely garrison farms) |
| `infrastructureNode` | `infrastructure_node` ∈ tags | usually none | **2.0×** (high-value, real militaries protect comms/fuel/power) |
| `isolatedCompound` | orphan cluster ≥2 buildings, no functional tag | none | 1.0× (the random-encounter sweet spot) |

`roadsideCheckpoint` is deferred to D.6+ (needs a road-detection pass
in the scanner).

**Controller projection model**

A controlling faction with a base/outpost/camp nearby should *project*
outward into surrounding compounds — patrols and guard clusters in the
ring around each installation. This produces a realistic gradient:
dense military presence near installations, fading into civilian /
contested territory, with irregulars dominating the gaps between
controllers.

At microzone activation, the handler calls a shared helper:

```sqf
private _projection = [_zone] call DSC_core_fnc_resolveMicrozoneProjection;
// returns hashmap:
//   "controllerSide"     <SIDE>    east/west/sideUnknown (no controller in range)
//   "controllerFaction"  <STRING>  cfg faction id of controlling installation
//   "guardChance"        <NUMBER>  0..1, includes type multiplier
//   "patrolChance"       <NUMBER>  0..1, includes type multiplier
//   "guardSize"          <ARRAY>   [min,max] units for guard cluster
//   "patrolSize"         <ARRAY>   [min,max] units for patrol
//   "strength"           <NUMBER>  raw projection strength, for debug
```

Resolution:

1. **Find controller** — nearest base/outpost/camp within
   `projectionRange = 3000m` (read from zone's recorded distance to
   the influence map's installations, no spatial scan needed at tick
   time)
2. **Projection strength** —
   `controller.influence × (1 - dist/projectionRange)` clamped to 0..1
3. **Guard chance** —
   `baseGuard × strength × typeMultiplier` where `baseGuard = 0.55`
4. **Patrol chance** —
   `basePatrol × strength × typeMultiplier` where `basePatrol = 0.45`
5. **Fallback when no controller in range** — original civilian /
   irregular rolls apply (25-30% irregular fireteam on opFor-leaning
   `_missionSites`, lone armed civilian on `infrastructureNode`)

**Worked examples** (with `baseGuard=0.55`, `basePatrol=0.45`):

| Setup | Strength | Guard chance | Patrol chance |
|---|---|---|---|
| `isolatedCompound` 800m from opFor base, influence 1.0 | 0.73 | 40% | 33% |
| `industrialSite` 1500m from contested outpost, influence 0.5 | 0.25 | 14% | 11% |
| `infrastructureNode` 1200m from opFor outpost, influence 0.8 | 0.48 | **53%** (2× type mult) | **43%** |
| `agriculturalSite` 2500m from opFor base, influence 1.0 | 0.17 | 5% (0.5× mult) | 4% |
| Any microzone with no controller in 3km | 0 | 0% | falls back to irregular roll |

The model naturally produces the desired feel: walking out from an
opFor base you'll hit guarded compounds at 1km, occasional patrols at
2km, mostly empty / irregular activity beyond 3km. Bluefor-controlled
rings work the same way; bluefor projection is friendly to the player
but the patrols still exist and read as "secured AO."

**Implementation notes**:
- `controllerSide` comes from the faction profile (east for opFor, etc.) so
  spawned units inherit the correct hostility. Irregular fallback
  still force-east as elsewhere in the manager.
- The 3000m projection range can shrink for camps (`projectionRange =
  1500m`) since camps are weaker installations — held as a config knob
  on the influence-installation data, not the microzone.

**Anchored foot patrols** (folded in from a separate scope discussion)

D.5 includes anchored patrols as a first-class handler-config option,
not a separate system. Anchored = the group's waypoints loop within a
fixed radius of the microzone center; despawn is governed by the same
state machine as the rest of the zone's entities. This is distinct
from **roving** foot patrols (Sprint E), which traverse between points
with no home anchor and need their own activation/despawn rules.

Why anchored belongs in D.5:
- They map perfectly onto the existing state machine (zone has a fixed
  position, hysteresis bands work)
- `fnc_filterPatrolGroups` + the existing waypoint loop logic from
  `fnc_presenceActivateMilitary` ports over directly — smaller
  radius, single group
- Read as "patrol" to the player even though they're attached to a
  zone — covers the "walking 2km from infil, bump into a 3-man
  patrol" gap

Handler config shape — each microzone type declares **shape** (radius,
size bounds, pool source, skill), and `fnc_resolveMicrozoneProjection`
supplies the **chance**. Type multipliers live on the handler:

```sqf
["military", createHashMapFromArray [
    ["typeMultiplier",  1.0],          // 0.5 for ag, 2.0 for infra
    ["guard", createHashMapFromArray [
        ["size",        [2, 4]],       // min/max units in the anchor cluster
        ["radius",      40],           // satellite spawn radius around anchor
        ["skill",       "garrison_light"],
        ["irregularFallback", true]    // use irregulars when no controller in range
    ]],
    ["patrol", createHashMapFromArray [
        ["size",        [2, 3]],
        ["radius",      300],          // patrol waypoint radius
        ["skill",       "garrison_light"]
    ]]
]]
```

Per-type rollout (only the shape knobs vary; chance is projection-driven):

| Zone type | typeMult | Guard size / radius | Patrol size / radius | Irregular fallback |
|---|---|---|---|---|
| `industrialSite` | 1.0× | 2-4 / 40m | 2-3 / 250m | yes |
| `isolatedCompound` | 1.0× | 2-3 / 30m | 2-3 / 300m | yes (the random-encounter case) |
| `infrastructureNode` | 2.0× | 1-2 / 20m | 2 / 200m | no (just a lone armed civ) |
| `agriculturalSite` | 0.5× | (no guard config) | (no patrol config) | rare lone armed civ |

Both guards and patrols use combat activation (FiredNear EH), so
dormant clusters cost basically nothing until the player engages.

**Density / cost controls**

At microzone-registration time (one pass in `fnc_initPresenceManager`):

1. **Major-zone exclusion** — skip any microzone whose center is within
   1200m of an existing base/outpost/camp/populatedArea. Those zones'
   radii already cover that ground; doubling up wastes budget and
   creates weird overlap visuals.
2. **Greedy spacing cull** — 600m minimum between accepted microzones,
   first-come-first-served. Otherwise an industrial complex
   generates 8 overlapping `industrialSite`s.

At tick time:

3. **Per-tick microzone activation cap** — at most 3 new microzone
   activations per tick on top of major-zone activations. Cheap
   individually, but a fast traverse across a dense strip shouldn't
   pay 30 spawns in one tick.
4. **Sort preference** — major zones win budget ties when both
   compete. Keep microzones from starving major-zone activations.

**Expected steady-state cost**

Walking infil, ~2km traverse: encounter 2-4 microzones along the way,
with a meaningful mix of civilians + military presence the closer you
get to opFor installations. Standing budget consumption ~15-25u at any
time (vs ~10-15u of a civilians-only model). Major-zone budget
untouched. Per-tick activation throttle (3 microzones max) bounds the
worst-case spawn cost in any single tick to ~18u, spread across the
8s tick window via `fnc_spawnGroupYielding`'s per-unit `uiSleep`.

Target frame-time delta: 0-1ms at sustained traverse. Levers if it
creeps higher: drop per-tick cap 3→2, shrink projection range
3000m→2500m, lower `baseGuard`/`basePatrol` constants.

**Files (planned)**

- `fnc_initPresenceManager.sqf` — consume `_missionSites`; tag-dispatch
  to microzone types; major-zone exclusion + spacing cull pass;
  pre-compute per-microzone nearest-controller distance + side so the
  tick-time helper is O(1)
- `fnc_resolveMicrozoneProjection.sqf` (new shared helper) — reads
  zone's recorded controller distance + handler's `military` block,
  returns `{controllerSide, controllerFaction, guardChance,
  patrolChance, guardSize, patrolSize, strength}`. One place for the
  projection math.
- `fnc_presenceHandlerIndustrialSite.sqf` — civilian_worker pass +
  projection-driven guard + optional anchored patrol
- `fnc_presenceHandlerAgriculturalSite.sqf` — small civilian_worker
  pass, CARELESS, very rare lone armed civilian
- `fnc_presenceHandlerInfrastructureNode.sqf` — projection-driven
  (2× multiplier) guard / patrol; usually no civilians
- `fnc_presenceHandlerIsolatedCompound.sqf` — projection-driven
  guard / patrol with irregular fallback when no controller in range
- `fnc_setupAnchoredPatrol.sqf` (new shared helper) — single small
  group, waypoint loop within radius around an anchor, combat
  activation, `garrison_light` skill, **`uiSleep` between
  `createUnit` calls** via `fnc_spawnGroupYielding`. Reused by all
  microzone handlers that opt in via the patrol config block. Also a
  candidate for retrofit into populatedArea / camp handlers if the
  smaller patrol size reads better than the current 1-2 full-size
  patrols.
- `fnc_setupAnchoredGuard.sqf` (new shared helper) — small static-ish
  cluster (no waypoints, or single SENTRY waypoint at anchor) sized
  per handler config, combat activation, `garrison_light` skill,
  yielding spawn. Lighter weight than `fnc_setupGarrison` — no
  satellite buildings, no interior placement.
- `fnc_registerPresenceHandler.sqf` — no change (existing schema
  already supports arbitrary type keys + nested config blocks)

**Acceptance criteria**

- Walking 2km from a HALO/extract point: at least 1 microzone
  encounter on average; world doesn't feel empty between zones
- Frame time delta vs pre-D.5: within noise (target ≤ 1ms)
- Budget skip rate ≤ 10% on a 15-min mixed traverse (driving + walking)
- Microzone abandoned rate ≤ 15% (slightly looser than major zones —
  small zones with small bands, by design)
- Anchored patrol groups are visibly *patrolling* (waypoints cycling),
  not standing at the anchor — verified in playtest

**Open items deferred to D.6+ / E**

- `roadsideCheckpoint` — needs road-segment scan pass
- Roving foot patrols (no anchor) → Sprint E
- Roving vehicles / boats → Sprint E
- Stationary military emplacements on roads (HMG nests etc. away from
  any installation) → either D.6 or fold into `roadsideCheckpoint`

### Sprint E — Roving Entities Subsystem (separate from zones)

Some presence is fundamentally not zone-based:
- Civilian vehicles wandering between towns
- Military motorized/mechanized patrols on roads
- Boats along coastline
- Roving **foot** patrols with no home anchor — long waypoint chains,
  spawn at bubble edge, despawn behind player

These need their own loop, their own budget, their own activation logic
(probably "spawn near a road within Nkm of the player, drive, despawn at
distance"). Built as a sibling system to the zone manager, not a new zone
type.

D.5's *anchored* patrols cover most of the "world feels populated
between zones" perceived value. Roving foot patrols in E are
polish — at human walking speed across kilometers, player
intersections are rare and the budget vs. perceived-impact ratio is
worse than roving vehicles or boats.

## Diagnostics and Tuning Tools

### Periodic STATS report (every 60s)

```
DSC: ===== PRESENCE STATS (10 min) =====
DSC: stats — activations=9 completed=9 timedOut=0 abandoned=0 (completion=100%)
DSC: stats — budget approved=9 skipped=0 (skipRate=0%)
DSC: stats — latency avg=7996ms max=8031ms (samples=9)
DSC: stats — paused=7 resumed=3 expired=4 (resumeRate=43%, save=3 spawns avoided)
```

### Per-zone activation timing

```
DSC: presence timing [base/loc_94] total=4664ms u=25 v=5 |
  staticDefenses=2107 patrols=1915 mortars=270 vehicles=359 curator=13
```

### Per-zone latency

```
DSC: presence latency [loc_56/populatedArea] 8005ms (2 ticks)
  dist=1048m speed=68m/s
```

### Active-duration and pause/resume logs

```
DSC: presence active-duration [loc_56/populatedArea] 48s (player left, dist=2853m)
DSC: presence active-duration [loc_80/populatedArea] 104s (paused, dist=2817m, 10u/0v frozen)
DSC: presence resumed [loc_85/populatedArea] (paused for 56s, dist=1193m, 10u/0v unfrozen)
DSC: presence pause-expired [loc_79/populatedArea] (deleting 10u/0v)
DSC: presence pause-forced [loc_X/camp] (mission AO, deleting)
```

### Debug map markers

Each zone has an ellipse marker colored by state:
- DORMANT: grey (alpha 0.25)
- ACTIVATING: yellow
- ACTIVE: green
- PAUSED: blue
- DESPAWNING: orange
- COMBAT: red (reserved, not yet used)

Marker text shows `ZoneName [STATE]`.

### Live in-game commands

```sqf
copyToClipboard str (missionNamespace getVariable "DSC_presenceStats");
copyToClipboard str (missionNamespace getVariable "DSC_presenceLatencies");
copyToClipboard str (missionNamespace getVariable "DSC_presenceTimingTotals");
copyToClipboard str (missionNamespace getVariable "DSC_presenceHandlers");
```

## Files

| File | Purpose |
|---|---|
| `addons/core/functions/presence/fnc_initPresenceManager.sqf` | Main loop, state machine, worker, handler registration, instrumentation |
| `addons/core/functions/presence/fnc_registerPresenceHandler.sqf` | Adds a handler config to `DSC_presenceHandlers` (Sprint A) |
| `addons/core/functions/presence/fnc_activatePresenceZone.sqf` | Dispatcher — looks up `DSC_presenceHandlers[type].populate` (Sprint A) |
| `addons/core/functions/presence/fnc_despawnPresenceZone.sqf` | Dispatcher + default entity teardown |
| `addons/core/functions/presence/fnc_presenceActivateMilitary.sqf` | Shared activation body for base/outpost/camp handlers (Sprint A) |
| `addons/core/functions/presence/fnc_presenceHandlerBase.sqf` | Base preset (delete lifecycle) |
| `addons/core/functions/presence/fnc_presenceHandlerOutpost.sqf` | Outpost preset (pause lifecycle, 150s) |
| `addons/core/functions/presence/fnc_presenceHandlerCamp.sqf` | Camp preset (pause lifecycle, 120s); short-circuits to irregular overlay for neutral |
| `addons/core/functions/presence/fnc_presenceHandlerPopulatedArea.sqf` | Civilians + military overlay + skirmish + irregular overlay + indoor garrison passes (pause lifecycle, 120s) |
| `addons/core/functions/presence/fnc_presenceLogTimings.sqf` | Per-call timing aggregation |
| `addons/core/functions/ai/fnc_setupCivilians.sqf` | Civilian peds with CARELESS waypoints; accepts weighted `classMix` |
| `addons/core/functions/ai/fnc_setupGarrison.sqf` | Indoor anchor+satellite garrison engine; `unitPoolOverride` config supported |
| `addons/core/functions/ai/fnc_setupGarrisonCivilians.sqf` | Civilian indoor garrison wrapper (dormant — currently unused) |
| `addons/core/functions/ai/fnc_setupLightMilitaryGarrison.sqf` | Indoor military garrison wrapper, mission-density caps, `garrison_light` skill |
| `addons/core/functions/ai/fnc_setupStaticDefenses.sqf` | Tower + bunker defenders, marksman-preferred pool |
| `addons/core/functions/ai/fnc_setupMortarEmplacement.sqf` | Mortar tube + crew |
| `addons/core/functions/ai/fnc_setupContestedSkirmish.sqf` | West-side opposing patrol for contested zones |
| `addons/core/functions/ai/fnc_resolveIrregularOverlay.sqf` | Armed-civilian patrol for neutral-influence zones (east-side, hostile to player) |
| `addons/core/functions/ai/fnc_resolveCivilianMix.sqf` | Tag → resolver-key weighted civilian mix |
| `addons/core/functions/ai/fnc_setupPatrols.sqf` | Group spawn + `taskPatrol`, supports `spawnAngle` |
| `addons/core/functions/ai/fnc_filterPatrolGroups.sqf` | Recce/fireteam filter |
| `addons/core/functions/ai/fnc_getSkillProfile.sqf` | Skill profiles incl. `garrison_light` |
| `addons/core/functions/faction/fnc_resolveEntityClass.sqf` | Civilian resolver keys (`civilian`, `_suit`, `_labcoat`, `_worker`) |
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
9. **Sprint A** — Handler registry refactor (mechanical, no behavior change)
10. **Sprint B** — Per-handler tuning: 8s tick, asymmetric hysteresis bands, 150u/40v budget, active-duration log
11. **Sprint C** — PAUSED state + freeze/resume lifecycle (populatedArea, camp, outpost); base stays delete
12. **Tangent (post-C)** — Irregular overlay fills neutral-influence populated areas and camps with a small armed-civilian patrol, force-east-side for player hostility
13. **Sprint D** — Functional location tags (`industrial_zone`, `commercial_hub`, `port_zone`, etc.) + `primaryFunction` from scanner; populatedArea civilians now flavored by zone character via weighted `classMix` (new `civilian_worker` resolver); indoor garrison layer adds two passes per populated zone — a controlling-faction garrison (gated by control + influence, mission-density caps/satellites) and an always-on irregular garrison (low-chance armed-civilian compound, runs regardless of control). New helpers: `fnc_setupLightMilitaryGarrison`, `garrison_light` skill profile. Civilian-garrison variant built but disabled.
14. **Stutter Pass (June 2026)** — Post-Sprint-D stutter investigation. Five independent fixes shipped: (a) `fnc_setupGarrison` got `uiSleep` yields per createUnit + between buildings + between clusters (was the only setup fn without yields; Sprint D's controlling+irregular passes were bursting 12-20 createUnits in one scheduler slot). (b) `enableDynamicSimulationSystem true` + global category distances added to `fnc_initServer` (was completely off — every `triggerDynamicSimulation` call in the codebase was a silent no-op); every presence-spawned group opts in via `enableDynamicSimulation true`. Discovered `setDynamicSimulationDistanceCoef` is a global category setter (takes a String like `setDynamicSimulationDistance`), not a per-group setter — there is no per-group coef in stock Arma. (c) `pauseGrace` shortened across the board (populatedArea 120→60s, outpost 150→75s, camp 120→45s). (d) Speed-aware pause skip — when avg player speed >35 m/s, ACTIVE→exit routes to `delete` regardless of registered lifecycle, preventing helicopter sprints from filling the cap with PAUSED zones that will never resume. (e) DESPAWNING excluded from budget gate calculation — condemned zones were inflating `usedUnits` while waiting for the worker, causing false-positive cap exhaustion. Combined result: `skipRate` dropped 60% → 0%, peak budget 163u → 143u, active zones during sustained sprint 0-1 → 4-6.
15. **Engine dyn-sim layer enabled** — see dedicated section below.

## Sprints Up Next

- **Real-mission shakedown** — verify dyn-sim doesn't freeze AI at wrong moments, combat activation triggers cleanly, no boundary stutters when crossing population edges on foot/in vehicle
- **Sprint E** *(separate subsystem)* — Roving entities (civilian vehicles, mil patrols, boats)

## Engine Dynamic Simulation Layer (June 2026)

Orthogonal to the state machine and the pause lifecycle. Activated in
`fnc_initServer` Step 0:

```sqf
enableDynamicSimulationSystem true;
"Group"        setDynamicSimulationDistance 1500;
"Vehicle"      setDynamicSimulationDistance 2000;
"EmptyVehicle" setDynamicSimulationDistance 500;
"Prop"         setDynamicSimulationDistance 300;
```

Every presence-spawned group opts in (`enableDynamicSimulation true`):

| Setup fn | Opt-in | Effective AI distance |
|---|---|---|
| `setupCivilians` | ✓ | 1500m (Group) |
| `setupGarrison` | ✓ | 1500m |
| `setupPatrols` | ✓ | 1500m |
| `setupStaticDefenses` | ✓ (group + statics) | 1500m / 2000m statics |
| `setupMortarEmplacement` | ✓ (group + mortars) | 1500m / 2000m mortars |
| `setupVehicles` | ✓ (crew + vehicles) | 1500m / 500m parked empty |
| `setupGuards` | ✓ | 1500m |
| `setupVehiclePatrol` | ✓ | 1500m / 2000m vehicle |

`setDynamicSimulationDistanceCoef` is **global** (takes a class String,
same as `setDynamicSimulationDistance`) — there is no per-group or
per-unit coef. To vary AI ranges per role, tune the global category
distances. We initially attempted civilian-specific shortening via coef
calls on Groups/Objects; those error and were reverted.

Interaction with presence lifecycle:
- Pause (`enableSimulation false`) is the explicit "player left" freeze
- Dyn-sim is the per-frame "no one's looking" auto-freeze inside ACTIVE
- They stack cleanly. Combat activation (FiredNear) bypasses both.

Previously the engine system was off — `triggerDynamicSimulation true`
calls in `fnc_setupBase.sqf` were silent no-ops. Discovered and fixed
during the post-Sprint-D stutter investigation.
