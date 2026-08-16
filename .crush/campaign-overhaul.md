# Campaign Overhaul — Road to MVP

*Status: **PLANNING** (August 2026). This is the master design doc for the
"deployment / mission-series / simulated-intel / dynamic-briefing / basing"
overhaul. It captures the full scope of intended variety so future agents can
build it up incrementally. No code has been written for this yet.*

> Read `.crush/mission-archetypes.md`, `.crush/mission-generation.md`,
> `.crush/c2-network.md`, `.crush/presence-manager.md`, and the
> `docs/Dynamic_SOF_Mission_Catalog.md` before working from this plan — this
> doc assumes they are the ground truth for what already exists.

---

## 0. The One-Paragraph Vision

Today the mission loop is a dice roll: pick a type, pick a variation, spawn it,
wait for debrief, score, repeat. The overhaul wraps that same loop in **three
new layers that supply the "why"**: a **Deployment** (who you are, where you
operate from, what campaign you're prosecuting), a **Mission Series** (an
ordered/branching thread of missions that advance one storyline), and a
**Simulated Intel** ledger (a persistent store of what you know, fed by SSE and
every encounter, that *unlocks* series steps, *shapes* how hard each mission is,
and *feeds* dynamically-composed paragraph briefings). Nothing about the
existing raid generator is thrown away — it becomes the bottom layer that the
new layers drive.

**The tempo the design is chasing:** a Tier-1 CT deployment with rich HQ intel
runs surgical one-night hits; a Green Beret deployment starting blind grinds a
9-month teardown out of recon, tips, and body-searched intel. Same engine,
opposite feel, entirely driven by the intel state and the deployment archetype.

---

## 1. Where We Are Today (honest inventory)

What already exists and is **directly reusable** — the overhaul is mostly
*orchestration on top of these*, not a rewrite:

| Capability | Function(s) | Reuse in overhaul |
|---|---|---|
| Data-driven raid generator | `fnc_generateRaidMission` + entity/object/completion archetypes | The bottom layer. New mission types = data. |
| Template → resolver pipeline | `fnc_selectMission` → `fnc_resolveMissionConfig` → `fnc_getMissionProfiles` | Series controller emits templates into this unchanged. |
| Standardized outcome | `fnc_buildMissionOutcome` → `DSC_lastMissionOutcome` | Series + intel already have a clean input. |
| Intel tokens (embryonic) | `fnc_addInteractionHandler` populates `intelTokens`; outcome carries `intelGathered` | Formalize into the Intel Ledger. |
| Briefing fragments | `fnc_createMissionBriefing` + `fnc_getBriefingFragments` | Evolve from one-liners into paragraph composition. |
| Location tagging | `fnc_scanLocations` (tags[], functionalProfile{}) | Drives both operating-base and mission-location selection. |
| Military installations + influence | `fnc_initInfluence`, base registry, `fnc_initBases` | Source of operating locations (hub/FOB/outstation/patrol-base). |
| Enemy comms + ISR | C2 network (`fnc_initC2Network`, ISR coverage, BFT contacts) | A *native intel source* — SIGINT/observation feed the ledger. |
| World simulation | Presence + Roving managers | Where "SSE off any encounter" lives — every ambient group is a potential intel source. |
| Admin/debug UI | Commander's Tablet (Mission Gen / BFT / INTEL tabs) | Home for Deployment status, Series tracker, Intel browser panels. |
| Mission queue hook | `DSC_missionQueue` in the loop | Series controller pushes templates here (or replaces the arbiter). |

What is **missing** and must be built (the five pillars):

1. Special-operations mission-type breadth (only 4 RAID variants exist; SWEEP /
   DEFEND / MOVEMENT archetypes are unbuilt).
2. Any notion of a **series** (missions are independent dice rolls).
3. A persistent, queryable **Intel Ledger** with a real token schema and an
   API; intel that actually *shapes* a mission's difficulty and presentation.
4. **Paragraph briefings** with unit-voice flavor and intel-driven inserts
   (current briefings are single-line fragments).
5. A **Deployment / basing** layer that ties unit archetype + operating
   location + campaign thread together and makes the map's installations matter.

