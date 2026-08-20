# Workflow Rules — Operating Contract for Every Session

*Distilled from `.crush/agentic-workflow-and-testing.md`. This is the short
version every build session is pointed at. The long version is authoritative;
this is the checklist. Treat these as **laws** for the campaign overhaul.*

---

## The cost model (why these rules exist)

Two things dominate token spend, and neither is "writing code":
1. **Re-sent context per turn** — every turn re-sends the whole conversation.
   → **Short, scoped sessions. One subsystem per session. Start fresh.**
2. **Rediscovery / flailing** — an agent without the pattern, the definition of
   done, or a way to verify will explore, guess, and re-read.
   → **Point at the doc, give a definition of done, name an exemplar.**

Writing code is cheap; *deciding* what to write and *fixing* wrong-direction
code is expensive. Optimize the deciding.

---

## Laws for the agent (every session must obey)

1. **Scope to one thing.** Build only what the work order asks. Do not
   opportunistically refactor neighbors.
2. **Reference context, don't paste it.** Read the cited doc sections and
   exemplar functions; don't ask for files to be pasted.
3. **Definition of done is binding.** A session is done when *every* listed
   criterion is met — not before, not after. Do not over-build.
4. **Push logic into pure functions.** Inputs → outputs, no global reads, no
   spawning, wherever possible. Pure logic is Tier-1 testable, which is where the
   agent's self-verification lives. The more that's headless-testable, the less
   the human has to playtest.
5. **Author Tier-1 tests alongside the feature, not after.** Register them in the
   test suite; they must print `PASS/FAIL` and pass before you call the session
   done.
6. **`hemtt check` must be clean.** Respect the HEMTT gotchas (parens around unary
   commands in comparisons; `select` over `if/then/else` for constant assignment;
   the CBA log-macro comma-counting trap — hoist inline array literals to a local
   first).
7. **Follow the conventions in `AGENTS.md`.** CBA log macros (never `diag_log`),
   `DSC_core_fnc_*` naming via `PREP_SUB`, hashmaps + `getOrDefault`, the yield
   convention for any multi-spawn/teardown, `joinSilent` after every `createUnit`.
8. **Respect the gotcha list.** The nastiest bugs (createUnit side inheritance,
   rating renegade, `distance2D` precedence, side-on-dead-unit) are documented.
   Do not re-introduce them.
9. **Register every new function in `XEH_PREP.hpp`.** A function that isn't
   PREP'd doesn't exist at runtime.
10. **Update the docs as part of the task.** New engine gotcha → `AGENTS.md`.
    Subsystem shipped → `.crush/roadmap.md` status + (if earned) a detail doc.
    This compounds: the next session is cheaper because the knowledge is captured.
11. **For non-trivial work: plan → approve → execute.** Produce the mini-spec
    first (signatures + test plan + gotchas), get it approved, *then* write code.
    Cheap to redirect a plan; expensive to redirect 400 lines.

---

## Where the agent CANNOT help (stop trying — this saves the most)

The agent cannot launch Arma and cannot perceive frame feel, AI behavior, or
fun. **The human is the playtest loop.** Do not spend tokens asking the agent to
reason about:
- Whether the mission is *fun*.
- How the AI actually behaves (detection, pathing, firefights).
- Frame performance under load.
- Final tuning dials (accuracy, densities, timings) — these need in-game feel.

The agent's responsibility **ends at**: compiles clean, passes headless tests,
logic is sound, follows conventions. The human's begins at: launch, play,
observe, report.

---

## The three test tiers (use the cheapest that can catch the bug)

- **Tier 1 — Headless logic** (`test.VR`, seconds, agent fully owns). Assertion
  suites for the deterministic core (ledger add/query/best/decay, arbiter
  advance, briefing composition, config cascade). Runs via `fnc_runTests`,
  prints `PASS/FAIL: <name>` + a summary. **No playtest needed.**
- **Tier 2 — Feature harness** (real terrain, one feature, human playtests). The
  deliberate single-mission harness (`fnc_initTestScenario` + `DSC_testConfig`):
  predetermined site, player spawned nearby, only prerequisite subsystems booted,
  one mission, no loop.
- **Tier 3 — Full scenario** (current setup, integration + emergent). Slowest;
  run last for regression, not during iteration.

---

## Definition-of-done template (state this in every prompt)

> Done = functions registered in `XEH_PREP.hpp`; `hemtt check` clean; Tier-1 unit
> tests added to the suite and passing; a `DSC_testConfig` block committed so the
> feature is playtestable; docs updated (`roadmap.md` status, new gotchas into
> `AGENTS.md`).

---

## The contract (who owns what)

| Phase | Agent | Engineer |
|---|---|---|
| Prompt | drafts spec/plan (Opus for slice) | sets scope + definition of done, approves |
| Setup | writes harness config + Tier-1 tests | runs build/launch, checks Tier-1 gate |
| Play Test | — (cannot run Arma) | launches, plays, collects filtered evidence + feel |
| Revise | targeted fix, re-check, doc updates | re-playtests, judges fun, calls done |
