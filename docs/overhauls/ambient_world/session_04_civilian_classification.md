# Session 04 — Civilian Classification

**Owner item:** 2
**Model:** Opus spec → Sonnet build
**Ships:** An expanded civilian archetype registry with behavior intent, a
**hardcoded class→archetype table** (vanilla + a mod seam), an ethnicity /
regional casting layer, a strict-allowlist pool, and a rewritten resolver.
**Depends on:** 01 (subtypes) ✅ shipped, 03 (map profile) ✅ shipped.
**Status:** ⬜ not started — **mini-spec v2 drafted below, awaiting owner
approval.** Blocked on the one-time class dump (§A0).

> **v2 — the keyword heuristics are gone.** The first draft of this spec
> resolved archetypes by substring-matching classnames. The owner rejected
> that: *Arma 3 does a poor job with classnames when it comes to civilians*,
> and a heuristic is a permanent source of silent gaps. v2 hardcodes the
> mapping. See §A0 for why that changes the risk profile completely, and the
> v1→v2 delta table at the end of this section.

---

## Owner's stated problems

1. *"People in full suits walking around in the woods 10km from the nearest
   community."*
2. *"Hologram/VR civilians walking around everywhere."*
3. Only four archetypes exist (`civilian`, `civilian_worker`, `civilian_suit`,
   `civilian_labcoat`) and the owner wants depth **with behavior**.

### Root causes found in the planning pass

| Symptom | Cause | Fix lands in |
|---|---|---|
| VR / hologram civilians | `fnc_initFactionData`'s `_extractManPool` filters only `scope >= 2 && faction == '<X>' && isMan == 1`. Anything the engine calls a person in that faction enters the pool. | **This session** |
| Every suit is the same man | `fnc_resolveEntityClass`'s `civilian_suit` and `civilian_labcoat` branches take the **first** keyword match, not a random one | **This session** |
| Wrong-archetype civilians anywhere | All three specialty branches fall back to `selectRandom _pool` (an unfiltered pool member) when no keyword matches | **This session** |
| Specialty archetypes silently never resolve | Keyword lists are guesses against classnames that often carry no role information at all (`C_man_1`, `C_Nikos`) | **This session** |
| Civilians in the woods / on water | `fnc_setupCivilians` fallback spawn is a raw polar offset, `z = 0`, no terrain/water/slope validation | **Session 05** |
| Hamlet draws the same mix as a city | `fnc_resolveCivilianMix` baseline is uniform | **Session 05** |

### The v1 → v2 delta

