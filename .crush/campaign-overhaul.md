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

## 11. Resolved Design Decisions (owner-approved, August 2026)

These were the Phase 0/1 open questions; the project owner has ruled on all five.
They are now **design constraints**, not options.

1. **A failed mid-series mission fails the branch — the subject *diverts*, it does
   not soft-retry.** A blown DA doesn't respawn the same compound; the HVI / cache
   / convoy / hostage **relocates** and re-enters the intel pipeline as a future
   lead. Mechanically: on failure the thread emits a *diversion event* — the
   subject's live intel tokens are invalidated (or knocked down to low confidence
   with a new candidate area), and a re-find beat is queued to fire *later*, not
   immediately. This models real SOF: you tipped your hand, the target went to
   ground, and you have to re-develop the picture. It also naturally paces the
   campaign — failure injects a recon lull instead of a frustrating instant redo.
   *Design note:* the diversion should feel like consequence, not punishment —
   the re-find is new content (a fresh area, degraded intel), and the subject may
   surface via a body-search or civ-tip mid-way through unrelated tasking.

2. **Intel is per-deployment.** The ledger is created with the deployment and
   dies with it; decay (`expiresAt`) handles staleness within a deployment. No
   cross-deployment intel carryover for MVP. (A future "campaign continuity"
   feature could seed a new deployment with a few faded tokens, but that is out
   of scope and must not complicate the per-deployment model.)

3. **Always wrap missions in a thread — even the "random" ones.** There is no
   pure-random fallback path in the final design; when no *narrative* thread is
   active, the arbiter starts a lightweight **one-off thread** (a single mission
   with its own minimal briefing + intel home). Rationale from the owner, and it's
   sound doctrine: real units in an intel lull get *tasked with other things* —
   presence patrols, cordon support, a target of opportunity — while the network
   picture re-develops. So a one-off is not "filler," it's the between-intel
   tempo, and it can *itself* drop a lead (body-search / civ-tip) that promotes
   into the next real thread. **Implementation consequence:** briefing composer,
   intel ledger, and outcome handling never have to special-case a "thread-less"
   mission — everything always has a `DSC_activeSeries`, even if it's length-1.
   This deletes an entire class of null-checks from the arbiter.

4. **Dryhole frequency is deliberately HIGH — and a dryhole is not an empty
   objective.** Imperfect intel is a *feature*, not a failure state. A dryhole
   means the picture was wrong in an *interesting* way, and it must still be fun:
   the HVT already left but left SSE behind (a lead to the new location); the
   compound holds a lower-value target or a cache instead of the named HVI; the
   layout intel was stale so the assault goes in blind; the "undefended" site is
   actually reinforced. **Rule for authors:** a dryhole must always yield either
   (a) a fight, (b) a fresh intel token, or (c) both — never a walk to an empty
   marker and an anticlimactic auto-complete. This is what lets confidence sit
   low without feeling broken, and it's the mechanic that makes low-tier "grind"
   deployments *content-rich* rather than tedious.

5. **Tempo is a function of deployment type (unit budget + battlespace priority),
   not a free-floating dial.** `unitArchetype` sets the *starting* intel richness
   and the *quality* of objectives assigned:
   - **Tier-1 (DEVGRU/Delta):** high-quality intel delivered *now*; short threads;
     surgical one-night hits; HVT_LOCATION arrives at high confidence. The
     battlespace commander spends premium ISR on them.
   - **Tier-2 (Rangers/MARSOC/SEAL):** mixed — some HQ intel, some self-developed;
     medium threads.
   - **Lower-tier / SF long-stint (ODA):** low-quality, low-confidence objectives;
     long grind; the deployment *manufactures* its own intel through recon,
     body-search, and partner-force reporting before it can act. This is the
     9-month-teardown feel, and it falls out of the same machinery — it's just a
     lower starting `intelLevel` and a bias toward SWEEP/SSE-heavy threads.

   So the "dial" is really a **per-archetype preset bundle** (starting intel level
   + objective-quality bias + thread-length tendency + mission-pool weighting),
   authored once per unit voice. No global tuning number to balance.

---

## 12. Reality Check — This Vision vs. the Arma 3 Engine

Constructive criticism, so the scope stays *fun and shippable* rather than
aspirational. The vision is genuinely well-suited to Arma 3 — the good news
first, then the honest risks and where to cut.

### 12.1 What Arma 3 does *well* here (lean into these)

