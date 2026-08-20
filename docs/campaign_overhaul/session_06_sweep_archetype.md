# Session 6 — SWEEP Archetype (observe/sweep mission + new completion conditions + intel yield)

**Phase:** 1 (vertical slice) · **Model:** **Opus spec → approve → fresh Sonnet
build** · **Ships:** the first intel-*producing* mission type — the missing half
of every "find, then finish" series.

> ⚠ Scope brief, not a finished spec. Opus writes the mini-spec first; you
> approve; a fresh Sonnet session builds. SWEEP is the intel-production engine —
> its whole job is to drop tokens into the ledger so a follow-on DA can unlock.

---

## Why now

`campaign-overhaul.md` **§3** (mission types are configs, not generators; SWEEP =
"BUILD FIRST"), **§3 SWEEP design notes** (the important new build), **§4.3 #3**
(recon is the primary deliberate intel producer), **§12.2 / §12.3** (the AI
reality check — SWEEP leans on Arma's twitchy detection model; design so getting
spotted *converts* the mission rather than failing it). Prereqs: Sessions 1–5
(SWEEP produces intel via the interaction-site/ledger seams and is briefed via
the composer).

---

## The design to implement (from §3)

Player is inserted at a vantage/search area; the objective is **information, not
a body count**. New completion conditions (§3):
- **`OBSERVED`** — line-of-sight + dwell timer on the objective while the enemy's
  `knowsAbout` stays below a compromise threshold.
- **`AREA_SWEPT`** — visit N sub-points.
- **`TARGET_IDENTIFIED`** — PID a specific unit/object.

Core rules:
- **Detection is a complication, not an instant fail** (§3, §12.2). Getting
  spotted degrades intel yield and can **convert** the mission (SWEEP → RAID or
  SWEEP → exfil-under-pressure) — the same series machinery from Pillar 2, fired
  mid-mission. This is the pressure valve for Arma's bad AI perception; **keep
  it**.
- **Every SWEEP yields intel tokens on success** (§3) — this is the seam that
  makes "find" matter. Yield scales with dwell time, proximity, and staying
  undetected. Use the Session-5 interaction-site/`fnc_intelAdd` seam.
- **Reuses `fnc_populateAO`** for the observed force and the existing compound
  markers — but markers are drawn **from** the intel gained, not handed out free
  (the blind-assault gradient, §4.4).
- **Faction-agnostic** (§3): pull from `DSC_factionData` role pools; never
  hardcode classnames.

---

## The SWEEP archetype IS a configuration (not a new generator)

Per §3's established principle and `mission-archetypes.md`: a mission type is
data on top of an archetype. Decide with Opus whether SWEEP rides the existing
`fnc_generateRaidMission` path with observe-style completion + no-assault intent,
or warrants a thin sibling generator. **Lean toward config-on-existing** — the
raid generator already populates an AO, draws markers, and builds completion
state; SWEEP mostly changes the *win condition* and the *intel-yield-on-success*,
and withholds markers until intel is earned. Justify the choice in the mini-spec.

---

## Likely deliverables (Opus to finalize)

- New completion conditions `OBSERVED` / `AREA_SWEPT` / `TARGET_IDENTIFIED` added
  to `fnc_getCompletionTypes` (pure `[_state] -> bool` checks, matching the
  existing shape).
- SWEEP mission config/template + profile entry (`fnc_getMissionProfiles` /
  resolver) so `selectMission` can emit a SWEEP.
- Dwell/`knowsAbout`-driven **intel-yield** logic on success → `fnc_intelAdd`
  (yield scales with dwell + proximity + undetected). Reuse Session 5's token
  builder.
- **Detection→convert** hook: when `knowsAbout` crosses the compromise threshold,
  fire a mid-mission conversion event through the arbiter/series (SWEEP → RAID or
  exfil). Keep flee/convert behavior **coarse** (§12.2) — no cinematic chase.
- Intel-gated markers: draw compound markers only if `AREA_LAYOUT` intel exists,
  else a broad search circle (§4.4).
- Register everything in `XEH_PREP.hpp`.

---

## Definition of done

- [ ] Mini-spec produced (Opus) and approved before code.
- [ ] SWEEP config + `OBSERVED`/`AREA_SWEPT`/`TARGET_IDENTIFIED` conditions + intel
      yield + detection→convert hook written, headered, `PREP_SUB`'d where new.
- [ ] On success, a SWEEP drops the correct token(s) into `DSC_intelLedger`.
- [ ] `hemtt check` clean.
- [ ] Tier-1 suite `sweep` covering the pure logic: each new completion condition's
      check against mock state; the intel-yield calculation (dwell/proximity/
      undetected → token confidence); the compromise-threshold decision.
- [ ] `DSC_testConfig` block committed (a forced SWEEP at a fixed site).
- [ ] `AGENTS.md` (detection tuning notes) + `roadmap.md` updated.

---

## Tier-2 playtest (human — the AI-feel session)

This is the session where Arma's AI reality check bites. You own the feel dials.
1. Harness a forced SWEEP near a populated site. Observe from a vantage: does
   `OBSERVED` complete on dwell? Does a token land on success?
2. Deliberately get spotted: does the mission **convert** (not hard-fail) and does
   the yield degrade? Is the compromise threshold tolerable, or laser-twitchy?
3. Confirm markers are **withheld** without `AREA_LAYOUT` intel and appear with it.
4. Detailed detection-feel notes + suggested threshold dials → playtest notes.
   *Do not ask the agent to guess these numbers — measure them in-game and hand
   back specifics.*

## Gotchas to hand the agent

- `knowsAbout` is binary-ish and twitchy (§12.2) — expose the compromise threshold
  as a tunable, don't bury a magic number.
- Never let a stuck/lost defender soft-lock a SWEEP (§13.2 principle) — completion
  is dwell/observation, not "area clear".
- Reuse `fnc_populateAO` and the interaction-site seam; don't spawn extra entities
  outside the budget (§10).
- Keep convert/flee coarse (§12.2) — relocate to a building, no crowd chase.

---

## Paste-ready prompt (Opus, for the spec)

```
Read docs/campaign_overhaul/WORKFLOW_RULES.md,
docs/campaign_overhaul/session_06_sweep_archetype.md, and
.crush/campaign-overhaul.md §3 + §4.3 + §4.4 + §12.2/§12.3, plus
.crush/mission-archetypes.md. Produce a mini-spec for the SWEEP archetype:
decide config-on-existing-generator vs thin sibling (justify), the new
OBSERVED/AREA_SWEPT/TARGET_IDENTIFIED completion conditions, the intel-yield
formula (dwell/proximity/undetected → token confidence via fnc_intelAdd, reusing
Session 5's token builder), the detection→convert hook, intel-gated markers, the
Tier-1 test plan, the harness DSC_testConfig, and gotchas. No implementation code
yet — spec for approval. Opus scope.
```

Then, fresh Sonnet session:

```
Implement the approved SWEEP mini-spec from
docs/campaign_overhaul/session_06_sweep_archetype.md. Register in XEH_PREP.hpp,
add the sweep Tier-1 suite, commit the harness DSC_testConfig, keep hemtt check
clean, meet every Definition-of-Done checkbox, and fold detection/tuning notes
and any new gotcha into AGENTS.md. Sonnet scope — build the approved spec.
```

## Results log

- Spec approved: _pending_ · Build: _pending_ · Tier-1: _pending_ · Playtest/feel: _pending_
