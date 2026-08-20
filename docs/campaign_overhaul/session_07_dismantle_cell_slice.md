# Session 7 — DISMANTLE_CELL Slice (thread + `NETWORK_LINK` chain + intel-conditioned briefing) → EXIT CRITERION

**Phase:** 1 (vertical slice) · **Model:** **Opus spec → approve → fresh Sonnet
build** · **Ships:** the whole thing wired together — **this is where the
increment's exit criterion is met.**

> ⚠ Scope brief + integration risk. This is the session `campaign-overhaul.md`
> §9.1 calls out for Opus: "Step 4 is the integration risk; spend Opus to write
> the slice spec *first*, then execute." Do not start until Sessions 1–6 pass
> their Tier-1 tests.

---

## The exit criterion (the definition of done for the whole increment)

> A `DISMANTLE_CELL` thread runs end-to-end: a **SWEEP** recon drops a
> `NETWORK_LINK` token into the **Intel Ledger**, which unlocks a follow-on **DA**
> whose **paragraph briefing cites the recon beat** — and it is fun enough to want
> a second lap.

Everything in Sessions 1–6 exists to make this session small. This session is
mostly *wiring proven parts* + authoring two pieces of content (the thread DAG
and the intel-conditioned briefing lines).

---

## Why now / prereqs

`campaign-overhaul.md` **§5.3** (thread archetypes — DISMANTLE_CELL is the first
row: `SR find bombmaker → DA capture → ...`, each DA's SSE grants a
`NETWORK_LINK` unlocking the next find), **§5.3.1** (branching), **§5.4** (series
briefing thread — the overarching narrative individual briefings cite), **§6.2**
(intel-conditioned inserts + prior-beat callback), **§4.2** (`NETWORK_LINK` token
→ "reveals the next node in a series"), **§4.4** (intel shapes the DA), **§11**
(all five decisions apply — especially #1 divert-on-failure and #3 one-off
thread). Prereqs: **all of 1–6 green.**

---

## What this session assembles (mostly wiring)

1. **The `DISMANTLE_CELL` thread definition** — a small stage DAG (§5.1 schema)
   authored as data:
   - Stage A: **SWEEP** (find the bombmaker / cell node) → `intelReward` grants a
     `NETWORK_LINK` token pointing at the next subject.
   - Stage B: **DA** (KILL_CAPTURE) gated by that `NETWORK_LINK` /
     `HVT_LOCATION` confidence (§5.2 `entryConditions`), targeting the subject the
     recon revealed.
   - `onFailure` on Stage B → a **divert** re-find beat per §11 decision 1 (subject
     relocates, live tokens knocked down, re-find queued *later* — not an instant
     redo). The slice needs the branch wired even if you only playtest the happy
     path first.
2. **`NETWORK_LINK` chaining** — the SWEEP's `onComplete`/outcome grants the token;
   `advanceCampaign` (Session 3) reads it as Stage B's entry condition and injects
   the subject into the DA template. This is the "find→finish" spine (§5.3).
3. **Intel-conditioned briefing inserts + prior-beat callback** (§6.2, §5.4) — the
   DA briefing composed by `fnc_composeBriefing` (Session 4) now **reads the
   ledger + active series narrative** and appends lines like *"Following the intel
   recovered at %priorBeat, we've traced the facilitator to %targetName"* only
   when the matching token exists. Author the intel-conditioned line bank for the
   DISMANTLE_CELL DA (this is the content §6.2 describes; batch it).
4. **Hardcode one `DSC_deployment`** (§2, §8 item 2, §11 decision 5) — per
   **Decision D1** (see README; recommended `SF_ODA`: starts near-blind so the
   SR→DA chain is *forced*). Set its `intelLevel` low so Stage A can't be skipped.
   Nothing reads deployment yet except the arbiter + briefing composer.
5. **Start the thread** — make the arbiter start a `DISMANTLE_CELL` thread for the
   deployment (instead of a one-off) so the chain runs. Provide a
   `DSC_testConfig`/tablet hook to force-start it deterministically.

---

## Design constraints (all of §10 + §11 apply)

- **Don't duplicate C2 counterplay** (§10) — if SIGINT ever feeds the `NETWORK_LINK`,
  a group wiped before it transmits yields no token. For the slice the token comes
  from SWEEP/SSE, so this is just a "don't fork C2" reminder.
- **Outcome is the only series input** (§10) — the arbiter reads
  `DSC_lastMissionOutcome` + ledger, never live mission internals.
- **Divert, don't soft-retry** (§11 #1) — a blown DA relocates the subject and
  queues a re-find later; it does not respawn the same compound.
