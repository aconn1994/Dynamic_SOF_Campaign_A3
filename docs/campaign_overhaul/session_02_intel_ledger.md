# Session 2 — Intel Ledger (`DSC_intelLedger` + the 4-call API)

**Phase:** 0 (seams) · **Model:** Sonnet (spec is complete) · **Ships:** the
keystone data store, invisible to gameplay.

> The keystone before the arch. Pure data/logic, no dependencies, *perfectly*
> headless-testable — so it immediately exercises the harness from Session 1.

---

## Why now

`campaign-overhaul.md` §4 (the keystone), §4.5 (the minimal API), §8 item 1,
§9.1 step 2. Intel is the connective tissue for all five pillars: series
unlocking, briefing flavor, and mission difficulty all read from it. Build it
early and simple.

**Prerequisite:** Session 1 done (needs `fnc_runTests`).

---

## Read before building

- `.crush/campaign-overhaul.md` **§4.1** (token schema — implement it verbatim),
  **§4.2** (token type catalog — the `type` values; you don't author all payloads
  now, just don't hardcode a closed enum), **§4.4** (how intel *shapes* a mission
  — informs the query surface), **§4.5** (the four calls — this is the whole API),
  **§11 decision 2** (intel is **per-deployment**; ledger created with the
  deployment, dies with it; decay handles staleness).
- `addons/core/functions/missions/fnc_buildMissionOutcome.sqf` — see how
  `intelGathered` is currently produced (lines ~90–105). The retrofit bridges this
  into the ledger.
- `addons/core/functions/missions/fnc_addInteractionHandler.sqf` — the embryonic
  token producer (writes `DSC_currentMission.intelTokens`). **Do not deep-refactor
  it here** — that's Session 5. Only add a thin bridge so its output can reach the
  ledger.
- Exemplar for hashmap-heavy pure logic + `getOrDefault`: any `fnc_c2*` function.

---

## Deliverables

New folder `addons/core/functions/intel/` (add a `script_component.hpp` mirroring
the pattern in `ai/script_component.hpp`).

1. **`DSC_core_fnc_intelInit`** — creates/clears `DSC_intelLedger` (a hashmap:
   `id -> token`). Called at deployment start; for the slice, call it once during
   harness/init boot. Idempotent.
2. **`DSC_core_fnc_intelAdd`** — takes a partial token hashmap, fills defaults per
   the §4.1 schema (`id` uid-generated if absent, `discoveredAt = serverTime`,
   `expiresAt` from a per-type or passed TTL, `confidence` clamped 0–1), writes it
   to the ledger, returns the token id. Pure except the one global write —
   structure so the compose-token logic is a testable pure helper.
3. **`DSC_core_fnc_intelQuery`** — filter the ledger by any of `subjectRef`,
   `type`, `scope`, `source`; returns matching **live** (non-expired) tokens.
   Pure over `[ledger, criteria]` — pass the ledger in so it's Tier-1 testable
   without touching the global.
4. **`DSC_core_fnc_intelBest`** — `[subjectRef, type]` → the highest-`confidence`
   live token (or the null/empty sentinel). This is what the resolver and series
   gates call.
5. **`DSC_core_fnc_intelDecay`** — expire tokens where `expiresAt <= serverTime`;
   return the count dropped. A tick will call this later; for now it's a function
   the tests drive.
6. **Retrofit bridge** — after `buildMissionOutcome` produces `intelGathered`, the
   mission loop (and the harness single-shot) should feed those tokens into the
   ledger via `intelAdd`. Add this call at the **outcome-handling site** in
   `fnc_initServer.sqf` (the `if (!_aborted)` block, ~line 588) **and** in the
   harness single-shot path — not inside `buildMissionOutcome` (keep it a pure
   builder). Normalize the legacy sentinel token (`{"type":"generic"}`) into a
   schema-valid token on the way in.
7. **Register** all five in `XEH_PREP.hpp` under a new `// Intel` block.

---

## Design constraints (from §10 + §11)

- **Intel decay ≠ C2 alert decay.** Separate clock, separate store. Do not
  overload C2 node state as intel confidence.
