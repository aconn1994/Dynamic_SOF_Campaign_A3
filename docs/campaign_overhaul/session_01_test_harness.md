# Session 1 — Test Harness (`fnc_runTests` + `fnc_initTestScenario`)

**Phase:** 0 (seams) · **Model:** Sonnet (spec is complete below) · **Ships:**
the testing ruler — no gameplay change.

> Build the ruler before you measure. This is not a campaign feature, but it is
> the highest-leverage first move: small, deterministic, mostly headless, and it
> makes every later session cheaper to iterate.

---

## Why this first

`campaign-overhaul.md` §9.1 step 1. Everything downstream is verified through
these two functions:
- `fnc_runTests` — a debug-only registry+runner that executes Tier-1 assertion
  suites and logs `PASS/FAIL: <name>` + a summary to RPT. The agent's
  self-verification lives here.
- `fnc_initTestScenario` — a deterministic harness that boots **only** the init
  steps a feature needs, forces a mission template, generates **one** mission,
  and places the player near the site — no infinite loop, no ambient noise.

---

## Read before building

- `.crush/agentic-workflow-and-testing.md` **Part B** (B.2 tiers, B.3 the
  `fnc_initTestScenario` design + the init-step dependency map, B.4 where test
  missions live). This is the spec — follow its `DSC_testConfig` shape and step
  whitelist verbatim.
- `addons/core/functions/init/fnc_initServer.sqf` — the monolith being
  decomposed. Note STEP 0 (globals + dynamic sim), STEP 1 `scanLocations`, STEP 2
  `initFactionData`, STEP 3 `initInfluence`, STEP 4c/d/e (C2/presence/roving),
  STEP 5 the mission loop. The harness runs a **whitelisted subset** of these,
  then a single-shot version of STEP 5's body.
- `AGENTS.md` §"Debug Modes" + §"SQF Conventions" (CBA log macros, `PREP_SUB`).
- Exemplar for a data-returning registry function: `fnc_getCompletionTypes.sqf`.
- Exemplar for the single-shot mission body: `fnc_initServer.sqf` lines ~518–631
  (the `spawn` block) — `fnc_initTestScenario` must call the **same** generation
  functions (`selectMission` → `generateMission` → `evaluateCompletion` →
  `buildMissionOutcome`), just without the `while {true}` and with a forced
  template. **If it forks the generation path it stops testing the real thing.**

---

## Deliverables

1. **`DSC_core_fnc_runTests`** (`addons/core/functions/debug/fnc_runTests.sqf`)
   - Reads a registry global `DSC_testSuites` (hashmap: `name -> CODE`), where each
     suite `CODE` returns an array of `[label, bool]` results (or calls a shared
     `assert` helper — your call, keep it simple).
   - Executes every suite, logs `PASS: <suite>/<label>` or `FAIL: <suite>/<label>`
     per assertion via CBA `INFO`/`ERROR`, and a final summary
     `runTests: N passed, M failed`.
   - Returns `[passed, failed]`. Debug-only guard is fine (it lives in `debug/`).
   - Provide a tiny `DSC_core_fnc_assert`-style helper **or** a documented result
     shape so later sessions can register suites trivially. Document the
     registration contract in the function header.
2. **`DSC_core_fnc_initTestScenario`** (`addons/core/functions/init/fnc_initTestScenario.sqf`)
   - Reads `DSC_testConfig` (shape exactly as `agentic-workflow-and-testing.md`
     §B.3). Fields: `factionProfile`, `steps` (whitelist), `missionTemplate`,
     `singleShot`, `playerSpawn`, `timeOfDay`, `freezeWeather`, `extraDebug`.
   - Runs only the whitelisted init steps, in dependency order, reusing the **real**
     functions from `fnc_initServer` (do not copy their bodies — call them).
     Implement the **init-step map** from §B.3: `globals` (STEP 0), `locations`,
     `factions`, `influence`, and leave hooks for `c2`/`presence`/`roving`/`bft`
     (off by default).
   - Applies `timeOfDay` (`setDate`) and `freezeWeather` deterministically.
   - Forces the template into `selectMission` (no random path), runs
     `generateMission`, and — if `singleShot` — runs one debrief cycle
     (`evaluateCompletion` → `buildMissionOutcome` → publish
     `DSC_lastMissionOutcome`) instead of looping.
   - `playerSpawn == "nearSite"` teleports the player ~150m from the objective.