- **The intel-shapes-difficulty loop is a perfect fit.** Fuzzy markers, dryholes,
  "go in blind," troop-estimate fuzz — these are cheap in SQF (they're mostly
  *withholding* information the engine already has) and they map exactly onto how
  Arma missions already feel tense. You are not fighting the engine; you're
  gating information, which is free.
- **Text-templated briefings are ideal for Arma.** No engine limits, trivial to
  author, and the player's imagination does the heavy lifting. This pillar is
  almost pure upside.
- **You already solved the hard part.** The presence manager, C2 network, faction
  pipeline, and yielding-spawner performance discipline are the genuinely
  difficult Arma systems, and they exist and work. The campaign layer is
  *orchestration* — hashmaps, state machines, string composition — which is
  exactly what SQF is comfortable with and what stays off the render/sim
  hot-path.
- **DRO-style SSE-off-any-body is proven in Arma.** DRO ships it; it's an
  `addAction` + a hashmap write. Very low risk.

### 12.2 Where Arma 3 will fight you (design *around* these, don't fight them)

- **AI is the ceiling on every "immersion" mission type, and it's a hard ceiling.**
  This is the single biggest realism check. Several catalog types lean on AI
  behaving like competent humans, and Arma's AI does not:
  - **Special Recon / stealth (SWEEP):** `knowsAbout` and the detection model are
    binary-ish and twitchy — AI either hasn't noticed you or is laser-accurate.
    "Sneak past a patrol" gameplay is *possible* but fragile; expect to spend real
    tuning on detection thresholds, and design SWEEP so that *getting spotted
    converts the mission* rather than failing it (you already specced this — keep
    it, it's the pressure valve for bad AI perception).
  - **UW/FID partner-force AI as squadmates or the "unit doing the fighting":**
    friendly AI is Arma's weakest link. They path badly, clump, and die in the
    open. "Advise an AI squad that fights competently while you overwatch" (FID,
    JTAC, sniper overwatch) is the *highest-risk* set of mission types in the
    whole catalog. **Recommendation: treat FID/UW/SUPPORT as Phase 3+ and keep
    them *simple* — the AI element holds/patrols a small area and you plug gaps,
    rather than the AI conducting a real assault you merely support.** Don't build
    a thread that *depends* on friendly AI winning a firefight on its own.
  - **HVT surrender/flee behavior:** `setCaptive` + disabling AI is reliable;
    scripted "flee and hide among civilians" is janky (pathfinding, civilian AI).
    Keep flee behavior *coarse* — the HVT relocates to a room/building, not a
    cinematic chase through a crowd.
- **CSAR carry / escort-a-wounded-survivor:** carrying/dragging AI, AI keeping up
  while escorted, and AI in vehicles are all historically buggy. ACE helps if
  present. Keep MOVEMENT missions tolerant of AI escort jank (allow vehicle evac,
  don't require a flawless on-foot drag across 2km).
- **Convoy / ambush AI driving:** you already documented `fnc_buildRoadRoute`
  pain and vehicle-patrol dismount being deferred. Convoys that path reliably to
  a destination are non-trivial. Ambush (J) is worth it but budget for driving-AI
  frustration; prefer shorter, road-simple convoy routes.
- **Performance is a standing tax, not a solved problem.** You have excellent
  discipline (yielding spawner, dynamic sim, budgets), but *every* new layer adds
  ambient entities the player expects to interact with. The campaign layer itself
  is cheap; the risk is that "a living world" + "SSE off every encounter" + "recon
  targets everywhere" tempts you to keep more units alive at once. Hold the line
  on the presence/roving budgets — the campaign should feel bigger through
  *information and narrative*, not through more simultaneous AI.
- **No real save/continuity.** Arma SP/coop persistence is painful. Per-deployment
  intel (decision #2) is the *right* call partly *because* it sidesteps this. Do
  not let scope creep toward cross-session campaign saves — it's a swamp.

### 12.3 Mission types to prioritize vs. approach with caution

Ranked by *fun-per-engine-risk* in Arma specifically:

| Tier | Types | Why |
|---|---|---|
| **Green — build freely** | DA, CT/HR, SSE, cache interdiction, sabotage, HVT kill/capture, intel-gather/dryhole | All RAID; you already ship them; AI-as-static-defenders is Arma's strongest mode. |
| **Yellow — build, but scope AI carefully** | SR/SWEEP, sniper overwatch, ambush/interdiction, CSAR, airfield seizure/DEFEND | Fun and iconic, but each leans on a shaky AI behavior (detection, driving, escort, waves). Ship with the "convert on failure" and "keep it coarse" mitigations. |
| **Red — defer & keep minimal** | UW train-up, FID/COIN advise, JTAC pairing, VBSS/maritime | Depend on *competent friendly AI* and/or assets Arma handles poorly. Huge immersion payoff *if* they work, high chance of feeling broken. Do them last, keep the AI's job trivial, never make a thread *require* them. |

### 12.4 The honest bottom line

**The vision is realistic for Arma 3 — with one reframe.** The parts that make
this special (the *why*, the intel economy, the branching narrative, the
deployment identity) are all **information and orchestration**, which Arma
handles beautifully and cheaply. The parts that are risky are the ones that ask
**Arma's AI to be a competent human teammate or a stealthy adversary**, which it
isn't. So the winning strategy is: **let the campaign layer carry the immersion,
and let the moment-to-moment gameplay stay in Arma's wheelhouse — assaulting
static-ish defenders with good intel-driven setup.** A DEVGRU one-night raid with
a sharp, intel-shaped briefing and an SSE that opens the next thread is *both*
maximally fun *and* squarely inside what the engine does well. Chase that first;
treat FID/UW/maritime as ambitious garnish, not load-bearing pillars.

One concrete cut to protect the fun: **do not let "realism" push you toward
mission types whose fun depends on friendly AI competence.** The single fastest
way to make this feel broken is a signature UW mission where the partner force
faceplants. Model those relationships through *intel, briefing, and light
scripting* (the partner force "reports" a lead; a friendly element "secured" an
area off-screen) far more than through actual AI-vs-AI firefights the player
watches. Immersion sold through tasking text and consequence is bulletproof;
immersion sold through AI theater is at the mercy of the engine.

---

## 13. Objective Abstraction — Interaction Sites over Scattered Objects (approved)

Owner proposal (August 2026): stop building cache/intel/SSE objectives by
scattering physical objects (ammo boxes, laptops) at `buildingPos`, and instead
define the objective as a **trigger/area sized to the structure or site plus a
player action** ("Conduct SSE", "Verify Cache"). Physical objects become
*optional set-dressing* (Zeus, Eden Interiors, hand-placed compositions), never
the load-bearing mechanic. **Agreed — with refinements below. This supersedes
the object-scatter default in `mission-archetypes.md`.**

### 13.1 Why this is the right call

The object-scatter approach fights the engine at exactly the point the reality
check (§12) warns about — it depends on finicky engine features for its *core
mechanic*, not its flavor:

- `buildingPos -1` returns `[]` for non-enterable buildings, so placement
  silently fails on huge swaths of the map (documented gotcha).
- Objects clip, float, fall through floors, get knocked around by explosions,
  and require per-object collision rejection.
- Interior placement is fiddly per-building and varies wildly by mod.
- Mass `createVehicle` is a frame-spike source needing yield discipline.
- Completion polls object state, which is fragile (an object deleted by an
  explosion reads the same as one destroyed on purpose).

The interaction-site model leans on Arma's **most robust** primitives instead —
triggers, `addAction`, distance checks — the same category of "withhold/gate
information and interaction" work that §12.1 flagged as pure upside. It is also
**building- and mod-agnostic by construction**: any structure or area works,
because the objective is "do the action *here*," not "touch *this* object."

### 13.2 The model — "interaction site" as a first-class objective primitive

Generalize cache / intel / SSE / sabotage / dryhole into one archetype:

```
interactionSite = createHashMapFromArray [
  ["pos",           _sitePosition],        // structure center or area anchor
  ["radius",        _r],                    // sized to the structure/compound
  ["action",        "Conduct SSE"],         // player-facing verb
  ["duration",      [20, 60]],              // hold/timer — tension, QRF pressure
  ["onComplete",    { /* grant intel token / mark destroyed / etc. */ }],
  ["dressing",      ""],                     // OPTIONAL Eden composition / Zeus spawn
  ["requireCount",  [1, 1]]                  // N-of-M sites for movement missions
]
```

**No completion gate — deliberately.** The action is available whenever the
player is in range; clearing the site first is the *smart* play, but that's the
player's call, not a scripted precondition. This is a direct application of the
"build smart around AI" principle (§12): an `AREA_CLEAR`-style gate would hand a
single stray defender — one AI clipped into terrain, stuck on a ladder, or lost
under a building — the power to soft-lock the entire objective. We never let AI
state block mission progress. The only availability condition is distance to the
site (§13.3); risk from remaining enemies is emergent (they can interrupt or kill
you mid-search), never a hard lock.

Completion is "action fired" (clean, event-driven), not "object destroyed"
(polled, fragile). This slots straight into the existing `completionExpr` system
and `fnc_buildMissionOutcome`.

### 13.3 Refinements (the "better way" details)

- **Put the action on the player, gated by distance** (`player distance _site <
  radius`), *not* on a placed object — this avoids `buildingPos`/object placement
  entirely. Optionally add an inside-building or LOS check. One cheap per-frame
  condition, no spawned entity, works in any structure.
- **Make it timed** (hold action or a "searching…" timer). Instant pickup is
  weak; a 20–60s exploitation window creates real tension and lets the QRF/C2
  response matter. This is more fun *and* simpler than object interaction.
- **N-of-M sites** force movement across a compound without scattering props —
  "search 2 of 3 buildings," "verify both cache points." One trigger per site.
- **Destroy/"Verify Cache-and-deny" variant** = a "Plant Charge" action → scripted
  explosion FX + `setDamage` on any dressing present. No real destructible object
  required; if a composition *is* present, blow it for the money shot.
- **Progressive enhancement, three tiers, all optional above the first:**
  1. **Abstract (default, always works):** trigger + action, zero objects.
  2. **Focal prop (cheap middle ground):** a *single* hero object at the site
     anchor (one laptop / one crate) — trivial, no collision-rejection scatter,
     gives the player something to look at. Optional.
  3. **Composition (force multiplier):** an Eden/Zeus interior composition via the
     archetype's `dressing`/`compositionPath` field. This is exactly the deferred
     "Eden Composition Integration" already noted in `mission-archetypes.md` — the
     abstraction is what makes it a clean opt-in rather than a rewrite.
- **Markers tie into the intel pillar:** with `AREA_LAYOUT` intel you get the
  precise "search here" marker on the right building; without it you get a broad
  "SSE somewhere in this area" circle and must sweep. Free difficulty gradient,
  no extra content.

### 13.4 Unifies the intel economy (bonus, not incidental)

The **body/site search on any encounter** intel source (§4.3 #2) is *the same
interaction-site pattern* — a "Search" action gated by distance to a dead group,
firing an `onComplete` that grants tokens. Building the interaction-site
primitive once gives you mission-site SSE *and* world-encounter SSE from one code
path. This is a real simplification of Pillars 1 and 3 together.

### 13.5 What changes in the plan

- **Demote, don't delete, the object-placement strategies.**
  `fnc_placeInterior` / `fnc_placeOnGround` / `fnc_placeOutdoorPile` /
  `fnc_placeObjects` stay available as the *focal-prop* and *legacy* tiers, but
  the **default** for cache/intel/SSE objectives becomes the abstract interaction
  site. Entities that genuinely must be physical (HVTs, hostages — units, not
  props) are unaffected; they keep `fnc_placeInDeepBuilding`.
- **Add an `INTERACTION_SITE` completion/objective archetype** and route
  `SUPPLY_DESTROY` / `INTEL_GATHER` / SSE tack-ons through it. This is a small
  addition, not a rework — the raid generator already dispatches by archetype.
- **Fold into the §8 foundation work:** build the interaction-site primitive
  alongside the SWEEP archetype and the Intel Ledger, since all three share the
  action→token seam.

### 13.6 Honest cost (so it's a real decision, not a rubber stamp)

A purely abstract site — an empty Arma room you "search" with nothing in it — can
feel hollow. Mitigations: (1) the fiction carries it (a sharp intel-shaped
briefing makes "exploit the site" meaningful even in a bare room); (2) most Arma
buildings already have some interior clutter; (3) the focal-prop tier is one
cheap object away from tangible; (4) the composition tier makes it rich wherever
you invest the authoring time. The key insight: **tangibility becomes an
*optional quality layer* you can add per-site over time, instead of a mandatory
problem you must solve before the mission type works at all.** That is exactly
the "workable now, expandable later" tradeoff you're after, and it keeps the core
mechanic off the engine's fragile paths.

**Verdict:** adopt the interaction-site model as the default; keep object
placement as opt-in dressing. Simpler to ship, more robust, mod-agnostic,
strengthens the intel economy, and expansion (Eden/Zeus interiors) becomes
additive rather than blocking.

---

*This document is the scope-of-vision reference. As pillars ship, fold their
"LIVE" status back into `.crush/roadmap.md` and add per-system detail docs
(e.g. `.crush/intel-ledger.md`, `.crush/mission-series.md`) the way the existing
subsystems each earned one.*
