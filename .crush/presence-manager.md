# Presence Manager — DSC World Simulation

*Last updated: June 2026 — Sprints 1-8 + A/B/C/D + Stutter Pass + Sprint D.5 Microzones shipped, real-mission shakedown next, Sprint E after*

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

### Zone Types and Defaults (post Sprint D.5 retune, June 2026)

| Type | Class | actR | depR | grace | budgetU/V | lifecycle | pauseGrace | Spawn content |
|---|---|---|---|---|---|---|---|---|
| `base` | major | 1500 | 2000 | 90s | 20 / 3 | delete | (180s configured, not used) | Static defenders + 2-3 patrols + 1-2 mortars + 2 parked vehicles |
| `outpost` | major | 1200 | 2000 | 75s | 8 / 1 | pause | 75s | Static defenders (towers, marksmen, statics) + 1-2 small patrols + 0-1 parked vehicle |
| `camp` | major | 900 | 1500 | 60s | 4 / 1 | pause | 45s | 1 patrol if controlled; armed-civilian patrol if `controlledBy=neutral` |
| `populatedArea` | major | 1500 | 2000 | 60s | 8 / 0 | pause | 60s | Civilians (3-12, influence-scaled) + indoor garrison clusters + optional military overlay (0-2 patrols) + contested skirmish opposing patrol + irregular overlay on neutral zones |
| `industrialSite` | micro | 1000 | 1500 | 30s | 8 / 0 | delete | — | 3-5 civilian workers + projection-driven guard/patrol + 55% irregular fallback when no controller in range |
| `isolatedCompound` | micro | 1000 | 1500 | 30s | 8 / 0 | delete | — | 2-3 civilians + projection-driven guard/patrol + 65% irregular fallback |
| `infrastructureNode` | micro | 1000 | 1500 | 30s | 8 / 0 | delete | — | 1-3 civilians + projection-driven guard/patrol (typeMult 2.0×) |
| `agriculturalSite` | micro | 1000 | 1500 | 30s | 6 / 0 | delete | — | 2-4 farmers + control-tiered lone armed-civilian roll (30%/25%/12% opFor/contested/neutral) |

Tick interval: 8s (global). Budget cap: 150 units / 40 vehicles.
Per-tick microzone activation cap: 4 (major zones bypass throttle).

**Why despawn radii tightened in the D.5 retune** — pre-D.5 the major
zone hysteresis bands were wide (base 1500/4000, outpost 1200/3000,
populated 1500/2400) to absorb helicopter sprints without abandoning
zones. With 172+ microzones live and tighter zone budgets per
microzone (8u), keeping major zones alive for 4km past the
activation distance was burning standing budget the player wouldn't
re-enter. The retune set despawn = activate + ~500m for major zones
and a uniform 1000/1500 band for microzones — short enough that exit
clears budget fast, wide enough that pause/resume still saves spawns
when the player loops back.

**populatedArea civilian density retune** — opFor influence reduction
factor dropped 0.7 → 0.5, contested 0.65 → 0.5, bluFor 1.0 → 0.7,
default (neutral) 0.9 → 0.6. With microzones now adding wandering
civilians across the rural map, populated areas no longer need to be
fully packed to sell "the world is inhabited." Combined with the
0-2 (was 0-3) military overlay patrol count, populated zones run ~25%
lighter on the budget without losing the lived-in feel.

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

### Sprint D.5 — Microzones (SHIPPED June 2026)

Adds a fifth zone bucket: `_missionSites` from `fnc_initInfluence`, the
"everything else" pile (orphan-recovery clusters from Stage 3.5, small
`NameLocal` pockets, isolated industrial-shed complexes, agricultural
holdings). All of them carry Sprint D's `tags`, `primaryFunction`, and
`functionalProfile` data. D.5 turns them into a new family of zone
types registered against Sprint A's handler registry — same tick loop,
same worker, same state machine, same budget gate, same mission AO
arbitration. No second loop, no second worker.

**Design principles** (all held)

- Reuse Sprint A's registry verbatim. Every microzone type is a
  one-file handler + `registerPresenceHandler` call. Tick loop stays
  type-agnostic.
- Small radii + `lifecycle=delete`. Pausing 170+ microzones would
  torch the 150u budget cap; they're cheap enough that re-spawning on
  re-entry beats carrying frozen entities.