---

## 2. The Unifying Data Model

Everything the five pillars need collapses into **four nested state objects**
plus one cross-cutting ledger. Getting these shapes right *now* is "what needs
to change" — once they exist, every pillar grows as pure content.

```
DSC_deployment                (1 active; the campaign root)
├─ unitArchetype              "DEVGRU" | "SF_ODA" | "RANGER" | "MARSOC" | "SEAL" | "AFSOC" ...
├─ homeLocationId             an installation from the influence/base registry
├─ homeLocationType           "HUB" | "FOB" | "OUTSTATION" | "PATROL_BASE"
├─ intelLevel                 starting intel richness (drives tempo)
├─ supportAssets              what infil/CAS/UAV the archetype can call
├─ threads[]                  active + queued narrative threads
└─ history[]                  completed series outcomes (for callbacks)

DSC_activeSeries              (0-N; the "why" for the current run of missions)
├─ threadType                 "DISMANTLE_CELL" | "HVI_MANHUNT" | "UW_INSURGENCY" ...
├─ stages[]                   DAG of stage defs (entry conditions, mission template)
├─ stageIndex / branchState   where we are; how we got here
├─ subjectRefs                the faction/location/entity this thread is about
├─ narrative                  overarching briefing thread + beat callbacks
└─ intelRequirements          which ledger tokens gate the next stage

<mission>                     (the existing per-mission hashmap — unchanged shape)
└─ …emits DSC_lastMissionOutcome as today

DSC_intelLedger               (cross-cutting, persistent for the deployment)
└─ tokens[]                   see §4 for the token schema
```

Design rule: **each layer only reads the layer below via its already-existing
standardized surface.** Series reads `DSC_lastMissionOutcome` (exists) and the
Intel Ledger. Deployment reads series `history`. The mission generator never
needs to know a series or deployment exists — the arbiter hands it a template,
exactly like the tablet queue does today. This keeps the raid generator
decoupled and lets each pillar ship independently.

---

## 3. Pillar 1 — Special-Operations Mission Types

**Principle already established in `mission-archetypes.md`: mission types are
configurations, not generators.** The work is (a) build the three missing
*archetypes* (RAID exists; SWEEP / DEFEND / MOVEMENT do not) and (b) express the
catalog's 17 mission types as data on top of them.

### Archetype → catalog-type mapping

| Archetype | Build status | Catalog types it covers |
|---|---|---|
| **RAID** (single AO, attacker) | LIVE | DA, CT/HR, SSE, HVT-capture, sabotage, cache interdiction, VBSS-clear |
| **SWEEP** (multi/large AO, observer→optional engage) | **BUILD FIRST** | Special Recon, Show-of-Force patrol, search & cordon, sniper overwatch, combat-diver recon |
| **MOVEMENT** (path A→B with attached entity/object) | build | CSAR carry-out, HVT exfil, convoy escort, ambush/interdiction, infil-as-mission |
| **DEFEND** (single AO, defender, waves) | build | Airfield seizure hold-phase, FID overwatch, protect-VIP, UW train-up defend |
| **SUPPORT** (player enables an AI element) | build (can lean on DEFEND/SWEEP) | FID/COIN advise, JTAC/CCT, sniper overwatch pairing |

**Priority order for MVP:** SWEEP first — it is the intel-production engine
(recon feeds the ledger, which unlocks the DA), and it is the missing half of
every "find, then finish" series. MOVEMENT second (CSAR + ambush are
high-value, self-contained). DEFEND / SUPPORT after the series loop is proven.

### SWEEP archetype design notes (the important new build)

- Player is placed/inserted at a vantage or search area; the objective is
  *information*, not a body count. Completion conditions are new: `OBSERVED`
  (line-of-sight + dwell timer on the objective while `knowsAbout` stays below a
  compromise threshold), `AREA_SWEPT` (visit N sub-points), `TARGET_IDENTIFIED`
  (PID a specific unit/object).
- **Detection is a complication, not an instant fail** (per catalog B). Getting
  spotted degrades the intel yield and can *convert* the mission (SWEEP → RAID
  or SWEEP → exfil-under-pressure). This conversion is the same series machinery
  from Pillar 2, fired mid-mission.
