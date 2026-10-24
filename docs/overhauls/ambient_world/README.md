# Ambient World Overhaul — Program Entry Point

*Planning session, October 2026. This folder **supersedes** `docs/campaign_overhaul/`.
It pursues the same end goal — a believable find-then-finish SOF campaign — by a
different route: **build the world, not the AI choreography.***

> **What this is:** a sequence of self-contained **work orders**, one per build
> session, in the same format as the campaign overhaul. Each has a paste-ready
> prompt, a definition of done, the exact docs/functions to read, and a human
> playtest checklist. The engineer drives; a fresh agent session executes one
> work order, then the session closes and the next opens.

---

## Why this program exists

The campaign overhaul was deferred after Session 6. Its exit criterion
(`DISMANTLE_CELL` runs end-to-end) was correct; the **route** was wrong. SWEEP /
OBSERVE put mission-critical progression on Arma's AI detection model, and the
AI is not reliable enough to carry it — the playtest found the player either
walked up unseen or was spotted at 800m, with nothing in between.

The diagnosis (`docs/overhauls/Mission_Type_Ramblings.md`):

> **The mission generator controls the situation. The AI contributes
> uncertainty. The player creates the tactical experience.**

So: stop asking the AI to perform. Ask the **world** to perform. A small library
of reliable objective templates, placed into an environment with enough depth and
variety that the same objective reads differently every time.

AFO and DA survive — but as **operational philosophies** (signature, posture,
spotting baseline, acceptable escalation), not as different AI scripts.

---

## Source-of-truth docs (reference them, don't duplicate them)

| Doc | Role |
|---|---|
| `docs/overhauls/Ambient_Elements.md` | **Owner's raw notes — the WHAT.** Structure tag refinement, civilian depth, OP/checkpoint direction. |
| `docs/overhauls/Mission_Type_Ramblings.md` | **Owner's raw notes — the WHY.** Design philosophy, AFO/DA, spotting profiles, compromise model. |
| `docs/campaign_overhaul/WORKFLOW_RULES.md` | The operating contract. **Still law.** Not re-written here. |
| `.crush/agentic-workflow-and-testing.md` | Test tiers, cost model, the Prompt→Setup→PlayTest→Revise loop. |
| `AGENTS.md` | Codebase conventions + the gotcha list. Non-negotiable. |
| `.crush/presence-manager.md` | The subsystem most of this program lands in. |
| `.crush/intel-ledger.md` | Survives from the campaign overhaul; Session 07 consumes it. |

**Workflow rules are unchanged.** Read `docs/campaign_overhaul/WORKFLOW_RULES.md`
at the start of every session. The laws (scope to one thing, pure functions,
Tier-1 tests alongside, `hemtt check` clean, register in `XEH_PREP.hpp`, respect
the gotcha list, plan→approve→execute) apply verbatim.

---

## Relationship to the campaign overhaul

| Campaign overhaul asset | Status in this program |
|---|---|
| Session 1 — Test harness (`fnc_runTests`, `fnc_initTestScenario`) | **Kept.** This program's Tier-1/Tier-2 gate. |
| Session 2 — Intel Ledger | **Kept.** Session 07 is its first real consumer under the new model. |
| Session 3 — Series arbiter | **Kept, dormant.** Still wraps the mission loop; ONE_OFF thread keeps working. |
| Session 4 — Briefing composer | **Kept.** Session 02's POI registry is what finally gives it something interesting to say. |
| Session 5 — Interaction sites | **Kept, load-bearing.** The informant meeting, checkpoints, and SSE all ride this primitive. |
| Session 6 — SWEEP archetype | **Stays deferred.** Code is intact and commented out at the generator. Do not revive it; its *intent* (intel-producing recon) is re-expressed as AFO objectives in Session 07+. |
| Session 7 — DISMANTLE_CELL slice | **Superseded.** Re-scoped as this program's end state. |

