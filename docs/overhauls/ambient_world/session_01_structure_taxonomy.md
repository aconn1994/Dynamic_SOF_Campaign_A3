# Session 01 — Structure Taxonomy

**Owner item:** 1 (Location Tagging, part A)
**Model:** Opus scaffold → **human hand-edit** → Sonnet wire-up
**Ships:** A category / subtype / flag table covering every structure class DSC
knows about, with derived reverse indices that keep every existing consumer
working.
**Status:** 🟨 **spec approved** — Q1–Q5 answered in the README Decision Log
(B15–B19); the mini-spec is approved and written up below as
*"Approved Mini-Spec (Session 01)"* (§A0–§A10). **Ready for a Sonnet build
session** — see the paste-ready prompt.

---

## Why this is first

Everything downstream reads from it:

- **POI registry** (Session 02) needs a subtype per structure to index by.
- **Briefings** need a display name per subtype to say "the school" or "the
  abandoned police barracks".
- **Civilian placement** (Session 05) needs to know a building is a *home* vs a
  *workplace* vs a *shop* to put the right person in it and give them something
  to do.
- **Deliberate military siting** (Session 10) needs `sentry_only` and
  `hvt_suitable` to stop putting an HVT on top of a fuel tank.
- **Actionable infrastructure** (Session 12) needs `comms_tower` /
  `power_substation` subtypes and `sabotage_target` / `hackable` flags to hang
  power and comms objectives off — and completes C2 Sprint F.5, whose
  `infraLinks` node field already exists and is never read.

It is also the single largest hand-authoring task in the program, which is why
it is isolated: the agent produces a scaffold, the human corrects it, and the
wire-up is mechanical.

---

## Current state

`addons/core/functions/data/fnc_getStructureTypes.sqf` — 1023 lines,
**~565 unique classnames**, returning 11 keys:

```
main, side, mainMilitary, mainCivilian, sideMilitary, sideCivilian,
exclusions, functionalCategories, functionalLookup,
nonOccupiable, nonOccupiableLookup
```

Problems:

1. **The same class is authored two to three times** — once in a garrison array
   (`_mainCivilian`), once in a functional array (`_func_residential`). They can
   and do drift. The damaged shop classes (`Land_i_Shop_01_V2_dam_F` and
   friends) are in `_mainCivilian` and filed under **`_func_residential`**, not
   commercial.
2. **No sub-type axis.** "Residential" cannot distinguish a slum shack from an
   estate, so a briefing cannot name anything.
3. **No per-class role flags.** Nothing can express "this is a great sniper
   perch and a terrible place to stash a hostage".
4. **Thin categories.** `law_enforcement` = 1 class. `medical` = 6.
   `agricultural` = 14.

### Consumers (do not break these)

| Key | Read by |
|---|---|
| `main`, `side`, `mainMilitary`, `sideMilitary` | `fnc_scanLocations` Stage 1 |
| `exclusions` | `fnc_scanLocations` Stage 1 |
| `functionalLookup` | `fnc_scanLocations` Stage 1 + Stage 4 |
| `nonOccupiableLookup` | `fnc_scanLocations` Stage 4 |
| `functionalCategories`, `nonOccupiable`, `mainCivilian`, `sideCivilian` | currently unread or read defensively — verify before assuming |

---

## Target design

### Two authored tables, everything else derived

**This is the ergonomic that makes 565 classes hand-checkable.** The owner
usually writes *one word per class*.

#### Table 1 — Subtype registry (~60 rows, fully hand-authored)

```sqf
// subtype, category, displayName, defaultFlags
["house_small",    "residential", "a small house",        ["occupiable","satellite","civilian_home"]],
["house_big",      "residential", "a large house",        ["occupiable","anchor","civilian_home"]],
["estate",         "residential", "an estate",            ["occupiable","anchor","civilian_home","hvt_suitable","landmark"]],
["slum",           "residential", "a shanty",             ["occupiable","satellite","civilian_home"]],
["school",         "commercial",  "a school",             ["occupiable","anchor","hvt_suitable","landmark"]],
["police_station", "law_enforcement", "a police station", ["occupiable","anchor","hvt_suitable","landmark"]],
["fuel_tank",      "industrial",  "a fuel tank",          ["sentry_only"]],
...
```

Subtypes come from the owner's `Ambient_Elements.md` list. Every subtype belongs
to exactly one category.

#### Approved vocabulary (Decision Log B15–B26)

**Categories** (11) — `residential`, `commercial`, `industrial`,
`agricultural`, `medical`, `religious`, `infrastructure`, `port`, `airport`,
`law_enforcement`, **`military`**.

`military` is **both** a category and a flag, deliberately (Decision B23):

- **Category `military`** — purpose-built structures with no civilian analogue:
  barracks, bunkers, guard posts, command posts, cargo/logistics houses, camp
  tents. This exists because **119 of 127 military classes currently have no
  functional category at all**.
- **Flag `military`** — *affiliation*. True for every class in the `military`
  category, **plus** crossover classes that are physically something else:
  `Land_Hangar_F` is `airport` + `military`; `Land_Medevac_HQ_V1_F` is
  `medical` + `military`; radar components are `infrastructure` + `military`.

Invariant: *category `military` ⇒ flag `military`*. Pinned by a Tier-1
assertion. The flag is what you **query**; the category is what the thing
**is**.

**Authored flags** (set in Table 1, overridable per class in Table 2):

| Flag | Meaning |
|---|---|
| `occupiable` | has usable `buildingPos` |
| `anchor` | garrison-cluster anchor (derives legacy `main`) |
| `satellite` | garrison satellite (derives legacy `side`) |
| `military` | military structure, orthogonal to category |
| `sentry_only` | good overwatch/perch, bad for placing people |
| `hvt_suitable` | plausible place for a commander/HVT |
| `hostage_suitable` | plausible place to hold someone — **deliberately wider than `hvt_suitable`** (a shed works for a hostage, not for an HVT) |
| `ruined` | derelict/damaged variant |
| `landmark` | nameable in a briefing; drives `has_<subtype>` tags in Session 02 |
| `infrastructure_node` | part of a power/comms/water network (Session 12) |
| `sabotage_target` | can be destroyed for a gameplay effect (Session 12) |
| `hackable` | can be exploited for intel (Session 12) |

**Derived flags** (computed, never authored): `workplace`, `public_access`,
`civilian_home`.

**Infrastructure subtypes** (Q2 resolved — one category, actionable subtypes):
`power_station`, `power_substation`, `power_distribution`, `comms_tower`,
`comms_relay`, `water_facility`, `fuel_infrastructure`, `rail_station`,
`lighthouse`, `solar_array`, `radar_site`.

**Fuel** (Decision B22): retail petrol stations
(`Land_FuelStation_Build_F`, `Land_FuelStation_Shed_F`) move to **`commercial`**
with subtype `fuel_station`. `infrastructure` / `fuel_infrastructure` is
reserved for bulk storage and depot classes (`Land_FuelStation_Feed_F`, tank
farms).

> ### Affiliation is NOT authored (Decision B25)
>
> There is no `law_enforcement` flag and barracks are not authored as police
> structures. **A barracks is a barracks.** The same class appears on airbases
> *and* as a lone compound in a city with no military installation — the
> catalog is context-free and cannot distinguish them.
>
> Whether a structure reads as army, police, insurgent-held or derelict is
> resolved **at runtime from location context** by
> `fnc_resolveStructureAffiliation` (Session 02), using the host location's
> `isMilitary` / `militaryTier` / influence controller.
>
> Do not add affiliation flags to this table.

> **Keep mission mechanics out of the catalog.** The catalog says what a
> building *is*. `sabotage_target` / `hackable` are *affordance* flags — they
> mark that an action is possible. **What the action does** lives in a separate
> effects registry built in Session 12. Do not put effect data in this table.

#### Table 2 — Class table (~565 rows, scaffold-generated, hand-corrected)

```sqf
["Land_House_Small_01_F",  "house_small"],
["Land_School_01_F",       "school"],
["Land_dp_bigTank_old_F",  "fuel_tank"],
// flag override form, used only for oddities:
["Land_Cargo_Tower_V1_F",  "warehouse_big", ["+sentry_only","-civilian_home"]],
```

Third element is optional. `+flag` adds, `-flag` removes from the subtype
default. Keeps the common case to one word.

#### Derived at call time (built once, cached)

| Derived key | Rule |
|---|---|
| `byClass` | class → `{subtype, category, displayName, flags}` |
| `bySubtype` | subtype → `[classnames]` |
| `main` | classes whose flags contain `anchor` |
| `side` | classes whose flags contain `satellite` |
| `mainMilitary` / `mainCivilian` | `main` partitioned on the `military` flag |
| `sideMilitary` / `sideCivilian` | `side` partitioned on the `military` flag |
| `functionalCategories` | category → `[classnames]` |
| `functionalLookup` | class → category |
| `nonOccupiable` | category → classes **without** `occupiable` |
| `nonOccupiableLookup` | class → category, for the same set |
| `exclusions` | unchanged — stays a hand-authored per-map list |

**All 11 legacy keys keep their exact shape and semantics.** Nothing downstream
changes in this session.

---

## Deliverables