- **Per-deployment lifetime.** No cross-deployment carryover. `intelInit` wipes.
- **Do not duplicate C2 counterplay.** (Relevant later when SIGINT bridges in —
  not this session, but keep the query surface source-tagged so it's ready.)
- Keep the API to exactly these calls — "that is the entire keystone; everything
  else reads through these" (§4.5). Resist adding speculative helpers.

---

## Definition of done

- [ ] Five functions written, headered (document the token schema in
      `intelAdd`'s header), and `PREP_SUB`'d.
- [ ] `hemtt check` clean.
- [ ] Tier-1 suite `intel_ledger` registered with `fnc_runTests`, covering:
      add fills defaults + returns id; query filters by type/subjectRef/scope;
      best returns the highest-confidence live token; decay drops expired and
      keeps live; expired tokens never returned by query/best. **All PASS.**
- [ ] Retrofit: a mission that sets `intelGathered` lands a schema-valid token in
      `DSC_intelLedger` (verify in the Session-1 harness single-shot).
- [ ] `roadmap.md` updated; token schema documented (header is fine, or stub
      `.crush/intel-ledger.md`).

---

## Tier-1 expectations

This session is almost entirely Tier-1. The `intel_ledger` suite is the proof.
No firefight needed to validate the ledger itself.

## Playtest steps (human — light)

1. Run `fnc_runTests`; confirm `intel_ledger` all PASS in RPT.
2. Harness single-shot an `ANY_INTERACTED`/intel mission, recover the intel,
   confirm one token appears in `DSC_intelLedger` with correct `type`, `source`,
   `confidence`, `expiresAt`. Filtered RPT + verdict → playtest notes.

## Gotchas

- Clamp `confidence` to [0,1] on add.
- `expiresAt` in the past = already dead; `intelAdd` should still store but
  `query`/`best` must exclude it (test this edge).
- CBA log-macro comma trap on any `getOrDefault ["k", []]` inside a log macro —
  hoist to a local.

---

## Paste-ready prompt

```
Read docs/campaign_overhaul/WORKFLOW_RULES.md and
docs/campaign_overhaul/session_02_intel_ledger.md, then implement the Intel
Ledger exactly as specified: fnc_intelInit / intelAdd / intelQuery / intelBest /
intelDecay in a new addons/core/functions/intel/ folder, using the token schema
from .crush/campaign-overhaul.md §4.1 and the API contract in §4.5. Keep the
query/best/decay logic pure over a passed-in ledger so it's Tier-1 testable.
Add the retrofit bridge so buildMissionOutcome's intelGathered lands in the
ledger at the mission-loop outcome site and in the harness single-shot path (not
inside buildMissionOutcome). Register everything in XEH_PREP.hpp, add an
intel_ledger Tier-1 suite to fnc_runTests covering add/query/best/decay +
expiry, keep hemtt check clean, and meet every Definition-of-Done checkbox.
Sonnet scope — the spec is complete.
```

## Results log

- Build: `hemtt check` clean (165 sqf files compiled, 0 errors/warnings).
- Tier-1: `intel_ledger` suite registered in `fnc_initServerDebug.sqf` — add
  fills defaults + clamps confidence + returns id; query filters by
  type/subjectRef/scope; best returns the highest-confidence live token and
  ignores a higher-confidence expired one; decay drops expired tokens and
  keeps live ones. Not yet run in-engine (requires `hemtt launch` + `test.VR`
  with `fnc_runTests` enabled — human playtest step).
- Retrofit: `fnc_buildMissionOutcome`'s `intelGathered` now feeds
  `fnc_intelAdd` at the mission-loop outcome site (`fnc_initServer.sqf`,
  STEP `if (!_aborted)` block) and the harness single-shot path
  (`fnc_initTestScenario.sqf`). `fnc_intelInit` is called once at server
  boot (STEP 0, before location scanning) and once per harness "globals"
  step.
- Playtest: _pending_ — human to run `fnc_runTests` in `test.VR` and confirm
  `intel_ledger/*` all PASS, then harness single-shot an
  `ANY_INTERACTED`/intel mission and confirm one token appears in
  `DSC_intelLedger` with correct `type`/`source`/`confidence`/`expiresAt`.
- Follow-ups / new gotchas: none surfaced during build. Docs: `.crush/intel-ledger.md`
  added, `.crush/roadmap.md` Phase 3 Intel System section updated.