---

## Exit criterion

**TBD — deliberately.** The shape is *"an AFO mission success unlocks a DA
mission, and both are good"*, but the owner's call is that it is too early to
pin the exact wording until the world layer exists and has been played.

**Revisit at the close of Session 05.** By then there is a tagged world with
civilians in it, and the right exit test will be obvious. Record it in the
Decision Log when set.

Interim gate used to steer sessions 01–05:

> *Stand in a generated town and be able to tell — without opening the map —
> that it is a town and not a village, that the people in it belong there, and
> that the buildings around you have identities the mission generator could
> name in a briefing.*

---

## Session sequence

Ordering is the owner's, with Location Tagging split into two sessions (data
authoring and scanner surgery are different risks) and ambient dressing broken
out of the civilian work.

| # | Session | Owner's item | Model | Ships | Gate to next |
|---|---|---|---|---|---|
| 01 | [Structure taxonomy](session_01_structure_taxonomy.md) | 1 | **Opus scaffold → human edit → Sonnet wire-up** | Category/subtype/flag table for ~565 classes | Tier-1 invariants pass; legacy return keys still satisfy every existing consumer |
| 02 | [Location POI registry](session_02_location_poi_registry.md) | 1 | Sonnet | ✅ Per-structure POIs retained on every location + query API | Tier-1 query tests pass; scan time unchanged |
| 03 | [Map profile](session_03_map_profile.md) | 2 (prereq) | Sonnet | `fnc_getMapProfile` — per-world region, civilian/police factions, climate stub | Tier-1: every shipped map resolves; unknown world falls back |
| 04 | [Civilian classification](session_04_civilian_classification.md) | 2 | **Opus spec → Sonnet build** | Civilian archetype registry, resolver v2, pool hygiene (VR purge) | Tier-1 resolver tests pass; no VR/hologram civilians in a scan |
| 05 | [Ambient civilians](session_05_ambient_civilians.md) | 3 | **Opus spec → Sonnet build** | Tag-driven density, role-anchored behavior, night falloff, position validation, civilian-priority budget | Playtest: towns read urban, hamlets read rural, nobody in the woods |
| 06 | [Ambient dressing](session_06_ambient_dressing.md) | 3 | Sonnet | Animals (farms + isolated residential), civilian//work vehicles | Playtest: farms have livestock and a tractor |
| 07 | [POI-driven mission area](session_07_poi_mission_area.md) | 4 | **Opus spec → Sonnet build** | One-off mission built deliberately from POIs, feeding the Intel Ledger | Mission names real buildings in its briefing; token lands in ledger |
| 08 | [Spotting & compromise](session_08_spotting_compromise.md) | 5 | **Opus spec → Sonnet build** | Spotting profiles + graduated compromise model | AFO and DA runs of the same objective feel different |
| 09 | [Faction overhaul](session_09_faction_overhaul.md) | 6 | **Opus spec → Sonnet build** | TBD — map-profile-driven faction casting, police disposition | TBD |
| 10 | [Military presence rework](session_10_military_presence.md) | 7 | **Opus spec → Sonnet build** | TBD — OPs, checkpoints, deliberate placement | TBD |
| 11 | [Weather & time](session_11_weather_time.md) | 8 | **Opus spec → Sonnet build** | TBD — time of year, climate-consistent weather | TBD |
| 12 | [Actionable infrastructure](session_12_actionable_infrastructure.md) | new | **Opus spec → Sonnet build** | TBD — power/comms sabotage + hack-for-intel; completes C2 Sprint F.5 | TBD |

**Why this order:** the structure table is the keystone — POIs, civilian
placement, briefings, and deliberate military siting all read from it. Civilians
come before military because the owner's judgment is that ambient military
currently *costs* more than it gives (random gunfights, frame cost, campaign
disruption), and the SOF premise is that operations happen among people.
Sessions 09–11 are deliberately under-specified; their work orders get written
after Session 07 proves the world layer. **Session 12 is new scope** raised
while answering Q2 — it can slot any time after Session 02, and is a strong
candidate to pull forward because it completes an already-designed,
already-hooked C2 sprint (F.5) and produces the program's best AFO content.