1. **`fnc_getStructureCatalog`** (`addons/core/functions/data/`) — returns a
   hashmap with the derived indices above **plus** the legacy 11 keys. Cached in
   `uiNamespace`/`missionNamespace` on first call; the derivation walks ~565
   classes and should not run per location.
2. **`fnc_getStructureSubtypes`** (`addons/core/functions/data/`) — Table 1.
   Pure data.
3. **`fnc_resolveStructureInfo`** (`addons/core/functions/data/`) — pure.
   `[_classnameOrObject] → hashmap {subtype, category, displayName, flags}`.
   Unknown class returns a well-formed `"unknown"` record and **WARNs once per
   class**, never per call.
4. **`fnc_getStructureTypes`** — reduced to a thin shim that returns the catalog's
   legacy keys, so no consumer edits are needed. Deprecate in the header; delete
   in a later session once call sites migrate.
5. **Scaffold artifact** — Table 2 pre-populated for all ~565 classes, subtype
   guessed from the existing garrison/functional membership plus classname
   heuristics, with a `// REVIEW` comment on every row the agent was not
   confident about. This is the thing the human hand-corrects.
6. **Ambiguity list** — a short markdown list of classes the agent genuinely
   could not place, with its best guess and why. Do **not** silently guess on
   these; ask.
7. **Close the known gaps** — see the README's *"Classes to add in Session 01"*
   and *"The military residue"* sections. Adds ~11 missing vanilla
   infrastructure classes, fixes the verified miscategorisations
   (`Land_CoalPlant_01_MainBuilding_F` and `Land_spp_Tower_F` are power
   generation filed as `industrial`; `Land_ReservoirTank_V1_F` is water filed as
   `industrial`; `Land_PowerPoleWooden_F` is commented out; the damaged shop
   classes are filed as `residential`), moves fuel stations to `commercial`, and
   **gives all 119 uncategorised military classes a home**.

---

## Tier-1 test plan (`suite: structure_catalog`)

All pure, no world required.

| Assertion | Why |
|---|---|
| Every class in Table 2 maps to a subtype that exists in Table 1 | catches typos, the #1 failure mode |
| Every subtype's category is in the known category vocabulary | catches category drift |
| Every flag in Table 1/2 is in the known flag vocabulary | catches typo'd flags silently doing nothing — **the `unitClassResolver` gotcha class of bug** |
| No classname appears twice in Table 2 | the current file's duplication problem |
| Every subtype has a non-empty `displayName` | briefings depend on it |
| Every category has ≥1 subtype and ≥1 class | catches a category that exists only on paper |
| Derived `main` ∪ `side` covers every `occupiable` class | no occupiable building is invisible to the garrison system |
| `main` ∩ `side` is empty | a class cannot be both anchor and satellite |
| Derived `functionalLookup` is total over Table 2 | no class can be functionally invisible |
| `nonOccupiableLookup` and `functionalLookup` are disjoint | a class is one or the other |
| `fnc_resolveStructureInfo` on an unknown class returns a well-formed record and does not throw | degrade loudly, not fatally |
| Catalog build is idempotent and cached (second call returns the same ref) | perf guard |
| Every `hvt_suitable` class is also `occupiable` | you cannot hide a commander in a fuel tank |
| No class is both `hvt_suitable` and `sentry_only` | the two are mutually exclusive by design |
| `hvt_suitable` ⊆ `hostage_suitable` | a place good enough for an HVT is good enough for a hostage; the reverse is not true (the shed case) |
| Every `sabotage_target` / `hackable` class is also `infrastructure_node` | Session 12 queries on the node flag |
| Every class in category `military` carries flag `military` | Decision B23 invariant |
| At least one class outside category `military` carries flag `military` | proves crossover works (hangar, medevac, radar) |
| **No class carries an affiliation flag** (no `law_enforcement`/`police` flag exists in the vocabulary) | Decision B25 — stops a later pass re-introducing intrinsic affiliation |
| Zero classes have category `""` or `"unknown"` | the 119-orphan problem cannot recur |

**Coverage report** (print once in the suite, not an assertion): class count per
category and per subtype, plus the count of rows still carrying `// REVIEW`.
This is how the human tracks hand-editing progress.

---

## Gotchas for this session

- **`AGENTS.md` unitClassResolver precedent.** A typo'd resolver key hit a
  `default` branch and silently returned a CSAT officer for a Syndikat mission.
  The same failure shape applies to subtypes and flags — hence the vocabulary
  assertions above. Unknown subtype/flag must **ERROR or WARN**, never
  silently no-op.
- **CBA log macro comma counting.** Any inline array literal in a `LOG_n` /
  `WARNING_n` arg breaks the HEMTT build. Hoist to a local first. This session
  will be full of `count (_x get "flags")` style expressions — hoist them.
- **Do not change scan behavior.** This session must be behaviorally invisible.
  `fnc_scanLocations` is untouched; a playtest should produce an identical
  location set. Session 02 is where behavior changes.
- **Cache correctly.** 565 classes × flag-set derivation per location would be a
  real cost. Build once.
- **`exclusions` stays hand-authored per map.** It is not derivable from
  category/subtype and the per-map structure must survive.

---

## Definition of done

- `fnc_getStructureSubtypes`, `fnc_getStructureCatalog`,
  `fnc_resolveStructureInfo` registered in `addons/core/XEH_PREP.hpp`.
- `fnc_getStructureTypes` reduced to a shim; **zero edits required at any
  existing call site**.
- Scaffold Table 2 covers every class previously present in
  `fnc_getStructureTypes` — no class lost.
- Ambiguity list written to `docs/overhauls/ambient_world/session_01_ambiguities.md`.
- Tier-1 suite `structure_catalog` registered and passing under `fnc_runTests`.
- `hemtt check` clean.
- Playtest: launch, confirm the location scan summary in RPT is **unchanged**
  from before the session.
- `AGENTS.md` key-systems table updated; new gotchas folded in.

---

## Paste-ready prompt (Opus, for the spec) — ✅ DONE, spec approved below

> Read `docs/campaign_overhaul/WORKFLOW_RULES.md` (still law),
> `docs/overhauls/ambient_world/README.md`, and this work order
> (`session_01_structure_taxonomy.md`).
>
> Build Session 01 — the structure taxonomy. The design is specified above:
> two authored tables (subtype registry + class table) with all legacy return
> keys derived, so `fnc_scanLocations` and every other consumer is untouched.
>
> **Produce the mini-spec first** (function signatures, the subtype vocabulary
> you intend to author, and the Tier-1 assertion list) and stop for approval.
> The category and flag vocabularies are already fixed by Decision Log
> B15–B19 — do not re-litigate them. Do not write the 565-row class table until
> the **subtype** vocabulary is approved; a wrong vocabulary means re-authoring
> everything.
>
> After approval: generate the scaffold with `// REVIEW` markers on low-confidence
> rows, write the ambiguity list, add the Tier-1 suite, and run `hemtt check`.
>
> Definition of done is the list in the work order. Do not touch
> `fnc_scanLocations` — that is Session 02.

### Paste-ready prompt (Sonnet, to build the approved spec)

```
Read docs/campaign_overhaul/WORKFLOW_RULES.md (still law),
docs/overhauls/ambient_world/README.md, and
docs/overhauls/ambient_world/session_01_structure_taxonomy.md.

Implement the APPROVED MINI-SPEC at the bottom of the session doc
("## Approved Mini-Spec (Session 01)"). It is fully decided — the subtype
vocabulary (83 subtypes), the function signatures, the flag-derivation rules,
the complete class->subtype scaffold mapping (§A5), the per-subtype flag
defaults (§A4), and the 25 Tier-1 assertions are all signed off. Do NOT
re-litigate any of it, and do NOT re-derive the mapping from
fnc_getStructureTypes.sqf — transcribe §A5.

Your job is transcription + wiring, in this order:

1. Write addons/core/functions/data/fnc_getStructureSubtypes.sqf — Table 1,
   the 83 rows in §A4, verbatim.
2. Write addons/core/functions/data/fnc_getStructureCatalog.sqf — Table 2
   inlined per §A5 (~576 rows), the derivation in §A3, the per-map
   exclusions table moved verbatim from fnc_getStructureTypes.sqf, and the
   missionNamespace cache. Put // REVIEW on every row listed in §A6.
3. Write addons/core/functions/data/fnc_resolveStructureInfo.sqf per §A2.
4. Reduce fnc_getStructureTypes.sqf to the shim in §A2. ZERO call-site edits.
5. PREP_SUB(data,...) the three new functions in addons/core/XEH_PREP.hpp.
6. Add the structure_catalog Tier-1 suite to fnc_initServerDebug.sqf as an
   inline _testSuites set [...] block (that is the established pattern — no
   per-suite files, no XEH_PREP entry for the suite). All 25 assertions in
   §A7, plus the printed coverage report.
7. Write docs/overhauls/ambient_world/session_01_ambiguities.md from §A6.
8. hemtt check clean.
9. Docs: AGENTS.md key-systems row + the gotchas in §A8; README.md status
   tracker row for Session 01; record the expected functionalLookup deltas
   (§A9) so the human playtest does not read them as a regression.

Hard constraints:
- Do NOT touch fnc_scanLocations — that is Session 02.
- The legacy keys main / side / mainMilitary / mainCivilian / sideMilitary /
  sideCivilian MUST be byte-identical to today. They derive mechanically from
  anchor/satellite flags, which §A5 derives from current array membership.
  functionalLookup / functionalCategories / nonOccupiable* are the ONLY keys
  allowed to change, and only in the ways listed in §A9.
- Invariant: occupiable <=> exactly one of anchor / satellite. A non-occupiable
  class has neither and must not appear in main or side.
- Respect the CBA log-macro comma-counting trap — hoist every inline array
  literal (count (_x get "flags"), getOrDefault ["k", v], etc.) to a local
  before passing it to LOG_n / INFO_n / WARNING_n / ERROR_n / TRACE_n.
- Unknown subtype or unknown flag must ERROR or WARN, never silently no-op
  (the unitClassResolver precedent).

Sonnet scope — build the approved spec, do not redesign it.
```

