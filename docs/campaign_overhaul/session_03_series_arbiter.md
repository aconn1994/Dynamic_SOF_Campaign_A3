# Session 3 — Series Arbiter (`fnc_advanceCampaign` + one-off thread wrapper)

**Phase:** 0 (seams) · **Model:** Sonnet (spec is complete) · **Ships:**
**invisibly** — the current random mission loop must keep behaving exactly as
today.

> One thin insertion in the loop. The whole existing generate → wait → score →
> cleanup body is untouched. This is the merge-without-breaking-anything step.

---

## Why now

`campaign-overhaul.md` §5 (mission series), §5.2 (the one loop change), §8 item
3, §9.1 step 3, **§11 decision 3** (always wrap missions in a thread — even
"random" ones become a length-1 one-off thread, which deletes an entire class of
null-checks). Prereqs: Sessions 1 & 2.

---

## The core idea (§11 decision 3 — read this twice)

There is **no pure-random fallback path** in the final design. When no narrative
thread is active, the arbiter starts a lightweight **one-off thread**: a single
mission with its own minimal briefing + intel home. So briefing composer, intel
ledger, and outcome handling never special-case a "thread-less" mission —
everything always has a `DSC_activeSeries`, even if length-1. A one-off is *not*
filler; it's the between-intel tempo, and it can itself drop a lead (Session 5+)
that promotes into a real thread.

This session ships that wrapper with the one-off thread producing **exactly
today's random mission template**, so behavior is unchanged.

---

## Read before building

- `.crush/campaign-overhaul.md` **§5.1** (stage-definition schema — implement the
  shape), **§5.2** (the arbiter pseudocode — implement this control flow),
  **§2** (the `DSC_activeSeries` state object shape), **§11 decision 1** (failed
  mission → subject *diverts*, does not soft-retry — the arbiter must expose an
  `onFailure` branch, even if the slice's one-off thread doesn't use it yet),
  **§11 decision 3** (one-off thread), **§10** ("Series must honor the tablet
  override" — `DSC_missionQueue` outranks series selection; "Outcome is the only
  series input").
- `addons/core/functions/init/fnc_initServer.sqf` **lines ~518–631** — the
  spawned mission loop. The arbiter inserts between "consume queue" and
  `selectMission`. Study exactly how `DSC_missionQueue`, `DSC_lastMissionOutcome`,
  and `updateInfluence` are used so you preserve them.
- `addons/core/functions/missions/fnc_selectMission.sqf` — the random template it
  builds today (`KILL_CAPTURE` + `AFO_rural`). The one-off thread must emit an
  equivalent template so parity holds.
- `addons/core/functions/missions/fnc_buildMissionOutcome.sqf` — the `seriesId` /
  `seriesIndex` fields already exist on the outcome; wire them.

---

## Deliverables

New folder `addons/core/functions/campaign/` (+ `script_component.hpp`).

1. **`DSC_activeSeries` schema** + a constructor
   **`DSC_core_fnc_startSeries`** — builds a series hashmap (§2 shape:
   `threadType`, `stages[]`, `stageIndex`, `branchState`, `subjectRefs`,
   `narrative`, `intelRequirements`). Provide a **one-off thread factory**
   (`threadType == "ONE_OFF"`, a single stage whose `missionTemplate` is today's
   random template) as the default when no narrative thread is queued.
2. **`DSC_core_fnc_advanceCampaign`** — the arbiter. Signature roughly
   `[_lastOutcome, _intelLedger] -> _template`. Control flow per §5.2:
   - If `DSC_missionQueue` non-empty → return that (tablet override wins,
     unchanged).
   - Else if `DSC_activeSeries` exists → evaluate the current stage's
     `entryConditions` against the ledger + last outcome, pick the next stage
     (`onSuccess`/`onFailure`), return its `missionTemplate`.
   - Else → `startSeries` a one-off thread, return its template.
   - **Post-outcome half:** a companion call (or a mode of the same function) that
     *consumes* `DSC_lastMissionOutcome`, grants the completed stage's
     `intelReward` via `fnc_intelAdd`, advances `stageIndex`/`branchState`, and
     clears the series when its stages are exhausted (one-off → cleared after one).
3. **Loop insertion** in `fnc_initServer.sqf` — replace the inline
   "build random template" with `advanceCampaign`, and add the post-outcome
   advance call after `buildMissionOutcome`. **Keep the queue-consume, abort flag,
   influence update, and cleanup exactly as they are.** Behavior with no thread
   configured must be byte-for-byte the same missions as today.
4. **Register** all functions in `XEH_PREP.hpp` under a `// Campaign` block.

---

## Definition of done

- [ ] `startSeries` (with one-off factory) + `advanceCampaign` written, headered,
      `PREP_SUB`'d.
- [ ] `hemtt check` clean.
- [ ] Tier-1 suite `series_arbiter` covering: no thread → one-off template equals
      today's random template; tablet queue outranks series; a mock 2-stage
      series advances on success to the right stage; failure takes `onFailure`;
      `intelReward` tokens land in the ledger on stage completion; series clears
      when exhausted. **All PASS.**
- [ ] **Invisibility proof (Tier-3):** full `DSC_Altis.Altis` run — random loop
      still generates back-to-back missions with no visible change; RPT shows each
      wrapped in a `ONE_OFF` series.
- [ ] `roadmap.md` updated.

---

## Tier-1 expectations

The arbiter is deterministic given `[outcome, ledger, queue, activeSeries]` —
push all branch logic into a pure `advanceCampaign` that takes those as
arguments (the global reads happen in a thin wrapper the loop calls). The
`series_arbiter` suite is the proof; it needs no firefight.

## Playtest steps (human)

1. `fnc_runTests` → `series_arbiter` all PASS.
2. Full Altis run: confirm missions still spawn as before (this is a regression
   check — the point is that *nothing looks different*). Grep RPT for
   `ONE_OFF`/series lines to confirm the wrapper is live. Verdict → playtest notes.

## Gotchas

- **Outcome is the only series input** (§10) — do not reach into live mission
  internals; read `DSC_lastMissionOutcome` + ledger only.
- **Tablet override precedence** must be preserved (`DSC_missionQueue` first).
- Do not re-introduce per-mission `setFriend` or any faction-side logic here.
- The abort path (`DSC_missionAbortRequested`) must still skip scoring and *not*
  advance the series (an aborted mission has no outcome to consume).

---

## Paste-ready prompt

```
Read docs/campaign_overhaul/WORKFLOW_RULES.md and
docs/campaign_overhaul/session_03_series_arbiter.md. Implement the series
arbiter exactly as specified: DSC_core_fnc_startSeries (with a ONE_OFF thread
factory that emits today's random template) and DSC_core_fnc_advanceCampaign
(control flow per .crush/campaign-overhaul.md §5.2, honoring the tablet-queue
override and reading only DSC_lastMissionOutcome + the intel ledger). Insert it
into the fnc_initServer mission loop without changing the queue-consume, abort,
influence-update, or cleanup behavior — a run with no thread configured must
produce the same missions as today. Add the post-outcome advance that grants
intelReward via fnc_intelAdd and advances/clears the series. Register in
XEH_PREP.hpp, add a series_arbiter Tier-1 suite, keep hemtt check clean, and
meet every Definition-of-Done checkbox. Ship this invisibly. Sonnet scope.
```

## Results log

- Build: _pending_ · Tier-1: _pending_ · Playtest/regression: _pending_ · Gotchas: _pending_