### Non-occupiable structures are now first-class (scope change to Session 02)

Answering Q2 surfaced this. Today `fnc_scanLocations` Stage 1 **discards** every
non-enterable structure (`buildingPos -1` empty → `continue`), and Stage 4 only
re-scans them to increment category *counts*. The objects themselves are never
retained anywhere.

But `Land_Communication_F`, `Land_TTowerBig_1_F`, `Land_PowerLine_distributor_F`
and every fuel tank are exactly the things the owner wants to sabotage, hack,
and post snipers on. **Session 02 must retain non-occupiable POIs as first-class
POIs**, not counts. That is the difference between "this town has
infrastructure" and "that comms tower, right there".

---

## Key findings from the planning pass

These were verified against the code and change the shape of the work.

### Per-structure POIs are nearly free

`fnc_scanLocations` **already computes** per-structure classname, military flag,
and functional category into the function-local parallel arrays
`_structureClasses` / `_structureMilitary` / `_structureFunctional`, indexed by
`_structIndexMap` — and then **discards all of it at Stage 4**, storing only
aggregate counts (`mainCount`, `militaryCount`, `functionalProfile`) on the
location hashmap.

Session 02 is therefore *stop throwing the data away*, not *scan harder*. No
extra world query, no extra `typeOf` pass. Cost is one additional index hashmap
per location (~100–300 locations × ~10 subtype buckets). **Answer to the owner's
load question: negligible.**

### The briefing examples are currently impossible

- `Land_School_01_F` is filed under the generic `commercial` category with 40+
  shops, kiosks and hotels, and there is no sub-type axis — "the HVT has taken
  over a school" cannot be generated, because nothing can distinguish a school
  from a corner shop.
- `_func_law_enforcement` contains **exactly one** classname
  (`Land_PoliceStation_01_F`) — "the abandoned police barracks" cannot be
  generated.

> **Correction (Session 01 mini-spec pass).** An earlier draft of this document
> and of the Session 01 work order claimed `Land_School_01_F` was in *no*
> functional category at all. That is wrong — it is in `_func_commercial`
> (`fnc_getStructureTypes.sqf:775`). The real defect is the missing sub-type
> axis, as described above. The other five miscategorisations listed below were
> verified and are accurate.
- `_func_medical` has 6 entries, `_func_agricultural` has 14.

The owner's new category list fixes this by construction, which is the point.

### The "suits in the woods" bug has three independent causes

1. `fnc_setupCivilians` line ~109: when a location has fewer building positions
   than civilians, the fallback spawn is a **raw polar offset with `z=0` and no
   terrain, water, or slope validation** — civilians get flung into forest and
   onto the sea surface.
2. `fnc_resolveEntityClass`'s `civilian_suit` / `civilian_labcoat` branches take
   the **first** keyword match (not a random one), so every suit on the map is
   the same man; and both fall back to `selectRandom _pool` (an unfiltered pool
   member) when no keyword hits.
3. Isolated/remote zones run the same `fnc_resolveCivilianMix` baseline as
   towns, so a one-house hamlet draws from the same distribution as Kavala.

All three are in scope for Sessions 04/05 and should be fixed as named defects,
not discovered again.

### VR/hologram civilians are a faction-extraction hole, not a structure problem

`fnc_initFactionData`'s `_extractManPool` filters on
`scope >= 2 && faction == '<X>' && isMan == 1` and nothing else. **There is no
classname denylist anywhere in the repo.** Any `scope=2` man class assigned to a
configured civilian faction enters the pool verbatim. Session 04 adds pool
hygiene (denylist + a positive `scope == 2` public-release check) as a named
deliverable.

