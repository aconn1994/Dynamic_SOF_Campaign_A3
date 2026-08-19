# Agentic Workflow & Testing Framework

*Status: **PROCESS DOC** (August 2026). How to build the campaign overhaul (and
everything after) cost-effectively with an AI agent, and the deliberate testing
procedure that makes each feature verifiable before it touches the full
scenario. This is advice + convention, not a spec.*

> Companion to `.crush/campaign-overhaul.md`. That doc says *what* to build; this
> one says *how to build it without burning hundreds of dollars in tokens* and
> *how to know it works*.

---

## PART A — Getting the Most Out of the Agent

### A.1 The core cost model (understand this first)

Two things dominate spend, and neither is "the agent wrote code":

1. **Re-sent context per turn.** Every turn re-sends the whole conversation. A
   200-turn session pays for its entire history *on every message*. Long
   exploratory sessions are the #1 silent cost. **Lever: short, scoped sessions.
   Start fresh per subsystem.**
2. **Rediscovery / flailing.** An agent that doesn't know the pattern, the
   definition of done, or how to verify will explore, guess, and re-read files.
   This codebase already fights that with a huge `AGENTS.md` + `.crush/*.md`
   docs. **Lever: point at the doc, give a definition of done, provide an
   exemplar.**

Writing the actual code is cheap. *Deciding* what code to write, and *fixing*
code that went the wrong way, is expensive. Optimize the deciding.

### A.2 Opus vs Sonnet — a division of labor

Think of it as **architect (Opus) vs. builder (Sonnet)**. The single highest-ROI
pattern for this project:

> **Opus writes the spec. Sonnet executes it in a fresh session.**

You get Opus-quality architecture at Sonnet-priced execution. This whole
planning arc (the campaign-overhaul doc) is the expensive Opus artifact — it
exists precisely so that execution sessions are cheap.

**Use Opus for** (low token volume, high leverage — a wrong call costs many
downstream tokens):
- Planning / architecture / data-model design (like this session).
- Designing a new subsystem before any code (produce a mini-spec + function
  signatures + test plan + gotchas).
- Cross-system debugging where the bug spans C2 ↔ presence ↔ sides. The nastiest
  bugs in `AGENTS.md`'s gotcha list (createUnit side inheritance, rating
  renegade, distance2D precedence) are exactly this class — worth Opus.
- Reviewing a plan or a risky diff before you commit to it.