3. **Register both** in `addons/core/XEH_PREP.hpp` (`PREP_SUB(debug,runTests);`
   and `PREP_SUB(init,initTestScenario);`).
4. **A first self-test suite** proving `fnc_runTests` works: one trivially-true
   and one trivially-false assertion in a suite named `harness_selftest`, so the
   summary line shows both a pass and a fail. (Later sessions replace/extend.)
5. **Wire the launch switch** — flip `.hemtt/launch.toml` to a commented preset
   pattern that documents how to point at `test.VR` (Tier-1) vs `DSC_Altis.Altis`
   (Tier-2/3). Do **not** break the current default. `test.VR` already exists
   (`.hemtt/missions/test.VR/`); its `initServer.sqf` currently calls the real
   init — add a **commented** `fnc_runTests` invocation there and document how to
   enable it, but leave the default behavior intact.
6. **Commit `DSC_testConfig` examples** under `docs/test_harness/` (create it): one
   headless block (VR, `steps: [globals]`, run suites) and one Tier-2 block
   (`DSC_Test.Altis` pattern, `steps: [globals,locations,factions,influence]`,
   forced template, `singleShot`).

---

## Definition of done

- [ ] `fnc_runTests` + `fnc_initTestScenario` written, headered, and `PREP_SUB`'d.
- [ ] `hemtt check` clean.
- [ ] `harness_selftest` suite registered; `fnc_runTests` prints one PASS and one
      FAIL and a correct summary in RPT.
- [ ] `fnc_initTestScenario` boots `globals+locations+factions+influence`, forces a
      `KILL_CAPTURE` template at a fixed location, generates exactly one mission,
      and stops (no loop) — verified in RPT.
- [ ] `docs/test_harness/` holds the two example `DSC_testConfig` blocks.
- [ ] `roadmap.md` notes the harness exists.

---

## Tier-1 expectations (what the agent verifies itself)

- The runner correctly tallies passes/fails and the summary matches.
- Registering a suite is a one-liner (`DSC_testSuites set ["name", { ... }]`).

## Playtest steps (human — Tier-2 smoke only)

1. `hemtt build`, launch with `test.VR` active and the commented `fnc_runTests`
   line enabled. Confirm RPT shows `PASS`/`FAIL`/summary lines.
2. Point the harness at `DSC_Altis.Altis` with the Tier-2 `DSC_testConfig`,
   launch, confirm: exactly one mission spawns near you, no second mission spawns,
   no presence/roving/C2 noise in RPT.
3. Filtered RPT (`DSC:` lines) + verdict → `docs/playtest_notes/<date>/`.

## Gotchas to respect

- `fnc_initTestScenario` must **call** the real init functions, never re-implement
  them (§B.3 design constraint).
- Aircraft/`setDate`/weather determinism: set them *before* generation so the
  mission composes against fixed conditions.
- CBA log-macro comma trap: hoist any inline array literal to a local first.

---

## Paste-ready prompt

```
Read docs/campaign_overhaul/WORKFLOW_RULES.md and
docs/campaign_overhaul/session_01_test_harness.md, then build exactly what that
work order specifies: DSC_core_fnc_runTests and DSC_core_fnc_initTestScenario,
following .crush/agentic-workflow-and-testing.md Part B (use the DSC_testConfig
shape and init-step map from §B.3 verbatim). Reuse the real init functions from
fnc_initServer.sqf — do not fork the generation path. Register both in
XEH_PREP.hpp, add the harness_selftest suite, commit the two example
DSC_testConfig blocks under docs/test_harness/, keep hemtt check clean, and meet
every checkbox in the work order's Definition of Done. This is Sonnet scope —
the spec is complete; build it, don't redesign it.
```

## Results log (fill in after the session)

- Build: _pending_
- Tier-1: _pending_
- Playtest: _pending_
- Follow-ups / new gotchas: _pending_
