# Presence Manager — DSC World Simulation

*Last updated: June 2026 — Sprints 1-8 + A/B/C/D shipped, irregular-overlay tangent shipped, Sprint E next*

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
| `outpost` | 1200 | 3000 | 75s | 8 / 1 | pause | 150s | Static defenders (towers, marksmen, statics) + 1-2 small patrols + 0-1 parked vehicle |
| `camp` | 900 | 1800 | 60s | 4 / 1 | pause | 120s | 1 patrol if controlled; armed-civilian patrol if `controlledBy=neutral` |
| `populatedArea` | 1500 | 2400 | 60s | 8 / 0 | pause | 120s | Civilians (3-12, influence-scaled) + optional military overlay + contested skirmish opposing patrol + irregular overlay on neutral zones |

Tick interval: 8s (global). Budget cap: 150 units / 40 vehicles.

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

| Metric | Pre-tuning | Post Sprint B | Post Sprint C |
|---|---|---|---|
| Activations | 41 | 24 | 9 |
| Completion rate | 98-100% | 100% | 100% |
| Budget skip rate | 5% | 0% | 0% |
| Avg latency | 20.06s | 8.7s | 8.0s |
| **Abandoned (spawned but player blew past)** | **22%** | **0%** | **0%** |
| Active duration (avg) | ~25s | ~50-80s | ~60-100s |
| Pause/resume saves | n/a | n/a | 3 of 7 paused zones resumed (43%) |

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

**Part 3 — Indoor garrison layer (populated areas + neutral camps).** On
top of the wandering civilian pass, the populatedArea handler now places
1-2 *indoor* clusters per zone using `fnc_setupGarrison` driven by two new
wrappers:

- `fnc_setupGarrisonCivilians` — civilians inside building positions
  (CARELESS, allowFleeing 0, skill 0.3). Headcount is hard-capped by an
  inverse-density size tier so cities don't get destroyed by population
  scaling:

  | sizeTier | bldg count | anchor range | unit caps (main/side) | zone-gate roll |
  |---|---|---|---|---|
  | isolated   | <5    | 1     | 2 / 1 | 80% |
  | settlement | 5-14  | 1-2   | 2 / 1 | 70% |
  | town       | 15-49 | 1     | 2 / 1 | 45% |
  | city       | 50+   | 1     | 2 / 1 | 45% (= town for first rollout) |

- `fnc_setupLightMilitaryGarrison` — small armed garrison from the
  controlling side's foot-infantry pool. Uses combat activation
  (FiredNear EH) and the new `garrison_light` skill profile (softer than
  `cqb_baseline` — slow reactions, wide spread). Gate: `controlledBy ∈
  {opFor, bluFor, contested}` AND `influence ≥ 0.4`.

Both wrappers share an `anchorCount` override so the handler can
orchestrate per-cluster civ-vs-military splits. The roll matrix:

| Zone control | Civilian | Light Mil | Notes |
|---|---|---|---|
| neutral   | 100% | 0% | No military gate passes |
| bluFor    | 70% | 30% | Friendly partner occupies a house |
| opFor     | 60% | 40% | Hostile-occupied house |
| contested | 50% | 50% | Side re-rolled per cluster (opFor *or* bluFor) |

Per-cluster roll creates emergent "is that building occupied? civilians
or hostiles?" tension. A 2-anchor town can land both civ, both mil, or
one of each — and the player has no way to tell from outside.

**Camp handler** also gets a rare (~30%) indoor civilian garrison on
neutral camps to add "abandoned compound that turns out to be inhabited"
moments. Other camp control types skip the garrison pass — military
pipeline already handles them.

**Excluded by design**: `base` and `outpost` zones never spawn indoor
garrisons. Bases are deterrent territory players are meant to *avoid*,
not clear room by room.

**Files added/changed**:
- `addons/core/functions/ai/fnc_setupGarrison.sqf` — `unitPoolOverride`
  config branch (skips CfgGroups walk when supplied)
- `addons/core/functions/ai/fnc_setupGarrisonCivilians.sqf` — new
  wrapper, classMix-driven pool, CARELESS post-processing
- `addons/core/functions/ai/fnc_setupLightMilitaryGarrison.sqf` — new
  wrapper, combat-activation, `garrison_light` skill profile
- `addons/core/functions/ai/fnc_getSkillProfile.sqf` — added
  `garrison_light` profile
- `addons/core/functions/presence/fnc_initPresenceManager.sqf` — zone
  hashmap now carries `mainStructures` / `sideStructures` (anchor
  selection needs them)
- `addons/core/functions/presence/fnc_presenceHandlerPopulatedArea.sqf`
  — orchestrates per-cluster civ/mil split
- `addons/core/functions/presence/fnc_presenceHandlerCamp.sqf` — rare
  neutral-camp civilian garrison

**Budget impact**: ~2-4 added units per typical zone, gated by the
spawn-chance roll (≈55% of populated zones add nothing). Cities held
flat to town levels intentionally for first observation pass; will be
dialed down separately if perf degrades.

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
| `addons/core/functions/presence/fnc_presenceHandlerPopulatedArea.sqf` | Civilians + military overlay + skirmish + irregular overlay (pause lifecycle, 120s) |
| `addons/core/functions/presence/fnc_presenceLogTimings.sqf` | Per-call timing aggregation |
| `addons/core/functions/ai/fnc_setupCivilians.sqf` | Civilian peds with CARELESS waypoints |
| `addons/core/functions/ai/fnc_setupStaticDefenses.sqf` | Tower + bunker defenders, marksman-preferred pool |
| `addons/core/functions/ai/fnc_setupMortarEmplacement.sqf` | Mortar tube + crew |
| `addons/core/functions/ai/fnc_setupContestedSkirmish.sqf` | West-side opposing patrol for contested zones |
| `addons/core/functions/ai/fnc_resolveIrregularOverlay.sqf` | Armed-civilian patrol for neutral-influence zones (east-side, hostile to player) |
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
9. **Sprint A** — Handler registry refactor (mechanical, no behavior change)
10. **Sprint B** — Per-handler tuning: 8s tick, asymmetric hysteresis bands, 150u/40v budget, active-duration log
11. **Sprint C** — PAUSED state + freeze/resume lifecycle (populatedArea, camp, outpost); base stays delete
12. **Tangent (post-C)** — Irregular overlay fills neutral-influence populated areas and camps with a small armed-civilian patrol, force-east-side for player hostility
13. **Sprint D** — Functional location tags (`industrial_zone`, `commercial_hub`, `port_zone`, etc.) + `primaryFunction` from scanner; populatedArea civilians now flavored by zone character via weighted `classMix` (new `civilian_worker` resolver); indoor garrison layer adds per-cluster civilian-vs-light-military roll on populated areas + rare civilian garrison on neutral camps (`fnc_setupGarrisonCivilians`, `fnc_setupLightMilitaryGarrison`, `garrison_light` skill profile)

## Sprints Up Next

- **Sprint E** *(separate subsystem)* — Roving entities (civilian vehicles, mil patrols, boats)
