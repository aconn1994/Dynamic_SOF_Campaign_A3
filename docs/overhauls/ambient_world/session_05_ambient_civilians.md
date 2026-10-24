# Session 05 — Ambient Civilians in the Presence Manager

**Owner item:** 3
**Model:** Opus spec → Sonnet build
**Ships:** Tag/POI-driven civilian density and placement, role-anchored
behavior, night falloff, position validation, and civilian budget priority.
**Depends on:** 01, 02, 04.

> **This session sets the program exit criterion.** By its close there is a
> populated, tagged world to judge. Record the exit criterion in the README
> Decision Log before moving on.

---

## Scope

### 1. Density and mix from location character

Replace the uniform `fnc_resolveCivilianMix` baseline with a resolver that reads
the Session 02 `subtypeProfile` and `poiBySubtype`, not just coarse tags.

- A city with apartment blocks, shops, and a school gets **urban** density and
  an urban mix.
- A hamlet of four small houses gets **two or three residents**, not a city
  draw scaled down.
- An isolated compound gets **whoever lives there** — possibly nobody.
- Count scales off *occupiable residential capacity*, not location radius.

### 2. Role-anchored placement and behavior

Each spawned civilian is anchored to a POI appropriate to its archetype
(`anchorSubtypes` / `anchorFlags` from Session 04) and given behavior from the
intent vocabulary:

| Intent | Implementation sketch |
|---|---|
| `IDLE_ANCHORED` | stays within ~15m of its anchor building, idle animations |
| `WORK_LOOP` | short waypoint loop between 2–4 positions at/near the workplace |
| `WANDER_LOCAL` | current behavior, but bounded to the **built-up footprint**, not the location radius |
| `STAND_POST` | static at a door/counter position |
| `TRANSIT` | road-following between two points, the only long-range mover |

**No time-of-day job scheduling** (owner decision C11).

### 3. Night falloff

Populated areas get quieter after dark. One multiplier, applied per archetype
(`nightPresence`), driven by `sunOrMoon` or `daytime` rather than a hard hour
cutoff so it survives Session 11's seasonal date changes.

### 4. Position validation — the "civilians in the woods" fix

`fnc_setupCivilians`'s fallback spawn (raw polar offset, `z = 0`, no validation)
is replaced with a validated placement helper:

- Prefer a building position from the anchor POI.
- Then a road position within the built-up footprint.
- Then `BIS_fnc_findSafePos` constrained to the footprint, rejecting water and
  steep slope.
- If all fail, **spawn fewer civilians** — do not place one badly. An empty
  patch of ground reads better than a man in a suit standing in a forest.

### 5. Budget priority

Owner decision C14: civilians get priority. Split the presence manager's single
cap into a **civilian reservation** plus a military allowance, so ambient
military can be throttled hard (pending Session 10) without starving the
population.

---

## Tier-1 test plan (`suite: ambient_civilians`)

Push the decisions into pure functions so they test headlessly. The spawner
stays impure; the *math* must not.

- `fnc_resolveCivilianDensity` — pure. `[subtypeProfile, tags, timeFactor, budget] → count`.
  - A 4-house hamlet yields a small count; a 60-building city yields a large one.
  - Night factor reduces count monotonically.
  - Count never exceeds the supplied budget.
  - Zero residential capacity yields zero (an industrial-only zone has no residents).
- `fnc_resolveCivilianMix` v2 — pure.
  - Weights sum > 0 and every key resolves to a Session 04 archetype
    (**cross-table integrity assertion**).
  - A farm-heavy profile yields a `FARMER`-dominant mix.
  - A city profile does **not** yield `FARMER`-dominant.
- `fnc_resolveCivilianAnchor` — pure over a mock POI index.
  - Returns a POI matching the archetype's `anchorSubtypes` when one exists.
  - Falls back to `anchorFlags`, then to any residential, then `objNull`.
  - Never returns a `sentry_only` POI.
- Budget split: civilian reservation is honored when the military allowance is
  saturated.

---

## Gotchas

- **Yield convention.** `fnc_setupCivilians` already `uiSleep 0.15`s between
  creates. Any new spawn path keeps it. `uiSleep`, not `sleep`.
- **`joinSilent` after `createUnit`** — existing code does it; preserve it.
- **Civilians must never be C2-stamped** — the presence dispatcher's
  `side != civilian` filter is load-bearing.
- **`enableDynamicSimulation true`** on every civilian group (already done).
- **Dead-object refs in POI indices** — null-check before using an anchor
  (Session 02 gotcha).
- **Do not touch the military blocks of `fnc_presenceHandlerPopulatedArea`**
  beyond the budget split. There are **three** independent military blocks in
  that function (`AGENTS.md`) and reworking them is Session 10.
- **`distance2D` precedence** in any footprint math — parenthesise.

---

## Definition of done

- New resolvers registered in `XEH_PREP.hpp`; `hemtt check` clean.
- Tier-1 `ambient_civilians` passing.
- A `DSC_testConfig` block exists that boots **only** scan + presence +
  civilians, so the population can be judged without a mission running.
- Playtest (the real gate):
  - [ ] Kavala reads as a city; a coastal hamlet reads as a hamlet.
  - [ ] **Zero civilians in forests, fields far from buildings, or on water.**
  - [ ] Farmers are near barns; workers near industry; nobody in a suit at a
        remote compound.
  - [ ] Noticeably fewer people out at 0300 than 1300.
  - [ ] Frame cost acceptable with the civilian budget raised.
- Exit criterion for the program decided and recorded in the README.
- `.crush/presence-manager.md` updated; `AGENTS.md` key-systems table updated.