- **Every SWEEP produces intel tokens on success** — this is the seam that makes
  "find" missions matter. Yield scales with dwell time, proximity, and staying
  undetected.
- Reuses `fnc_populateAO` for the observed force and the existing compound
  markers — but markers are drawn *from* the intel gained, not handed out free
  (see Pillar 3 blind-assault mechanic).

### Faction-agnostic composition

Already solved — the faction pipeline (`fnc_extractGroups` / `fnc_extractAssets`
/ role sides normalized at `initServer`) means every new mission type is
mod-agnostic by construction. New types must *not* hardcode classnames; they
pull from `DSC_factionData` role pools exactly like the raid generator does.

### Variety bank to author over time (Pillar 1)

Per catalog, each type gets randomizable axes so no two instances feel alike:
time of day, enemy alert posture (static / patrolling / reinforced), infil
method (HALO / heli / boat / ground / foot), presence-vs-absence of a named
target (dryhole chance), civilian-presence ROE constraints, weather/visibility
modifiers, QRF responsiveness, secondary SSE tack-on. These axes are already
partly expressed as template fields — extend the template vocabulary rather than
adding branches.

---

## 4. Pillar 3 — Simulated Intel (the keystone)

Intel is the connective tissue for all five pillars, so it is specified in the
most detail. **Build this early** — series unlocking, briefing flavor, and
mission difficulty all read from it.

### 4.1 Token schema

```
intelToken = createHashMapFromArray [
  ["id",          "<uid>"],
  ["type",        "HVT_LOCATION"],   // see type catalog below
  ["subjectKind", "ENTITY|LOCATION|FACTION|THREAD|AREA"],
  ["subjectRef",  "<id of the thing this is about>"],
  ["confidence",  0.65],             // 0.0 fuzzy rumor → 1.0 confirmed
  ["source",      "SSE|BODY_SEARCH|RECON|HQ|CIV_TIP|SIGINT|ISR"],
  ["scope",       "AREA|LOCATION|SERIES|DEPLOYMENT"],
  ["discoveredAt", serverTime],
  ["expiresAt",    serverTime + 3600], // intel decays; stale intel misleads
  ["payload",      createHashMap]      // type-specific (grid, pattern, classname)
]
```

### 4.2 Token type catalog (author incrementally)

| Type | Payload | What it unlocks / shapes |
|---|---|---|
| `HVT_LOCATION` | candidate grids + radius | Low conf → wide search marker + dryhole risk; high conf → precise compound, HVT guaranteed. |
| `HVT_IDENTITY` | name, appearance, faction | Enables PID / capture-alive ROE; wrong-man dryhole if absent. |
| `ENEMY_STRENGTH` | garrison size band | Narrows the briefing troop estimate; high conf marks exact composition. |
| `PATROL_PATTERN` | route/timing window | Reveals patrol routes or a "gap" insertion window on the map. |
| `AREA_LAYOUT` | building/anchor map | Draws the A1/B2 compound intel markers; **absent = blind assault, markers hidden.** |
| `TACTICAL_ADVANTAGE` | asset ref (substation, back route, friendly) | Unlocks an optional map action (cut power, back-door infil, local guide). |
| `NETWORK_LINK` | next-subject ref | Reveals the next node in a series (bombmaker → financier → leader). |
| `CACHE_LOCATION` | grid | Seeds a cache-interdiction mission. |
| `QRF_POSTURE` | response profile | Predicts/relaxes the QRF that will answer contact. |

### 4.3 Intel sources (how tokens enter the ledger)

1. **SSE at mission sites** — existing interaction handler; formalize its output
   into tokens with subject/confidence instead of a bare boolean.
2. **Body / site search on *any* encounter** — a universal "Search" addAction on
   dead groups and points of interest, available from presence + roving spawns,
   not just missions. Yield scales with the searched group's relevance: a random
   patrol gives low-confidence **AREA** intel; a group belonging to the current
   mission/thread faction gives targeted **SERIES** intel. *This is the Dynamic
   Recon Operations feel the vision calls out.*