---

## Decisions already made (October 2026 planning session)

| # | Decision | Choice | Rationale |
|---|---|---|---|
| A1 | One program or two (ambient vs mission-layer) | **One program.** Ambient sessions first, mission-layer (spotting, compromise, AFO objective) in the back half. | The AFO objective is what *proves* the world layer is good enough. |
| A2 | Exit criterion | **TBD, revisit at close of Session 05.** Shape is "AFO success unlocks DA success". | Too early to pin wording before the world exists. |
| A3 | Relationship to campaign overhaul | **Supersedes it.** Same end goal, different route. Its shipped primitives are kept and reused. | Campaign overhaul's plan failed in execution, not in intent. |
| B4 | Taxonomy shape | **Option A** — category → subtype → per-class flags, single authored table, derived reverse indices. Flags extensible. | Author once, slice many ways. |
| B5 | Who authors the table | **Agent generates the scaffold, owner hand-corrects class by class.** | Highest-leverage agent task in the program. |
| B6 | Modded terrains | **Out of scope.** Vanilla-authoritative, same coverage posture as today. A map-scanning tool is a future project, not a keyword-heuristic feature. | Keyword heuristics would be a feature unto themselves. |
| B7 | Hand-tag scale | **~565 classes**, owner hand-checks all. Agent asks about anything genuinely ambiguous rather than guessing. | Already the existing file's scale. |
| B8 | Per-structure POIs | **Yes.** Load confirmed negligible (data already computed and discarded). | Required by the briefing examples. |
| C9 | Map profile | **Yes** — `fnc_getMapProfile` keyed on `worldName`, carrying region, civilian/police/host-nation factions, and (later) climate. | One table serves civilians, factions, and weather. |
| C10 | Civilian archetype depth | **Deep archetypes with behavior**, not just appearance. | Current state produces suits in the woods and VR holograms. |
| C11 | Scheduling ambition | **No go-to-work simulation.** Role-appropriate anchored behavior now; populated areas get quieter after dark. | Right cost/benefit line. |
| C12 | Animals | **Farms and isolated residential only.** | Avoid scope creep. |
| C13 | Civilian vehicles | **In scope**, configurable per location type. | — |
| C14 | Budget | **Civilians get priority.** Ambient military is deliberately reduced until Session 10 can justify each unit's presence. | Ambient military currently causes faction gunfights, frame cost, and campaign disruption without immersion payoff. |
| B15 (Q1) | Is `military` a category or a flag? | **Flag.** | A hangar is `airport` + `military`; a medevac HQ is `medical` + `military`. Composes instead of forcing a false choice. |
| B16 (Q2) | Infrastructure categories | **One `infrastructure` category with actionable subtypes** (`power_station`, `power_substation`, `power_distribution`, `comms_tower`, `comms_relay`, `water_facility`, `fuel_infrastructure`, `rail_station`, `lighthouse`, `solar_array`). Mission affordances are **flags + a separate effects registry**, not categories. | The catalog says what a building *is*; what you can *do* to it is a different table. Splitting `power` and `comms` into sibling categories would pollute the category axis with mission mechanics. Spawned **Session 12**. |
| B17 (Q3) | Flag vocabulary | Authored: `occupiable`, `anchor`, `satellite`, `military`, `sentry_only`, **`hvt_suitable`**, **`hostage_suitable`** (split), `ruined`, `landmark`, `infrastructure_node`, `sabotage_target`, `hackable`. Derived: `workplace`, `public_access`, `civilian_home`. | Owner: "putting a hostage in a shed seems realistic but not an HVT." |
| B18 (Q4) | Two-table authoring model | **Approved.** Subtype registry (~60 rows, fully authored) + class table (~565 rows, mostly one word per class, optional `+flag`/`-flag` overrides). | Makes 565 classes hand-checkable. |
| B19 (Q5) | Display names | **Subtype level.** | Per-class would be ~565 strings for near-zero gain. |
| C20 (Q7) | Civilian archetype depth | **Keep the full list**, including archetypes that resolve to visually identical vanilla classes. Behavior differentiates them; modded civilian factions fill in appearance. | Owner's instinct matched. |
| C21 | Mod dependency posture | **Mods must never be required.** Every archetype resolves to a generic civilian fallback that fits all scenarios; mods only improve fidelity. | Owner plays with many mods but will not gate future players behind them. |
| B22 | Fuel stations | **Move to `commercial`**, subtype `fuel_station`. The `fuel_infrastructure` subtype under `infrastructure` is reserved for bulk storage/depot classes (`Land_FuelStation_Feed_F`, tank farms). | A petrol station is a shop that sells fuel. |
| B23 | `military` is **both** a category and a flag | **Category `military`** = purpose-built structures with no civilian analogue (barracks, bunkers, guard towers, HQs, cargo/logistics houses). **Flag `military`** = affiliation, true for the whole military category *plus* crossover classes. So a hangar is `airport` + `military` flag; a bunker is category `military`. Invariant: *category `military` ⇒ flag `military`*, pinned by a Tier-1 assertion. | Q1's flag decision stands for crossover, but 119 of 127 military classes still need a physical home. The flag is what you query; the category is what the thing *is*. |
| B24 | Barracks | **Category `military`, subtype `barracks`**, flags `occupiable` + `anchor` + `hvt_suitable` + `hostage_suitable`. **Not** authored as `law_enforcement`. | A barracks is a barracks. *Who occupies it* is contextual — see B25. |
| B25 | **Affiliation is contextual, not intrinsic** | A structure's catalog entry is context-free. **Whether a barracks reads as army, police, or derelict insurgent-held is resolved at runtime from location context** (`fnc_resolveStructureAffiliation`, Session 02) using the host location's `isMilitary` / `militaryTier` / influence controller. | The owner's exact use case: the same barracks class appears both on airbases *and* as a lone compound in a city with no military installation. The catalog cannot know which; the location does. |
| B26 | Medical + decon tents | **Category `medical`, flag `military`.** 26 `MedicalTent_01_*` + 8 `DeconTent_01_*` are currently in `_mainMilitary` with **no** functional category. | Obvious home; 34 classes recovered for free. |
| B27 (S01 spec) | Subtype vocabulary size | **83 subtypes** across the 11 fixed categories. Trimmed from a 90-row draft by folding `caravan`, `ruin_shop`, `ruin_house_big`/`ruin_house_small`, `silo_industrial`, `gazebo`, `fire_escape`, `compound_wall`. | Expandable later — a new subtype is one Table 1 row plus a re-point of the affected Table 2 rows. Start narrow. |
| B28 (S01 spec) | Where Table 2 lives | **Inlined in `fnc_getStructureCatalog`**, not a separate function. | Owner's call; keeps the authored data and its derivation in one file. |
| B29 (S01 spec) | Is a shed a dwelling? | **No — `civilian_home` excludes `shed_domestic`, `garage_private`, `house_annex`, `castle`.** The *contextual* fallback ("a shed is a home if the hamlet has nothing better") is a **Session 05 consumer cascade**, not a catalog flag: prefer `civilian_home` → else `occupiable ∧ residential` → else any `occupiable`. | Mirrors B25 (context resolved at runtime) and the existing `fnc_setupGarrison` side-promotion fallback (lines 244–264). `fnc_setupCivilians` has **no** hierarchy today — it flattens every `buildingPos` into one bag — so the fallback has to be built, not preserved. |
| B30 (S01 spec) | Session 01 is not fully behaviorally invisible | **Accepted.** The legacy garrison keys (`main`/`side`/`main*`/`side*`) stay byte-identical, but `functionalLookup` **will** shift — most notably a `military` functional category appearing for the first time with ~90 classes. The exact expected delta list is §A9 of the work order. | The mandated fixes (119 orphaned military classes, fuel stations, power/water miscategorisations) cannot be made without moving categories. Pretending otherwise would make the regression playtest unreadable. |