**Use Sonnet for** (high volume, well-specified, pattern-following — where this
codebase's strong conventions shine):
- Implementing a function against an approved spec.
- Content authoring: briefing sentence banks, faction classification data,
  adding a mission-type config, intel token-type entries.
- Mechanical refactors that follow an existing pattern ("do X like
  `fnc_setupGuards` does").
- Writing the headless unit tests (Part B.2).

**Rule of thumb:** if the task is "decide" → Opus. If the task is "produce, and
the shape is already decided" → Sonnet. When unsure, spend a *little* Opus to
produce the spec, then switch models.

### A.3 Prompting patterns that pay for themselves

1. **Reference context, don't paste it.** "Read `.crush/campaign-overhaul.md`
   §13 and `fnc_generateRaidMission`, then implement the interaction-site
   primitive" is cheaper and more accurate than pasting files. The docs exist for
   this.
2. **State the definition of done.** e.g. "Done = function registered in
   `XEH_PREP.hpp`, `hemtt check` clean, unit test added to the intel suite and
   passing, test-harness config committed." An agent with no stop condition
   over-works and over-spends.
3. **Scope to one thing.** One function or one subsystem per session. Broad
   scope fills the context window with exploration you pay to re-send.
4. **Plan-approve-execute for anything non-trivial.** Ask for the plan, correct
   it (cheap), *then* let it write code (expensive to redo). Never let it write
   400 lines against an unapproved approach.
5. **Point at exemplars.** "Follow the pattern in `fnc_setupGuards` /
   `fnc_getBriefingFragments`." Pattern-matching is Sonnet's cheapest, strongest
   mode.
6. **Feed filtered evidence, not raw dumps.** For a bug, paste the *greppable
   `DSC:` lines* around the failure, not the whole RPT. For build errors, run
   `hemtt check` yourself and paste only the errors. Raw logs are pure token
   waste.
7. **Batch content.** "Write 20 DEVGRU DA briefing sentences across the 5
   sections" is one cheap call. Don't dribble content one line at a time.
8. **Update the docs as part of the task.** Ask the agent to fold new gotchas
   into `AGENTS.md` and status into `roadmap.md`. This compounds — the next
   session is cheaper because the knowledge is captured.

### A.4 Where the agent CANNOT help — and stop trying (this saves the most)

The agent cannot launch Arma, cannot perceive frame feel, AI behavior, or fun.
**The human is the playtest loop.** Do not spend tokens asking the agent to
reason about things only the running game reveals:
- Whether the mission is *fun*.
- How the AI actually behaves (detection, pathing, firefights).
- Frame performance under load.
- Final tuning dials (accuracy, densities, timings) — these need in-game feel.

The agent's responsibility **ends at**: compiles clean, passes headless tests,
logic is sound, follows conventions. The human's begins at: launch, play,
observe, report. Part B is the contract between those two halves. **The biggest
cost saving is refusing to burn Opus tokens on questions only a playtest can
answer.**

### A.5 The compounding assets (protect these)

`AGENTS.md`'s gotcha list and the `.crush/*.md` docs are why an agent can be
productive here without re-learning the codebase every session. Every bug you fix
should leave a gotcha behind; every subsystem should leave a design doc. This is
the cheapest token investment you can make — it's paid once and saves on every
future session.

---

## PART B — The Testing Framework

### B.1 The problem with today's setup

Every map's `initServer.sqf` is just:

```sqf
[] call DSC_core_fnc_initServer;
[] call DSC_core_fnc_initServerDebug;
```

`fnc_initServer` is monolithic — it boots globals → locations → factions →
influence → C2 → presence → roving → BFT → the *infinite* mission loop. To test
one new mission type you boot the entire living world and then *wait for the
random loop to maybe pick your type at a random location*. That is slow,
non-deterministic, expensive to iterate, and it mixes the feature under test with
every other subsystem's noise. We need to be deliberate.

### B.2 Three test tiers (use the cheapest that can catch the bug)

The campaign layer is mostly **data orchestration** (hashmaps, state machines,
string composition), which means *most of it is testable without launching a
firefight*. Push logic into **pure functions** (inputs → outputs, no global
reads, no spawning) so it can be asserted headlessly. This is the single biggest
lever for cheap iteration: the more of a pillar that's headless-testable, the
less the human has to playtest and the more the agent can verify itself.

**Tier 1 — Headless logic tests (VR map, seconds to run, agent can fully own).**
Assertion suites for the deterministic core:
- Intel Ledger: `add` / `query` / `best` / `decay` behave; expired tokens drop.
- Series arbiter: given an outcome + ledger, `advanceSeries` returns the expected
  next template; failure branches/diverts correctly.
- Briefing composer: given a mock context hashmap, produces the expected
  sections and honors intel-conditioned inserts.
- `resolveMissionConfig`: the priority cascade (template > profile > auto) is
  respected.
- Faction extraction/classification: known faction → expected role pools.

  Convention: a `fnc_runTests` (debug-only) that executes registered suites and
  logs `PASS/FAIL: <name>` + a summary line to RPT. The agent writes these, runs
  `hemtt check`, and reasons about correctness — **no playtest needed**, so this
  tier is where the agent's self-verification lives. Author these *alongside* the
  feature, not after.

**Tier 2 — Feature harness (real terrain, one feature, human playtests).**
The deliberate single-mission harness you described: predetermined site, player
spawned nearby, only the prerequisite subsystems booted, one mission generated,
no loop. Details in B.3. This is the Prompt→Setup→PlayTest→Revise loop for
anything with in-world behavior (mission types, presence, AI, UI).

**Tier 3 — Full scenario (current setup, integration + emergent).**
The whole thing running, for regression and emergent-behavior checks before
calling a feature done. Slowest; run last, not during iteration.

### B.3 The feature harness — `fnc_initTestScenario` (design)

A debug init that reads a `DSC_testConfig` hashmap and boots **only what the
feature needs**, deterministically. Replaces `initServer` in a dedicated test
mission (see B.4).

```sqf
DSC_testConfig = createHashMapFromArray [
  ["factionProfile", "vanilla"],   // fixed faction set — reproducible composition
  ["steps", ["globals","locations","factions","influence"]],
                                    // whitelist of init steps to run (see map below)
  ["missionTemplate",              // FORCED template — no random selection
     createHashMapFromArray [
       ["type", "INTEL_GATHER"],
       ["location", <fixed location id or hashmap>],  // OR regionCenter+radius
       ["missionProfile", "AFO_rural"]
     ]],
  ["singleShot", true],            // generate ONE mission, then stop — no loop
  ["playerSpawn", "nearSite"],     // teleport player ~150m from the objective
  ["timeOfDay", 6],                // deterministic lighting
  ["freezeWeather", true],
  ["extraDebug", true]             // verbose LOG/markers for this run
];
```

**Init-step dependency map** (what each mission-generation prerequisite needs —
derived from `fnc_initServer`):

| Step key | Function | Needed for | Skip when |
|---|---|---|---|
| `globals` | Step 0 (globals + dynamic sim) | always | never |
| `locations` | `fnc_scanLocations` | any location-based mission | testing a pure function |
| `factions` | `fnc_initFactionData` | any AI composition | " |
| `influence` | `fnc_initInfluence` | area faction, selection weighting | fixed-location single-shot can stub this |
| `c2` | `fnc_initC2Network` | testing C2 or wanting provenance | most mission-type tests |
| `presence` | `fnc_initPresenceManager` | testing ambient world | most mission-type tests |
| `roving` | `fnc_initRovingManager` | testing rovers | most mission-type tests |
| `bft` | `fnc_bftSnapshot` | testing tablet BFT | most tests |
| `missionLoop` | Step 5 loop | full integration | **always in harness — use `singleShot`** |

For a **mission-type test** the minimal set is `globals + locations + factions
(+ influence)`, force the template, `singleShot`, spawn near the site. Presence /
roving / C2 stay **off** so the feature isn't drowned in ambient noise — turn
them on only when the interaction *with* them is the thing being tested.

**Design constraint:** `fnc_initTestScenario` must call the *same* generation
functions the real loop calls (`resolveMissionConfig` → `generateMission` →
`generateRaidMission`). It only differs in (a) which prerequisites boot, (b)
forcing the template, (c) single-shot instead of loop, (d) player placement. If
it forks the generation path it stops testing the real thing.

### B.4 Where test missions live

Keep the harness reproducible without maintaining a zoo of map PBOs:
- **One VR mission** (`test.VR`, already stubbed in `launch.toml`) for Tier-1
  headless suites — fastest load, no terrain.
- **One test mission per terrain you care about** (e.g. a `DSC_Test.Altis`) whose
  `initServer.sqf` sets `DSC_testConfig` and calls `fnc_initTestScenario` instead
  of `initServer`. Switch which feature it runs by editing the one config block,
  not by making new PBOs.
- HEMTT's `.hemtt/missions/` and the commented `mission = "test.VR"` line in
  `launch.toml` are the switch points. A launch preset per tier keeps it one
  command.

Commit the `DSC_testConfig` blocks used for each feature as small snippets under
`docs/test_harness/` (or in the feature's design doc) so a future session can
reproduce the exact test.

---

## PART C — The Procedure: Prompt → Setup → Play Test → Revise

One feature = one lap of this loop. Keep laps small.

### C.1 Prompt  *(engineer + agent; Opus for spec, Sonnet for build)*

- Point at the design-doc section (e.g. "campaign-overhaul §13") and the
  exemplar function to follow.
- State scope: **one** mission type / subsystem.
- State the **definition of done**:
  - functions registered in `XEH_PREP.hpp`;
  - `hemtt check` clean;
  - Tier-1 unit tests added + passing (for any pure logic);
  - a `DSC_testConfig` block committed so it's playtestable.
- For anything non-trivial: **ask for a plan first (Opus), approve it, then build
  (Sonnet, fresh session).** Cheap to redirect a plan, expensive to redirect
  code.

### C.2 Setup  *(engineer, agent assists)*

- Agent produces/updates the `DSC_testConfig` for the feature (fixed site, spawn,
  minimal step whitelist).
- Run Tier-1 first: launch `test.VR`, read `PASS/FAIL` from RPT — cheap gate
  before you spend a full playtest.
- `hemtt build`, then `hemtt launch <preset>` with the test mission active for
  Tier-2.

### C.3 Play Test  *(engineer only — the agent cannot do this)*

- Launch, spawn at the site, exercise the feature deliberately (do the SSE, let
  the HVT flee, trigger the QRF, etc.).
- Collect three things:
  1. **Filtered RPT** — the `DSC:` / `[DSC]` lines for this run (grep, don't
     dump).
  2. **Behavioral observations** — specific, not "it's broken": *"SSE action only
     appeared at 3m; expected ~15m radius"* / *"HVT ran into a wall and stuck"*.
  3. **Verdict against definition of done** — which criteria passed, which didn't.
- Note anything about *feel* (fun, pacing, AI jank) — this is data only you can
  produce, and it's the point of the whole exercise.
- Log it under `docs/playtest_notes/<date>/` (existing convention).

### C.4 Revise  *(engineer + agent)*

- Hand the agent the **filtered RPT + specific observations**, not a vague
  complaint. Precise input = narrow fix = few tokens.
- Agent makes a targeted fix, re-runs `hemtt check` + Tier-1 tests.
- If the fix reveals a new engine gotcha, agent folds it into `AGENTS.md`.
- Loop back to C.3. Stop when the definition of done is met.
- On completion: agent updates `roadmap.md` status and, if the subsystem earned
  one, writes its `.crush/<system>.md` detail doc.

### C.5 What each side owns (the contract)

| Phase | Agent | Engineer |
|---|---|---|
| Prompt | drafts spec/plan (Opus) | sets scope + definition of done, approves |
| Setup | writes harness config + Tier-1 tests | runs build/launch, checks Tier-1 gate |
| Play Test | — (cannot run Arma) | launches, plays, collects filtered evidence + feel |
| Revise | targeted fix, re-check, doc updates | re-playtests, judges fun, calls done |

**The golden rule:** the agent proves *correctness* (compiles, tests, logic,
conventions); the human proves *fun* (feel, AI behavior, pacing, performance).
Every token spent asking the agent to judge fun, or asking the human to hand-check
logic a test could catch, is waste. Build the harness so the split is clean.

---

*As the testing framework gets built, this doc's `fnc_initTestScenario` /
`fnc_runTests` designs should graduate into real functions and get their status
folded into `.crush/roadmap.md`.*