3. **Recon (SWEEP missions)** — the primary deliberate producer; yield scales
   with dwell/stealth (Pillar 1).
4. **HQ ready-made intel** — granted at deployment start and at series milestones,
   scaled by `unitArchetype.intelLevel`. Tier-1 CT starts intel-rich; SF ODA
   starts near-blind. *This single dial produces the surgical-vs-grind tempo.*
5. **Civilian tips** — Show-of-Force / presence-patrol random events drop a
   low-confidence lead that seeds the next series (catalog P).
6. **C2 / SIGINT / ISR** — the C2 network already intercepts enemy comms and
   registers observed contacts (BFT SIGINT/VISUAL). Bridge those into the ledger
   as first-class intel tokens so the existing comms sim *is* an intel source.
   (Do **not** duplicate C2's report-timer counterplay — an enemy wiped before it
   transmits should also yield no SIGINT token.)

### 4.4 How intel *shapes* a mission (the gameplay, not the lore)

The rule the whole system serves: **less intel = harder / blinder; more intel =
surgical.** Concretely, at generation time the resolver reads the ledger for
tokens matching the mission subject and modulates:

- **Objective precision** — no `HVT_LOCATION` ⇒ wide search area + real dryhole
  chance; high confidence ⇒ tight marker, guaranteed presence.
- **Map markers** — the A1/B2 compound markers are *earned* via `AREA_LAYOUT`
  intel. Blind assault = no interior markers; you clear it the hard way.
- **Threat picture** — briefing troop estimate fuzz is a function of
  `ENEMY_STRENGTH` confidence (ties into the existing fuzzy-estimate briefing).
- **Tactical options** — `TACTICAL_ADVANTAGE` tokens spawn optional pre-mission
  actions (cut the village power for a night stealth bonus; back-route infil;
  friendly guide reveals a patrol gap).
- **Series gating** — `NETWORK_LINK` / `HVT_LOCATION` confidence thresholds are
  the entry conditions on the next series stage (Pillar 2).

Intel is **consumed/spent** when it unlocks a DA, and it **decays** (`expiresAt`)
— a stale location sends you to an empty compound, which itself is content
(dryhole → re-find). This keeps intel a currency with pressure, not a checklist.

### 4.5 Minimal API to build now

`fnc_intelAdd(token)`, `fnc_intelQuery(subjectRef | type | scope)`,
`fnc_intelBest(subjectRef, type) → highest live confidence`, `fnc_intelDecay`
(tick that expires stale tokens). Persist on `DSC_intelLedger`. That is the
entire keystone; everything else reads through these four calls.

---

## 5. Pillar 2 — Mission Series ("mission series," not "missions")

A **series** is one narrative thread expressed as a small **DAG of stages**. The
roadmap already lists the hooks (`fnc_initMissionSeries`, `DSC_activeSeries`,
conditional branching) and the standardized outcome that feeds them.

### 5.1 Stage definition

```
stage = createHashMapFromArray [
  ["id", "find_bombmaker"],
  ["entryConditions", [ /* intel/outcome predicates */ ]],  // when this stage may fire
  ["missionTemplate", createHashMap],                        // fed to fnc_selectMission
  ["onSuccess", "capture_bombmaker"],                        // next stage id
  ["onFailure", "reacquire_bombmaker"],                      // branch (chase/re-find)
  ["intelReward", [ /* tokens granted on success */ ]],
  ["narrativeBeat", "<briefing thread text ref>"]
]
```

### 5.2 The arbiter (the one loop change)

Insert a `fnc_advanceCampaign` step **between** the mission loop and
`fnc_selectMission`:

```
loop:
  if DSC_missionQueue non-empty → use it            (tablet override, unchanged)
  else if DSC_activeSeries exists →
       next stage template = advanceSeries(DSC_lastMissionOutcome, intelLedger)
  else → startNewSeries(deployment) OR random fallback (today's behavior)
  → fnc_selectMission(template) → …unchanged from here down…
  after outcome:
       advanceSeries consumes DSC_lastMissionOutcome + grants intelReward
```