- **Dryhole is content, not failure** (§11 #4) — if the DA target already left,
  it must yield a fight, a fresh token, or both — never a walk to an empty marker.
  The slice should demonstrate at least the happy path; wire the dryhole hook.
- **Tempo is the deployment preset** (§11 #5) — SF_ODA = low starting intel, bias
  to SWEEP/SSE. This falls out of `intelLevel` + thread bias, no global dial.
- **Sides normalized once** (§10) — no per-mission `setFriend`.

---

## Definition of done (= the increment's exit criterion)

- [ ] Mini-spec produced (Opus) and approved before code.
- [ ] `DISMANTLE_CELL` thread DAG authored; one hardcoded `DSC_deployment`
      (D1 archetype); arbiter starts the thread deterministically via harness/tablet.
- [ ] SWEEP Stage A grants a `NETWORK_LINK` token; DA Stage B's entry condition
      reads it and targets the revealed subject.
- [ ] DA briefing **cites the recon beat** via intel-conditioned inserts (the
      `%priorBeat` callback appears only because the token exists).
- [ ] `onFailure` divert branch wired (§11 #1); dryhole hook present (§11 #4).
- [ ] `hemtt check` clean.
- [ ] Tier-1 suite `dismantle_cell` covering: Stage A→B advance on the
      `NETWORK_LINK` token; entry-condition gate blocks B without it; failure takes
      the divert branch; the intel-conditioned insert fires iff the token exists
      (assert on composed briefing string).
- [ ] `DSC_testConfig` block committed to force-run the whole chain.
- [ ] `.crush/mission-series.md` written; `roadmap.md` updated; new gotchas → `AGENTS.md`.
- [ ] **Playtest: the full SR→DA chain runs end-to-end and is fun enough to want a
      second lap.** (Only the human can sign this off.)

---

## Tier-2/3 playtest (human — the payoff run)

1. Force-start a `DISMANTLE_CELL` thread. Run Stage A (SWEEP): confirm on success a
   `NETWORK_LINK` token lands and the next stage becomes available.
2. Run Stage B (DA): confirm the briefing **cites Stage A's location/beat**, the
   marker precision matches the intel you earned, and the target is the revealed
   subject.
3. Blow Stage B on purpose once: confirm the subject **diverts** (re-find queued
   later), not an instant redo.
4. The real test: **do you want a second lap?** Capture feel, pacing, and any AI
   jank → `docs/playtest_notes/<date>/`. This verdict closes the increment.

## Gotchas to hand the agent

- Keep flee/divert **coarse** (§12.2) — subject relocates to a building/new area,
  no scripted crowd chase.
- Intel-conditioned inserts must be **additive** to the parity briefing (Session
  4) — don't regress the base briefing when no token exists.
- `distance2D`/`getDir` precedence in any new briefing/geometry math.
- The one-off thread (Session 3) still handles the between-thread lulls — the
  arbiter must cleanly hand off DISMANTLE_CELL → one-off when the thread completes.

---

## Paste-ready prompt (Opus, for the spec)

```
Read docs/campaign_overhaul/WORKFLOW_RULES.md,
docs/campaign_overhaul/session_07_dismantle_cell_slice.md, and
.crush/campaign-overhaul.md §5.3/§5.3.1/§5.4 + §6.2 + §4.2/§4.4 + §11 (all five
decisions). Assume Sessions 1-6 are done. Produce the vertical-slice mini-spec:
the DISMANTLE_CELL stage DAG (SWEEP→DA gated by NETWORK_LINK, with an onFailure
divert branch), the hardcoded DSC_deployment (use Decision D1 from the README —
recommend SF_ODA, low intelLevel), the arbiter wiring to start/advance/clear the
thread, the intel-conditioned briefing insert bank citing the prior beat, the
dryhole hook, the Tier-1 test plan (dismantle_cell suite), the harness
DSC_testConfig to force-run the chain, and the gotchas. This is the exit
criterion — call out the integration risks. No implementation code yet. Opus scope.
```

Then, fresh Sonnet session:

```
Implement the approved DISMANTLE_CELL slice mini-spec from
docs/campaign_overhaul/session_07_dismantle_cell_slice.md. Wire SWEEP→DA via the
NETWORK_LINK token, add the intel-conditioned briefing inserts, the divert branch,
and the dryhole hook. Register everything in XEH_PREP.hpp, add the dismantle_cell
Tier-1 suite, commit the force-run DSC_testConfig, keep hemtt check clean, write
.crush/mission-series.md, update roadmap.md, fold new gotchas into AGENTS.md, and
meet every Definition-of-Done checkbox. Sonnet scope — build the approved spec.
```

## Results log

- Spec approved: _pending_ · Build: _pending_ · Tier-1: _pending_
- **Exit-criterion playtest (want a second lap?):** _pending_