---

## Human playtest checklist

This session is behaviorally invisible, so the playtest is a **regression check**:

- [ ] `hemtt check` clean.
- [ ] `test.VR` → `fnc_runTests` prints `PASS: structure_catalog`.
- [ ] Read the coverage report — does the class-per-category distribution look
      sane, or is everything dumped in `residential`?
- [ ] Launch `hemtt launch developer_factions` on Altis. Compare the
      `[DSC] (core) INFO: ========== Anchor-Based Location Scan ==========`
      block and the tag-distribution summary against a pre-session RPT. The
      **location set, anchor count and main/side counts must be identical**.
      The **tag distribution will shift** — see §A9 for the exact expected
      deltas. Check the shift against that list; anything not on it is a bug.
- [ ] Then: hand-correct the class table. Expect this to be the long pole.

---

# Approved Mini-Spec (Session 01)

*Opus draft, October 2026. **Approved by owner** — subtype vocabulary trimmed to
83, Table 2 inlined, `civilian_home` exclusion confirmed. This section is the
build contract; everything above it is the problem statement.*

---

## A0 — Decisions taken at approval

| # | Question | Decision |
|---|---|---|
| S1 | Subtype vocabulary size | **83 subtypes** (the trimmed list). Expandable later; a new subtype is a one-row addition to Table 1 plus a re-point of the affected Table 2 rows. |
| S2 | Table 2 location | **Inlined** in `fnc_getStructureCatalog`, not a separate function. |
| S3 | `civilian_home` excludes sheds/garages/annexes | **Yes, excluded.** A shed is not a dwelling. |
| S4 | Does the primary/side hierarchy still exist? | **Yes — and it is preserved byte-identically.** See A0.1. |
| S5 | Fold targets for the trimmed subtypes | Two deviations from the original trim list — see A0.2. |

### A0.1 — The primary/side hierarchy (answer to S4)

Verified in code, because this determined the `civilian_home` call:

- **`fnc_scanLocations` has no hierarchy.** `main`/`side` are flat labels
  assigned by `isKindOf` (main tested first, side only if not main — lines
  68–82), then split into two parallel per-location arrays with no parent/child
  relationship (lines 330–343, 478–482). Anchors in that function are *named map
  locations and cluster centroids*, not buildings.
- **`fnc_setupGarrison` is where the hierarchy lives**, and it does have the
  promotion fallback: main structures are consumed as cluster anchors first
  (lines 220–242), and when they run out — including the zero-main case — **side
  structures are promoted to anchor** (lines 244–264, logged as
  `%3 promoted side`). Satellites are then claimed within `satelliteRadius`
  (50m) from what remains (lines 274–286). A promoted side anchor still gets the
  *side* occupancy cap, because the cap test is membership-based (lines 302–303).
- **`fnc_setupCivilians` has no hierarchy at all.** It flattens every supplied
  structure's `buildingPos` into one shuffled bag (lines 93–99) with zero
  residential / main / side awareness. The "shed becomes a dwelling when nothing
  better exists" behavior **does not currently exist for civilians**.

**Therefore:** `civilian_home` stays a context-free static truth — a shed is not
a dwelling — consistent with Decision B25 (context is resolved at runtime, not
baked into the catalog). The *contextual fallback* belongs in the Session 05
consumer, as a cascade that mirrors `fnc_setupGarrison`'s promotion:

```
prefer  civilian_home
else    occupiable AND category == residential
else    any occupiable
```

Session 01 ships the data that makes that cascade expressible. It does **not**
ship the cascade. Recorded as a hand-off in A10.

### A0.2 — Trim list, as applied

| Dropped subtype | Folded into | Note |
|---|---|---|
| `caravan` | `shed_domestic` | |
| `ruin_shop` | `shop_damaged` | ruins carry the `ruined` flag instead |
| `ruin_house_big` + `ruin_house_small` | `ruin_residential` (one subtype) | |
| `silo_industrial` | `storage_tank` | |
| `gazebo` | **`house_annex`** *(not `estate`)* | folding into `estate` would make a gazebo `hvt_suitable` |
| `fire_escape` | **`house_annex`** *(not `apartment_block`)* | folding into `apartment_block` would make a fire escape a dwelling |
| `compound_wall` | `house_annex` | |

90 → **83**.

---

## A1 — Scope

**In:** the three new data functions, the shim, the scaffolded class table, the
Tier-1 suite, the ambiguity list, the doc updates.

**Out:** `fnc_scanLocations` (Session 02), `fnc_resolveStructureAffiliation`
(Session 02), the POI registry (Session 02), the Session 12 effects registry,
any consumer migration off the shim.

---

## A2 — Function signatures

| Function | Signature | Purity |
|---|---|---|
| `DSC_core_fnc_getStructureSubtypes` | `[] → ARRAY` of `[subtype, category, displayName, defaultFlags]` | pure data |
| `DSC_core_fnc_getStructureCatalog` | `[_rebuild] → HASHMAP` (`_rebuild` BOOL, default `false`) | impure (cache) |
| `DSC_core_fnc_resolveStructureInfo` | `[_classnameOrObject] → HASHMAP` | deterministic (reads cache) |
| `DSC_core_fnc_getStructureTypes` | `[] → HASHMAP` — **unchanged signature** | shim |

### `fnc_getStructureCatalog`

Returns a hashmap carrying **both** the new derived indices and the legacy 11
keys:

| Key | Shape |
|---|---|
| `byClass` | class → `{subtype, category, displayName, flags}` |
| `bySubtype` | subtype → `[classnames]` |
| `byCategory` | category → `[subtypes]` |
| `subtypeInfo` | subtype → `{category, displayName, flags}` |
| `byFlag` | flag → `[classnames]` |
| `main`, `side`, `mainMilitary`, `mainCivilian`, `sideMilitary`, `sideCivilian` | legacy, `ARRAY` |
| `exclusions` | legacy, `ARRAY` (per-map, hand-authored) |
| `functionalCategories`, `functionalLookup` | legacy, `HASHMAP` |
| `nonOccupiable`, `nonOccupiableLookup` | legacy, `HASHMAP` |

**Cache:** `missionNamespace` under `DSC_structureCatalogCache`, **not**
`uiNamespace` — `uiNamespace` survives a mission restart and would serve a stale
table across dev iterations. `_rebuild == true` discards and recomputes, which
is how the Tier-1 suite exercises a cold build.

### `fnc_resolveStructureInfo`

Accepts a classname `STRING` or an `OBJECT` (`typeOf` applied). Returns the
`byClass` record. An unknown class returns a **well-formed** record:

```sqf
createHashMapFromArray [
    ["subtype", "unknown"], ["category", "unknown"],
    ["displayName", "a building"], ["flags", []]
]
```

and `WARNING_1` **once per distinct class**, tracked in a
`DSC_structureUnknownWarned` hashmap. Never once per call — the scan touches
thousands of objects.

`"unknown"` is reachable only at runtime for a class absent from Table 2. It is
**not** a legal authored value: assertion 20 pins that no Table 2 row resolves
to it.

### `fnc_getStructureTypes` (shim)

```sqf
private _cat = [] call DSC_core_fnc_getStructureCatalog;
createHashMapFromArray [
    ["main", _cat get "main"], ... // the 11 legacy keys, verbatim
]
```

Header marked `@deprecated — use DSC_core_fnc_getStructureCatalog`. **Zero edits
at any call site.** Deleted in a later session once consumers migrate.

---

## A3 — Derivation rules

### The load-bearing invariant

> **`occupiable` ⟺ exactly one of `anchor` / `satellite`.**

A non-occupiable class carries neither and must not appear in `main` or `side`.
This single rule makes assertions 7, 8 and 10 structural rather than hopeful.

### How the legacy keys stay byte-identical

The scaffold does **not** guess `occupiable` / `anchor` / `satellite` /
`military`. It derives them **mechanically from each class's current membership**
in `_mainMilitary` / `_mainCivilian` / `_sideMilitary` / `_sideCivilian` /
`_nonOccupiable`:

| Current membership | Flags |
|---|---|
| `_mainMilitary` | `occupiable`, `anchor`, `military` |
| `_mainCivilian` | `occupiable`, `anchor` |
| `_sideMilitary` | `occupiable`, `satellite`, `military` |
| `_sideCivilian` | `occupiable`, `satellite` |
| `_nonOccupiable` | neither `occupiable` nor `anchor`/`satellite` |