| | v1 (rejected) | v2 (this spec) |
|---|---|---|
| Class → archetype | substring keyword match at runtime | **hardcoded table**, authored once per faction |
| Unmapped class | falls through to a blind `selectRandom _pool` | **never spawns**; logged once as a mapping worklist entry |
| VR / hologram exclusion | a six-token denylist, grown by guesswork | **structural** — not in the table, cannot be picked. Denylist deleted. |
| Ethnicity / region | not modelled | first-class: every row carries an ethnicity, every map region carries a mix |
| Per-class frequency | uniform | per-row weight (named story characters rare, generics common) |
| Mods | same keyword lists, hoped to match | a separate table file keyed by faction; vanilla table stays readable |
| Risk of a wrong entry | silent (keyword matches nothing, costs one fallback step) | **loud** — a Tier-1 assertion fails the build (§A8 #14/#15) |

---

## Target

### Archetype registry — `fnc_getCivilianArchetypes`

17 archetypes, each carrying **behavior intent and placement affinity**. It no
longer carries appearance data of any kind — appearance is the class table's
job (§A4).

Candidate archetype list (owner approved, unchanged from v1):
`RESIDENT`, `FARMER`, `WORKER`, `DOCKWORKER`, `SHOPKEEPER`, `OFFICE_WORKER`,
`MEDICAL_STAFF`, `CLERGY`, `TEACHER`, `FISHERMAN`, `MECHANIC`, `VENDOR`,
`LOITERER`, `TRAVELLER`, plus `AID_WORKER`, `JOURNALIST`, `CONTRACTOR` on the
`environmentalActors` role.

Behavior vocabulary (intent only; Session 05 implements):
`IDLE_ANCHORED` · `WORK_LOOP` · `WANDER_LOCAL` · `STAND_POST` · `TRANSIT`.

### Class table — `fnc_getCivilianClassTable`

`faction -> archetype -> [[class, weight, ethnicity], ...]`. Authored, not
inferred. Vanilla in one file, mods in a sibling.

### Resolver v2 — `fnc_resolveCivilianClass`

Table lookup + weighted pick, biased by the map's regional ethnic mix. Total —
never returns `""`.

### Pool hygiene — `fnc_buildCivilianPool`

Becomes a **strict allowlist**: the table *is* the pool. The scan is kept only
as evidence — anything scanned that the table doesn't map is logged once as the
mapping worklist.

---

## Open questions — all closed

| Q | Resolution |
|---|---|
| Q7 — trim the archetype list? | **Decision C20: keep all 17.** Several resolve to the same class with different *behavior*; behavior is what sells it. |
| Q8 — separate registry for `environmentalActors`? | **Decision C32: one registry, one resolver, one table.** Separation is a `roles` key on the archetype, not a second system. |
| Q9 — how are classes mapped? | **Decision C33: hardcoded tables, no keyword heuristics.** Arma classnames are not reliably descriptive for civilians. Owner call. |
| Q10 — table shape? | **Decision C34: `faction -> archetype -> rows`** (shape A), a class may appear under several archetypes. 1:1 would starve most roles — vanilla `CIV_F` is ~40 men against 17 archetypes. |
| Q11 — per-class weights? | **Decision C35: yes.** `[class, weight, ethnicity]`. Named story characters (`C_Nikos`, `C_Orestes`) rare, generics common. Cheap now, awful to retrofit. |
| Q12 — regional/ethnic casting now or Session 09? | **Decision C36: now.** The data is free at authoring time, and it is also an *intel* surface — an African or Asian HVT on Altis is meaningful information for the operator. |
| Q13 — unmapped classes? | **Decision C37: strict.** An unmapped class never spawns. This is what structurally kills the VR/hologram bug, and the one-time log is the mapping worklist for mods. |
| Q14 — mod tables? | **Decision C38: separate file**, so the vanilla table stays readable. Faction keys stubbed for RHS / 3CB / CUP / Aegis (Western Sahara contractors). |
| Q15 — `environmentalActors` scope? | **IDAP only this session.** UN / contractor factions arrive with the mods the owner runs; `CONTRACTOR` has no vanilla civilian class and resolves through its chain. |

**Deferred, recorded here so it isn't lost:** the owner's broader intent is
Antistasi-style per-faction config files mapping *every* class (not just
civilians) to roles — "there are a lot of gaps and plenty of assets get left
out with our current state". That is **Session 09 (faction overhaul)** scope.
This session establishes the table *pattern* on the civilian side; Session 09
decides whether to generalise it.

---

# Approved Mini-Spec v2 (Session 04)

*Status: drafted for approval. Sonnet scope once the §A0 dump has been pasted
in — the four function contracts, the registry table, the class table format,
the ethnic mix table, the resolution algorithm and the 30 Tier-1 assertions
below are the whole session.*

---

## §A0 — Prerequisite: the class dump (SHIPPED, run it before building)

`addons/core/functions/debug/fnc_dumpCivilianClasses.sqf` is already written
and PREP'd (`PREP_SUB(debug,dumpCivilianClasses);`). It is an **authoring
tool** — nothing calls it, it is on no runtime path.

```sqf
// Debug console, any mission:
[] call DSC_core_fnc_dumpCivilianClasses;              // all civilian-side factions
[["IDAP"], true] call DSC_core_fnc_dumpCivilianClasses; // one faction, any side
```

It walks `CfgVehicles` once for `scope >= 2 && isMan == 1`, groups by faction,
sorts, dumps to the RPT with a greppable `DSCDUMP` prefix **and copies the
whole thing to the clipboard**. Columns: `CLASS | DISPLAY | SIDE |
GENERICNAMES | IDENTITY | EDITORSUBCAT | VEHCLASS`.

**Why these columns.** `DISPLAY` is usually the single best archetype signal
(`"Fisherman"`, `"Priest"`, `"Doctor"`) and is exactly the field a classname
heuristic cannot see. `GENERICNAMES` (`"GreekMen"` / `"AfricanMen"` /
`"TanoanMen"`) is how BI itself tags ethnic variants and is far more reliable
than reading `_afro`/`_asia` out of a classname — it is the backbone of the
§A5 ethnicity column. `IDENTITY` (`identityTypes[]`, e.g.
`"Head_Greek","LanguageGRE_F"`) is the second regional signal and carries the
spoken language, which Session 09's host-nation work will want. `SIDE` makes
a miscast class visible immediately.

### Why the dump is required, and what it is *not* required for

These are different guarantees and it matters which is which:

- **Correctness** is covered by Tier-1, not the dump. Assertions #14/#15 check
  that every vanilla class named in the table actually exists in
  `CfgVehicles`, is `scope >= 2`, is `isMan == 1`, and is config-side
  civilian. A classname typed from memory that is wrong **fails the test
  suite** — it cannot ship as a silent gap. This is the single biggest
  structural improvement over v1, where a wrong keyword was invisible.
- **Completeness** is what only the dump can give. Tests cannot tell us about
  a class that exists but that nobody thought to put in the table. That is the
  owner's actual concern ("no missed gaps"), and it is a coverage question, not
  a correctness question.

So: the build session may author a provisional vanilla table from known
classnames, but it is **not done** until the dump has been reconciled against
it and the unmapped list is empty for `CIV_F`. Paste the dump into §A5.4.

---

## §A1 — Scope and non-goals

**In scope:** two new authored data registries (archetypes, class table), a
mod-table sibling, a resolver, a pool builder, a reverse-lookup helper, one
surgical delegation inside `fnc_resolveEntityClass`, one wiring change in
`fnc_initFactionData`, a 30-assertion Tier-1 suite, and three doc updates.

**Explicitly NOT in scope:**

| Non-goal | Why | Lands in |
|---|---|---|
| Implementing the behavior vocabulary (`WORK_LOOP`, `STAND_POST`, …) | Ships **intent labels only**. Nothing reads `behavior` when this session closes. | Session 05 |
| Touching `fnc_setupCivilians` — spawn positions, the polar-offset fallback, terrain/water/slope validation, waypoints, density | The "civilians in the woods / on water" defect is a Session 05 item in this work order's own root-cause table. Fixing it here means two sessions edit the same spawn loop. | Session 05 |
| Changing `fnc_resolveCivilianMix`'s weights, tag vocabulary, or output format | Its output is `classMix`, consumed verbatim by `fnc_setupCivilians`. Both get rewritten together. | Session 05 |
| Spawning civilian vehicles or animals | The `vehicles` key is an **authored seam**, not a consumer. | Session 06 |
| Overriding the faction profile's civilian faction list from the map profile | Role sides are normalized exactly once at `initServer`; faction casting is the riskiest change in the program. This session **unions**, never overrides (§A8). | Session 09 |
| Police / host-nation archetypes | `policeFaction` / `hostNationFaction` are still `""` in the map profile. | Session 09 |
| Generalising the table pattern to combat factions (the Antistasi-style config idea) | Correctly identified by the owner as a bigger job. This session proves the pattern on civilians. | Session 09 |
| Authoring real mod tables | The owner runs RHS / 3CB / CUP / Aegis. This session ships the **file and the faction-key stubs**, not guessed mod classnames. | as the owner dumps each preset |
| Consuming the ethnicity column for intel/briefings | The data and the reverse-lookup helper ship; no briefing text changes. | Session 07 / 09 |
| Density, night falloff, urban/rural mix weights | Session 05's dials; they would rot unused for a session. | Session 05 |

---

## §A2 — Deliverables at a glance

| # | File | PREP entry | Position |
|---|---|---|---|
| 1 | `addons/core/functions/data/fnc_getCivilianArchetypes.sqf` | `PREP_SUB(data,getCivilianArchetypes);` | between `getC2Archetypes` and `getCivilianClassTable` |
| 2 | `addons/core/functions/data/fnc_getCivilianClassTable.sqf` | `PREP_SUB(data,getCivilianClassTable);` | after `getCivilianArchetypes` |
| 3 | `addons/core/functions/data/fnc_getCivilianClassTableMods.sqf` | `PREP_SUB(data,getCivilianClassTableMods);` | after `getCivilianClassTable` |
| 4 | `addons/core/functions/faction/fnc_resolveCivilianClass.sqf` | `PREP_SUB(faction,resolveCivilianClass);` | between `initFactionData` and `resolveEntityClass` |
| 5 | `addons/core/functions/faction/fnc_buildCivilianPool.sqf` | `PREP_SUB(faction,buildCivilianPool);` | first in the Faction block |
| 6 | `addons/core/functions/faction/fnc_describeCivilianClass.sqf` | `PREP_SUB(faction,describeCivilianClass);` | after `buildCivilianPool` |
| — | `addons/core/functions/debug/fnc_dumpCivilianClasses.sqf` | `PREP_SUB(debug,dumpCivilianClasses);` | **already shipped** (§A0) |

Plus two edits to existing files (§A7/§A8) and the Tier-1 suite (§A9).

> **Deliverable 6 is included deliberately and is ~20 lines.** The reverse
> index (`class -> [archetypes, ethnicity, weightTotal]`) is built anyway to
> satisfy assertion #16's duplicate check, and it is the *only* thing that
> makes the ethnicity column usable later (the owner's intel point). Shipping
> the lookup now costs nothing and avoids a second pass over the same table.
> It has **no consumers this session** — same posture as `fnc_getMapProfile`
> in Session 03.

---

## §A3 — `fnc_getCivilianArchetypes` — the registry

### Contract

```sqf
/*
 * Function: DSC_core_fnc_getCivilianArchetypes
 *
 * Arguments:
 *     0: _rebuild <BOOL> - Discard the cache and recompute. Default false.
 *
 * Return Value:
 *     <HASHMAP> - archetypeKey <STRING> -> archetype <HASHMAP>.
 *                 Cached instance; treat as READ-ONLY.
 */
params [["_rebuild", false, [false]]];
```

- Pure data, cached in `missionNamespace` under
  **`DSC_civilianArchetypeCache`**. Never `uiNamespace` (the
  stale-cache-while-hand-editing failure mode in `AGENTS.md`).
- Same posture as `fnc_getStructureCatalog` / `fnc_getMapProfile`.
- **Performs no validation.** Vocabulary and cross-table integrity are checked
  by Tier-1, not at runtime.

### Required keys (schema, checked by Tier-1 as a **subset** check)

| Key | Type | Notes |
|---|---|---|
| `displayName` | STRING | Briefing noun phrase, lowercase, with article: `"a farmhand"`, matching `fnc_getStructureSubtypes`. |
| `behavior` | STRING | From the §A3.1 vocabulary. Intent only this session. |
| `anchorSubtypes` | ARRAY of STRING | Must all exist in the Session 01 catalog. May be `[]`. |
| `anchorFlags` | ARRAY of STRING | Must all be in the 15-flag vocabulary (12 authored + 3 derived). May be `[]`. |
| `outdoorBias` | NUMBER | `[0,1]`. Likelihood of being outdoors vs. inside an anchor. |
| `nightPresence` | NUMBER | `[0,1]`. Multiplier applied to density after dark (Session 05). |
| `vehicles` | ARRAY of STRING | From the §A3.2 vehicle-key vocabulary. Abstract keys, **never classnames**. May be `[]`. |
| `fallbackChain` | ARRAY of STRING | Other archetype keys, in order. Must be acyclic and must terminate (§A6). |
| `roles` | ARRAY of STRING | Non-empty subset of `["civilians","environmentalActors"]`. Decision C32. |

**There is no `keywords` key.** Assertion #10 pins its absence — if a later
pass reintroduces one, the suite goes red. That is the point of the assertion.

**Subset semantics, deliberately** — Session 05 adds density/mix fields and
Session 06 adds animal keys; an exact-key assertion would turn this suite red
for no reason. Pinned by assertion #2.

### §A3.1 — Behavior vocabulary (fixed this session, 5 values)

`IDLE_ANCHORED` · `WORK_LOOP` · `WANDER_LOCAL` · `STAND_POST` · `TRANSIT`

Intent only. **Nothing dispatches on these in Session 04.**

### §A3.2 — Vehicle-key vocabulary (fixed this session, 9 values)

`civ_car` · `civ_offroad` · `civ_van` · `civ_truck` · `tractor` · `bus` ·
`boat_small` · `ambulance` · `utility_truck`

Abstract keys. Session 06 maps them to classnames per map profile. **Do not
author a classname here** — same rule as `policeFaction` in Session 03.

### §A3.3 — The authored registry (transcribe verbatim, 17 rows)

Every `anchorSubtypes` entry below has been checked against
`fnc_getStructureSubtypes.sqf`. (The earlier draft's illustrative `"cowshed"` /
`"field"` do **not** exist — the real subtypes are `livestock_shed`, and open
farmland has none because the catalog only indexes structures.)

**Civilian role (14):**

| Key | `displayName` | `behavior` | `outdoorBias` | `nightPresence` | `fallbackChain` |
|---|---|---|---|---|---|
| `RESIDENT` | a local resident | `WANDER_LOCAL` | 0.50 | 0.35 | `[]` |
| `FARMER` | a farmhand | `WORK_LOOP` | 0.80 | 0.15 | `["RESIDENT"]` |
| `WORKER` | a labourer | `WORK_LOOP` | 0.60 | 0.25 | `["RESIDENT"]` |
| `DOCKWORKER` | a dockhand | `WORK_LOOP` | 0.85 | 0.20 | `["WORKER","RESIDENT"]` |
| `SHOPKEEPER` | a shopkeeper | `STAND_POST` | 0.30 | 0.20 | `["RESIDENT"]` |
| `OFFICE_WORKER` | an office worker | `IDLE_ANCHORED` | 0.25 | 0.10 | `["RESIDENT"]` |
| `MEDICAL_STAFF` | a medic | `WORK_LOOP` | 0.30 | 0.40 | `["OFFICE_WORKER","RESIDENT"]` |
| `CLERGY` | a clergyman | `IDLE_ANCHORED` | 0.30 | 0.10 | `["RESIDENT"]` |
| `TEACHER` | a teacher | `IDLE_ANCHORED` | 0.30 | 0.05 | `["OFFICE_WORKER","RESIDENT"]` |
| `FISHERMAN` | a fisherman | `WORK_LOOP` | 0.90 | 0.30 | `["DOCKWORKER","RESIDENT"]` |
| `MECHANIC` | a mechanic | `WORK_LOOP` | 0.60 | 0.15 | `["WORKER","RESIDENT"]` |
| `VENDOR` | a street vendor | `STAND_POST` | 0.80 | 0.10 | `["SHOPKEEPER","RESIDENT"]` |
| `LOITERER` | a local | `WANDER_LOCAL` | 0.90 | 0.30 | `["RESIDENT"]` |
| `TRAVELLER` | a traveller | `TRANSIT` | 1.00 | 0.20 | `["RESIDENT"]` |

**`environmentalActors` role (3) — Decision C32:**

| Key | `displayName` | `behavior` | `outdoorBias` | `nightPresence` | `fallbackChain` |
|---|---|---|---|---|---|
| `AID_WORKER` | an aid worker | `WORK_LOOP` | 0.70 | 0.25 | `["MEDICAL_STAFF","RESIDENT"]` |
| `JOURNALIST` | a journalist | `WANDER_LOCAL` | 0.80 | 0.20 | `["OFFICE_WORKER","RESIDENT"]` |
| `CONTRACTOR` | a contractor | `STAND_POST` | 0.60 | 0.40 | `["WORKER","RESIDENT"]` |

**Anchors and vehicles:**

| Key | `anchorSubtypes` | `anchorFlags` | `vehicles` |
|---|---|---|---|
| `RESIDENT` | `[]` | `["civilian_home"]` | `["civ_car"]` |
| `FARMER` | `["barn_large","barn_small","livestock_shed","greenhouse","grain_silo","windmill","sawmill","hunting_stand"]` | `[]` | `["tractor","civ_truck"]` |
| `WORKER` | `["factory","warehouse_big","warehouse_small","workshop","shed_industrial","processing_plant","mine_site","construction_site","storage_tank"]` | `["workplace"]` | `["civ_truck","utility_truck"]` |
| `DOCKWORKER` | `["shipyard","container_terminal","pier","crane"]` | `[]` | `["civ_truck","utility_truck"]` |
| `SHOPKEEPER` | `["shop","village_store","supermarket","kiosk","fuel_station"]` | `["public_access"]` | `["civ_van"]` |
| `OFFICE_WORKER` | `["office","hotel","rail_station","terminal"]` | `[]` | `["civ_car"]` |
| `MEDICAL_STAFF` | `["hospital","clinic","field_hospital","decon_facility"]` | `[]` | `["ambulance"]` |
| `CLERGY` | `["church","chapel","temple","mausoleum","ruin_church"]` | `[]` | `[]` |
| `TEACHER` | `["school"]` | `[]` | `["civ_car"]` |
| `FISHERMAN` | `["pier","navigation_aid","lighthouse"]` | `[]` | `["boat_small"]` |
| `MECHANIC` | `["autoshop","garage_complex","garage_private","fuel_station"]` | `[]` | `["civ_offroad"]` |
| `VENDOR` | `["kiosk","village_store","fuel_station","stadium"]` | `["public_access"]` | `["civ_van"]` |
| `LOITERER` | `[]` | `["public_access"]` | `[]` |
| `TRAVELLER` | `["rail_station","terminal","fuel_station","hotel"]` | `[]` | `["civ_car","bus"]` |
| `AID_WORKER` | `["field_hospital","clinic","warehouse_big","camp_tent"]` | `[]` | `["civ_offroad","civ_truck"]` |
| `JOURNALIST` | `["hotel","office"]` | `[]` | `["civ_offroad"]` |
| `CONTRACTOR` | `["warehouse_big","cargo_structure","command_post","hangar"]` | `[]` | `["civ_offroad"]` |

`roles` is `["civilians"]` for the first 14 and `["environmentalActors"]` for
the last 3.

---

## §A4 — `fnc_getCivilianClassTable` — the hardcoded mapping

### Contract

```sqf
/*
 * Function: DSC_core_fnc_getCivilianClassTable
 *
 * Arguments:
 *     0: _rebuild <BOOL> - Discard the cache and recompute. Default false.
 *
 * Return Value:
 *     <HASHMAP> - Cached instance, READ-ONLY. Schema:
 *       "byFaction"   <HASHMAP> faction -> archetypeKey -> ARRAY of rows
 *                               row = [class <STRING>, weight <NUMBER>,
 *                                      ethnicity <STRING>]
 *       "byClass"     <HASHMAP> class -> HASHMAP ["archetypes", ARRAY]
 *                                              ["ethnicity", STRING]
 *                                              ["factions",  ARRAY]
 *       "ethnicMix"   <HASHMAP> region -> HASHMAP ethnicity -> weight
 *       "defaultFaction" <STRING> "CIV_F" — used when a faction is unmapped.
 */
params [["_rebuild", false, [false]]];
```

- Builds the vanilla table inline, then **merges
  `fnc_getCivilianClassTableMods` on top**, then derives `byClass` in one pass.
- Merge rule: a mod faction key that collides with a vanilla faction key is an
  **ERROR and the vanilla row wins** (assertion #19). Mods add factions; they
  do not silently redefine `CIV_F`.
- Cached in `missionNamespace` under **`DSC_civilianClassTableCache`**.
- Uses the copy-and-set idiom for the merge — **HashMap has no binary `+`**
  (`AGENTS.md`).

### §A4.1 — Row format

```sqf
["C_man_polo_1_F", 10, "european"]
//  ^class          ^weight  ^ethnicity
```

- **`weight`** — relative frequency *within this archetype for this faction*.
  Integer, `> 0`. No normalisation required; `selectRandomWeighted` handles it.
  Convention: generics `10`, flavourful-but-common `5`, named story characters
  (`C_Nikos`, `C_Orestes`) `1`.
- **`ethnicity`** — from the §A4.2 vocabulary. Use `"any"` for a class whose
  model carries no ethnic read (a full-body coverall, a distant-model prop
  person). `"any"` is **never filtered out** and is weighted at `1.0` in every
  region.

A class may legitimately appear under several archetypes (`C_man_polo_1_F` is
a plausible `RESIDENT`, `LOITERER` and `TRAVELLER`). It may **not** appear
twice under the *same* archetype (assertion #16).

### §A4.2 — Ethnicity vocabulary (fixed this session, 6 values)

`european` · `african` · `asian` · `tanoan` · `middle_eastern` · `any`

This is a **casting** vocabulary, not a demographic claim — it exists because
BI ships ethnic model variants (`GENERICNAMES` = `GreekMen` / `AfricanMen` /
`AsianMen` / `TanoanMen`) and because a minority-ethnicity HVT is *information*
(Decision C36). Derive each row's value from the dump's `GENERICNAMES` column
first and `IDENTITY` second; only fall back to the classname suffix when both
are empty.

### §A4.3 — Regional ethnic mix (`ethnicMix`)

Keyed on **`fnc_getMapProfile`'s `region` vocabulary** so the two tables cannot
drift. Values are relative weights, multiplied into each candidate row's weight
at resolve time.

| region | european | african | asian | tanoan | middle_eastern |
|---|---|---|---|---|---|
| `mediterranean` | 1.00 | 0.08 | 0.04 | 0.00 | 0.06 |
| `tropical` | 0.15 | 0.05 | 0.10 | 1.00 | 0.00 |
| `temperate_continental` | 1.00 | 0.03 | 0.03 | 0.00 | 0.03 |
| `temperate` | 1.00 | 0.08 | 0.08 | 0.00 | 0.05 |
| `arid` | 0.25 | 0.20 | 0.05 | 0.00 | 1.00 |
| `synthetic` | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 |

- The dominant entry is `1.00` and minorities are a small tail — that is what
  makes a minority sighting *noteworthy* rather than noise (Decision C36).
- `"any"` is implicitly `1.00` in every region and is **not** listed.
- A region whose mix zeroes every available ethnicity must still spawn
  somebody: the resolver falls back to raw class weights in that case (§A6
  step 3c). Pinned by assertion #27.
- `synthetic` (VR) is deliberately flat — the test world should exercise
  everything.
- These numbers are **feel dials, not research**. Flag them `// REVIEW` and
  expect the Tier-3 pass to move them.

### §A4.4 — The vanilla table (AUTHORED FROM THE §A0 DUMP — do not guess)

> 🔴 **This subsection is intentionally empty in the spec.** Paste the
> `DSCDUMP` output for `CIV_F` and `IDAP` here, then author the rows against
> it. Assertions #14/#15 will catch a wrong classname; nothing but the dump
> catches a *missing* one (§A0).

Authoring rules:

1. **Every** class in the dump for a mapped faction must appear in at least one
   archetype, **or** be consciously left out. There is no third state — the
   unmapped-class log (§A7) is the list that must reach zero for `CIV_F`.
2. Prefer `DISPLAY` over `CLASS` when deciding the archetype. That is the whole
   reason the dump exists.
3. `RESIDENT` is the catch-all and should be the largest list. A class with no
   obvious role is a `RESIDENT`, not an omission.
4. Reuse freely across archetypes (§A4.1). Starving an archetype to keep the
   table tidy defeats Decision C20.
5. An archetype with **no** vanilla classes is acceptable and expected
   (`CLERGY`, `DOCKWORKER`, `CONTRACTOR` likely) — it resolves through its
   fallback chain. Decision C21 is pinned structurally by assertion #30, not by
   padding the table.

### §A4.5 — `fnc_getCivilianClassTableMods`

Same `byFaction` shape, **ships essentially empty**. Its job this session is to
exist, be merged, be tested, and carry commented faction-key stubs for the
presets the owner actually runs:

```sqf
// RHS / 3CB / CUP / Aegis (Western Sahara contractors) — author from a
// per-preset DSCDUMP run, one faction at a time. See §A0.
// ["<faction classname>", createHashMapFromArray [
//     ["RESIDENT", [["<class>", 10, "european"]]]
// ]],
```

**Do not author a single mod classname this session.** A guessed mod classname
is unverifiable (assertion #14 skips classes whose faction isn't loaded, by
design — see §A9) and would read as an intentional decision later. Same rule
that produced the Session 01 phantom-classname backlog.

---

## §A5 — `fnc_describeCivilianClass` — the reverse lookup

```sqf
/*
 * Function: DSC_core_fnc_describeCivilianClass
 *
 * Arguments:
 *     0: _class <STRING>  - a CfgVehicles classname
 *     1: _table <HASHMAP> - override the class table (Tier-1 seam)
 *
 * Return Value:
 *     <HASHMAP> - ["known", BOOL], ["archetypes", ARRAY], ["ethnicity", STRING],
 *                 ["factions", ARRAY], ["displayName", STRING]
 *                 known == false for an unmapped class; every other field is
 *                 then empty/[] — never nil.
 */
```

Pure given an explicit table. One `byClass` lookup. `displayName` is the
*archetype's* display name (first archetype, which is the primary mapping),
not the config display name — it is for briefing text.

**No consumers this session.** It is the seam for the owner's intel idea
(Decision C36) and for Session 07's POI-driven briefings.

---

## §A6 — `fnc_resolveCivilianClass` — resolver v2

### Contract

```sqf
/*
 * Function: DSC_core_fnc_resolveCivilianClass
 *
 * Arguments:
 *     0: _archetypeKey <STRING>  - e.g. "FARMER". Case-insensitive.
 *     1: _context      <HASHMAP> -
 *        "faction"    <STRING>  Civilian faction to draw from. Default: the
 *                               first faction in DSC_factionData's civilians
 *                               role, else the table's defaultFaction.
 *        "region"     <STRING>  Map-profile region key. Default: the current
 *                               map profile's "region".
 *        "ethnicity"  <STRING>  Force one ethnicity ("" = use the region mix).
 *        "table"      <HASHMAP> Override the class table (Tier-1 seam).
 *        "archetypes" <HASHMAP> Override the registry (Tier-1 seam).
 *        "default"    <STRING>  Terminal class. Default "C_man_1".
 *
 * Return Value:
 *     <STRING> - A CfgVehicles classname. NEVER "" and never nil.
 */
params [["_archetypeKey", "", [""]], ["_context", createHashMap, [createHashMap]]];
```

**Pure given explicit `faction`, `region`, `table` and `archetypes`.** The only
permitted impure touches are the four defaults above, the two warn-dedup maps,
and the single `isClass` guard on the terminal return. Same posture as
`fnc_getMapProfile`'s "pure given an explicit world name".

### Resolution algorithm

```
resolveCivilianClass [_key, _context]
  _key      = toUpper _key
  _registry = context.archetypes  (default: getCivilianArchetypes)
  _table    = context.table       (default: getCivilianClassTable)
  _faction  = context.faction     (default: first civilian faction, else
                                   _table.defaultFaction)
  _region   = context.region      (default: map profile "region")
  _force    = context.ethnicity   (default "")
  _default  = context.default     (default "C_man_1")

  0. Faction resolution
     if (_faction not in _table.byFaction):
         ERROR once per distinct faction (DSC_civilianFactionUnmappedWarned)
         _faction = _table.defaultFaction        // vanilla CIV_F
         if that is also absent -> skip to step 4

  1. Archetype resolution
     if (_key not in _registry):
         ERROR once per distinct key (DSC_civilianArchetypeUnknownWarned)
         _key = "RESIDENT"
         if "RESIDENT" also missing -> skip to step 4

  2. Walk order = [_key] + archetype.fallbackChain + ["RESIDENT"]
     - pushBackUnique, so a chain already naming RESIDENT doesn't repeat it
     - hard depth cap of 8 links (defence against a hand-edit cycle)

  3. For each link, in order:
       _rows = _table.byFaction[_faction][link]          // may be absent -> next link
       if (_rows isEqualTo []) -> next link

       a. if (_force != ""):
              _rows = _rows select { (_x#2) in [_force, "any"] }
              if (_rows isEqualTo []) -> next link
          // forcing an ethnicity NEVER falls back to another ethnicity:
          // a caller that asked for an Asian HVT gets an Asian HVT or the
          // chain moves on. Pinned by assertion #26.

       b. _mix = _table.ethnicMix[_region]  (default: an all-1.0 map)
          build the selectRandomWeighted pairs:
              finalWeight = row.weight * (mix[row.ethnicity] default 1.0)
          // "any" is not in the mix table and therefore weights at 1.0

       c. if (every finalWeight == 0):
              // the region zeroes everything this archetype offers.
              // Spawn somebody rather than nobody — fall back to raw
              // class weights for this link only.
              finalWeight = row.weight

       d. return selectRandomWeighted [class1, w1, class2, w2, ...]

  4. Terminal. Nothing in the chain had rows for this faction.
     if (isClass (configFile >> "CfgVehicles" >> _default)) -> _default
     "C_man_1"                                    // literal, never ""
```

### The named defects, and exactly where each one closes

| Defect | Old behavior | New behavior |
|---|---|---|
| "Every suit is the same man" | `civilian_suit` iterated the pool and `exitWith`-ed on the **first** keyword hit | step 3d is a weighted random over the whole authored list |
| "Wrong-archetype civilians anywhere" | specialty branches fell straight to `selectRandom _pool` the moment their keywords missed | there is no blind pool pick **at all**. The walk is archetype → chain → `RESIDENT` → terminal literal. An unmapped class can never be selected. |
| "Hologram/VR civilians everywhere" | nothing excluded them | structural: they are not in the table. No denylist needed, and none ships. |
| "Specialty archetypes silently never resolve" | a keyword list that matched nothing was invisible | a mapping gap is a **logged, enumerable worklist** (§A7) |

**`selectRandomWeighted` guards.** It returns `nil` on an empty array and on an
all-zero weight array. Step 3c removes the second case; the `isEqualTo []`
checks remove the first. A `nil` classname reaching `createUnit` is a silent
no-spawn — guard every call.

### Decision C21 is pinned structurally

Steps 2–4 are the C21 guarantee: **every archetype resolves to a non-empty
classname on a vanilla-only install**, even when several resolve to the same
class. Behavior is what differentiates them (Decision C20). Assertions
#29–#30.

---

## §A7 — `fnc_buildCivilianPool` — strict allowlist

### Contract

```sqf
/*
 * Function: DSC_core_fnc_buildCivilianPool
 *
 * Arguments:
 *     0: _faction    <STRING>  - Faction being built, e.g. "CIV_F".
 *     1: _scanned    <ARRAY>   - Classnames the config scan found for this
 *                                faction. Evidence only. NOT mutated.
 *     2: _options    <HASHMAP> -
 *        "table" <HASHMAP> Override the class table (Tier-1 seam).
 *        "role"  <STRING>  Log context, e.g. "civilians".
 *
 * Return Value:
 *     <HASHMAP> -
 *        "pool"      <ARRAY> Allowlisted classnames (union of every archetype
 *                            row for this faction), deduped, authored order.
 *        "unmapped"  <ARRAY> Scanned classes absent from the table. These
 *                            NEVER spawn. This is the mapping worklist.
 *        "phantom"   <ARRAY> Table classes the scan did NOT find — i.e. the
 *                            table names something this mod load doesn't
 *                            provide. Usually a typo or a missing DLC.
 */
params [["_faction", "", [""]], ["_scanned", [], [[]]],
        ["_options", createHashMap, [createHashMap]]];
```

**This is the inversion that makes the session work.** v1 filtered a scan with
a denylist and hoped the denylist was complete. v2 ignores the scan for
*selection* entirely — the pool is the table — and uses the scan only to
produce two diagnostics.

- **`unmapped` is the mapping worklist.** For `CIV_F` it must reach `[]`
  before the session is done. For a mod faction with no table yet it will be
  the entire faction, which is correct and is exactly the list the owner pastes
  into the mod table next.
- **`phantom` is the typo detector at runtime**, complementing assertion #14's
  build-time check. A class in the table that the current preset doesn't
  provide is a `WARNING`, not an error — a DLC the owner doesn't own is a
  legitimate cause.
- **Never throws.** An unmapped faction returns `pool == []` plus one `ERROR`
  naming the faction and the scanned count; the resolver's step 0 then falls
  back to `CIV_F`.
- **Does not mutate `_scanned`** (assertion #34 — the caller reuses it).
- **Logs each distinct class once**, deduped in `missionNamespace` under
  `DSC_civilianPoolWarned`. One `INFO` per faction with the pool / unmapped /
  phantom counts; one `WARNING` per distinct unmapped class and per distinct
  phantom class. Hoist every count into a `private` before it reaches a log
  macro (`AGENTS.md`).

**There is no denylist and no config-side check in this function.** Both were
v1 mechanisms for filtering an open scan. With an allowlist they are dead
weight — a hologram cannot be selected because nobody mapped it. The config-side
rule survives only as **build-time assertion #15**, where it belongs: it now
catches *an author mistake in the table*, not a runtime surprise.

---

## §A8 — Wiring: existing files

### §A8.1 — `fnc_resolveEntityClass`: the four civilian branches

The only edit to existing mission logic, and what makes the fixes reach **every
current caller with zero call-site edits**.

| Legacy resolver key | Delegates to archetype |
|---|---|
| `civilian` | `RESIDENT` |
| `civilian_worker` | `WORKER` |
| `civilian_suit` | `OFFICE_WORKER` |
| `civilian_labcoat` | `MEDICAL_STAFF` |

```sqf
case "civilian";
case "civilian_worker";
case "civilian_suit";
case "civilian_labcoat": {
    private _legacyMap = createHashMapFromArray [
        ["civilian", "RESIDENT"], ["civilian_worker", "WORKER"],
        ["civilian_suit", "OFFICE_WORKER"], ["civilian_labcoat", "MEDICAL_STAFF"]
    ];
    private _archetype = _legacyMap getOrDefault [_resolverKey, "RESIDENT"];
    // The caller's _fallback is deliberately NOT consulted: a literal
    // fallback classname is precisely what put a CSAT officer in a Syndikat
    // compound (AGENTS.md). fnc_resolveCivilianClass is total.
    [_archetype, createHashMapFromArray [["default", "C_man_1"]]]
        call DSC_core_fnc_resolveCivilianClass
};
```

**Hard rules for this edit:**

- The four legacy keys **must keep working**. `fnc_resolveCivilianMix` emits
  them, `fnc_setupCivilians`'s `classMix` consumes them, and
  `fnc_getEntityArchetypes` uses `civilian_suit` / `civilian_labcoat` for HVTs.
  The `classMix` wire format does not change this session (§A1).
- **Do not touch** the `officer` branch, the literal-classname path, the
  `_fnc_promoteFactionUnit` helper, or the `default` ERROR branch. This is a
  narrowing, not a rewrite. The `officer` path **keeps its keyword
  heuristics** — combat-faction classnames *are* reliably descriptive, which is
  exactly the asymmetry that motivated Decision C33.
- `_fnc_civilianPool` becomes **dead on the civilian paths**. Leave it in place
  only if the `officer` path still uses it; otherwise delete it and say why in
  the commit. Do not leave an unreferenced helper behind.

### §A8.2 — `fnc_initFactionData`

Two changes, both inside the existing `_noncombatRoles` handling.

**1. Route the extracted men through the allowlist.**

```sqf
if (_role in _noncombatRoles) then {
    private _menForFaction = [_faction] call _extractManPool;   // evidence
    private _opts = createHashMapFromArray [["role", _role]];
    private _built = [_faction, _menForFaction, _opts] call DSC_core_fnc_buildCivilianPool;
    private _clean = _built get "pool";
    { _roleManPool pushBackUnique _x } forEach _clean;
    ...
};
```

Hoist every count into a `private` before it reaches a log macro — `count
(_built get "unmapped")` inside a `TRACE_n`/`INFO_n` argument breaks HEMTT's
comma counting (`AGENTS.md`).

**2. Union the map profile's `civilianFactions` into the `civilians` role.**

Before the faction loop, for `_role == "civilians"` only:

```sqf
private _profile = [] call DSC_core_fnc_getMapProfile;
private _mapFactions = _profile getOrDefault ["civilianFactions", []];
{ if !(_x in _factionList) then { _factionList pushBack _x; /* INFO */ } } forEach _mapFactions;
```

- **Union, never override.** The authored faction profile stays authoritative;
  the map profile can only *add*. Overriding is faction casting and that is
  Session 09.
- Today this is a **behavioral no-op**: every map-profile row ships
  `civilianFactions = ["CIV_F"]` and the faction profiles already list `CIV_F`.
  That is the correct risk posture — the seam exists and is exercised, and it
  starts mattering the moment Session 09 fills the table.
- This makes Session 04 the **first consumer of `fnc_getMapProfile`**, exactly
  as the Session 03 work order predicted.
- Do **not** apply the union to `environmentalActors` — the map profile has no
  field for it.

---

## §A9 — Tier-1 assertion list (`suite: civilian_class`, 34 assertions)

Registered as an inline `_testSuites set ["civilian_class", { ... }]` block in
`fnc_initServerDebug.sqf`, after the `map_profile` block. Same shape as every
existing suite: `private _results = [];`, raw `_results pushBack ["<label>",
<bool>];`, bare `_results` return, no helper. Force a rebuild once at the top
(`[true] call DSC_core_fnc_getCivilianArchetypes; [true] call
DSC_core_fnc_getCivilianClassTable;`) for a deterministic baseline, exactly as
`structure_catalog` and `map_profile` do.

### Registry integrity (10)

| # | Assertion | Why |
|---|---|---|
| 1 | All 17 expected archetype keys are present and the registry has no extras | pins the authored table |
| 2 | Every archetype carries every §A3 required key with the right type, **and an archetype with an extra key still passes** | schema guard + the C31-style growth escape hatch |
| 3 | Every `behavior` is in the 5-value §A3.1 vocabulary | typo guard |
| 4 | Every entry of every `anchorSubtypes` exists in `fnc_getStructureSubtypes` | **cross-table integrity.** Catches exactly the `cowshed`/`field` class of error. |
| 5 | Every entry of every `anchorFlags` is in the 15-flag vocabulary | typo guard across the Session 01 seam |
| 6 | Every `vehicles` entry is in the 9-key §A3.2 vocabulary | Session 06 seam stays clean |
| 7 | `outdoorBias` and `nightPresence` are NUMBER in `[0,1]` on every archetype | Session 05 multiplies by these |
| 8 | Every `fallbackChain` entry names an existing archetype key | dangling-reference guard |
| 9 | Every chain is **acyclic** and terminates, walked with a depth cap; `RESIDENT` exists and its own chain is `[]` | a `WORKER→MECHANIC→WORKER` pair would hang or silently truncate the resolver |
| 10 | **No archetype carries a `keywords` key** | **Decision C33 pinned.** If a later pass reintroduces heuristics, this goes red. |

### Class table integrity (9)

| # | Assertion | Why |
|---|---|---|
| 11 | `byFaction` has at least one faction, and every faction has at least one archetype with at least one row | the table isn't empty |
| 12 | Every archetype key used anywhere in `byFaction` exists in the registry | dangling-reference guard across the two tables |
| 13 | Every row is `[STRING, NUMBER > 0, STRING]` and the ethnicity is in the §A4.2 vocabulary | row-format guard |
| 14 | **Every class named for a LOADED faction resolves in `CfgVehicles` with `scope >= 2` and `isMan == 1`** | **the typo killer — the single highest-value assertion in this suite.** This is what makes authoring from memory safe (§A0). Classes belonging to a faction absent from `CfgFactionClasses` are skipped, so a mod table doesn't fail the suite on a preset that doesn't load it. |
| 15 | **Every class named for a loaded faction has config `side == 3` (civilian)** | catches an author mistake that would reintroduce the owner's bug from the other direction. `// REVIEW` the `3` constant. |
| 16 | No class appears twice within one archetype's row list for one faction | authoring hygiene; also validates the `byClass` build |
| 17 | `byClass` is consistent with `byFaction` — every class in a row appears in `byClass`, with every archetype it was listed under | the reverse index can't drift |
| 18 | `ethnicMix` covers every region in `fnc_getMapProfile`'s region vocabulary; every key inside a mix is in the §A4.2 vocabulary; no mix is all-zero | **cross-table integrity with Session 03** |
| 19 | A mod-table faction key colliding with a vanilla faction key is rejected (vanilla wins) and the merge is otherwise additive | `fnc_getCivilianClassTableMods` can't silently redefine `CIV_F` |

### Resolver (11)

| # | Assertion | Why |
|---|---|---|
| 20 | A known archetype + known faction returns a class **from that archetype's row list** | baseline correctness |
| 21 | Across 30 calls against an archetype with ≥3 rows, **>1 distinct value** is returned | **pins the first-hit defect closed** |
| 22 | With a 100:1 weight skew, the heavy class is returned in the clear majority over 200 calls | weights are actually applied, not ignored |
| 23 | An unknown archetype key ERRORs once and returns the `RESIDENT`-chain result (non-empty); a second call with the same key does not re-ERROR | the `unitClassResolver` gotcha class + warn-once |
| 24 | Lowercase / mixed-case archetype keys resolve identically to uppercase | the §A8.1 legacy map and any future caller |
| 25 | The fallback chain is followed **in order**: a mock faction with rows only under `OFFICE_WORKER`, queried for `MEDICAL_STAFF`, returns an `OFFICE_WORKER` row | |
| 26 | A forced `ethnicity` returns **only** rows of that ethnicity or `"any"`, and never falls back to another ethnicity within a link | Decision C36 — an Asian HVT request gets an Asian HVT or the chain moves on |
| 27 | Region biases the result: a mock table with `european` and `tanoan` rows returns a `tanoan` majority under `region = "tropical"` and a `european` majority under `"mediterranean"`; **and** a region that zeroes every available ethnicity still returns a class | §A6 step 3b + the 3c safety net |
| 28 | An unmapped faction ERRORs once and falls back to `defaultFaction`, returning non-empty | mod faction with no table yet |
| 29 | A faction present but with no rows anywhere in the chain returns `"C_man_1"`, never `""` or nil | spawn code must never receive an empty classname |
| 30 | **Every one of the 17 archetypes resolves to a non-empty classname against the real vanilla `CIV_F` table** | **Decision C21 — mods are never a requirement** |

### Pool builder + reverse lookup (4)

| # | Assertion | Why |
|---|---|---|
| 31 | `pool` for a mock faction equals the deduped union of its table rows, and a scanned class absent from the table lands in `unmapped`, **not** in `pool` | **Decision C37 — strict allowlist pinned.** A `_VR_`/`Hologram` class in the scan can never reach `pool`. |
| 32 | A table class the scan did not find lands in `phantom` and the call does not throw | runtime typo detector |
| 33 | An unmapped faction returns `pool == []` and does not throw | mod faction with no table |
| 34 | The `_scanned` input array is **not mutated**; and `fnc_describeCivilianClass` returns `known == false` with empty fields (never nil) for an unmapped class | the caller reuses the array; the reverse lookup is total |

*Assertions that loop over all 17 archetypes (or every row in the table) report
as a single labelled result whose failure message names the offending
archetype/class — do not split them 17 ways.*

---

## §A10 — Gotchas and hard constraints

- **`selectRandomWeighted` returns `nil` on an empty array AND on an all-zero
  weight array.** Both cases are handled in §A6 (the `isEqualTo []` checks and
  step 3c). A `nil` classname reaching `createUnit` is a silent no-spawn.
- **`selectRandom []` returns `nil`, not `""`.** Same rule anywhere else.
- **HashMap has no binary `+` merge.** The vanilla⊕mods merge uses the
  copy-and-set idiom: `private _r = +_vanilla; { _r set [_x, _y] } forEach
  _mods;` (`AGENTS.md`).
- **🔴 `joinSilent` after every `createUnit`.** No new spawn path ships in this
  session, but if one appears, it inherits the rule.
- **Civilians must never be C2-stamped.** Preserve the `side != civilian`
  filter at the presence dispatcher. Nothing here goes near it.
- **`setCaptive true` makes `side _unit` report CIVILIAN.** Assertion #15 reads
  the **config** side, not a live unit's side, so this cannot bite — do not
  "improve" it into a runtime `side _unit` check.
- **Don't widen `fnc_resolveEntityClass`'s contract.** §A8.1 is a narrowing.
  The `officer` path keeps its heuristics *on purpose* — combat classnames are
  descriptive, civilian ones are not. That asymmetry is Decision C33 and should
  be stated in a comment so a future pass doesn't "unify" them.
- **`fnc_resolveCivilianMix`'s output format is frozen this session.** It emits
  the four legacy keys; `fnc_setupCivilians` consumes them; the §A8.1
  delegation is what makes them better without changing the wire format.
- **CBA log macros only, never `diag_log`** — except in
  `fnc_dumpCivilianClasses`, which is an authoring tool and deliberately uses
  raw `diag_log` with a `DSCDUMP` prefix so it works at any debug tier (same
  precedent as `fnc_diagSideDump`). **Hoist every inline array literal out of a
  log macro argument.** Max `_8` suffix.
- **`#include "..\..\script_component.hpp"`** at the top of each new file.
- **Cache in `missionNamespace`, never `uiNamespace`** —
  `DSC_civilianArchetypeCache`, `DSC_civilianClassTableCache`,
  `DSC_civilianPoolWarned`, `DSC_civilianArchetypeUnknownWarned`,
  `DSC_civilianFactionUnmappedWarned`.
- **Warn/ERROR once per distinct key, never once per call.** The resolver runs
  per civilian spawn; an unbounded ERROR would flood the RPT faster than the
  presence manager spawns. Same precedent as `DSC_structureUnknownWarned`.
- **`select` over `if/then/else` for constant assignment**, and parenthesise
  any unary command inside a comparison — HEMTT lints both.
- **Do not reintroduce keyword matching on the civilian path**, in any form,
  including "just as a last resort". Assertion #10 exists specifically to make
  that attempt fail loudly.

---

## §A11 — Unverified data (the agent cannot launch Arma)

Flag these in-file with `// REVIEW`.

1. **Config `side == 3` means civilian** (assertion #15). From the standard
   `CfgVehicles` side enumeration (0 east / 1 west / 2 independent / 3 civilian
   / 4 ambient life). A wrong constant here fails assertion #15 loudly rather
   than shipping — which is the correct failure mode.
2. **The §A4.3 ethnic mix weights** are feel dials, not research. Expect the
   Tier-3 pass to move them. The *structure* is what's being approved.
3. **The §A4.4 vanilla table itself** is the §A0 item. Correctness is covered
   by assertions #14/#15; **completeness is covered only by the dump**.
4. **`civilianFactions` beyond `CIV_F`** — still the Session 03 §A9 item 3
   caveat. Do not add a second faction from memory; grow it from this session's
   `unmapped` logs.
5. **`genericNames` / `identityTypes` availability per mod.** Vanilla populates
   both reliably; a mod may leave them empty, in which case the ethnicity
   column falls back to author judgement from `DISPLAY`. Not a blocker — mod
   tables are authored one preset at a time anyway.

---

## §A12 — Definition of done

1. `fnc_getCivilianArchetypes.sqf` — §A3 contract, the 17-row table, cached,
   **no `keywords` key**.
2. `fnc_getCivilianClassTable.sqf` — §A4 contract, the vanilla table authored
   against the §A0 dump, the §A4.3 ethnic mix, the mods merge, the derived
   `byClass` index, cached.
3. `fnc_getCivilianClassTableMods.sqf` — correct shape, essentially empty,
   commented faction-key stubs for RHS / 3CB / CUP / Aegis.
4. `fnc_resolveCivilianClass.sqf` — §A6 contract and the exact step 0→4
   algorithm. Total; never returns `""` or nil. **No keyword matching.**
5. `fnc_buildCivilianPool.sqf` — §A7 strict allowlist, `pool` / `unmapped` /
   `phantom`, warn-once evidence log, no denylist.
6. `fnc_describeCivilianClass.sqf` — §A5 reverse lookup, total.
7. Six `PREP_SUB` entries at the §A2 positions (the seventh,
   `dumpCivilianClasses`, is already in).
8. `fnc_resolveEntityClass`'s four civilian branches delegate per §A8.1;
   nothing else in that file changes; no unreferenced helper left behind.
9. `fnc_initFactionData` builds non-combat man pools through the allowlist and
   unions the map profile's `civilianFactions` into the `civilians` role
   (§A8.2).
10. `hemtt check` clean.
11. Tier-1 suite `civilian_class` registered with all 34 assertions, passing.
12. **`unmapped` is empty for `CIV_F` on a vanilla run.** This is the
    completeness gate and the reason §A0 exists.
13. Docs:
    - `AGENTS.md` — key-systems rows for the new functions; new gotchas
      (the hardcoded-table / strict-allowlist model and why the heuristic was
      removed; `selectRandomWeighted` nil-on-all-zero; the officer-vs-civilian
      heuristic asymmetry).
    - `docs/overhauls/ambient_world/README.md` — status tracker row 04;
      Decisions **C32**–**C38** in the Decision Log; Q8–Q15 struck from Open
      Questions; note that Session 04 is the first consumer of
      `fnc_getMapProfile`.
    - This file — Results log appended, §A4.4 filled in with the real table.
14. **No new `DSC_testConfig` harness file.** The behavior change is
    population-wide, which a Tier-2 single-mission harness cannot show; the
    gate is the Tier-1 suite plus the Tier-3 Altis run below.

---

## Paste-ready prompt (Sonnet, to build the approved spec)

```
Read docs/campaign_overhaul/WORKFLOW_RULES.md (still law),
docs/overhauls/ambient_world/README.md, and
docs/overhauls/ambient_world/session_04_civilian_classification.md.

Implement the APPROVED MINI-SPEC V2 at the bottom of the session doc
("# Approved Mini-Spec v2 (Session 04)"). It is fully decided — the six
function contracts (§A3-§A7), the 17-row archetype registry (§A3.3), the
class-table row format and ethnicity vocabulary (§A4.1/§A4.2), the regional
ethnic mix (§A4.3), the resolution algorithm (§A6), the strict-allowlist pool
(§A7), the wiring edits (§A8) and the 34 Tier-1 assertions (§A9) are all
signed off. Do NOT re-litigate any of it and do NOT add fields that are not
in the spec.

⚠ THE SINGLE MOST IMPORTANT CONSTRAINT: there is NO keyword/substring
matching on the civilian path, anywhere, in any form, including "as a last
resort". Classes are mapped to archetypes by a HARDCODED TABLE (§A4). Arma 3
civilian classnames carry no reliable role information, which is why the
previous draft of this spec was rejected. Assertion #10 exists specifically
to fail the build if a `keywords` key reappears. The "officer" branch of
fnc_resolveEntityClass KEEPS its heuristics — combat classnames are
descriptive — and that asymmetry must be stated in a comment.

Build order:

1. addons/core/functions/data/fnc_getCivilianArchetypes.sqf — §A3 signature
   and header contract, the §A3.3 table inlined, cached in missionNamespace
   under DSC_civilianArchetypeCache with a [_rebuild] arg. fnc_getMapProfile
   and fnc_getStructureCatalog are the exemplars for cache + header style.
   NO keywords key.

2. addons/core/functions/data/fnc_getCivilianClassTableMods.sqf — §A4.5. The
   right shape, essentially empty, commented faction-key stubs only. Author
   ZERO mod classnames.

3. addons/core/functions/data/fnc_getCivilianClassTable.sqf — §A4. Vanilla
   byFaction table from §A4.4, the §A4.3 ethnicMix, merge the mods table on
   top (copy-and-set idiom; HashMap has no binary +; vanilla wins a collision
   with an ERROR), derive byClass in one pass, cache under
   DSC_civilianClassTableCache.
   ⚠ If §A4.4 is still empty when you start, author a PROVISIONAL vanilla
   CIV_F + IDAP table from classnames you are confident about and say so in
   the Results log. Assertions #14/#15 will fail the suite on any wrong
   classname, so a wrong guess cannot ship silently — but COMPLETENESS still
   requires the owner's DSCDUMP output, so leave the "unmapped must be empty"
   item (§A12 #12) open.

4. addons/core/functions/faction/fnc_describeCivilianClass.sqf — §A5. Pure
   given an explicit table. Total; known=false with empty fields, never nil.

5. addons/core/functions/faction/fnc_resolveCivilianClass.sqf — §A6 contract
   and the exact step 0→4 algorithm. Weighted pick via selectRandomWeighted.
   Guard it: it returns nil on an empty array AND on an all-zero weight array
   (step 3c is the second guard). A forced ethnicity NEVER falls back to a
   different ethnicity within a link. ERROR once per distinct unknown
   archetype key and once per distinct unmapped faction.

6. addons/core/functions/faction/fnc_buildCivilianPool.sqf — §A7. STRICT
   ALLOWLIST: the table is the pool; the scan is evidence only, producing
   "unmapped" (worklist) and "phantom" (runtime typo detector). NO denylist,
   NO config-side check at runtime — both were v1 mechanisms for filtering an
   open scan and are dead weight against an allowlist. Never throws. Does not
   mutate the input. Warn once per distinct class via DSC_civilianPoolWarned.

7. Six PREP_SUB entries in addons/core/XEH_PREP.hpp at the §A2 positions.
   PREP_SUB(debug,dumpCivilianClasses); is already present — leave it.

8. fnc_resolveEntityClass.sqf — §A8.1. Replace ONLY the four civilian case
   bodies with the delegation through the legacy-key map. Do not touch the
   "officer" branch, the literal-classname path, _fnc_promoteFactionUnit, or
   the default ERROR branch. If _fnc_civilianPool becomes unreferenced,
   delete it rather than leaving dead code. The four legacy keys MUST keep
   working — fnc_resolveCivilianMix emits them and fnc_setupCivilians
   consumes them as classMix.

9. fnc_initFactionData.sqf — §A8.2. Route non-combat man pools through
   fnc_buildCivilianPool, and UNION (never override) fnc_getMapProfile's
   civilianFactions into the "civilians" role's faction list.

10. Add the civilian_class Tier-1 suite to
    addons/core/functions/init/fnc_initServerDebug.sqf as an inline
    _testSuites set ["civilian_class", { ... }] block after the map_profile
    block — the established pattern (no per-suite file, no XEH_PREP entry).
    All 34 assertions from §A9, same [label, passed] result shape, same bare
    `_results` return, same force-rebuild-once-at-the-top structure.

11. hemtt check clean.

12. Docs per §A12 item 13.

Hard constraints:
- DO NOT touch fnc_setupCivilians. Spawn positions, the polar-offset
  fallback, terrain/water/slope validation, waypoints, density and night
  falloff are all Session 05.
- DO NOT change fnc_resolveCivilianMix — not its weights, not its tag
  vocabulary, not its output format.
- Behavior strings (IDLE_ANCHORED / WORK_LOOP / WANDER_LOCAL / STAND_POST /
  TRANSIT) are INTENT LABELS ONLY. Nothing may dispatch on them. Same for the
  vehicles key — abstract keys from §A3.2, never classnames (Session 06).
- The map-profile read is a UNION, never an override. Faction casting is
  Session 09.
- Do not invent MOD classnames anywhere. Vanilla classnames are permitted
  because assertions #14/#15 verify them; mod classnames are not verifiable
  on an arbitrary preset and are explicitly out of scope (§A4.5).
- selectRandomWeighted / selectRandom return nil, not "". Guard every call.
- HashMap has no binary + merge; use copy-and-set.
- Cache in missionNamespace, never uiNamespace. Warn/ERROR once per distinct
  key, never once per call.
- Respect the CBA log-macro comma-counting trap: hoist every inline array
  literal into a private local before passing it to LOG_n / INFO_n /
  WARNING_n / ERROR_n / TRACE_n. Max _8 suffix.
- CBA log macros only, never diag_log (fnc_dumpCivilianClasses is the one
  documented exception and is already shipped).
- Put // REVIEW on the §A11 items.

Sonnet scope — build the approved spec, do not redesign it.
```

---

## Human playtest checklist

This session changes behavior in three visible ways: specialty civilians stop
all being the same man, VR/hologram classes become structurally unspawnable,
and civilian ethnicity starts tracking the map's region.

**Step 0 (do this first, it unblocks the build):**

- [ ] Launch any mission on Altis with your **vanilla-only** preset. In the
      debug console: `[] call DSC_core_fnc_dumpCivilianClasses;` — paste the
      clipboard contents into §A4.4.
- [ ] Repeat per mod preset you care about (RHS+3CB, CUP, Aegis/Western
      Sahara) and keep each dump; those become `fnc_getCivilianClassTableMods`
      entries later, one preset at a time.

**After the build:**

- [ ] `hemtt check` clean, `hemtt build` clean.
- [ ] `test.VR` → `fnc_runTests` prints `PASS: civilian_class/*` for all 34
      assertions, and every previously-passing suite is still green (the
      `fnc_resolveEntityClass` edit is the regression risk — watch
      `briefing_composer` and `interaction_site`).
- [ ] Launch `hemtt launch developer_factions` on Altis. In the RPT find the
      new per-faction lines: one `INFO` with pool / unmapped / phantom counts
      for `civilians/CIV_F`, one `WARNING` per distinct unmapped class, one per
      distinct phantom class.
- [ ] **`unmapped` must be empty for `CIV_F`.** Anything listed is a class the
      table missed — paste it back and it gets mapped. This is the
      completeness gate (§A12 #12).
- [ ] **`phantom` should be empty on a full vanilla+DLC install.** Entries here
      are either a typo (shouldn't survive assertion #14) or a DLC you don't
      own — confirm which.
- [ ] Confirm the warnings do **not** repeat: three towns' worth of civilian
      spawns must not produce three copies of the same WARNING.
- [ ] **Zero VR / hologram civilians observed in a full Altis run.** The
      owner's reported bug and the session's headline gate.
- [ ] Walk a town with a commercial/medical character and confirm the suits and
      medics are **not all the same model** — the first-hit defect closing.
- [ ] Confirm civilians still spawn at all, in normal numbers, with CARELESS
      wander behavior. A regression in the §A8.1 delegation would show as empty
      towns or `setupCivilians - no civilian classes resolved` warnings.
- [ ] Confirm HVT and hostage objectives still spawn a sane-looking target —
      `civilian_suit` / `civilian_labcoat` now route through the new resolver,
      so a `FINANCIER` or `BOMBMAKER` objective is the thing to check.
- [ ] **Eyeball the ethnic mix on Altis** — predominantly European with an
      occasional minority. If minorities feel too common or too rare, that's
      the §A4.3 table and it's a one-line edit. Then check Tanoa, which should
      invert.
- [ ] Confirm exactly one new class of map-profile `INFO` line appears at boot
      (the §A8.2 union) and that it reports `CIV_F` already present — i.e. the
      union added nothing.
- [ ] Confirm the §A11 `// REVIEW` markers are present.

---

## Results log

*(to be filled in by the build session — follow the template in
`docs/campaign_overhaul/session_02_intel_ledger.md`)*