This is deliberately a *thin arbiter*: the entire existing generate → wait →
score → cleanup body is untouched. Random generation stays as the fallback when
no deployment/series is active, so the mod still works exactly as today if the
new layers are disabled.

### 5.3 Thread archetypes (variety bank — author over time)

| Thread | Beats (example DAG) | Intel spine |
|---|---|---|
| **DISMANTLE_CELL** (IED network) | SR find bombmaker → DA capture → SSE find financier → DA financier → DA cell leader | Each DA's SSE grants a `NETWORK_LINK` unlocking the next find. |
| **HVI_MANHUNT** | loop{ SR / patrol / tip } until `HVT_LOCATION` conf ≥ 0.8 → surgical DA | HQ intel shortcuts the loop; blind start = many beats. |
| **DISRUPT_LOGISTICS** | cache interdiction → convoy ambush (MOVEMENT) → depot sabotage | `CACHE_LOCATION` chains sites. |
| **UW_INSURGENCY** (Green Beret) | contact guerrillas → train-up (DEFEND) → joint DA → seize | grows a persistent resistance-strength campaign variable. |
| **COIN_STABILIZE** | FID patrols (SUPPORT) + react-to-attack (DEFEND) + presence | holds/raises influence in a region. |
| **CSAR_FLASH** (wildcard) | QRF interrupt: locate (SWEEP) → carry-out (MOVEMENT) under time pressure | compressed, no free loadout (catalog O/F). |
| **DECAPITATE_NETWORK** (Tier-1) | short: HQ intel → one-night DA + SSE | the surgical counterpoint to the grind. |

### 5.3.1 Branching examples (the "immersion" the vision wants)

- HVT **escaped** the DA → `onFailure` spins a *chase* re-find stage using
  `PATROL_PATTERN` intel; the escape is content, not a loss screen.
- SSE found **nothing** (dryhole) → thread inserts an extra recon beat instead of
  advancing; briefing acknowledges the cold trail.
- Partner force **decimated** in a UW train-up → rebuild stage before the joint op.
- Recon **compromised** → next stage's enemy posture escalates to "reinforced."

### 5.4 Series briefing thread