Derivation back out:

```
main          = classes with flag anchor
side          = classes with flag satellite
mainMilitary  = main INTERSECT flag military      mainCivilian = main MINUS flag military
sideMilitary  = side INTERSECT flag military      sideCivilian = side MINUS flag military
```

**Consequence: subtype assignment is the only judgement call in the session, and
it can only move `functionalLookup` / `functionalCategories` / `nonOccupiable*`
— which is exactly the set of changes the README mandates.** See A9 for the
expected deltas.

> `military` is also set by subtype default for every subtype in category
> `military`, and by `+military` override on the crossover classes. Where
> membership-derivation and subtype-default disagree, they must be reconciled to
> the membership value or a legacy key shifts. A5 has already done this.

### Override syntax

Table 2's optional third element is an array of `"+flag"` / `"-flag"` strings
applied in order on top of the subtype default. One word per class is the common
case; A5 lists every row that needs an override.

### Derived flags (computed, never authored)

```
civilian_home  = occupiable AND NOT ruined AND NOT military
                 AND category == "residential"
                 AND subtype NOT IN {shed_domestic, garage_private, house_annex, castle}

workplace      = occupiable AND NOT ruined
                 AND category IN {commercial, industrial, agricultural, medical,
                                  infrastructure, port, airport, law_enforcement, military}

public_access  = occupiable AND NOT ruined AND NOT military
                 AND category IN {commercial, medical, religious, law_enforcement,
                                  airport, port}
```

These are rule inputs, not per-class authoring. The four excluded residential
subtypes are the S3 decision.

### `ruined` vs. damaged

- **`_dam_` variants** → their own `*_damaged` subtype, **no** `ruined` flag.
  Shot-up but standing and occupied.
- **`_ruins_` / `*Ruin*` / `*Ruins*` classes** → a `ruin_*` subtype **with** the
  `ruined` flag. Rubble.

This matters: `ruined` suppresses `civilian_home`, `workplace` and
`public_access`.

### `exclusions`

Moved **verbatim** from `fnc_getStructureTypes.sqf:615-635` into
`fnc_getStructureCatalog`, including the `INFO_2` line. Still hand-authored per
map, still not derived.

> Exclusion-only classnames (`Land_Cargo_Patrol_V2_F`, `Land_Cargo_Tower_V2_F`,
> `Land_Cargo_HQ_V2_F`) are **not** added to Table 2. They are in no garrison
> array today; adding them would either change a legacy key or violate the
> occupiable invariant. `exclusions` is a flat classname list, independent of the
> catalog.

---

## A4 — Table 1: the 83 subtypes

`O` = occupiable, `A` = anchor, `S` = satellite, `M` = military,
`Se` = sentry_only, `Hv` = hvt_suitable, `Ho` = hostage_suitable,
`R` = ruined, `L` = landmark, `In` = infrastructure_node,
`Sa` = sabotage_target, `Hk` = hackable.

### residential (12)

| subtype | displayName | default flags |
|---|---|---|
| `house_small` | a small house | O A |
| `house_small_damaged` | a damaged house | O A |
| `house_big` | a large house | O A Ho |
| `house_big_damaged` | a damaged two-storey house | O A Ho |
| `apartment_block` | an apartment block | O A Ho Hv |
| `estate` | an estate | O A Ho Hv L |
| `castle` | a castle | O A Se L |
| `slum` | a shanty | O S Ho |
| `house_annex` | an outbuilding | O S |
| `garage_private` | a garage | O S Ho |
| `shed_domestic` | a shed | O S Ho |
| `ruin_residential` | a ruined building | O S R |

### commercial (11)

| subtype | displayName | default flags |
|---|---|---|
| `shop` | a shop | O A |
| `shop_damaged` | a derelict shop | O A |
| `office` | an office building | O A Ho Hv L |
| `hotel` | a hotel | O A Ho Hv L |
| `school` | a school | O A Ho Hv L |
| `supermarket` | a supermarket | O A Ho L |
| `kiosk` | a kiosk | O S |
| `village_store` | a village store | O S |
| `garage_complex` | a garage complex | O A Ho |
| `fuel_station` | a petrol station | O S L |
| `stadium` | a stadium | O S L |

### industrial (12)

| subtype | displayName | default flags |
|---|---|---|
| `factory` | a factory | O A Ho L |
| `warehouse_big` | a large warehouse | O A Ho |
| `warehouse_small` | a storage shed | O A Ho |
| `workshop` | a workshop | O S Ho |
| `autoshop` | an auto repair shop | O A Ho |
| `shed_industrial` | an industrial shed | O S Ho |
| `storage_tank` | a storage tank | O S Se |
| `chimney` | a smokestack | O A Se L |
| `processing_plant` | a processing plant | O A Ho L |
| `mine_site` | a mine | O S L |
| `pipeline` | a pipeline run | *(none)* |
| `construction_site` | an unfinished building | O A Se |

### agricultural (8)

| subtype | displayName | default flags |
|---|---|---|
| `barn_large` | a large barn | O A Ho |
| `barn_small` | a barn | O S Ho |
| `livestock_shed` | a livestock shed | O S Ho |
| `sawmill` | a sawmill | O S L |
| `windmill` | a windmill | O S Se L |
| `greenhouse` | a greenhouse | *(none)* |
| `grain_silo` | a grain silo | Se |
| `hunting_stand` | a hunting stand | O S Se |

### medical (4)

| subtype | displayName | default flags |
|---|---|---|
| `hospital` | a hospital | O A Ho Hv L |
| `clinic` | a health centre | O A Ho L |
| `field_hospital` | a field hospital | O A **M** Ho |
| `decon_facility` | a decontamination facility | O A **M** |

### religious (5)

| subtype | displayName | default flags |
|---|---|---|
| `church` | a church | O A Ho L |
| `chapel` | a chapel | O S Ho L |
| `ruin_church` | a ruined church | O S R L |
| `mausoleum` | a mausoleum | O S L |
| `temple` | a temple | O A Ho L |

### infrastructure (12)

| subtype | displayName | default flags |
|---|---|---|
| `power_station` | a power station | O A In Sa Hk L |
| `power_substation` | an electrical substation | O S In Sa L |
| `power_distribution` | a power line | In Sa |
| `solar_array` | a solar array | O A In Sa L |
| `comms_tower` | a communications tower | In Sa Hk L |
| `comms_relay` | a relay mast | In Sa Hk |
| `water_facility` | a water facility | O S In Sa L |
| `fuel_infrastructure` | a fuel depot | In Sa Se |
| `rail_station` | a railway station | O A Ho L |
| `lighthouse` | a lighthouse | O A Se L |
| `radar_site` | a radar site | O A **M** In Sa Hk L |
| `bridge` | a bridge | O S In Sa L |

### port (5)

| subtype | displayName | default flags |
|---|---|---|
| `shipyard` | a shipyard | O A L |
| `container_terminal` | a container terminal | O A L |
| `pier` | a pier | O S |
| `crane` | a dockside crane | O S Se L |
| `navigation_aid` | a navigation light | *(none)* |

### airport (3)

| subtype | displayName | default flags |
|---|---|---|
| `terminal` | an airport terminal | O A Ho Hv L |
| `hangar` | a hangar | O A Ho L |
| `control_tower` | a control tower | O A Se L |

### law_enforcement (1)

| subtype | displayName | default flags |
|---|---|---|
| `police_station` | a police station | O A Ho Hv L |

### military (10) — all carry `M` by the B23 invariant

| subtype | displayName | default flags |
|---|---|---|
| `barracks` | a barracks | O A M Ho Hv L |
| `bunker` | a bunker | O S M Se |
| `guard_post` | a guard post | O S M Se |
| `cargo_structure` | a prefab logistics building | O S M Ho |
| `command_post` | a command post | O A M Ho Hv L |
| `camp_tent` | a camp tent | O S M Ho |
| `camp_house` | a camp hut | O S M Ho |
| `helipad` | a helipad | M |
| `fortification` | a barrier emplacement | M Se |
| `dome` | a radome | O S M Se |

**Vocabulary cross-checks (all pass by construction):**
`hvt_suitable` ⊆ `hostage_suitable` ✓ · `hvt_suitable` ⊆ `occupiable` ✓ ·
`hvt_suitable` ∩ `sentry_only` = ∅ ✓ · `sabotage_target` ∪ `hackable` ⊆
`infrastructure_node` ✓ · category `military` ⇒ flag `military` ✓ ·
non-military-category classes carrying `military`: `field_hospital`,
`decon_facility`, `radar_site`, plus `+military` overrides on `Land_Hangar_F`,
`Land_Airport_Tower_F`, `Land_Airport_Tower_dam_F` ✓.

---

## A5 — Table 2: the complete scaffold mapping

**This is the authoritative source. Transcribe it; do not re-derive it from
`fnc_getStructureTypes.sqf`.** Every class below is listed under its subtype.
Rows needing a third-element override are called out explicitly. Rows marked
`// REVIEW` go into the ambiguity list (A6) *and* carry the comment in code.