### Deferred by owner (questions parked, not answered)

- **D — Military presence rework** (OP definition, terrain-driven siting, intel
  reveal, checkpoint interaction, what gets deleted, patrols, roving) — direction
  noted below; full discussion at Session 10.
- **E — Weather & time** — Session 11.
- **F — Faction overhaul** (incl. police as a per-mission-disposition faction) —
  Session 09.
- **G — Spotting & compromise** — Session 08.

### Owner's direction notes for deferred items (capture only — do not build)

- **OPs**: presence-manager zone type *or* mission-area element. Could be a
  primary intel target or a supporting element of a mission site, revealed via
  the Intel Ledger.
- **OP siting**: terrain-driven preferred; can land late in the plan.
- **Checkpoints**: interaction-based would be "very cool"; needs its own
  session(s).
- **Patrols**: good in their current state. Discuss later, don't touch.
- **Roving manager**: candidate to fold into the presence manager once presence
  becomes deliberate. Decide after Session 10 discussion.

---

## Status tracker

| Session | Status | Tier-1 | Playtest verdict | Notes |
|---|---|---|---|---|
| 01 — Structure taxonomy | ✅ built, hand-edit pending | `structure_catalog` suite registered (25 assertions, not yet run in-engine) | ⬜ pending (regression check — see work order's playtest checklist) | `fnc_getStructureCatalog`/`fnc_getStructureSubtypes`/`fnc_resolveStructureInfo` shipped, `fnc_getStructureTypes` reduced to a shim, `hemtt check`/`hemtt build` clean. 41 rows still carry `// REVIEW` — see `session_01_ambiguities.md`. Hand-editing Table 2 is the next step before Session 02. |
| 02 — Location POI registry | ⬜ not started | — | — | |
| 03 — Map profile | ⬜ not started | — | — | |
| 04 — Civilian classification | ⬜ not started | — | — | |
| 05 — Ambient civilians | ⬜ not started | — | — | exit criterion set here |
| 06 — Ambient dressing | ⬜ not started | — | — | |
| 07 — POI mission area | ⬜ not started | — | — | |
| 08 — Spotting & compromise | ⬜ not started | — | — | work order not yet written |
| 09 — Faction overhaul | ⬜ not started | — | — | work order not yet written |
| 10 — Military presence | ⬜ not started | — | — | work order not yet written |
| 11 — Weather & time | ⬜ not started | — | — | work order not yet written |
| 12 — Actionable infrastructure | ⬜ not started | — | — | new scope (Q2); completes C2 Sprint F.5 |

Legend: ⬜ not started · 🟨 in progress · ✅ done · ⛔ blocked

---

## Open questions

**Q1–Q5 and Q7 are answered** — see Decision Log rows B15–B19, C20, C21.
**Session 01 is unblocked and ready to run.**

Remaining, in session order:

- **Q6 (Session 03)** — How much flavor in the map profile now? Minimum is
  region + civilian factions + climate stub, but it is cheap to carry vehicle
  classes, name lists, and architecture hints while the table is being authored.
  *Recommendation: add per-session as each consumer appears — unused fields rot.*
- **Q8 (Session 04)** — Should `environmentalActors` (IDAP, UN, contractors)
  route through the same civilian archetype system (`AID_WORKER`, `JOURNALIST`,
  `CONTRACTOR`)? *Recommendation: yes, same system, different registry entries.*
- **Q9 (Session 06)** — Do animals *matter*? A barking dog raising local
  alertness rides C2's existing noise grading cleanly. *Recommendation: dressing
  only in S06; evaluate the alert mechanic in S08 where it belongs.*
- **Q10–Q13 (Session 08)** — compromise ladder tuning, whether compromise feeds
  influence/ledger, how player signature is measured.
- **Q14–Q16 (Session 09)** — narrow vs wide faction scope, per-mission faction
  disposition, map-profile override vs merge.
- **Q17–Q23 (Session 10)** — OP persistence, terrain siting, intel reveal,
  checkpoint interaction, the kill list, patrol linking, roving disposition.
- **Q24–Q27 (Session 11)** — evolving vs static weather, what time-of-year
  drives, per-deployment vs per-mission, night-ops emphasis.
- **Q28–Q31 (Session 12)** — lights-out as visual or gameplay-only, side
  objective vs standalone mission, hack yields token vs timed buff,
  destruction persistence.

---

## Classes to add in Session 01 (found during planning)

The current file has **gaps and miscategorisations** in exactly the area
Session 12 depends on. Fix while authoring:

**Missing from every array** (vanilla A3, infrastructure-relevant):
`Land_spp_Panel_F`, `Land_spp_Transformer_F`, `Land_PowerGenerator_F`,
`Land_PowerWave_pole*`, `Land_TTowerSmall_1_F`, `Land_TTowerSmall_2_F`,
`Land_Communication_anchor_F`, `Land_WaterTower_01_F`, `Land_WaterTank_F`,
`Land_Pipes_large_F`, `Land_Radar_Small_F`.

**Miscategorised:**
- `Land_CoalPlant_01_MainBuilding_F` → currently `industrial`; it is a **power
  station**.
- `Land_spp_Tower_F` → currently `industrial`; it is a **solar power plant**.
- `Land_ReservoirTank_V1_F` → currently non-occupiable `industrial`; it is
  **water infrastructure**.
- `Land_PowerPoleWooden_F` → **commented out**. Decide in or out.
- `Land_School_01_F` → in `_func_commercial`, but with no sub-type it is
  indistinguishable from a corner shop. Needs its own `school` subtype, not a
  category move.
- `Land_FuelStation_*` → currently `infrastructure`; arguably `commercial` with
  a `fuel_infrastructure` subtype. Owner's call.

Also note `law_enforcement` currently contains **exactly one** class
(`Land_PoliceStation_01_F`). Per Decision B24/B25, barracks are **not** moved
into it — they get category `military` + subtype `barracks`, and their
law-enforcement reading is resolved contextually at runtime.

### The military residue (Decision B23/B26)

**119 of 127 military classes have no functional category at all.** Only 8 are
crossover-tagged (`Land_Hangar_F` → airport, `Land_Medevac_HQ_V1_F` → medical,
and 6 control towers). Session 01 must give the other 119 a home:

| Group | Count | Category | Flag | Subtype |
|---|---|---|---|---|
| `MedicalTent_01_*` | 26 | `medical` | `military` | `field_hospital` |
| `DeconTent_01_*` | 8 | `medical` | `military` | `decon_facility` |
| `ConnectorTent_01_*` | 18 | `military` | `military` | `camp_tent` |
| Barracks (incl. `_dam_` variants) | 13 | `military` | `military` | `barracks` |
| Bunkers / pillboxes | 12 | `military` | `military` | `bunker` |
| Guard houses / boxes / towers | 10 | `military` | `military` | `guard_post` |
| Cargo houses / patrol / tower | 10 | `military` | `military` | `cargo_structure` |
| Radar components | 6 | `infrastructure` | `military` | `radar_site` |
| HQ / MilOffices / research | 6 | `military` | `military` | `command_post` |
| Misc (domes, camp house) | ~10 | `military` | `military` | various |

**52 of the 127 (41%) are tents** — one deployable field-camp kit in three
flavours. Worth a dedicated `field_camp` grouping so a mission can place or
recognise a whole camp rather than 52 unrelated classes.

Guard posts and bunkers are the natural home of the `sentry_only` flag.
