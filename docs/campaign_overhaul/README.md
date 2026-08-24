# Campaign Overhaul — Increment 1 Entry Point

*Authored by the planning session (Opus), August 2026. This folder is the
**execution plan** for the first increment of the campaign overhaul. It exists
so that each subsequent build is a short, cheap, fresh session (Sonnet) with no
re-discovery. Read this file first, then run the session work orders in order.*

> **What this is:** a sequence of self-contained **work orders**, one per build
> session. Each work order has a paste-ready prompt, a definition of done, the
> exact docs/functions to read, and a human playtest checklist. You (the
> engineer/playtester) drive; a fresh agent session executes one work order,
> then you close the session and open the next.

---

## The source-of-truth docs (do not duplicate them — reference them)

| Doc | Role |
|---|---|
| `.crush/campaign-overhaul.md` | **WHAT** to build. The master design/vision. Section numbers cited throughout. |
| `.crush/agentic-workflow-and-testing.md` | **HOW** to build it cheaply + the test framework. Treated as **law** (see `WORKFLOW_RULES.md`). |
| `docs/campaign_overhaul/WORKFLOW_RULES.md` | The distilled operating contract every session is pointed at. |
| `AGENTS.md` | Codebase conventions + the gotcha list. Non-negotiable. |
| `docs/Dynamic_SOF_Mission_Catalog.md` | Mission-type source material for content authoring. |

---

## The Increment (from `campaign-overhaul.md` §9.1)

**Scope:** Phase 0 (the invisible seams) **+** the Phase 1 vertical slice, as one
unit of work. No PI ceremony, no story points — one increment with a hard exit
criterion, then build.

**Exit criterion (the only success test that matters):**

> A `DISMANTLE_CELL` thread runs end-to-end: a **SWEEP** recon drops a
> `NETWORK_LINK` token into the **Intel Ledger**, which unlocks a follow-on **DA**
> whose **paragraph briefing cites the recon beat** — and it is fun enough to want
> a second lap.

Everything after this increment is *breadth* (more mission types, unit voices,
threads, token types, briefing phrasings) layered onto proven plumbing.

---

## Session sequence (run in order — each gates the next)

Phase 0 sessions ship **invisibly** (the current random mission loop keeps
working the whole way). Do **not** start Phase 1 until every Phase 0 session has
passed its Tier-1 tests.

| # | Session | Phase | Model | Ships | Gate to next |
|---|---|---|---|---|---|
| 1 | [Test harness](session_01_test_harness.md) — `fnc_runTests` + `fnc_initTestScenario` | 0 | Sonnet (spec is complete) | The ruler. No gameplay change. | Tier-1 self-test suite runs + prints PASS/FAIL in RPT |
| 2 | [Intel Ledger](session_02_intel_ledger.md) — `DSC_intelLedger` + 4-call API | 0 | Sonnet | Keystone data store. Invisible. | Ledger unit tests pass under `fnc_runTests` |
| 3 | [Series arbiter](session_03_series_arbiter.md) — `fnc_advanceCampaign` + one-off thread | 0 | Sonnet | Loop wrapped in a thread; random still works | Arbiter unit tests pass; random loop unchanged in playtest |
| 4 | [Briefing composer refactor](session_04_briefing_composer.md) — `fnc_composeBriefing` (parity) | 0 | Sonnet | Same briefings, new seam | Parity test: composed briefing == today's for a fixed context |
| 5 | [Interaction-site primitive](session_05_interaction_site.md) — abstract site + `INTERACTION_SITE` + universal Search→token | 1 | **Opus spec → Sonnet build** | SSE/search becomes action→token | Site fires token into ledger in harness |
| 6 | [SWEEP archetype](session_06_sweep_archetype.md) — observe/sweep mission + new completion conditions + intel yield | 1 | **Opus spec → Sonnet build** | First intel-producing mission type | SWEEP completes + yields a token in harness |
| 7 | [DISMANTLE_CELL slice](session_07_dismantle_cell_slice.md) — thread + `NETWORK_LINK` chain + intel-conditioned briefing | 1 | **Opus spec → Sonnet build** | **Exit criterion met** | Full SR→DA chain runs end-to-end |

**Why this order:** build the ruler before you measure (harness), the keystone
before the arch (ledger), keep the existing scenario working the whole way
(invisible arbiter), then lay the slice content on proven plumbing. The
interaction-site primitive (5) precedes SWEEP (6) because SWEEP consumes it and
it is the ledger's first real producer (`campaign-overhaul.md` §13.5).