Shorthand used below: `→ S` means override `["+satellite","-anchor"]`,
`→ A` means `["+anchor","-satellite"]`, `→ NO` means `["-occupiable","-anchor"]`
or `["-occupiable","-satellite"]` as appropriate for the subtype default.

### residential

**`house_small`** — `Land_i_House_Small_01_V1_F` `_V2_F` `_V3_F`,
`Land_i_House_Small_02_V1_F` `_V2_F` `_V3_F`, `Land_i_House_Small_03_V1_F`,
`Land_i_House_Small_01_b_{yellow,pink,whiteblue,blue,white,brown}_F`,
`Land_i_House_Small_02_b_{whiteblue,blue,white,pink,brown,yellow}_F`,
`Land_i_House_Small_02_c_{pink,whiteblue,blue}_F`,
`Land_u_House_Small_01_V1_F`, `Land_u_House_Small_02_V1_F`,
`Land_i_Stone_HouseSmall_V1_F` `_V2_F` `_V3_F`,
`Land_House_Small_01_F`…`_06_F`,
`Land_House_Native_01_F`, `Land_House_Native_02_F`
— **→ S:** `Land_House_1W01_F`…`_1W13_F` (13 classes, Livonia, currently `_sideCivilian`)

**`house_small_damaged`** — `Land_i_House_Small_01_V1_dam_F` `_V2_dam_F` `_V3_dam_F`,
`Land_i_House_Small_02_V1_dam_F` `_V2_dam_F` `_V3_dam_F`,
`Land_i_House_Small_03_V1_dam_F`,
`Land_d_House_Small_01_V1_F`, `Land_d_House_Small_02_V1_F`,
`Land_u_House_Small_01_V1_dam_F`, `Land_u_House_Small_02_V1_dam_F`,
`Land_i_Stone_HouseSmall_V1_dam_F` `_V2_dam_F` `_V3_dam_F`,
`Land_d_Stone_HouseSmall_V1_F`

**`house_big`** — `Land_i_House_Big_01_V1_F` `_V2_F` `_V3_F`,
`Land_i_House_Big_02_V1_F` `_V2_F` `_V3_F`,
`Land_i_House_Big_01_b_{yellow,blue,pink,white,whiteblue,brown}_F`,
`Land_i_House_Big_02_b_{pink,brown,whiteblue,blue,yellow,white}_F`,
`Land_u_House_Big_01_V1_F`, `Land_u_House_Big_02_V1_F`,
`Land_i_Stone_HouseBig_V1_F` `_V2_F` `_V3_F`,
`Land_i_Stone_House_Big_01_b_clay_F`,
`Land_House_Big_01_F`…`_05_F`,
`Land_House_2W01_F`…`_2W05_F`, `Land_House_2B01_F`…`_2B04_F`,
`Land_House_1B01_F`

**`house_big_damaged`** — `Land_i_House_Big_01_V1_dam_F` `_V2_dam_F` `_V3_dam_F`,
`Land_i_House_Big_02_V1_dam_F` `_V2_dam_F` `_V3_dam_F`,
`Land_u_House_Big_01_V1_dam_F`, `Land_u_House_Big_02_V1_dam_F`,
`Land_d_House_Big_01_V1_F`, `Land_d_House_Big_02_V1_F`,
`Land_i_Stone_HouseBig_V1_dam_F` `_V2_dam_F` `_V3_dam_F`,
`Land_d_Stone_HouseBig_V1_F`

**`apartment_block`** — `Land_MultistoryBuilding_01_F` `_03_F` `_04_F`

**`estate`** — `Land_GH_MainBuilding_left_F` `_middle_F` `_right_F`,
`Land_GH_House_1_F`

**`castle`** — `Land_Castle_01_tower_F`;
`Land_CastleRuins_01_bastion_F` → `["+satellite","-anchor","+ruined"]` `// REVIEW`

**`slum`** — `Land_Slum_House01_F` `02` `03`, `Land_Slum_01_F`…`_05_F`

**`house_annex`** — `Land_i_Addon_02_V1_F` `_03_V1_F` `_03mid_V1_F` `_04_V1_F`,
`Land_u_Addon_01_V1_F` `_02_V1_F`, `Land_Addon_04_F`, `Land_d_Addon_02_V1_F`,
`Land_u_Addon_01_V1_dam_F`,
`Land_GH_Gazebo_F` `// REVIEW`, `Land_GH_House_2_F` `// REVIEW`,
`Land_FireEscape_01_tall_F` `// REVIEW`, `Land_FireEscape_01_short_F` `// REVIEW`,
`Land_WoodenWall_04_s_d_5m_F` `// REVIEW`, `Land_BrickWall_03_l_gate_F` `// REVIEW`

**`garage_private`** — `Land_i_Garage_V1_F`, `Land_i_Garage_V2_F`,
`Land_i_Garage_V1_dam_F`, `Land_i_Garage_V2_dam_F`,
`Land_Highway_Pillar_01_garage_F` `// REVIEW`;
`Land_GarageShelter_01_F` → `["+anchor","-satellite"]`

**`shed_domestic`** — `Land_i_Stone_Shed_V1_F` `_V2_F` `_V3_F`,
`Land_i_Stone_Shed_V1_dam_F`, `Land_i_Stone_Shed_V2_dam_F` `// REVIEW`,
`Land_i_Stone_Shed_V3_dam_F` `// REVIEW`, `Land_d_Stone_Shed_V1_F`,
`Land_i_Stone_Shed_01_b_{raw,clay,white}_F`,
`Land_i_Stone_Shed_01_c_{white,clay,raw}_F`,
`Land_Shed_01_F` `02` `03` `04` `05` `06` `07` `09` `10` `11` `12` `14`,
`Land_Shed_08_brown_F`, `Land_Shed_08_grey_F`,
`Land_Caravan_01_rust_F` `// REVIEW`;
`Land_Shed_05_ruins_F` → `["+ruined"]`

**`ruin_residential`** — `Land_HouseRuin_Small_01_half_F`,
`Land_House_Small_01_V1_ruins_F`, `Land_House_Small_02_V1_ruins_F`,
`Land_Stone_HouseBig_V1_ruins_F`, `Land_Stone_Shed_V1_ruins_F`,
`Land_Garage_V1_ruins_F`, `Land_Addon_02_V1_ruins_F`, `Land_Addon_04_V1_ruins_F`
— **→ A:** `Land_HouseRuin_Big_01_F` `_01_half_F` `_02_F` `_02_half_F`
`_03_half_F`, `Land_House_Big_01_V1_ruins_F`, `Land_House_Big_02_V1_ruins_F`

### commercial

**`shop`** — `Land_i_Shop_01_V1_F` `_V2_F` `_V3_F`,
`Land_i_Shop_02_V1_F` `_V2_F` `_V3_F`,
`Land_u_Shop_01_V1_F`, `Land_u_Shop_02_V1_F`,
`Land_Shop_City_01_F` `_02_F` `_04_F` `_05_F` `_06_F` `_07_F`,
`Land_Shop_Town_01_F` `_03_F` `_05_F`,
`Land_i_Shop_02_b_{whiteblue,brown,white,yellow,pink,blue}_F`;
`Land_Shop_Town_02_F` → `["-occupiable","-anchor"]`

**`shop_damaged`** — `Land_i_Shop_01_V1_dam_F` `_V2_dam_F` `_V3_dam_F`,
`Land_i_Shop_02_V1_dam_F` `_V2_dam_F` `_V3_dam_F`,
`Land_u_Shop_01_V1_dam_F`, `Land_u_Shop_02_V1_dam_F`, `Land_d_Shop_01_V1_F`;
`Land_d_Shop_02_V1_F` → `["+satellite","-anchor"]`;
`Land_Shop_01_V1_ruins_F` → `["+ruined"]`; `Land_Shop_02_V1_ruins_F` → `["+ruined"]`

**`office`** — `Land_Offices_01_V1_F`
**`hotel`** — `Land_Hotel_01_F`, `Land_Hotel_02_F`
**`school`** — `Land_School_01_F`
**`supermarket`** — `Land_Supermarket_01_F`, `Land_Supermarket_01_malden_F`
**`kiosk`** — `Land_Kiosk_blueking_F` `_gyros_F` `_papers_F` `_redburger_F`
**`village_store`** — `Land_VillageStore_01_F`
**`garage_complex`** — `Land_GarageRow_01_large_F`, `Land_GarageOffice_01_F`;
`Land_GarageRow_01_small_F` → `["+satellite","-anchor"]`
**`fuel_station`** — `Land_FuelStation_Build_F`, `Land_FuelStation_Shed_F`,
`Land_FuelStation_01_shop_F`, `Land_FuelStation_01_workshop_F`,
`Land_FuelStation_02_workshop_F`, `Land_FuelStation_03_shop_F`
**`stadium`** — `Land_Stadium_p4_F` `_p5_F` `_p9_F` `// REVIEW`

### industrial

