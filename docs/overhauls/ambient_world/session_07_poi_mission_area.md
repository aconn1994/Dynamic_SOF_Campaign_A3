# Session 07 — POI-Driven Mission Area

**Owner item:** 4
**Model:** Opus spec → Sonnet build
**Ships:** A one-off mission whose area is composed **deliberately** from
location POIs, with the full Intel Ledger loop exercised.
**Depends on:** 01, 02, 04, 05.

---

## Purpose

This is the **proof session** for the world layer. Everything before it is
infrastructure; this is where the owner finds out whether a tagged, populated
world actually produces a better mission than a random one.

The owner's framing: *"Spawn one off mission area utilizing location tagging,
with full intel ledger to test meticulous creation of mission area."*

---

## What "deliberate" means

Today, `fnc_generateRaidMission` picks positions from `location.structures` —
an undifferentiated bag. With POIs it can reason:

| Decision | Today | With POIs |
|---|---|---|
| Where is the HVT? | a random deep building | an `hvt_suitable` interior — the school, the estate, the police station |
| Where are the guards? | scattered | `sentry_only` perches, plus the buildings adjacent to the HVT's |
| Where is the intel? | random interior | an office/admin POI in the same compound |
| What does the briefing say? | generic | *"The HVT and his security have taken over the school on the north edge of town."* |
| Where does a QRF come from? | a nearby installation | a named POI — *"the abandoned police barracks"* |

**The briefing is the test.** If the composer can name real buildings, the POI
layer works.

---

## Scope

1. **POI-aware placement strategy** — a new strategy in
   `addons/core/functions/placement/` that takes a POI filter instead of a raw
   structure list, and dispatches through the existing
   `fnc_placeInDeepBuilding` / `fnc_placeInterior` once it has chosen a POI.
   Do **not** rewrite the existing strategies; select *into* them.
2. **Mission template authoring** — one AFO-shaped objective and one DA-shaped
   objective over the **same** POI-selected site, so the difference between them
   is visible and the Session 08 spotting/compromise work has something to
   differentiate.
3. **Briefing composer wiring** — `fnc_composeBriefing` (campaign overhaul
   Session 04) consumes `fnc_describeStructure` output. This is the first time
   it has something interesting to say.
4. **Intel Ledger loop** — the objective yields a token via the existing
   interaction-site → `fnc_buildIntelTokenFromSite` → `fnc_intelAdd` seam
   (campaign overhaul Session 05). **No new ledger writers.** The retrofit
   bridge in the mission loop remains the only writer.
5. **Tier-2 harness config** — a `DSC_testConfig` block that spawns the player
   near a chosen POI-rich town and runs exactly one mission.

---

## Explicitly out of scope

- Do **not** revive SWEEP. Its deferral stands.
- Do **not** build the series/thread chaining yet. One mission, one token.
  AFO→DA chaining is the program exit criterion and comes after Session 08
  makes the two feel different.
- Do **not** touch military presence. Session 10.

---

## Tier-1 test plan (`suite: poi_mission`)

- POI selection for a mission site is pure over a mock location:
  - An `hvt_suitable` POI is chosen when one exists.
  - A `sentry_only` POI is **never** chosen for an HVT (pinned assertion).
  - Falls back gracefully when a location has no `hvt_suitable` POI — the
    mission must still generate (`AGENTS.md` posture: degrade loudly, stay
    coherent).
- Briefing composition over a mock POI set produces a string containing the
  POI's display name and no empty nouns.
- Token context built from a POI-based site carries the POI subtype, and the
  resulting token validates against the ledger schema.

---

## Gotchas

- **`raidConfig` nests INSIDE the template**, not beside it. A template's
  `completion` / `interactionSites` must live under
  `["raidConfig", createHashMapFromArray [...]]` or they silently do nothing
  (`AGENTS.md`).
- **`fnc_cleanupMission` must remove every mission-scoped interaction site**
  (`missionScoped: true`), same as it clears C2 QRFs.
- **Harness runs need `"c2"` in `steps`** if the mission expects any enemy
  reaction; without a node in reach, groups are never stamped and the absence
  looks like a broken feature.
- **Dead-object refs** in POI indices — null-check before placing into a POI.
- **A POI can be destroyed between selection and use.** Re-validate at placement.
- **The known gap from campaign overhaul Session 5 still exists**: a
  roving/presence body despawns before its "Search Body" site does. Do not
  re-fix it here; just do not make it worse.

---

## Definition of done

- POI placement strategy registered; `hemtt check` clean; Tier-1 `poi_mission` passing.
- A `DSC_testConfig` block is committed and documented.
- Playtest:
  - [ ] The briefing names a real, findable building.
  - [ ] Going to that building finds the objective there.
  - [ ] An intel token lands in `DSC_intelLedger` and survives to debrief.
  - [ ] Running the same template twice on different towns produces visibly
        different missions.
- `.crush/mission-archetypes.md` + `.crush/intel-ledger.md` updated.