---

## Model split (why some sessions say "Opus spec first")

Per `agentic-workflow-and-testing.md` §A.2: **Opus decides, Sonnet produces.**

- **Sessions 1–4** are Phase-0 plumbing with a *complete* spec already written in
  the work order. Open a **Sonnet** session, paste the prompt, build.
- **Sessions 5–7** carry integration risk (new mission behavior, cross-system
  chaining). Their work orders are **scope briefs**, not full specs. Spend a
  *little* **Opus** to produce + approve the mini-spec (function signatures, test
  plan, gotchas), then switch to a fresh **Sonnet** session to execute it. Never
  let a session write 400 lines against an unapproved approach.

---

## Decisions the human must make (before Session 5)

These are the only open choices in the increment. Record answers in the
**Decision Log** below so future sessions inherit them.

- **D1 — Deployment archetype for the slice.** `campaign-overhaul.md` §9 says pick
  `SF_ODA` *or* `DEVGRU`. **Planning recommendation: `SF_ODA`.** It starts
  near-blind, which *forces* the SR→DA find-then-finish chain the exit criterion
  tests; DEVGRU's HQ intel would let you skip the recon beat and under-exercise
  the plumbing. Keep DEVGRU as the later "surgical tempo" showcase. **Not yet
  decided — confirm at Session 3/5.**
- **D2 — Interaction-site as the default objective model.** Already owner-approved
  (`campaign-overhaul.md` §13). Object scatter is demoted to optional dressing.
  No action; just don't reintroduce object-scatter as the load-bearing mechanic.
- **D3 — One deployment, hardcoded.** MVP hardcodes a single `DSC_deployment`
  (§8.2). Player-selectable deployments are Phase 5. The data model must support
  the choice, but the slice ships one.

---

## The per-session loop (from `agentic-workflow-and-testing.md` Part C)

One session = one lap:

1. **Prompt** — open a fresh session, paste the work order's prompt. For
   Sessions 5–7, ask for the mini-spec first, approve it, *then* let it build.
2. **Setup** — the agent writes/updates the `DSC_testConfig` block and Tier-1
   tests. You run `hemtt check`, then launch `test.VR` and read PASS/FAIL from
   RPT (cheap gate before a full playtest).
3. **Play Test** — *only you can do this.* Launch, exercise the feature
   deliberately, collect: **filtered `DSC:` RPT lines**, **specific behavioral
   observations** (not "it's broken"), and a **verdict vs definition of done**.
   Log under `docs/playtest_notes/<date>/`.
4. **Revise** — hand the agent the filtered RPT + specific observations (not a
   vague complaint). Targeted fix → re-run `hemtt check` + Tier-1. New engine
   gotcha → fold into `AGENTS.md`. Loop until the definition of done is met.

**The golden rule:** the agent proves *correctness* (compiles, tests, logic,
conventions); you prove *fun* (feel, AI behavior, pacing, performance). Do not
spend agent tokens asking it to judge fun; do not hand-check logic a test could
catch.

---

## Status tracker (update as sessions close)

| Session | Status | Tier-1 pass | Playtest verdict | Notes |
|---|---|---|---|---|
| 1 — Test harness | ✅ done | pass | — | |
| 2 — Intel Ledger | ✅ done | pass (build-time; in-engine run pending) | — | |
| 3 — Series arbiter | ⬜ not started | — | — | |
| 4 — Briefing composer | ⬜ not started | — | — | |
| 5 — Interaction site | ⬜ not started | — | — | |
| 6 — SWEEP archetype | ⬜ not started | — | — | |
| 7 — DISMANTLE_CELL slice | ⬜ not started | — | — | |

Legend: ⬜ not started · 🟨 in progress · ✅ done · ⛔ blocked

---

## Decision Log

| Date | Decision | Choice | Rationale |
|---|---|---|---|
| _pending_ | D1 deployment archetype | _SF_ODA (recommended)_ | forces SR→DA chain |
| 2026-08 | D2 interaction-site default | approved | §13, owner-approved |
| 2026-08 | D3 single hardcoded deployment | approved | MVP scope |

---

## On completion of the increment

When Session 7 meets the exit criterion:
- Fold each new subsystem's status into `.crush/roadmap.md`.
- Write per-system detail docs (`.crush/intel-ledger.md`, `.crush/mission-series.md`)
  the way existing subsystems each earned one.
- Add any new engine gotchas discovered to `AGENTS.md`.
- The next increment is *breadth* — see `campaign-overhaul.md` §9 Phases 2–5.