**`factory`** — `Land_dp_mainFactory_F`, `Land_dp_smallFactory_F`,
`Land_DPP_01_mainFactory_F`, `Land_Factory_Main_F`, `Land_Factory_02_F`
**`warehouse_big`** — `Land_Warehouse_01_F` `_02_F` `_03_F`,
`Land_IndustrialShed_01_F`
**`warehouse_small`** — `Land_SM_01_shed_F` `// REVIEW`,
`Land_SM_01_shed_unfinished_F` `// REVIEW`;
`Land_Rail_Warehouse_Small_F` → `["+satellite","-anchor"]`
**`workshop`** — `Land_Workshop_01_F`…`_05_F`
**`autoshop`** — `Land_CarService_F`
**`shed_industrial`** — `Land_i_Shed_Ind_F`, `Land_i_Shed_Ind_old_F`,
`Land_u_Shed_Ind_F`, `Land_Metal_Shed_F`;
`Land_Shed_Ind_old_ruins_F` → `["+ruined"]`
**`storage_tank`** — `Land_dp_bigTank_old_F`, `Land_StorageTank_01_small_F`;
→ A: `Land_dp_bigTank_F`, `Land_StorageTank_01_large_F`;
→ `["-occupiable","-satellite"]`: `Land_dp_tankSmall_F`, `Land_dp_tankRound_F`,
`Land_Tank_rust_F`, `Land_Ind_TankSmall_F`, `Land_Ind_TankSmall2_EP1_F`,
`Land_Ind_SiloVelke_F`
**`chimney`** — `Land_Smokestack_01_F`, `Land_Smokestack_01_factory_F`,
`Land_SCF_01_chimney_F`
**`processing_plant`** — `Land_SCF_01_boilerBuilding_F` `_generalBuilding_F`
`_condenser_F` `_diffuser_F` `_clarifier_F` `_washer_F` `_crystallizer_F`
`_crystallizerTowers_F`, `Land_SCF_01_heap_bagasse_F` `// REVIEW`,
`Land_CementWorks_01_grey_F`, `Land_CementWorks_01_brick_F`;
→ S: `Land_SCF_01_feeder_F`, `Land_SCF_01_storageBin_big_F` `_medium_F` `_small_F`
**`mine_site`** — `Land_HaulTruck_01_abandoned_F` `// REVIEW`,
`Land_MiningShovel_01_abandoned_F` `// REVIEW`;
`Land_Mine_01_warehouse_F` → `["+anchor","-satellite"]`
**`pipeline`** — `Land_IndPipe1_ground_F`, `Land_IndPipe1_20m_F`,
`Land_Pipes_large_F` **(NEW)** `// REVIEW`
**`construction_site`** — `Land_Unfinished_Building_01_F`,
`Land_Unfinished_Building_02_F`, `Land_Unfinished_Building_01_noLadder_F`,
`Land_WIP_F`;
`Land_Unfinished_Building_01_ruins_F` → `["+ruined"]`;
`Land_Unfinished_Building_02_ruins_F` → `["+ruined"]`

### agricultural

**`barn_large`** — `Land_Barn_01_grey_F`, `Land_Barn_01_brown_F`,
`Land_Barn_03_large_F`, `Land_Barn_04_F`
**`barn_small`** — `Land_Barn_02_F`, `Land_Barn_03_small_F`
**`livestock_shed`** — `Land_Cowshed_01_B_F`, `Land_Cowshed_01_C_F`,
`Land_FeedShack_01_F`; `Land_Cowshed_01_A_F` → `["+anchor","-satellite"]`
**`sawmill`** — `Land_Sawmill_01_F`,
`Land_Sawmill_01_illuminati_tower_F` `// REVIEW`
**`windmill`** — `Land_i_Windmill01_F`, `Land_d_Windmill01_F`
**`greenhouse`** — `Land_Greenhouse_01_F`
**`grain_silo`** — `Land_Silo_01_F`, `Land_Silo_Wheat_F`
**`hunting_stand`** — `Land_DeerStand_02_F`

### medical

**`hospital`** — `Land_Hospital_main_F`, `Land_Hospital_side1_F`,
`Land_Hospital_side2_F`
**`clinic`** — `Land_HealthCenter_01_F`
**`field_hospital`** — all 33 `Land_MedicalTent_01_*` classes currently in
`_mainMilitary` (`tropic_closed`, `MTP_closed`, `greenhex_closed`,
`brownhex_closed`, `digital_closed`, `white_IDAP_med_closed`,
`white_generic_{closed,open,outer,inner}`, `white_IDAP_{closed,open,outer}`,
`aaf_generic_{inner,closed,open,outer}`, `NATO_generic_{inner,closed,open,outer}`,
`NATO_tropic_generic_{inner,closed,open,outer}`,
`CSAT_brownhex_generic_{inner,closed,open,outer}`,
`CSAT_greenhex_generic_{inner,closed,open,outer}`),
plus `Land_Medevac_HQ_V1_F`;
`Land_Medevac_house_V1_F` → `["+satellite","-anchor"]`
**`decon_facility`** — `Land_DeconTent_01_white_F` `_yellow_F` `_IDAP_F`
`_CSAT_brownhex_F` `_CSAT_greenhex_F` `_NATO_F` `_NATO_tropic_F` `_AAF_F` (8)

### religious

**`church`** — `Land_Church_01_F`, `Land_Church_02_F`, `Land_Church_03_F`,
`Land_Cathedral_01_F`, `Land_Church_01_V1_F`,
`Land_Church_04_{lightblue,yellow,white_red,red,damaged,yellow_damaged}_F`;
`Land_Church_05_F` → `["+satellite","-anchor"]`
**`chapel`** — `Land_Chapel_Small_V1_F` `_V2_F`, `Land_Chapel_V1_F` `_V2_F`,
`Land_Chapel_02_white_F`, `Land_Chapel_02_yellow_F`,
`Land_Chapel_02_white_damaged_F`, `Land_Chapel_02_yellow_damaged_F`
**`ruin_church`** — `Land_Chapel_02_white_ruins_F`,
`Land_Chapel_02_yellow_ruins_F`;
`Land_ChurchRuin_01_F` → `["+anchor","-satellite"]`
**`mausoleum`** — `Land_Mausoleum_01_F`
**`temple`** — `Land_Temple_Native_01_F` `// REVIEW`

### infrastructure

**`power_station`** — `Land_CoalPlant_01_MainBuilding_F`;
`Land_PowerStation_01_F` → `["+satellite","-anchor"]`;
`Land_PowerGenerator_F` **(NEW)** → `["-occupiable","-anchor"]` `// REVIEW`
**`power_substation`** — `Land_Substation_01_F`;
`Land_spp_Transformer_F` **(NEW)** → `["-occupiable","-satellite"]` `// REVIEW`
**`power_distribution`** — `Land_PowerLine_distributor_F`,
`Land_PowerPoleWooden_F` **(NEW / currently commented out)** `// REVIEW`,
`Land_PowerWave_pole_F`, `Land_PowerWave_pole_L_F`, `Land_PowerWave_pole_R_F`
**(NEW)** `// REVIEW`
**`solar_array`** — `Land_spp_Tower_F`;
`Land_spp_Panel_F` **(NEW)** → `["-occupiable","-anchor"]`
**`comms_tower`** — `Land_Communication_F`, `Land_TTowerBig_1_F`,
`Land_TTowerBig_2_F`
**`comms_relay`** — `Land_TTowerSmall_1_F` **(NEW)**,
`Land_TTowerSmall_2_F` **(NEW)**, `Land_Communication_anchor_F` **(NEW)** `// REVIEW`
**`water_facility`** — `Land_WaterStation_01_F`;
→ `["-occupiable","-satellite"]`: `Land_ReservoirTank_V1_F`,
`Land_WaterTower_01_F` **(NEW)**, `Land_WaterTank_F` **(NEW)**
**`fuel_infrastructure`** — `Land_FuelStation_Feed_F`
**`rail_station`** — `Land_Rail_Station_Big_F`
**`lighthouse`** — `Land_LightHouse_F`, `Land_Lighthouse_03_red_F`,
`Land_Lighthouse_03_green_F`;
`Land_Lighthouse_small_F` → `["+satellite","-anchor"]`
**`radar_site`** — `Land_Radar_F`, `Land_Radar_01_HQ_F`,
`Land_Radar_01_antenna_base_F`, `Land_Radar_01_kitchen_F` `// REVIEW`;
→ S: `Land_Radar_01_antenna_F`, `Land_Radar_01_cooler_F`,
`Land_MobileRadar_01_radar_F`;
`Land_Radar_Small_F` **(NEW)** → `["-occupiable","-anchor"]`
**`bridge`** — `Land_Bridge_HighWay_PathLod_F` `// REVIEW`,
`Land_Bridge_01_PathLod_F` `// REVIEW`, `Land_Bridge_Asphalt_PathLod_F` `// REVIEW`,
`Land_Bridge_Concrete_PathLod_F` `// REVIEW`, `Land_Canal_Wall_Stairs_F` `// REVIEW`,
`Land_Track_01_bridge_F` `// REVIEW`

### port