- Density caps at registration time so dense rural strips don't
  generate overlapping microzones.
- Per-tick activation throttle so a fast traverse never pays more
  than 4 microzone spawns in a single tick.
- New `class` field on every handler config (`"major"` or `"micro"`)
  — the throttle and budget tie-break read this rather than
  pattern-matching on type names.

**Tag-driven dispatch from `_missionSites`** — handler classification
happens at registration in `fnc_initPresenceManager`:

| Microzone type | Trigger |
|---|---|
| `agriculturalSite` | `agricultural_zone` ∈ tags OR `primaryFunction=agricultural` |
| `industrialSite` | `industrial_zone` ∈ tags OR `industrial_hub` ∈ tags OR `primaryFunction=industrial` |
| `infrastructureNode` | `infrastructure_node` ∈ tags |
| `isolatedCompound` | everything else (orphan cluster, untagged civilian pocket) |

**Shipped registered values** (per type, from
`fnc_initPresenceManager.sqf`):

| Property | All four microzones |
|---|---|
| activateRadius | 1000m |
| despawnRadius | 1500m |
| despawnGrace | 30s |
| lifecycle | delete |
| budgetUnits | 8 (6 for agriculturalSite) |
| budgetVehicles | 0 |
| class | "micro" |

**Controller projection model** — shared helper
`fnc_resolveMicrozoneProjection` reads precomputed nearest-controller
data off the zone (populated at init, no spatial scan at tick time)
and returns a hashmap with `controllerSide/Faction/Control`,
`guardChance`, `patrolChance`, `guardSize/Radius/Skill`,
`patrolSize/Radius/Skill`, and `strength`.

Resolution math (shipped constants):

```
strength       = controller.influence × (1 - dist / projectionRange)
guardChance    = 0.95 × strength × typeMultiplier
patrolChance   = 0.90 × strength × typeMultiplier
```

`baseGuard` and `basePatrol` were tuned up from initial 0.55/0.45 →
0.80/0.80 → final 0.95/0.90 across two playtest passes. With the
narrow 1000m activate radius, fewer microzones are live at once, so
each one needs to be denser to read as a real encounter rather than
a 1-2-unit shell.

Projection ranges, registered on the controller candidates:
- base / outpost: 4500m
- camp: 2500m

