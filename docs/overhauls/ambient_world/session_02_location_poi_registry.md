# Session 02 — Location POI Registry

**Owner item:** 1 (Location Tagging, part B)
**Model:** Sonnet (spec below is complete once Session 01 lands)
**Ships:** Every location retains per-structure identity, plus a query API, so
the mission generator and briefing composer can name specific buildings.
**Depends on:** Session 01.

---

## The finding that makes this cheap

`fnc_scanLocations` Stage 1 already builds, for every enterable structure on the
map:

```sqf
_structureClasses    // classname per structure
_structureMilitary   // bool per structure
_structureFunctional // functional category per structure
_structIndexMap      // object -> index into the above
```

Stage 3 assigns structures to anchors. Stage 4 then uses `_structIndexMap` to
compute `mainCount` / `sideCount` / `militaryCount` / `functionalProfile` —
**and throws the per-structure data away.**

So this session is *stop discarding it*. There is **no additional world query,
no additional `typeOf` pass, and no additional scan time.** The only new cost is
one subtype-index hashmap per location.

---

## Scope change: non-occupiable POIs are first-class

Added while answering Q2 (October 2026). **This is the most important part of
the session, and it is not a free ride like the occupiable POIs are.**

Today, `fnc_scanLocations` Stage 1 **discards** every non-enterable structure:

```sqf
if ((_struct buildingPos -1) isEqualTo []) then { continue };
```

Stage 4 later does a *separate* nearby-object scan (including `"Thing"`) purely
to increment `functionalProfile` counts. **The objects themselves are never
retained anywhere.**

But non-occupiable objects are exactly what the owner wants to act on:
`Land_Communication_F` and `Land_TTowerBig_*` (hack / sabotage, Session 12),
`Land_PowerStation_01_F` and `Land_Substation_01_F` (shut down / destroy),
fuel tanks and silos (`sentry_only` perches, Session 10).

So: Stage 4's non-occupiable scan must **retain object references** into the
same POI indices, not just count them. Non-occupiable POIs simply lack the
`occupiable` flag; every query path treats them identically otherwise.

**Watch the cost here.** Unlike the occupiable path (where the data is already
computed and merely discarded), this one re-scans per location and includes
`"Thing"`. Measure it. If it is expensive, restrict retention to classes
carrying `landmark` / `infrastructure_node` / `sentry_only` rather than
retaining everything.

---

## Target

Each location hashmap gains:

| Key | Shape | Purpose |
|---|---|---|
| `poiBySubtype` | HASHMAP `subtype -> [objects]` | "find me the school in this town" |
| `poiByCategory` | HASHMAP `category -> [objects]` | "find me a medical building" |
| `poiByFlag` | HASHMAP `flag -> [objects]` | "find me a `sentry_only` perch" / "find me an `hvt_suitable` interior" |
| `subtypeProfile` | HASHMAP `subtype -> count` | tagging + briefing flavor, sibling to the existing `functionalProfile` |

Existing keys (`structures`, `mainStructures`, `sideStructures`,
`functionalProfile`, `tags`, `primaryFunction`) are **unchanged**. This is
purely additive.

### Richer tags, derived from subtypes

The existing tag pass gains subtype-driven tags the owner's briefing examples
need: `has_school`, `has_police`, `has_clinic`, `has_church`, `has_fuel`,
`has_warehouse`, etc. Rule: emit `has_<subtype>` for subtypes marked
`landmark` in the catalog (keeps the tag list from exploding to 60 entries).

Also sharpen the urban/rural read the owner asked for — a location's
**subtype mix**, not just building count, should drive `urban` vs `rural`
(a settlement of 12 barns is rural; 12 apartment blocks is urban).

---

## Deliverables

1. **`fnc_scanLocations`** — Stage 4 retains per-structure records and builds
   the four new indices. Subtype comes from `fnc_resolveStructureInfo`.
2. **`fnc_queryLocationPOIs`** — **pure.**
   `[_location, _filter] → [objects]` where `_filter` is a hashmap supporting
   `subtype` / `subtypes` / `category` / `flag` / `flags` (all-of) /
   `anyFlag` (any-of) / `excludeFlags` / `near` (`[pos, radius]`) /
   `limit` / `random` (bool).
   Returns `[]` on no match — callers treat empty as "this location can't host
   that", not as an error.
3. **`fnc_describeStructure`** — **pure.** `[_object] → STRING` using the
   catalog display name, e.g. `"a school"`. Optional grid-reference variant for
   briefings: `"the police station at 034-112"`.
4. **`fnc_resolveStructureAffiliation`** — **pure.** `[_structureInfo, _location]
   → STRING`. Decision B25: the catalog is context-free, so *who occupies a
   structure* is resolved here from the host location.

   The owner's case: a barracks on an airbase is an **army** barracks; the same
   class standing alone in a city with no military installation is a **police /
   civil-defence / derelict** barracks, and a great mission compound.

   Inputs are the location's `isMilitary`, `militaryTier`, influence
   controller, and surrounding `subtypeProfile`. Output vocabulary:
   `military` · `law_enforcement` · `civil` · `derelict` · `unknown`.

   Affects the **display name** (`"the police barracks"` vs
   `"the barracks"`), and is a *hint* to later sessions' population and
   mission logic — it must not be load-bearing yet.