**`shipyard`** — `Land_SY_01_crusher_F`, `Land_SY_01_shiploader_F`,
`Land_SY_01_shiploader_arm_F`, `Land_DryDock_01_end_F`,
`Land_DryDock_01_middle_F`;
→ S: `Land_SY_01_reclaimer_F`, `Land_SY_01_conveyor_end_F`
**`container_terminal`** — `Land_ContainerLine_01_F` `_02_F` `_03_F`
**`pier`** — `Land_Pier_F`, `Land_Pier_small_F`, `Land_nav_pier_m_F`,
`Land_PierWooden_01_{dock,hut,platform,16m,10m_noRails}_F`,
`Land_PierWooden_02_{16m,30deg,ladder,barrel,hut}_F`
**`crane`** — `Land_Crane_F`, `Land_ContainerCrane_01_F`,
`Land_MobileCrane_01_F`, `Land_MobileCrane_01_hook_F`
**`navigation_aid`** — `Land_NavigLight_F`, `Land_Bollard_01_F`

### airport

**`terminal`** — `Land_Airport_01_terminal_F`, `Land_Airport_02_terminal_F`,
`Land_Airport_left_F`, `Land_Airport_right_F`
**`hangar`** — `Land_Airport_01_hangar_F`, `Land_Airport_02_hangar_left_F`,
`Land_Airport_02_hangar_right_F`, `Land_ServiceHangar_01_L_F`,
`Land_ServiceHangar_01_R_F`;
`Land_Hangar_F` → `["+military"]`
**`control_tower`** — `Land_Airport_01_controlTower_F`,
`Land_Airport_02_controlTower_F`, `Land_ControlTower_01_F`,
`Land_ControlTower_02_F`;
`Land_Airport_Tower_F` → `["+military"]`;
`Land_Airport_Tower_dam_F` → `["+military"]`

### law_enforcement

**`police_station`** — `Land_PoliceStation_01_F`

### military

**`barracks`** (13) — `Land_i_Barracks_V1_F`, `Land_i_Barracks_V2_F`,
`Land_u_Barracks_V2_F`, `Land_Barracks_01_camo_F`, `Land_Barracks_01_grey_F`,
`Land_Barracks_01_dilapidated_F`, `Land_Barracks_02_F` `_03_F` `_04_F` `_05_F`
`_06_F`, `Land_i_Barracks_V1_dam_F`, `Land_i_Barracks_V2_dam_F`
**`bunker`** (13) — `Land_Bunker_01_small_F`,
`Land_Bunker_02_{right,left,double,light_double,light_left,light_right}_F`;
→ A: `Land_Bunker_01_big_F`, `Land_Bunker_01_HQ_F`, `Land_Bunker_01_tall_F`,
`Land_PillboxBunker_01_big_F`, `Land_PillboxBunker_01_rectangle_F`,
`Land_PillboxBunker_01_hex_F`
**`guard_post`** (9) — `Land_GuardHouse_01_F`, `Land_GuardHouse_02_F`,
`Land_GuardHouse_02_grey_F`, `Land_GuardHouse_03_F`,
`Land_GuardBox_01_green_F`, `Land_GuardBox_01_brown_F`,
`Land_GuardBox_01_smooth_F`, `Land_GuardTower_01_F`, `Land_GuardTower_02_F`
**`cargo_structure`** (10) — `Cargo_Patrol_base_F`, `Cargo_Tower_base_F`,
`Land_Cargo_House_V1_F` `_V2_F` `_V3_F` `_V4_F`,
`Land_Cargo_House_V3_derelict_F`, `Land_Cargo_Tower_V3_derelict_F`;
`Land_Cargo_Patrol_V2_ruins_F` → `["+ruined"]`;
`Land_Cargo_Patrol_V3_ruins_F` → `["+ruined"]`
**`command_post`** (5) — `Cargo_HQ_base_F`, `Land_MilOffices_V1_F`,
`Land_Research_house_V1_F` `// REVIEW`, `Land_Research_HQ_F` `// REVIEW`,
`Land_Cargo_HQ_V3_derelict_F`
**`camp_tent`** (18) — `Land_ConnectorTent_01_white_{open,closed,cross}_F`,
`Land_ConnectorTent_01_CSAT_brownhex_{open,closed,cross}_F`,
`Land_ConnectorTent_01_CSAT_greenhex_{open,closed,cross}_F`,
`Land_ConnectorTent_01_NATO_{open,closed,cross}_F`,
`Land_ConnectorTent_01_NATO_tropic_{open,closed,cross}_F`,
`Land_ConnectorTent_01_AAF_{open,closed,cross}_F`
**`camp_house`** — `Land_Camp_House_01_brown_F`
**`helipad`** — `Land_HelipadCircle_F`, `Land_HelipadSquare_F`,
`Land_HelipadRescue_F`
**`fortification`** — `Land_HBarrier_Big_F`, `Land_HBarrier_1_F`
**`dome`** — `Land_Dome_Small_WIP_F` `// REVIEW`,
`Land_Dome_Small_WIP2_F` `// REVIEW`;
→ `["-occupiable","-satellite"]`: `Land_Dome_Big_F`, `Land_Dome_Small_F`

---

## A6 — Ambiguity list

`// REVIEW` rows in A5 are the agent's low-confidence guesses and go in the code
as comments. The subset below is where the agent **should not decide silently** —
write these into
`docs/overhauls/ambient_world/session_01_ambiguities.md` with the best guess, the
reasoning, and an explicit ask.

| # | Class(es) | Scaffold guess | The question |
|---|---|---|---|
| 1 | `Land_PowerPoleWooden_F` | `power_distribution`, non-occupiable | Currently commented out. There are *thousands* of instances on Altis — including it may swamp `infrastructure` counts at every location and shift tag thresholds. In or out? |
| 2 | `Land_Bridge_*_PathLod_F`, `Land_Canal_Wall_Stairs_F`, `Land_Track_01_bridge_F` | `bridge`, occupiable + satellite | These are in `_sideCivilian` today, so legacy says occupiable — but garrisoning a bridge pathing LOD is probably an existing bug. Keep occupiable (safe, no behavior change) or mark non-occupiable (correct, but changes `side`)? |
| 3 | `Land_Stadium_p4/p5/p9_F` | `commercial` / `stadium` | Is a stadium commercial, or does it want a `civic` / `recreation` category? Category vocabulary is fixed at 11, so `commercial` unless you want to reopen B15. |
| 4 | `Land_Research_HQ_F`, `Land_Research_house_V1_F` | `military` / `command_post` | Military research, or a civilian `research_facility` subtype under `industrial`? They sit on CSAT installations in vanilla. |
| 5 | `Land_WoodenWall_04_s_d_5m_F`, `Land_BrickWall_03_l_gate_F` | `residential` / `house_annex` | These are **walls**, not buildings. They are in `_sideCivilian` today. Keep them (no behavior change) or drop them from the garrison arrays entirely (correct, but changes `side`)? |
| 6 | `Land_HaulTruck_01_abandoned_F`, `Land_MiningShovel_01_abandoned_F` | `industrial` / `mine_site` | Abandoned vehicle props, not structures. Own `derelict_vehicle` subtype, or fine as mine dressing? |
| 7 | `Land_Caravan_01_rust_F` | `residential` / `shed_domestic` | A caravan **is** a dwelling, unlike a shed — so folding it into `shed_domestic` denies it `civilian_home`. Restore the `caravan` subtype, or accept? |
| 8 | `Land_i_Stone_Shed_V2_dam_F`, `Land_i_Stone_Shed_V3_dam_F` | `residential` / `shed_domestic` | Today these are in `_func_residential` alongside *houses*. The scaffold reads them as damaged sheds. Confirm. |
| 9 | `Land_Temple_Native_01_F` | `religious` / `temple` | Tanoa native temple — religious, or a `landmark`-only cultural site? |
| 10 | `Land_SM_01_shed_F`, `Land_SM_01_shed_unfinished_F` | `industrial` / `warehouse_small` | What is "SM"? Guessed from current `_func_industrial` membership. |
| 11 | `Land_SCF_01_heap_bagasse_F` | `industrial` / `processing_plant`, occupiable | It is a *heap*. In `_mainCivilian` today so legacy says occupiable; almost certainly shouldn't be. |
| 12 | `Land_Radar_01_kitchen_F` | `infrastructure` / `radar_site` | It is a kitchen building that happens to sit on a radar site. `radar_site` (site-coherent) or `military`/`cargo_structure` (building-coherent)? |
| 13 | The 11 **NEW** classnames | as listed in A5 | **Must be verified to exist in vanilla A3 with those exact names before shipping.** `Land_PowerWave_pole*` in particular is a guess at the family name. Any that don't resolve get dropped from Table 2 and listed here. |
| 14 | `Land_Sawmill_01_illuminati_tower_F` | `agricultural` / `sawmill` | Easter-egg object. Keep as sawmill dressing or drop? |
| 15 | `Land_Dome_Small_WIP_F`, `Land_Dome_Small_WIP2_F` | `military` / `dome` | "WIP" suggests construction, not a radome. `military`/`dome` or `industrial`/`construction_site`? They are in `_sideMilitary` today. |

**Verification rule for #13:** if a NEW classname cannot be confirmed, **omit the
row** rather than shipping a phantom. A phantom class is harmless to the legacy
keys (it is never matched) but pollutes the coverage report and assertion 23's
count, and it is exactly the kind of silent-no-op the `unitClassResolver` gotcha
warns about.