**Type multipliers** (live on each handler's `military` config block):

| Microzone type | typeMult | Notes |
|---|---|---|
| industrialSite | 1.0× | standard |
| isolatedCompound | 1.0× | standard |
| infrastructureNode | 2.0× | high-value — militaries prioritize comms/fuel/power |
| agriculturalSite | 0.5× | low-value, militaries rarely garrison farms |

**Shipped cluster sizes** (handler `military` blocks):

| Microzone | Guard size / radius | Patrol size / radius |
|---|---|---|
| industrialSite | 3-5 / 40m | 4-5 / 250m |
| isolatedCompound | 3-5 / 30m | 4-5 / 300m |
| infrastructureNode | 3-4 / 20m | 3-4 / 200m |
| agriculturalSite | — | — (no military block → projection returns 0) |

**Civilian baselines** (every microzone gets civilians — "people live
everywhere," matches AGENTS reading on rural Afghanistan
operations):

| Microzone | Civilians per activation |
|---|---|
| industrialSite | 3-5 workers (classMix tags → `civilian_worker`) |
| isolatedCompound | 2-3 (generic classMix) |
| infrastructureNode | 1-3 (technicians / residents) |
| agriculturalSite | 2-4 farmers (classMix → `civilian_worker`) |

**Irregular fallback** (when no controller is within projectionRange,
the projection returns strength=0 and these rolls fire):

| Microzone | Fallback chance | Size |
|---|---|---|
| industrialSite | 55% | 4-5-unit patrol, east side |
| isolatedCompound | 65% | 4-5-unit patrol, east side |
| infrastructureNode | 0% | (no fallback — quiet utility) |
| agriculturalSite | 30% / 25% / 12% (opFor / contested / neutral) | lone armed civilian guard (size 1) |

**Density / cost controls** (shipped values)

At registration:
1. **Major-zone exclusion**: 900m (was 1200m in the initial design —
   tightened so the projection ring around bases/outposts catches more
   microzones, which is the dense-encounter-near-installations
   scenario you actually want).
2. **Greedy spacing cull**: 600m minimum between accepted microzones.

At tick time:
3. **Per-tick microzone activation cap**: **4** (was 3 then 6 then 4
   across tuning passes — landed at 4 as the balance between
   queue-drain latency and rapid-traverse coverage).
4. **Sort preference**: major zones win budget ties via the
   class field check.

**Major-zone retune that shipped with D.5** — to free standing
budget for the microzone layer, all major zone despawn radii were
tightened in the same pass:

| Major zone | Old depR | New depR |
|---|---|---|
| base | 4000 | 2000 |
| outpost | 3000 | 2000 |
| camp | 1800 | 1500 |
| populatedArea | 2400 | 2000 |

Activate radii unchanged. Net hysteresis bands are now 500-700m wide
(was 800-2500m) — short enough that exits free budget fast, wide
enough that pause/resume still saves spawns when the player loops
back at moderate speed.

**Populated area density retune** (same pass):
- Civilian density factors: opFor `(1 - influence × 0.7)` →
  `(1 - influence × 0.5)`, contested `0.65 → 0.50`, bluFor `1.0 →
  0.70`, neutral `0.9 → 0.6`. With microzones now adding wandering
  civilians across the rural map, populated areas don't need to be
  fully packed to sell "the world is inhabited."
- Military overlay patrol count cap: `[0, 3]` → `[0, 2]`.
- Default-tier garrison cluster count: `[1, 2]` → `[1, 1]` (city
  tier still rolls `[1, 3]`).

**Files shipped**

- `addons/core/functions/presence/fnc_initPresenceManager.sqf` —
  consumes `_missionSites`, tag-classifies, runs major-zone
  exclusion + spacing cull pass, precomputes nearest-controller per
  microzone, registers all 8 handlers (4 major + 4 micro) with
  `class` field, runs per-tick microzone activation throttle in the
  budget loop
- `addons/core/functions/presence/fnc_resolveMicrozoneProjection.sqf`
  (new) — projection math helper, O(1) at tick time
- `addons/core/functions/presence/fnc_presenceHandlerIndustrialSite.sqf` (new)
- `addons/core/functions/presence/fnc_presenceHandlerIsolatedCompound.sqf` (new)
- `addons/core/functions/presence/fnc_presenceHandlerInfrastructureNode.sqf` (new)
- `addons/core/functions/presence/fnc_presenceHandlerAgriculturalSite.sqf` (new)
- `addons/core/functions/ai/fnc_setupAnchoredGuard.sqf` (new) —
  small static cluster, SENTRY waypoint, garrison_light skill,
  combat activation, `uiSleep 0.1` per createUnit
- `addons/core/functions/ai/fnc_setupAnchoredPatrol.sqf` (new) —
  small patrol group, BIS_fnc_taskPatrol, garrison_light skill,
  combat activation OFF by default (patrols need PATH enabled to
  actually patrol — dyn-sim handles dormant cost), yielding spawn
- `addons/core/functions/presence/fnc_presenceHandlerPopulatedArea.sqf`
  — civilian density factors + overlay patrol count retune
- `addons/core/XEH_PREP.hpp` — registered 7 new functions

**Tuning history (for future reference)**

Initial D.5 ship → first stress test → second stress test → current:

| Knob | Initial | Stress 1 (density bump) | Stress 2 (radius cut) | Current (post playtest) |
|---|---|---|---|---|
| Microzone actR | 600-500 | 2000 | 1100 | 1000 |
| Microzone depR | 1200-1000 | 2400 | 1700 | 1500 |
| baseGuard / basePatrol | 0.55 / 0.45 | 0.80 / 0.80 | 0.95 / 0.90 | 0.95 / 0.90 |
| Major base depR | 4000 | 4000 | 4000 | 2000 |
| Per-tick micro cap | 3 | 6 | 4 | 4 |
| Major-zone exclusion | 1200m | 1200m | 900m | 900m |
| isolatedCompound civilians | 0 | 1-2 | 2-3 | 2-3 |
| isolatedCompound irregular fallback | 30% | 55% | 65% | 65% |

**Acceptance criteria (validated in playtest)**

- Walking 2km from infil reliably yields 2-4 microzone encounters ✓
- Budget never observed > 130u during sustained traversal ✓
- 100% completion rate, 0% abandoned across multi-minute helicopter
  loops ✓
- Worker queue drains in 1-2 ticks under heavy load ✓
- Anchored patrols are visibly patrolling (waypoints cycling) ✓

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

### Sprint E Phase 1 — Ambient Air (SHIPPED June 2026)

Sibling subsystem to the zone manager. Independent globals, tick, worker,
budget. Phase 1 shipped air (rotary + fixed-wing). Phase 2 added ground
motorized/mechanized patrols. Phase 3 closes out the feature with foot
patrols and boats.

**Scheduler isolation strategy.** SQF `spawn`s don't run in parallel — they
time-slice on a single cooperative scheduler. "Independent" here means
decoupled state + decision timing, not parallelism. Three concrete moves:

1. **Phase-offset ticks.** Presence ticks at t=0, 8, 16; roving starts at
   t=4 and ticks every 8s. Decision windows alternate, so spawn queues fill
   at different wall-clock moments and the workers grab work at different
   times. The roving tick loop opens with `uiSleep 4` to seed the offset.
2. **Independent worker scope.** Roving worker has its own queue
   (`DSC_rovingSpawnQueue`), its own heartbeat, its own pacing
   (`uiSleep 1.5` between spawns). Yields with `uiSleep` so the engine
   gets frames even if the presence worker is also active.
3. **Independent budget.** Air caps are tiny (2 rotary + 1 fixed-wing
   concurrently). A rotary spawn is ~1 createVehicle + createVehicleCrew —
   roughly 1/40th the cost of a base activation, so contention with the
   presence worker is essentially impossible at Phase 1 scale.

A shared `DSC_presenceWorkerBusy` back-pressure flag was considered and
deferred. With Phase 1 air caps it's unnecessary; revisit when Phase 2
adds heavier ground spawns.

**Hotspot model.** Air spawn density is biased toward military
installations and airbases:

| Tier | Source | Weight |
|---|---|---|
| `airbase` | 3den-placed `player_base_<N>` markers | 4.0 |
| `base` | Bases from `DSC_influenceData` (opFor / bluFor controlled only) | 3.0 |
| `outpost` | Outposts from `DSC_influenceData` (opFor / bluFor controlled only) | 1.5 |

Airbases (`player_base_*` markers) sided to bluFor (west) by default —
they are the player's airfields and we want ambient west traffic biased
toward them. Bases and outposts sided per their controlling faction
(neutral / contested skipped — ambiguous side ownership = wrong-side
spawns and player confusion).

**Spawn algorithm** (`fnc_rovingSpawnAir`):

1. Side roll: per-tick independent east/west rolls (both can fire same tick)
2. Origin pick: candidates = side hotspots within 6km of player + 30% of
   farther side hotspots (rare ambient overflight floor)
3. Weighted random pick by `weight × (1 + influence)`
4. Destination: random hotspot 4-15km from origin; if none, synth point on
   far side of player along origin→player vector
5. Spawn position: 4-6km (rotary) or 6-9km (fixed-wing) from player along
   the player→origin direction, so the flight path passes through the
   player's vicinity en route to destination
6. Altitude: rotary 100-150m, fixed-wing 600-1000m
7. Waypoints: MID (near player) → DEST → EXIT (6km past dest) so the
   aircraft keeps flying outbound if the despawn sweep is delayed

**Behavior posture.** AWARE + `disableAI "AUTOCOMBAT"` + `disableAI
"TARGET"` + `disableAI "AUTOTARGET"`. Matches the `persistentUAV` gotcha:
CARELESS makes flyers cling to waypoints; AWARE without autocombat gives
clean ambient transit. Player can shoot first; the aircraft won't fire
back in Phase 1.

**Aircraft selection.** Pulls from `factionData[opFor|bluFor].assets[...]
.helicopters` (attack + transport) or `.planes` (attack + transport).
Partner roles (opForPartner, bluForPartner) skipped per design — keeps
side attribution clean. Irregulars don't fly.

**Spawn pacing.**

| Parameter | Value | Notes |
|---|---|---|
| Tick interval | 8s | Same as presence, phase-offset 4s |
| Per-tick roll chance | 35% per side | Independent east/west rolls |
| Min interval per side | 45s | Per-side cooldown |
| Rotary / fixed-wing split | 80% / 20% | Helo traffic feels more frequent |
| Rotary budget cap | 3 active | bumped from 2 post-playtest |
| Fixed-wing budget cap | 2 active | bumped from 1 post-playtest |

**Despawn rules** (`fnc_rovingDespawnSweep`, runs at top of every tick):

- Rotary: distance > 5km from player, OR vehicle dead/null
- Fixed-wing: distance > 8km from player, OR vehicle dead/null
- Failsafe: age > 600s catches any frozen / pathfinding-stuck aircraft

Dot-product "behind player" gating intentionally NOT used in Phase 1 —
spawn pattern already routes aircraft through the player's vicinity
toward a far destination, so pure distance is enough. Revisit if Phase 2
testing shows pop-in artifacts.

**Mission AO arbitration.** Independent of presence. When
`DSC_currentMission.state ∈ {"active", "briefing"}`, fresh air rovers are
not spawned. Existing rovers continue their flight path (high altitude,
ambient — they don't interfere with missions on the ground).

**Globals exposed.**

```sqf
DSC_rovingHotspots          // hashmap with "all", "east", "west" arrays
DSC_rovingActive            // active rover records
DSC_rovingSpawnQueue        // pending spawn requests
DSC_rovingBudgetRotary      // 2
DSC_rovingBudgetFixed       // 1
DSC_rovingWorkerHeartbeat   // diag_tickTime
DSC_rovingStats             // counters: spawned, rotarySpawned, fixedWingSpawned,
                            //   despawned, nearHotspotSpawns, skippedAoOverlap,
                            //   skippedBudget, spawnAttempts
```

**Instrumentation (every 60s):**

```
DSC: ===== ROVING STATS (10.0 min) =====
DSC: roving - spawned=12 (rotary=10 fixedWing=2) despawned=8 active=4
DSC: roving - attempts=34 skipBudget=18 skipAO=0 nearHotspot=11
```

Per-spawn log: `DSC: roving spawned [rotary] Mi-8 src=base/loc_94 dst=4200m alt=120m sideKey=east`
Per-despawn log: `DSC: roving despawned [rotary/roving_air_east_1234.56] dist=5320m`

**Files shipped.**

- `addons/core/functions/presence/fnc_initRovingManager.sqf` (new) — tick + worker, phase-offset 4s, budget gate, mission AO arbitration
- `addons/core/functions/presence/fnc_resolveRovingHotspots.sqf` (new) — hotspot registry from influence + `player_base_*` markers
- `addons/core/functions/presence/fnc_rovingSpawnAir.sqf` (new) — rotary / fixed-wing transit spawner
- `addons/core/functions/presence/fnc_rovingDespawnSweep.sqf` (new) — distance + death cull
- `addons/core/functions/init/fnc_initServer.sqf` — STEP 4d call after presence init
- `addons/core/XEH_PREP.hpp` — 4 new functions registered

### Sprint E Phase 2 — Roving Ground Patrols (SHIPPED June 2026)

Adds motorized / mechanized road patrols as a third roving category
alongside Phase 1 air. Same sibling subsystem, same tick + worker, same
phase-offset — just a new spawner and a third budget bucket.

**Spawn algorithm** (`fnc_rovingSpawnGround`):

1. Side roll: independent east/west rolls per tick (separate cooldowns
   from air so ground and air pacing don't drag each other)
2. Hotspot filter: non-airbase only (aircraft launch from airbases,
   ground vehicles roll from bases / outposts)
3. Range filter: hotspot must be within 5km of player — ground vehicles
   are slow; distant hotspots produce rovers that never reach the
   encounter window
4. Road pick: `nearRoads` within 1km of hotspot, filter to roads
   **1500-3000m from player** (spawn-bubble edge band — out of FOV/audio,
   close enough to drive into engagement window)
5. Group selection: classified groups tagged `MOTORIZED+PATROL`
   (preferred) → `MECHANIZED+PATROL` → `MOTORIZED` fallback; AT_TEAM /
   AA_TEAM excluded (too heavy for ambient transit)
6. Spawn via `BIS_fnc_spawnGroup` (handles vehicle + crew creation in
   one go — small burst, ~5-7 createUnits + 1 createVehicle)
7. Waypoints: `fnc_buildRoadRoute` from spawn position toward player
   direction, 4-5km route; sample 4 waypoints from the route
8. Final waypoint past the despawn ring so the rover keeps driving
   outbound if the despawn sweep is delayed

**Behavior posture** — matches Phase 1 air. AWARE + BLUE combat mode +
`disableAI "AUTOCOMBAT"` + `disableAI "TARGET"` + `disableAI
"AUTOTARGET"`. Speed `LIMITED` so AI actually navigates the road
network without flipping or oversteering. They return fire if attacked
but won't engage the player on detection.

**Spawn pacing.**

| Parameter | Value | Notes |
|---|---|---|
| Per-tick ground roll chance | 30% per side | lighter than air (35%); bumped from 20% post-playtest |
| Min interval per side (ground) | 60s | shortened from 90s post-playtest |
| Ground budget cap | 4 active | bumped from 3 post-playtest |
| Hotspot proximity | within 7km of player | bumped from 5km, with closest-side-hotspot fallback when nothing in range |
| Despawn radius | 4500m | bumped from 3500m so patrol can roam without instant culling |

**Ambient patrol redesign (post-playtest, iterated).** Original ground design
tied spawn position to a hotspot, which led to rovers spawning 5-10 km from
the player and despawning before reaching the encounter zone. Final model
decouples hotspot from spawn geometry entirely:

**Hotspot → faction; player position → spawn ring.** The nearest hotspot to
the player decides which faction shows up (player in opFor territory sees
opFor patrols; bluFor territory sees bluFor patrols). Spawn position is a
random road in a ring **2.5-4 km from the player** for ground / **2.5-4.5 km
(rotary) or 4-6 km (fixed-wing)** for air. The same rule applies to both
ground and air rovers.

This matches the user's intent: "spawn points can be similar to the
garrison/guard/patrol/statics/vehicles types" — the rover *exists in the
world near the player*, not at some distant installation. The hotspot
controls flavor, not geography.

**Ground spawn flow:**
1. Find nearest non-airbase hotspot to player → side / faction pool
2. Pick a random direction + distance (**0.8-2.5 km**), find a road near that point
3. Spawn group via `BIS_fnc_spawnGroup`, `moveInCargo` all dismounts so the
   whole team transits in the vehicle (not on foot), `selectLeader driver`
4. `spawn fnc_rovingGroundPatrolLoop` — single road-bound MOVE waypoint at
   a time via `fnc_buildRoadRoute`, brief 30-60s hold, repeat. Adapted from
   the proven `fnc_setupVehiclePatrol` pattern. (`BIS_fnc_taskPatrol` was
   tried; its `findSafePos` waypoints sent rovers off-road into pathing
   deadlocks.)
5. Despawn ring 5 km

**Air spawn flow:**
1. Find nearest hotspot to player (airbases included) → side / aircraft pool
2. Pick a random direction; spawn point at altitude on that side of player
3. Synth destination on the opposite side (6-10 km past player)
4. **Behavior roll** at spawn (55/45 split):
   - **TRANSIT** (~55%): MID → DEST → EXIT waypoints route the aircraft
     straight through the player's area. Reads as "flight passing through."
   - **LOITER** (~45%): 3 orbital waypoints on a ring around a near-player
     point (600m radius rotary / 1500m fixed-wing) with CYCLE waypoint to
     loop. A scheduled scope drops the cycle after 90-180s and adds the
     exit waypoint. Reads as "patrol / monitoring / deterrent orbit."
5. Despawn 5 km (rotary) / 8 km (fixed-wing)

**Force-mount dismounts (ground).** `BIS_fnc_spawnGroup` for motorized
infantry teams only auto-mounts driver + gunner from the CfgGroups vehicle
entry; dismounts spawn on foot. That left rovers with a stationary truck
and infantry milling around it. After spawn we `moveInCargo` everyone who
isn't already in the vehicle and `selectLeader driver` so the taskPatrol
waypoints route through the driver's control loop.

**Aircraft + ground worker dispatch.** The roving worker now dispatches
on queue-item subtype:

```sqf
if (_subtype == "ground") then {
    [_hotspots, _factionData, _sideKey] call DSC_core_fnc_rovingSpawnGround;
} else {
    [_subtype, _hotspots, _factionData, _sideKey] call DSC_core_fnc_rovingSpawnAir;
};
```

Air spawners still pace `uiSleep 1.5` after every spawn; ground spawns
respect the same yield. A ground spawn costs ~5-7 createUnit + 1
createVehicle (~200-400ms wall-clock), still well within Phase 1's
isolation budget vs the presence manager.

**Air far-floor tightened** in the same pass. The Phase 1 "spawn from
a distant hotspot when nothing's nearby" sprinkle dropped 30% → 15% —
post-playtest, 30% was producing too many irrelevant overflights when
the player was near installations. New value biases air harder toward
the player's local region while still preventing silence in empty
wilderness.

**Files shipped.**

- `addons/core/functions/presence/fnc_rovingSpawnGround.sqf` (new) — motorized / mechanized road patrol spawner
- `addons/core/functions/presence/fnc_rovingDespawnSweep.sqf` — extended with `ground` type (3500m cull)
- `addons/core/functions/presence/fnc_initRovingManager.sqf` — ground budget global, ground rolls, worker dispatcher
- `addons/core/functions/presence/fnc_rovingSpawnAir.sqf` — far-floor tightened 0.30 → 0.15
- `addons/core/XEH_PREP.hpp` — 1 new function registered

**Phase 3 — Foot patrols + boats (SHIPPED).** Closes out the roving feature
with two final rover types.

**Foot patrol spawn flow** (`fnc_rovingSpawnFoot.sqf`):
1. Nearest non-airbase hotspot → side / faction pool (same as ground/air)
2. Spawn position via `BIS_fnc_findSafePos` 600-1500m from player in random
   direction. Foot patrols spawn closer than vehicles since they're slower
   and the player needs to actually encounter them.
3. Group pool = classified FOOT + PATROL groups; excludes AT_TEAM / AA_TEAM
   / MOTORIZED / MECHANIZED / ARMORED. Falls back to FOOT-only if no PATROL
   group exists for the faction.
4. Spawn via `fnc_spawnGroupYielding` (the yielding variant) so the
   per-unit `createUnit` cost doesn't stutter the scheduler.
5. `BIS_fnc_taskPatrol` centered on the **player**, radius 1000m. Foot AI
   handles findSafePos waypoints cleanly (unlike vehicles, which is why
   we use the road-route loop for ground rovers).
6. Despawn ring **2000m** — tight since walkers can't outrun the player.
7. Budget cap **2 active**.

**Boat spawn flow** (`fnc_rovingSpawnBoat.sqf`):
1. Nearest hotspot (airbases included) → side / faction pool
2. Find a water spawn position 800-2000m from player via random angle +
   `surfaceIsWater` check. **Bails silently if no water in range** —
   inland maps (e.g. Livonia) skip boat spawns automatically.
3. Boat asset pulled from `extractAssets[faction].boats` (flat array).
   Boats don't reliably exist as CfgGroups entries, so this is
   classname-driven like air rovers.
4. `createVehicle` + `createVehicleCrew` (generic crew — faction-specific
   crew on boats requires per-slot `createUnit` from the manPool, which
   wasn't worth the complexity for ambient roving).
5. Patrol via 3-4 manually generated water waypoints in a ring 1000-2000m
   from the player (each validated with `surfaceIsWater`), with a `CYCLE`
   waypoint so the boat loops. If fewer than 2 water points are found
   (narrow coast), spawns a single "idle in place" waypoint at the spawn
   position rather than failing.
6. Despawn ring **3500m**.
7. Budget cap **2 active**.

**Cooldowns + roll chances:**

| Type | Cooldown | Roll chance per tick | Notes |
|---|---|---|---|
| Foot | 75s | 35% | Single roll (no per-side — side derived at spawn) |
| Boat | 120s | 30% | Single roll; silent no-op on inland maps |

**Despawn sweep extensions** — foot rovers have no vehicle, so the sweep
uses the group leader's distance and considers the rover "dead" if the
group has zero living units. Boats use the same vehicle-distance pattern
as ground/air.

**Behavior posture (all rover types):** AWARE + `disableAI` AUTOCOMBAT /
TARGET / AUTOTARGET. Ambient world presence, not forced encounter. All
rovers will return fire if attacked but won't engage on detection.

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