The series owns an **overarching narrative** that individual mission briefings
reference ("Following the intel recovered at Rogovo, we've traced the
facilitator to…"). This is where the campaign *feeling* is sold — the player
sees prior beats cited. Implemented via the briefing composer (Pillar 4) reading
`DSC_activeSeries.narrative` + `DSC_deployment.history` + the intel ledger.

---

## 6. Pillar 4 — Dynamic Briefings

Goal: multi-paragraph briefings with variety, per catalog Part 4, driven by
templated sentence pools + slot interpolation — **no LLM/DLL for MVP** (the
vision explicitly defers that on cost grounds; keep the seam open for a future
optional extension).

### 6.1 Structure

Compose a fixed skeleton, fill each section from a pool + slots:

```
SITUATION   — area control, faction, recent history (from influence + history)
MISSION     — the objective statement (from mission type)
EXECUTION   — infil method, ROE, tactical options unlocked by intel
INTEL       — threat estimate (fuzzed by ENEMY_STRENGTH conf) + prior-beat callbacks
SUPPORT     — available assets (from deployment.supportAssets)
```

### 6.2 The composer

Evolve `fnc_createMissionBriefing` + `fnc_getBriefingFragments` from single-line
fragments into a **sentence-bank composer**:

- Fragment banks are keyed by **(missionType × unitVoice)** so a DA reads like a
  DEVGRU tasking one deployment and a Green Beret advisory the next — *same
  mechanical mission, different voice* (catalog Part 4 is the exact spec).
- Each section pool holds 3–5 phrasings; `selectRandom` + `format` interpolates
  named slots: `%locationName`, `%targetName`, `%factionName`, `%threatEstimate`,
  `%priorBeat`, `%tacticalOption`.
- **Intel-conditioned inserts**: a line is appended only if the matching token
  exists ("Intel recovered from the previous operation has been folded into this
  tasking." / "We're going in cold — expect the layout to be unknown until you're
  inside."). This is what makes briefings feel written *for this run*.

### 6.3 Variety bank (author over time)

Per unit voice: 3–5 phrasings × 5 sections × N mission types. Start with one
voice and the four live mission types; expand as content. Named-slot vocabulary
(codenames for operations, threat adjectives, place descriptors) is a separate
interpolation pool that multiplies variety cheaply.

### 6.4 Future LLM seam (documented, not built)

Keep briefing composition behind a single `fnc_composeBriefing(context)` call so
a future optional path can swap the sentence-bank composer for a DLL/LLM call
fed the same `context` hashmap. MVP ships the deterministic composer only.

---

## 7. Pillar 5 — Deployment & Basing

Make the map's installations the *staging identity* of the campaign, per the
vision's Altis salt-flat-hub-vs-forward-outpost example.

### 7.1 Operating-location types

Derive from the existing installation/influence tiers + location tags:

| Type | Backed by | Infil / reach | Fits |
|---|---|---|---|
| **HUB** | airbase / large base | air mobility anywhere on map | Tier-1 CT, island-wide counter-terror |
| **FOB** | base | air + ground, regional | Rangers, MARSOC |
| **OUTSTATION** | outpost | limited air, tight AO radius | SF ODA long stint, HVI-in-area hunt |
| **PATROL_BASE** | camp | foot / ground, minimal | deep-territory UW, low-signature |

The deployment picks a home location whose type matches `unitArchetype`. That
choice sets the **AO generation radius**, the **default infil method**, and the
**support assets** available — so a patrol-base deployment naturally feels
smaller-radius and more foot-mobile than a hub deployment, for free.

### 7.2 Relocation (the "SOF operates from different places" beat)

Over a long campaign the deployment can **jump staging** to a forward
installation when a thread moves (e.g., HVI manhunt tracks the target into a new
region → relocate to the nearest outpost as an outstation). Relocation is a
series/deployment event that re-centres mission generation. This is high-value
immersion and cheap once operating-locations exist — defer to post-MVP but keep
the home-location as data (not hardcoded) from day one so it's swappable.

### 7.3 Player-selectable deployments (setup)

Eventually the tablet's Campaign Setup panel (already designed in
`faction-autoscan.md`) lets the player choose unit archetype + starting
installation + faction set. MVP can hardcode one deployment; the data model must
support the choice from the start.

---

## 8. What Needs to Change **Now** (the minimum foundation)

The vision's real question — the minimum for all five to coexist while allowing
step-by-step buildup. These are the *only* structural changes required before
content authoring can proceed in parallel:

1. **Intel Ledger** — `DSC_intelLedger` + the four-call API (§4.5) + token
   schema (§4.1). *Keystone; build first.* Retrofit the existing interaction
   handler and `DSC_lastMissionOutcome.intelGathered` to emit real tokens.
2. **Deployment state object** — `DSC_deployment` (§2), even hardcoded to one
   archetype + home installation at first. Nothing reads it yet except the
   arbiter and the briefing composer.
3. **Series arbiter** — `fnc_advanceCampaign` inserted in the loop (§5.2) +
   `DSC_activeSeries` + stage-DAG schema. Random generation stays as fallback.
4. **Briefing composer refactor** — `fnc_composeBriefing(context)` with
   sectioned sentence banks + intel-conditioned inserts (§6). Backwards
   compatible: existing fragments become the first entries.
5. **SWEEP archetype** — the missing mission archetype that produces intel and
   completes "find→finish" series (§3).
6. **Operating-location selection** — a resolver that picks a home installation
   from the base/influence registry and exposes AO radius + infil + support as
   data (§7.1). Deployment reads it.

Everything else in this doc is **content on top of these six seams**: more
mission types, more threads, more unit voices, more intel token types, more
briefing phrasings. None of them require re-architecting once the seams exist.

---

## 9. Suggested Build Order (phased, each phase playable)

**Phase 0 — Seams (no visible new content).**
Intel Ledger + API, Deployment object (hardcoded), series arbiter (fallback to
random so nothing breaks), briefing composer refactor (parity with today).
Ships invisible; proves the plumbing. Verify random loop still behaves.

**Phase 1 — Vertical slice (prove all five pillars coexist).**
One deployment (pick **SF_ODA** *or* **DEVGRU** to exercise the tempo dial), one
thread (**DISMANTLE_CELL**), the SWEEP archetype, intel chaining SR → DA via
`NETWORK_LINK`, paragraph briefings that cite the prior beat. This is the
smallest thing that *feels* like the vision. Playtest the "find then finish"
loop end-to-end.

**Phase 2 — Breadth of intel sources.**
Universal body/site search on presence + roving encounters; C2 SIGINT/ISR → intel
bridge; civilian tips from presence patrols; HQ ready-made intel dial. Now the
world *feeds* the campaign (the DRO feel).

**Phase 3 — Mission-type & archetype breadth.**
MOVEMENT (CSAR + ambush), DEFEND (airfield hold + UW train-up), SUPPORT
(FID/JTAC). More thread archetypes (HVI_MANHUNT, UW_INSURGENCY, CSAR_FLASH).

**Phase 4 — Deployment breadth & basing.**
Multiple unit voices with distinct pools + briefing banks + intel levels +
basing preferences; operating-location types; relocation events.

**Phase 5 — Player agency & polish.**
Tablet Campaign Setup panel (deployment selection), Intel browser panel, Series
tracker panel, present-2-3-mission-choice, save/load campaign state.

**Deferred (documented seams, not MVP):** LLM/DLL briefings; maritime/VBSS &
combat-diver (needs coastal basing + boat infil, roving boats already stubbed);
persistent cross-session campaign save.

---

## 10. Integration Landmines (respect existing systems)

- **Don't duplicate C2's counterplay.** The report-timer mechanic (a group wiped
  before it transmits produces *no* signal) must also mean *no SIGINT intel
  token*. Bridge C2 → intel as a *read*, don't fork the logic. See
  `.crush/c2-network.md`.
- **Sides are normalized once at `initServer`.** Partner-force AI squadmates for
  UW/FID must be cast through the existing role model (`bluForPartner` =
  independent, everything hostile collapses to east). Do not re-introduce
  per-mission `setFriend`. See `.crush/faction-sides.md`.
- **Intel decay ≠ C2 alert decay.** Separate clocks, separate stores. Don't
  overload C2's node alert state as intel confidence.
- **Series must honor the tablet override.** `DSC_missionQueue` (admin/debug)
  outranks series selection — keep that precedence so playtesting stays possible.
- **Outcome is the only series input.** Series reads `DSC_lastMissionOutcome` +
  the ledger; it must not reach into live mission internals. Preserve the
  decoupling that `fnc_buildMissionOutcome` already provides.
- **Presence/roving budget is finite.** SSE-on-any-encounter must not spawn extra
  entities — it attaches actions to groups the world *already* spawned.
- **Everything stays faction-agnostic.** New mission types / threads pull from
  `DSC_factionData` role pools; never hardcode classnames.

---

## 11. Open Questions (decide during Phase 0/1)

1. **Series ownership of scoring** — does a failed mid-series mission fail the
   whole series, branch, or retry? (Proposed: branch by default, thread defines.)
2. **Intel persistence scope** — per-deployment only, or across the mission-loop
   forever? (Proposed: per-deployment; decay handles staleness.)
3. **How much random?** — when no series is active, keep pure-random fallback, or
   always wrap random missions in a lightweight one-off "thread"? (Proposed:
   always wrap, so briefings/intel always have a home; a one-mission thread is
   cheap.)
4. **Dryhole frequency** — how often should stale/low-confidence intel send the
   player to an empty site? Tuning dial; too high frustrates, too low removes the
   point of intel.
5. **Tempo dial calibration** — what `intelLevel` values actually produce the
   "one-night hit" vs "9-month grind" spread without either extreme feeling
   broken?

---

*This document is the scope-of-vision reference. As pillars ship, fold their
"LIVE" status back into `.crush/roadmap.md` and add per-system detail docs
(e.g. `.crush/intel-ledger.md`, `.crush/mission-series.md`) the way the existing
subsystems each earned one.*