5. **Tag pass extension** — `has_<landmark subtype>` tags + subtype-weighted
   urban/rural classification.

---

## Tier-1 test plan (`suite: location_poi`)

`fnc_queryLocationPOIs` and `fnc_describeStructure` are pure, so they test
headlessly against a **mock location hashmap** — no Arma world, no scan.

| Assertion | Why |
|---|---|
| Query by `subtype` returns only that subtype | basic |
| Query by `category` returns the union of its subtypes | derivation is consistent |
| Query by `flags` is **all-of**; `anyFlag` is **any-of** | easy to get backwards |
| `excludeFlags` removes `sentry_only` from an HVT query | the owner's stated use case, pinned |
| Empty/missing index returns `[]`, never `nil`, never throws | locations scanned before this session, or with no buildings |
| `limit` caps result count; `random` does not change the result *set* | |
| Query on a location with no `poiBySubtype` key degrades to `[]` + one WARN | forward/backward compat |
| A non-occupiable POI (comms tower) is returned by a `subtype` query | the Session 12 dependency, pinned |
| An `occupiable: true` filter excludes non-occupiable POIs | garrison code must not try to enter a fuel tank |
| A `barracks` in a location with `isMilitary == true` resolves affiliation `military` | Decision B25, the owner's airbase case |
| The **same** `barracks` subtype in a civilian location with no military tier resolves `law_enforcement` or `civil`, **not** `military` | Decision B25, the owner's lone-city-compound case — the whole point, pinned |
| A `ruined` barracks in a civilian location resolves `derelict` | |
| Affiliation on a location with missing context fields returns `unknown`, never throws | locations predating this session |
| `fnc_describeStructure` reflects affiliation (`"the police barracks"` vs `"the barracks"`) | briefing quality is the visible payoff |
| `fnc_describeStructure` on an unknown class returns a generic string, not `""` | briefings must never render an empty noun |
| Mock location with 1 school + 3 houses yields the expected `subtypeProfile` | |
| `has_school` tag emitted only when a `landmark` subtype is present | tag explosion guard |

---

## Gotchas for this session

- **Memory shape.** Store **object references** in the indices, not copies. A
  location's `structures` array already holds the same refs; the indices are
  additional pointers, not additional objects.
- **Dead/deleted objects.** Indices are built once at init and hold refs for the
  whole campaign. Any consumer must null-check (`!isNull _x`) — destroyed
  buildings remain in the index. Document this; do **not** add a sweep.
- **`fnc_scanLocations` Stage 3.5 orphan recovery** creates synthetic anchors.
  Those must get indices too, or the orphan locations silently can't host
  POI-driven missions.
- **Do not change existing keys.** `functionalProfile` stays; `subtypeProfile`
  is its sibling. Several consumers read `functionalProfile` and
  `primaryFunction`.
- **Scan-time regression is the risk.** Measure. The occupiable path adds no
  work (the data is already computed and discarded), but the **non-occupiable
  retention path does re-scan per location including `"Thing"`**. Log scan
  duration before and after; if it regresses, narrow retention to
  `landmark` / `infrastructure_node` / `sentry_only` classes.
- **`distance2D` precedence** — the `near` filter will divide/compare distances.
  Parenthesise: `((_x distance2D _pos) < _r)`.

---

## Definition of done

- New functions registered in `XEH_PREP.hpp`.
- `hemtt check` clean.
- Tier-1 suite `location_poi` registered and passing.
- Altis scan summary logs subtype distribution; **scan duration within noise of
  the pre-session baseline** (log it).
- A throwaway debug command can answer *"give me the school in Kavala"* and get
  an object back.
- Docs: `.crush/architecture.md` location-hashmap schema updated; `AGENTS.md`
  key-systems table updated.

---

## Human playtest checklist

- [ ] `PASS: location_poi` in RPT.
- [ ] Scan duration vs baseline — log both. The non-occupiable retention is the
      part that can actually cost something.
- [ ] Confirm comms towers and power stations appear as queryable POIs, not
      just as `functionalProfile` counts.
- [ ] Find a lone barracks in a city with no military installation — confirm it
      resolves to a non-`military` affiliation and describes as such. This is
      the owner's "cool mission site" case and the reason B25 exists.
- [ ] Subtype distribution per location type reads correctly: Kavala should have
      shops/apartments/a school; a coastal hamlet should have small houses and
      maybe a pier.
- [ ] Spot-check 3 locations in-game: does `poiBySubtype` match what you can see
      standing there?
- [ ] Confirm orphan-recovery locations (`source == "orphan"`) have indices too.