---

## A7 — Tier-1 suite `structure_catalog` (25 assertions)

Registered as an inline `_testSuites set ["structure_catalog", { ... }]` block in
`fnc_initServerDebug.sqf` — the established pattern. No per-suite file, no
`XEH_PREP` entry for the suite itself.

**Vocabulary & table integrity**
1. Every Table 2 class maps to a subtype that exists in Table 1.
2. Every Table 1 category is in the fixed 11-category vocabulary.
3. Every flag in Table 1, and every `+`/`-` override token in Table 2, is in the known flag vocabulary.
4. No classname appears twice in Table 2.
5. Every subtype has a non-empty `displayName`.
6. Every category has ≥1 subtype **and** ≥1 class.
21. Every Table 1 subtype is used by ≥1 Table 2 class *(no dead subtype left by a hand-edit)*.
23. Table 2 class count ≥ 560 *(a hand-edit cannot silently delete a block)*.

**Derivation correctness**
7. `main` ∪ `side` covers every `occupiable` class.
8. `main` ∩ `side` is empty.
9. `functionalLookup` is total over Table 2.
10. `nonOccupiableLookup` ∩ `functionalLookup` is empty.
20. Zero classes resolve to category `""` or `"unknown"`.
22. The shim returns all 11 legacy keys, each of the correct type, with `main isEqualTo (mainMilitary + mainCivilian)` and `side isEqualTo (sideMilitary + sideCivilian)`.

**Flag semantics**
13. Every `hvt_suitable` class is also `occupiable`.
14. No class is both `hvt_suitable` and `sentry_only`.
15. `hvt_suitable` ⊆ `hostage_suitable`.
16. Every `sabotage_target` / `hackable` class is also `infrastructure_node`.
17. Every class in category `military` carries flag `military` *(B23 invariant)*.
18. ≥1 class **outside** category `military` carries flag `military` *(proves crossover)*.
19. No affiliation flag exists in the vocabulary — no `law_enforcement`, `police`, or `insurgent` flag *(B25; stops a later pass re-introducing intrinsic affiliation)*.
25. Derived-flag sanity: ≥1 class has `civilian_home`, ≥1 has `workplace`, ≥1 has `public_access`; **no `ruined` class has `civilian_home`**.

**Behavior**
11. `fnc_resolveStructureInfo` on an unknown class returns a well-formed record and does not throw.
12. Catalog build is idempotent and cached — a second call returns the **same reference**. *(Probe: write a sentinel key via handle A, read it via handle B, then delete it.)*
24. **Canary set** — these resolve exactly as stated:

| Class | subtype | category | also |
|---|---|---|---|
| `Land_School_01_F` | `school` | `commercial` | |
| `Land_CoalPlant_01_MainBuilding_F` | `power_station` | `infrastructure` | `sabotage_target` |
| `Land_FuelStation_Build_F` | `fuel_station` | `commercial` | |
| `Land_ReservoirTank_V1_F` | `water_facility` | `infrastructure` | NOT `occupiable` |
| `Land_spp_Tower_F` | `solar_array` | `infrastructure` | |
| `Land_Hangar_F` | `hangar` | `airport` | flag `military` |
| `Land_i_Barracks_V1_F` | `barracks` | `military` | flag `military`, `hvt_suitable` |
| `Land_dp_bigTank_old_F` | `storage_tank` | `industrial` | `sentry_only`, NOT `hvt_suitable` |
| `Land_PoliceStation_01_F` | `police_station` | `law_enforcement` | |
| `Land_MedicalTent_01_MTP_closed_F` | `field_hospital` | `medical` | flag `military` |
| `Land_Communication_F` | `comms_tower` | `infrastructure` | `hackable`, NOT `occupiable` |
| `Land_Slum_House01_F` | `slum` | `residential` | `civilian_home` |

**Coverage report** — printed once per run via `INFO`, not asserted: class count
per category, class count per subtype, count of rows still carrying `// REVIEW`,
and Table 2 total vs. the pre-session class count. This is how the owner tracks
hand-editing progress.

---

## A8 — Gotchas for the build session

- **CBA log-macro comma counting.** This session is wall-to-wall
  `count (_x get "flags")` and `getOrDefault ["k", v]`. **Every** inline array
  literal inside a `LOG_n` / `INFO_n` / `WARNING_n` / `ERROR_n` / `TRACE_n` arg
  breaks the HEMTT build. Hoist to a `private _tmp = …;` first. The coverage
  report is the highest-risk spot — build the string with `format` and emit a
  single `INFO(_msg)`.
- **Unknown subtype / unknown flag must be loud.** The `unitClassResolver`
  precedent: a typo'd key hit a `default` branch and silently shipped a CSAT
  officer into a Syndikat mission. A typo'd subtype or flag here must `ERROR`
  during catalog build, not silently produce an empty flag set.
- **Warn once per class, not once per call.** `fnc_resolveStructureInfo` is
  called per structure during a scan — thousands of times. Gate the unknown-class
  `WARNING` on a `DSC_structureUnknownWarned` hashmap.
- **Cache in `missionNamespace`, never `uiNamespace`.** `uiNamespace` survives a
  mission restart and will serve a stale table across dev iterations — this would
  present as "my hand-edit did nothing".
- **Build once.** 565 classes × flag-set derivation per location is a real cost.
  The derivation runs on first call only.
- **`exclusions` stays hand-authored per map** and is not derivable from
  category/subtype. Move it verbatim.
- **Do not change scan behavior beyond A9.** `fnc_scanLocations` is untouched.
  The location set, anchor count and main/side counts must be identical.
- **A phantom classname is not harmless.** It never matches at runtime, so it
  produces no error — it just inflates the coverage report and hides a real gap.
  Verify the NEW classes (A6 #13) or omit them.

---

## A9 — Expected `functionalLookup` deltas (the one accepted behavior change)

**This session is *not* fully behaviorally invisible, and pretending otherwise
will make the playtest read as a regression.** The legacy garrison keys are
byte-identical, but `functionalLookup` / `functionalCategories` /
`nonOccupiable*` change — that is the mandated point of the session. Expected,
and nothing else:

| # | Change | Cause |
|---|---|---|
| 1 | **A `military` key appears in `functionalCategories` / `functionalLookup` for the first time**, carrying ~90 classes | B23. Previously `military` existed only in `nonOccupiable`. **This is the largest delta and will change `functionalProfile` at every military location.** |
| 2 | 33 `MedicalTent` + `Medevac_HQ` + `Medevac_house` and 8 `DeconTent` → `medical` | B26; they had no category |
| 3 | 7 radar component classes → `infrastructure` | README military-residue table |
| 4 | 6 damaged shop classes (`Land_i_Shop_01_V2_dam_F` etc.) move `residential` → `commercial` | verified miscategorisation |
| 5 | `Land_CoalPlant_01_MainBuilding_F`, `Land_spp_Tower_F` move `industrial` → `infrastructure` | README |
| 6 | `Land_ReservoirTank_V1_F` moves non-occupiable `industrial` → non-occupiable `infrastructure` | README |
| 7 | `Land_FuelStation_Build_F`, `Land_FuelStation_Shed_F` move `infrastructure` → `commercial` | B22 |
| 8 | `Land_WIP_F` moves `commercial` → `industrial` | it is an unfinished building, not a shop |
| 9 | ~14 `Land_Shed_01..14_F` → `residential` (new) | had no category |
| 10 | `Land_Unfinished_Building_*` (4) → `industrial` (new) | had no category |
| 11 | `Land_Stadium_p*_F` (3) → `commercial` (new) | had no category |
| 12 | 6 bridge/track classes → `infrastructure` (new) | had no category |
| 13 | `Land_FireEscape_01_*` (2), `Land_CastleRuins_01_bastion_F`, `Land_Caravan_01_rust_F`, `Land_Highway_Pillar_01_garage_F`, 2 wall classes → `residential` (new) | had no category |
| 14 | `Land_DeerStand_02_F` → `agricultural` (new) | had no category |
| 15 | up to 11 NEW infrastructure classes added to `infrastructure` | README "Classes to add" |

**Required of the build session:** emit the per-category class-count table in the
coverage report so the owner can diff it against this list directly. Any
category shift **not** on this list is a bug.

---

## A10 — Hand-offs

| To | What |
|---|---|
| **Session 02** | `fnc_resolveStructureAffiliation` — resolves army / police / insurgent / derelict from the host location's `isMilitary` / `militaryTier` / influence controller. The catalog is deliberately context-free (B25). |
| **Session 02** | Non-occupiable POIs become first-class. `byFlag get "infrastructure_node"` is the query that makes that worth doing. |
| **Session 05** | The `civilian_home` fallback cascade (A0.1): prefer `civilian_home`, else `occupiable ∧ residential`, else any `occupiable`. Mirrors `fnc_setupGarrison`'s side-promotion. **Not shipped in Session 01.** |
| **Session 10** | `sentry_only` and `hvt_suitable` are the flags that stop an HVT being placed on a fuel tank. |
| **Session 12** | `sabotage_target` / `hackable` are *affordance* flags only. The effects registry — what the action actually does — is Session 12's, and must not be back-ported into this table. |
