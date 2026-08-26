# Session 4 — Briefing Composer Refactor (`fnc_composeBriefing`, parity)

**Phase:** 0 (seams) · **Model:** Sonnet (spec is complete) · **Ships:**
**parity** — same briefings the player sees today, behind a new seam.

> The last Phase-0 seam. Refactor the single-line-fragment briefing into a
> `fnc_composeBriefing(context)` call with sectioned output — but keep the output
> identical to today's for the same input. Intel-conditioned inserts and unit
> voices come in Session 7; this session only builds the seam and proves parity.

---

## Why now

`campaign-overhaul.md` §6 (dynamic briefings), §8 item 4 ("Backwards compatible:
existing fragments become the first entries"), §9 Phase 0 ("briefing composer
refactor (parity with today)"), §6.4 (keep composition behind a single
`fnc_composeBriefing(context)` so a future LLM path can swap in). Prereqs:
Sessions 1–3 (ledger exists so the context can carry it, even if unused for
inserts yet).

---

## Read before building

- `.crush/campaign-overhaul.md` **§6.1** (the five-section skeleton: SITUATION /
  MISSION / EXECUTION / INTEL / SUPPORT), **§6.2** (the composer — sentence banks
  keyed by `(missionType × unitVoice)`, `selectRandom` + `format` slot
  interpolation), **§6.4** (the single-call seam for a future LLM swap).
- `addons/core/functions/missions/fnc_createMissionBriefing.sqf` — the current
  implementation (read the whole file, it's ~200+ lines). Note it already builds:
  relative-location description, target block from entity/object archetypes, fuzzy
  troop estimates, threat detection from AO tags, area description. **These become
  the first entries in the section banks.** The task publishes a task via
  `BIS_fnc_taskCreate`/`setDescription` at the end — that stays.
- `addons/core/functions/data/fnc_getBriefingFragments.sqf` — the current fragment
  registry keyed by `briefingArchetype`. The new banks extend this shape.
- Exemplar for a data registry function: `fnc_getBriefingFragments.sqf` itself.

---

## Deliverables

1. **`DSC_core_fnc_composeBriefing`**
   (`addons/core/functions/missions/fnc_composeBriefing.sqf`)
   - Signature: `[_context] -> _briefingString` (HTML-formatted, as today).
   - `_context` is a hashmap assembled by the caller carrying everything the
     sections need: `mission`, `ao`, `location`, `missionType`, `unitVoice`
     (default a single MVP voice, e.g. `"GENERIC"`), plus a handle to the intel
     ledger / active series (carried but **not yet read for inserts** — that's
     Session 7). Document the context shape in the header.
   - Composes the five sections (§6.1) by pulling a phrasing per section from a
     bank and interpolating named slots (`%locationName`, `%targetName`,
     `%factionName`, `%threatEstimate`, `%priorBeat`, `%tacticalOption`).
   - **Parity rule:** for the current mission types with a single-entry bank and a
     fixed RNG seed (or single phrasing), the composed text must match today's
     briefing content section-for-section. Port the existing logic
     (relative-location, target block, fuzzy estimate, threats) into the section
     builders — do not invent new copy this session.
2. **`DSC_core_fnc_getBriefingBanks`** (data) — the sectioned sentence-bank
   registry keyed by `(missionType × unitVoice)`, seeded with the existing
   fragments as the first (only) entries per section. One voice (`GENERIC`) and
   the four live mission types is enough for parity.
3. **Rewire `fnc_createMissionBriefing`** to assemble the context and call
   `fnc_composeBriefing` for the body, then create/publish the task exactly as it
   does now. Keep its signature and return (the task id) unchanged so callers are
   untouched.
4. **Register** `composeBriefing` and `getBriefingBanks` in `XEH_PREP.hpp`.

---

## Definition of done

- [ ] `fnc_composeBriefing` + `fnc_getBriefingBanks` written, headered, `PREP_SUB`'d;
      `fnc_createMissionBriefing` rewired to use them with an unchanged signature.
- [ ] `hemtt check` clean.
- [ ] Tier-1 suite `briefing_composer` covering: given a fixed mock context, the
      composer emits all five sections; slot interpolation fills `%locationName`
      etc.; **parity** — the composed body for a representative mission equals the
      pre-refactor output (assert on the section strings, single-phrasing banks).
- [ ] Playtest parity: a generated mission's briefing reads the same as before.
- [ ] `roadmap.md` updated.

---

## Tier-1 expectations

The composer is a pure `context -> string` function — fully Tier-1 testable with
a mock context. The parity assertion is the key test: capture today's output for
one fixed context (paste it into the test as the expected string) and assert the
refactor reproduces it.

## Playtest steps (human)

1. `fnc_runTests` → `briefing_composer` all PASS.
2. Harness single-shot a KILL_CAPTURE mission; open the task briefing; confirm it
   reads the same as before the refactor (SITUATION/MISSION/EXECUTION/INTEL/
   SUPPORT present, troop estimate fuzzed, targets listed). Verdict → notes.

## Gotchas

- Keep the HTML formatting tags (`<t font='PuristaBold'>`, `<br/>`) identical —
  the task description renderer depends on them.
- `distance2D`/`getDir` precedence: parenthesise before arithmetic (§AGENTS.md).
- Don't read intel-conditioned inserts yet — carrying the ledger in context is
  fine, *using* it for conditional lines is Session 7. Keep this parity-only.

---

## Paste-ready prompt

```
Read docs/campaign_overhaul/WORKFLOW_RULES.md and
docs/campaign_overhaul/session_04_briefing_composer.md. Refactor the briefing
system into DSC_core_fnc_composeBriefing(context) + a sectioned bank registry
DSC_core_fnc_getBriefingBanks, per .crush/campaign-overhaul.md §6.1/§6.2, seeding
the banks with the EXISTING fragments so output is byte-parity with today.
Rewire fnc_createMissionBriefing to assemble the context and call the composer
while keeping its signature/return unchanged. One unit voice (GENERIC) and the
four live mission types is enough. Do NOT add intel-conditioned inserts or new
copy — this is a parity refactor only. Register in XEH_PREP.hpp, add a
briefing_composer Tier-1 suite with a parity assertion, keep hemtt check clean,
meet every Definition-of-Done checkbox. Sonnet scope.
```

## Results log

- Build: shipped — `fnc_composeBriefing` + `fnc_getBriefingBanks` added,
  `fnc_createMissionBriefing` rewired (signature/return unchanged), both
  registered in `XEH_PREP.hpp`. `hemtt check` clean.
- Tier-1: `briefing_composer` suite added to `fnc_initServerDebug` — five
  sections present, titlePrefix/taskIcon carried through, slot interpolation
  leaves no unfilled `%slot` placeholders, fixed KILL_CAPTURE context
  reproduces pre-refactor output byte-for-byte (verified by manual
  reconstruction against the pre-refactor format string; run `fnc_runTests`
  in-game to confirm PASS in RPT).
- Parity playtest: _pending_ (needs a human launch — generate a KILL_CAPTURE
  mission and confirm the task briefing reads the same as before).
- Gotchas: composer join order is legacy-shaped (MISSION, SITUATION, INTEL,
  EXECUTION, SUPPORT) rather than the canonical SITUATION-first §6.1 order,
  to keep the visible text byte-identical to today's; SUPPORT section is
  empty today (no `deployment.supportAssets` model exists yet). Named-slot
  interpolation uses `CBA_fnc_replace` (`[_string, _find, _replace]`).
