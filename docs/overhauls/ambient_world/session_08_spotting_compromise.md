# Session 08 — Spotting & Compromise

**Owner item:** 5
**Model:** Opus spec → Sonnet build
**Status:** ⬜ scope brief only — work order to be written after Session 07.
**Source material:** `docs/overhauls/Mission_Type_Ramblings.md` §3 and §4.

---

## Scope sketch

Two separable halves, both specified in the owner's notes:

### A. Spotting profiles (§3)

Configurable enemy detection baselines applied via `spotDistance` / `spotTime`
through the existing `fnc_applySkillProfile` — **the one path every DSC combat
unit already passes through**, so this is a small insertion point with a wide
blast radius.

Proposed profiles: `ROUTINE_SECURITY`, `REDUCED_VIGILANCE`, `HEIGHTENED_ALERT`,
`COMBAT_ALERT`, `ELITE_SECURITY`.

Resolution layers (lowest → highest priority): faction baseline → location
posture → mission signature (AFO vs DA) → C2 alert state.

**This is what makes AFO viable without SWEEP's fragility.** Detection becomes a
dial on atmosphere, never a completion gate.

### B. Graduated compromise model (§4)

Four levels (`0 Undisturbed` / `1 Minor Contact` / `2 Active Engagement` /
`3 Severe Engagement`) derived from **recorded events**, not inferred AI intent:
weapons fired by side, casualties by side, civilian casualties, alarms raised
(C2 already provides this), objective completed, withdrawal achieved.

**Objective completion and operational outcome stay independent.** A player can
succeed messily.

---

## Known design constraints

- **Extend `fnc_buildMissionOutcome`, don't parallel it.** It already owns the
  standardized result schema that series/influence consumers read. Add an
  `operationalOutcome` block.
- **C2 already records most of the needed events** — alert levels, contact
  reports, noise grading. Read from it rather than adding a second event bus.
- **Compromise must not reach back into completion.** The SWEEP post-mortem:
  getting spotted is a complication, never a fail condition.
- **`side` and `rating` are meaningless on a dead unit** (`AGENTS.md`) — any
  casualty attribution must use `side (group _killed)`.

---

## Parked questions (owner deferred from the planning pass)

- **Q10** — Is the 0–3 ladder the design, or a starting point to tune?
- **Q11** — Does compromise feed **influence** and the **Intel Ledger** (a
  compromised op raises regional alert / burns an informant), or is it
  debrief-text only for the first pass?
  *Recommendation: debrief-only first, then wire to influence once the levels
  are tuned — a mis-tuned ladder that mutates campaign state is hard to walk
  back.*
- **Q12** — Does the player's **signature** (loadout, vehicle, squad size) get
  measured, declared at mission select, or both?
- **Q13** — Carried over from Session 06: should a barking dog / disturbed
  livestock raise local alertness? It rides C2's existing noise grading cleanly.
