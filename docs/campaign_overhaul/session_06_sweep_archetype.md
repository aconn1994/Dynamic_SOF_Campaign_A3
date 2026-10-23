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

- [x] Mini-spec produced (Opus) and approved before code.
- [x] SWEEP config + `OBSERVED`/`AREA_SWEPT`/`TARGET_IDENTIFIED` conditions + intel
      yield + detection→convert hook written, headered, `PREP_SUB`'d where new.
- [x] On success, a SWEEP drops the correct token(s) into `DSC_intelLedger`.
- [x] `hemtt check` clean.
- [x] Tier-1 suite `sweep` covering the pure logic: each new completion condition's
      check against mock state; the intel-yield calculation (dwell/proximity/
      undetected → token confidence); the compromise-threshold decision.
- [x] `DSC_testConfig` block committed (a forced SWEEP at a fixed site).
- [x] `AGENTS.md` (detection tuning notes) + `roadmap.md` updated.

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

## Mini-Spec (Opus draft — awaiting approval)

### 0. Architecture decision — config-on-existing, plus a runtime monitor

**Decision: SWEEP is a configuration on `fnc_generateRaidMission`, NOT a sibling
generator.** The genuinely new behavior is not *generation* at all.

The justification, concretely:

1. **The raid generator is already archetype-neutral in its body.** It does
   "place data-driven entities → place data-driven objects → place data-driven
   interaction sites → draw markers → build a completionState → emit the mission
   hashmap." Nothing in that sequence is raid-specific except the literal
   `["archetype", "RAID"]` on line 429 and the `markerStyle` default. A SWEEP is
   the *same generation shape* with different data (usually zero entities, zero
   objects, a different completion condition, a withheld marker style).
2. **`fnc_populateAO` is mandated by the brief (§3) for the observed force**, and
   the raid generator already consumes the `_ao` it produces. A sibling would
   duplicate that plumbing on day one.
3. **AREA_SWEPT's "visit N sub-points" is structurally the N-of-M primitive
   Session 5 just shipped.** Forking the generator would immediately duplicate
   the interaction-site placement block (`fnc_generateRaidMission` L287-373).
4. **Everything SWEEP actually adds is runtime, not generation** — a dwell
   accumulator, a detection latch, a conversion hook, an intel-yield formula.
   The raid generator never monitors anything (the mission loop does), so these
   live outside it either way. Once you notice that, the sibling-generator
   argument evaporates: a second generator would be a near-copy whose only new
   content is a different `completionState` literal.
5. §3's own stated principle: *"mission types are configurations, not
   generators."*

**What this costs, and the mitigation.** `fnc_generateRaidMission`'s *name*
becomes slightly inaccurate. We do **not** rename it (surgical-in-existing-code
rule; it has ~10 call sites and two docs). Instead it gains one config field,
`"archetype"`, defaulting to `"RAID"`, so a SWEEP mission hashmap reports
`archetype: "SWEEP"` and any downstream consumer can branch on it. Two-line
change.

**Three small edits to the existing generator, nothing structural:**

| Edit | Where | What |
|---|---|---|
| `"archetype"` config field | `fnc_generateRaidMission` L429 | `_config getOrDefault ["archetype", "RAID"]` instead of the literal |
| New marker styles | `fnc_generateRaidMission` L378-387 switch | `"search_area"` and `"intel_gated"` cases (§5 below) |
| New completion-state keys | `fnc_generateRaidMission` L404-413 | the sweep accumulator keys, seeded from config (harmless to other types, exactly like `sitesCompleted` is today) |

---

### 1. Module layout

New folder `addons/core/functions/sweep/` (precedent: `campaign/`, `intel/`,
`interaction/` each earned a folder at 2-6 functions). Needs a
`script_component.hpp` — copy `interaction/script_component.hpp` verbatim.

| File | Purity | Role |
|---|---|---|
| `sweep/fnc_sweepEvaluateTick.sqf` | **PURE** | Per-tick accumulator math: dwell, proximity floor, compromise latch, PID dwell, swept count. Inputs → new state hashmap. No world reads. |
| `sweep/fnc_resolveSweepYield.sqf` | **PURE** | The intel-yield formula. Facts + tuning → ARRAY of partial intel tokens. No ledger write, no position enrichment. |
| `sweep/fnc_sweepMonitor.sqf` | impure, `spawn`ed | The one world-sampling loop. Samples players/enemies, calls `fnc_sweepEvaluateTick`, writes back into `DSC_currentMission.completionState`, fires the convert hook once, keeps `intelGathered` current. |
| `sweep/fnc_sweepConvert.sqf` | impure | Detection→convert hook. Mutates the live mission's `completion` + briefing, records `converted`/`convertedTo`. Fires at most once. |
| `data/fnc_getSweepArchetypes.sqf` | PURE data | Registry: `SR_OBSERVE`, `SR_AREA_SWEEP`, `SR_PID`. Sits with its siblings in `data/`, same as `getInteractionSiteArchetypes`. |

Existing files edited: `data/fnc_getCompletionTypes` (+3 conditions),
`data/fnc_getMissionProfiles` (+2 profiles), `data/fnc_getBriefingFragments`
(+3 fragments — banks auto-derive, `fnc_createMissionBriefing` and
`fnc_composeBriefing` need **zero** changes, verified: briefingArchetype is a
plain hashmap key lookup, never a switch), `missions/fnc_generateRaidMission`
(three edits above), `missions/fnc_generateMission` (+`case "SWEEP"`),
`missions/fnc_buildMissionOutcome` (+2 passthrough fields),
`missions/fnc_cleanupMission` (+1 defensive line),
`init/fnc_initTestScenario` (+`playerSpawnDistance`),
`init/fnc_initServerDebug` (+`sweep` suite), `XEH_PREP.hpp`.

---

### 2. The new completion conditions

All three follow the existing registry shape exactly — pure `[_state] -> BOOL`,
with `successMsg` / `partialMsg` / `stateKeys`. **None of them read AI state**,
which is the §13.2 anti-soft-lock rule: a defender stuck in terrain can never
block a SWEEP, because completion is driven entirely by player-side
accumulators.

```
["OBSERVED", [
    check: (state.observedSeconds) >= (state.observeRequired)
    successMsg: "Objective observed - intelligence collected"
    partialMsg: "Insufficient observation time on the objective"
    stateKeys: ["observedSeconds", "observeRequired"]
]]
```

**Deliberately, `OBSERVED` does not read `compromised`.** Getting spotted is a
complication, not a fail (§3, §12.2). Compromise suspends *accumulation* inside
`fnc_sweepEvaluateTick` and degrades *yield* inside `fnc_resolveSweepYield` — it
never appears in the completion gate. There is a Tier-1 assertion pinning this.

```
["AREA_SWEPT", [
    check: (state.sweptRequired) > 0 && (state.sweptPoints) >= (state.sweptRequired)
    successMsg: "Search area swept"
    partialMsg: "Search area not fully swept"
    stateKeys: ["sweptPoints", "sweptRequired"]
]]
```

The `sweptRequired > 0` guard mirrors `ALL_DESTROYED`'s empty-array guard: a
mission with no sub-points must return `false`, not auto-complete.

**`AREA_SWEPT` is proximity-driven, not hold-driven, and that is the point.**
It is *not* a reskin of `SITES_INTERACTED`: sweeping a sector is **movement**
("get eyes in that treeline"), while exploiting a site is **dwell** ("stand here
for 40 seconds"). Making every sub-point a 30s hold would be tedious and would
make a 5-point sweep a 3-minute standing simulator. Sub-points are therefore
**plain positions**, consumed by the monitor's distance check — **zero spawned
entities**, which is the §10 budget rule honored by construction. An author who
*does* want held exploitation per point already has `SITES_INTERACTED`; the two
coexist and compose through `completionExpr`.

```
["TARGET_IDENTIFIED", [
    check: state.targetIdentified   (default false)
    successMsg: "Target positively identified"
    partialMsg: "Target not identified"
    stateKeys: ["targetIdentified"]
]]
```

Same shape as `ANY_INTERACTED` — a bool maintained outside the check. The
monitor sets it when a player holds LOS within `pidRange` of `pidTarget` for
`pidDwellRequired` cumulative seconds. `pidTarget` defaults to
`completionState.hvt`, i.e. the first entity the existing raid-generator entity
path placed, so a PID sweep reuses the entity pipeline unchanged and stays
inside the AO budget.

---

### 3. `fnc_sweepEvaluateTick` — the pure core (where the testable logic lives)

```
[_sample, _tuning, _state] call DSC_core_fnc_sweepEvaluateTick -> <HASHMAP> newState
```

**`_sample`** (everything the monitor read from the world this tick):

| Key | Type | Meaning |
|---|---|---|
| `dt` | NUMBER | Measured `serverTime` delta since last tick (**not** the sleep constant — see gotcha 10) |
| `observerDistance` | NUMBER | Min 2D distance from any live player to the objective; `-1` = no live players |
| `hasLOS` | BOOL | That best observer has line of sight to the objective |
| `maxKnowsAbout` | NUMBER | Max `knowsAbout` any **alive** nearby enemy holds on any player |
| `newSweptPoints` | NUMBER | Sub-points newly entered this tick |
| `pidInRange` | BOOL | A player is within `pidRange` of a live `pidTarget` with LOS |

**`_tuning`**: `observeMax`, `observeIdeal`, `observeRequired`,
`compromiseThreshold`, `compromiseTicks`, `pidDwellRequired`.

**`_state` in / out**: `observedSeconds`, `bestProximity`, `compromised`,
`compromiseStreak`, `sweptPoints`, `pidSeconds`, `targetIdentified`,
`converted`, plus the output-only `convertRequested`.

Rules, in order:

1. **Dwell** accumulates `dt` iff `observerDistance >= 0` **and**
   `observerDistance <= observeMax` **and** `hasLOS` **and** `!compromised`.
2. **No minimum observe distance.** Closer is better yield *and* higher
   detection risk — let that tension be emergent rather than adding a gate that
   punishes a player for finding a good hide. (Pinned by a Tier-1 assertion so a
   later agent doesn't "fix" it.)
3. **`bestProximity`** is monotone non-increasing: `min(bestProximity,
   observerDistance)` while observing. It is the *closest the player ever got
   while collecting*, which is what the yield formula wants.
4. **Compromise latches.** `maxKnowsAbout >= compromiseThreshold` increments
   `compromiseStreak`; falling below **resets the streak to 0** (not the latch).
   When `compromiseStreak >= compromiseTicks` and `!compromised`, set
   `compromised = true` and return `convertRequested = true` **on that tick
   only**. Once `compromised` is true it never clears. This two-stage design is
   the direct answer to §12.2's "`knowsAbout` is binary-ish and twitchy" — a
   single spurious spike cannot convert the mission, and a real detection cannot
   un-convert it by the AI losing track of you two seconds later.
5. **PID**: `pidSeconds += dt` while `pidInRange`; at `>= pidDwellRequired`, latch
   `targetIdentified = true`.
6. **Swept**: `sweptPoints += newSweptPoints`.

Every number above is read from `_tuning`, never literal in the body — gotcha 1.

---

### 4. The intel-yield formula — `fnc_resolveSweepYield`

```
[_facts, _tuning] call DSC_core_fnc_resolveSweepYield -> <ARRAY> of partial tokens
```

Three normalized factors, each clamped to `[0,1]`:

```
dwellFactor     = clamp01(observedSeconds / observeRequired)
proximityFactor = clamp01((observeMax - bestProximity) / (observeMax - observeIdeal))
coverageFactor  = clamp01(sweptPoints / sweptRequired)        // only if sweptRequired > 0
stealthFactor   = compromised ? stealthPenalty : 1.0          // default 0.5
```

Combined as a **weighted sum scaled by a stealth multiplier**, not a triple
product:

```
quality    = (dwellW*dwellFactor + proxW*proximityFactor + covW*coverageFactor) / (sum of APPLICABLE weights)
confidence = clamp(baseConfidence * quality * stealthFactor, confMin, confMax)
```

Defaults: `dwellW 0.5`, `proxW 0.3`, `covW 0.2`, `baseConfidence 0.9`,
`stealthPenalty 0.5`, `confMin 0.05`, `confMax 0.95`.

- **Weighted sum, not product**, because a product collapses: ideal dwell with
  mediocre proximity would score 0.3 and feel like a punishment for a safe
  standoff. A sum degrades gracefully.
- **Weights renormalize over the applicable factors.** If `sweptRequired == 0`
  (a pure observe sweep), `covW` is dropped and the remaining weights are
  rescaled — no divide-by-zero, and a pure-observe mission isn't permanently
  capped at 80% quality. Tier-1 asserts this.
- **`confMin 0.05`, never 0.** §11 decision 4: a completed objective always
  yields *something*. **`confMax 0.95`, never 1.0** — total certainty is reserved
  for HQ-granted intel.

**Token set emitted** (scope is `"SERIES"` when the mission carries a
`seriesId`, else `"LOCATION"` — the exact rule the raid generator already uses
for interaction-site `tokenContext` at L340):

| Token | Emitted when | `subjectRef` | Notes |
|---|---|---|---|
| `AREA_LAYOUT` | always, if any collection happened | **location id** | **This is the token that unlocks compound markers** (§5) — it closes the §4.4 loop |
| `ENEMY_STRENGTH` | `sweptRequired > 0` and sweep complete | location id | |
| `PATROL_PATTERN` | `observedSeconds >= patrolObserveSeconds` (default 180) | location id | You watched long enough to see the rotation |
| `HVT_IDENTITY` + `HVT_LOCATION` | `targetIdentified` | `pidSubjectRef` | |
| `QRF_POSTURE` | **`compromised`** | location id | You saw how they respond because you triggered it |

The compromised path is deliberately **not just "less"** — it *changes the mix*.
You lose layout fidelity but you learn their reaction posture. Detection
produces different intel, not merely worse intel, which is what keeps "getting
spotted" from feeling like a straight penalty.

Returns `[]` when `observedSeconds == 0 && sweptPoints == 0 && !targetIdentified`
— a sweep that never collected anything yields nothing. (§11's
"a dryhole always yields" rule applies to a *completed* objective, not a no-show.)

#### 4.1 Reusing Session 5's token builder — and the one integration that matters

`fnc_resolveSweepYield` returns **partial** tokens with no position payload. The
monitor enriches each through the existing Session 5 builder:

```
_enriched = [_partialToken, _syntheticSite] call DSC_core_fnc_buildIntelTokenFromSite;
```

where `_syntheticSite = createHashMapFromArray [["pos", _objectivePos], ["id", _sweepRunId]]`.
The builder only ever reads `pos` and `id` off its `_site` argument
(`fnc_buildIntelTokenFromSite` L44-45), so this is legitimate reuse with **no
change to the builder** — and it guarantees RECON tokens carry byte-identical
`pos`/`grid`/`siteId` payload enrichment to SSE tokens. Tier-1 pins this.

**The ledger write reuses the existing bridge — there is NO new global write
site.** The monitor writes the enriched token array into
`completionState.intelGathered`. `fnc_buildMissionOutcome` L102-104 already
handles an ARRAY there (`if (_flag isEqualType []) then { _intelGathered = _flag }`),
and both the mission loop (`fnc_initServer` L625-627) and the harness
(`fnc_initTestScenario` L372-374) already iterate `outcome.intelGathered` into
`fnc_intelAdd`. So the entire SWEEP → ledger path is:

```
sweepMonitor → completionState.intelGathered (array)
             → fnc_buildMissionOutcome (unchanged)
             → existing retrofit bridge → fnc_intelAdd
```

Zero new plumbing, works identically under the Tier-2 harness, and
`fnc_intelAdd` remains the sole global-writing call per the Session 2
convention. **This is the single most important integration finding in this
spec — do not add a direct `fnc_intelAdd` call inside the monitor.**

---

### 5. Intel-gated markers (§4.4 — the blind-assault gradient)

Two new `markerStyle` values in `fnc_generateRaidMission`'s switch:

- **`"search_area"`** — always a single broad circle at the objective, radius
  from config (default 400m). This is SWEEP's own objective marker: you were
  told *roughly* where to look.
- **`"intel_gated"`** — reads `DSC_intelLedger` once, calls the already-pure
  `fnc_intelBest(_ledger, _locationId, "AREA_LAYOUT", serverTime)`. If a live
  token exists with `confidence >= DSC_markerIntelThreshold` (default 0.5) →
  draw the full `fnc_drawCompoundMarkers` set exactly as today. Otherwise →
  fall back to `"search_area"` with a radius scaled by `(1 - confidence)`, so
  partial intel narrows the circle instead of flipping a binary.

One `missionNamespace` read inside the generator is acceptable — it already
reads `opForFaction` at L83.

**`"intel_gated"` is opt-in, NOT the new default for RAID.** Flipping the
default would silently change the feel of every existing mission type with no
playtest behind it, and it is out of this session's scope (Law #1). Flagged as
Open Decision #2 below.

**Load-bearing invariant:** the `AREA_LAYOUT` token's `subjectRef` must be the
**location id** on both the write side (`fnc_resolveSweepYield`) and the read
side (the marker gate). A mismatch silently never unlocks markers and looks like
a dead feature. Gotcha 12.

---

### 6. Detection → convert — `fnc_sweepConvert`

Fires exactly once, when `fnc_sweepEvaluateTick` returns `convertRequested`.
Guarded by `completionState.converted`.

**It does not regenerate anything.** The AO already exists; conversion is a
*mutation of the live mission*:

1. **Swap the completion condition in place.** `DSC_currentMission` holds a
   hashmap, and SQF hashmaps are reference types — the mission loop's captured
   `_mission` local (`fnc_initServer` L579) is the *same object*, which is
   exactly why `fnc_interactionSiteFire` can bump `sitesCompleted` and have the
   loop observe it at debrief. So setting `_mission set ["completion", …]` is
   seen by the loop. Two convert targets, selected by the archetype's
   `convertOn` field:
   - **`"RAID"`** — `completionExpr` = *(dwell threshold already met)* **OR**
     *(hvt down/captured)*. You're blown; finish it the hard way or leave with
     what you banked.
   - **`"EXFIL"`** — `completionExpr` = *(dwell threshold already met)* **OR**
     *(every live player beyond `exfilDistance` from the objective)*. Break
     contact and you keep the partial yield.
   Both disjunctions **preserve** the original success path — a player who had
   already banked enough observation is not retroactively failed by being seen.
2. **Reveal the markers.** Once compromised there is no reason to withhold the
   layout; re-draw as `"compound"` and append to `mission.markers` for cleanup.
3. **Update the player-facing briefing/task** and fire one unconditional
   `systemChat` (player-facing feedback stays ungated per the logging policy).
4. **Record `converted: true` + `convertedTo: "RAID"|"EXFIL"` + `convertReason`**
   into `completionState`.

**The enemy-side reaction is deliberately nothing.** The unit that spotted you
is already stamped into the C2 network, and C2 will file the contact report,
raise the node, and dispatch recall/QRF through its own existing ladder. Writing
a bespoke chase would duplicate `fnc_c2Respond` *and* violate §12.2's
"keep flee/convert coarse." This is a genuine strength of the existing codebase —
use it, don't fork it.

#### 6.1 Why the series is NOT called mid-mission

The brief says "fire a mid-mission conversion event through the arbiter/series."
Taken literally that **violates §10's decoupling landmine** ("Outcome is the only
series input… it must not reach into live mission internals") and would make
`fnc_advanceCampaign` impure, which would wreck the Session 3 Tier-1 suite.

**Resolution:** conversion is purely *in-mission*, and the **series learns about
it through the standardized outcome**, like everything else. Add two
passthrough fields to `fnc_buildMissionOutcome` (read from `_state`, so the
function stays pure):

```
["converted",   _state getOrDefault ["converted", false]],
["convertedTo", _state getOrDefault ["convertedTo", ""]]
```

That gives §5.3.1's *"Recon compromised → next stage's enemy posture escalates to
reinforced"* its data source, at the correct seam, with no purity loss. Flagged
as Open Decision #1.

---

### 7. Wiring: profiles, archetypes, the `SWEEP` case

**`fnc_getSweepArchetypes`** — three presets carrying tuning + yield weights +
`convertOn`:

| Archetype | Completion | Shape |
|---|---|---|
| `SR_OBSERVE` | `OBSERVED` | Standoff vantage on a compound. `observeRequired 120`, `observeMax 600`, `observeIdeal 250`, `convertOn "EXFIL"`. |
| `SR_AREA_SWEEP` | `AREA_SWEPT` | 3-5 sub-points across a location. `sweptRadius 40`, `convertOn "RAID"`. |
| `SR_PID` | `TARGET_IDENTIFIED` | One entity placed via the existing entity-spec path. `pidRange 300`, `pidDwellRequired 5`, `convertOn "RAID"`. |

**`fnc_getMissionProfiles`** — two new profiles (data only, no code):

- **`SR_rural`** — `excludeTags ["military","urban","base","outpost"]`,
  `density "light"`, `qrfEnabled false`, `areaPresenceChance 0.4`,
  low guard coverage, `patrolCount [1,2]` (patrols are the *content* of a recon
  mission, so slightly more than AFO), `maxVehicles 1`.
- **`SR_installation`** — `requiredTags ["military"]`, **`excludeTags []`**
  (this is the one profile that must *not* exclude bases/outposts — observing a
  real installation from standoff is where DA-unlocking intel comes from),
  `density "heavy"`, `qrfEnabled true`.

**`fnc_generateMission`** gains `case "SWEEP":` which (a) reads an optional
`sweepConfig` off the mission config — same opaque-passthrough pattern as the
Session 5 `raidConfig` case, and same reason: `fnc_resolveMissionConfig` L434-438
carries unknown template keys straight through; (b) merges archetype defaults
under it; (c) builds the raid config with `archetype: "SWEEP"`, the resolved
completion, `markerStyle` defaulting to `"search_area"`, `briefingArchetype`
`"sweep_*"`; (d) calls `fnc_generateRaidMission`; (e) resolves sub-point
positions from the AO's `garrisonClusters` centers (positions only, nothing
spawned); (f) `spawn`s `fnc_sweepMonitor` — the same place the orchestrator
already spawns `fnc_persistentUAV`.

**`fnc_getBriefingFragments`** — `sweep_observe`, `sweep_area`, `sweep_pid`
(titlePrefix/objective/roe/taskIcon). The banks generator derives the five
sections automatically; `fnc_createMissionBriefing` and `fnc_composeBriefing`
need **no** changes.

**`fnc_cleanupMission`** — one defensive line clearing `DSC_sweepRunId` (the
monitor self-terminates on run-id mismatch; this makes it deterministic).

**`XEH_PREP.hpp`** — new `// Sweep (Campaign Overhaul Session 6)` block with
`PREP_SUB(sweep,sweepEvaluateTick|resolveSweepYield|sweepMonitor|sweepConvert)`
plus `PREP_SUB(data,getSweepArchetypes)`.

---

### 8. Tier-1 test plan — suite `sweep`

Registered in `fnc_initServerDebug` alongside `intel_ledger` / `series_arbiter` /
`briefing_composer`, same contract (array of `[label, passed]`). Everything below
is deterministic with hand-built hashmaps and **zero world reads**; the one
deliberate exception is #28, which mirrors the existing suites' intentional
`fnc_intelAdd` round-trip.

**A. Completion conditions** (through `fnc_evaluateCompletion`, matching how the
registry is exercised elsewhere):
1. `OBSERVED` false below threshold.
2. `OBSERVED` true at exactly threshold (boundary).
3. **`OBSERVED` completes even when `compromised` is true** — pins "detection is
   not a fail."
4. `AREA_SWEPT` false at N-1 of N.
5. `AREA_SWEPT` true at N and at N+1.
6. `AREA_SWEPT` false when `sweptRequired == 0` (no spurious auto-complete).
7. `TARGET_IDENTIFIED` false when the key is absent.
8. `TARGET_IDENTIFIED` true when set.
9. All three return `false` against an empty state hashmap (no error).

**B. `fnc_sweepEvaluateTick`:**
10. Dwell accumulates by `dt` when in band + LOS + not compromised.
11. No accumulation without LOS.
12. No accumulation beyond `observeMax`.
13. **Accumulation DOES occur at very close range** — pins the "no minimum
    distance" decision.
14. No accumulation while `compromised`.
15. **Latch:** streak reaching `compromiseTicks` sets `compromised`; a
    subsequent tick with `maxKnowsAbout` back below threshold leaves it true.
16. **Anti-twitch:** one single above-threshold tick with `compromiseTicks = 2`
    does **not** compromise; the streak resets on a below-threshold tick.
17. `bestProximity` is monotone non-increasing across ticks.
18. Threshold is honored from `_tuning` — identical sample, two thresholds, two
    different outcomes (pins "no magic number").
19. `convertRequested` is true **only** on the latching tick.
20. `convertRequested` is false when an already-`compromised` state is passed in
    (idempotent).

**C. `fnc_resolveSweepYield`:**
21. No collection at all → `[]`.
22. Full dwell + ideal proximity + undetected → an `AREA_LAYOUT` token with
    `confidence >= 0.7`.
23. Same inputs with `compromised: true` → `AREA_LAYOUT` confidence strictly
    lower **and still > 0** (degrade, never zero).
24. Compromised run emits a `QRF_POSTURE` token the clean run does not.
25. Proximity monotonicity: closer `bestProximity` ⇒ confidence `>=`, all else
    equal.
26. Dwell monotonicity + saturation: `2 × observeRequired` scores the same as
    `1 ×`, and both `>=` a half-dwell run.
27. `targetIdentified` ⇒ `HVT_IDENTITY` with the supplied `subjectRef`;
    absent otherwise.
28. `sweptRequired == 0` → weights renormalize, no divide-by-zero, confidence in
    range (and strictly greater than the naive un-renormalized value).
29. Every emitted confidence within `[confMin, confMax]`.
30. `seriesId != ""` ⇒ all tokens `scope == "SERIES"`; `""` ⇒ `"LOCATION"`.
31. `AREA_LAYOUT.subjectRef` equals the location id passed in (pins the marker-
    gate contract from §5).
32. **Round-trip:** one emitted token through `fnc_intelAdd` then
    `fnc_intelQuery` lands in `DSC_intelLedger` (deliberate impure assertion,
    same pattern as the `series_arbiter` suite's intelReward check).

**D. Builder reuse:**
33. `fnc_buildIntelTokenFromSite` with a **synthetic** site hashmap carrying only
    `pos` + `id` enriches `payload.pos` / `payload.grid` / `payload.siteId` —
    proves §4.1's reuse path without an actual interaction site.

~33 assertions, all sub-second, no Arma world required.

---

### 9. Harness `DSC_testConfig` — `docs/test_harness/05_tier2_altis_sweep_observe.sqf`

```sqf
DSC_testConfig = createHashMapFromArray [
    ["factionProfile", "vanilla"],
    ["steps", ["globals", "locations", "factions", "influence", "c2"]],
    ["missionTemplate", createHashMapFromArray [
        ["type", "SWEEP"],
        ["missionProfile", "SR_rural"],
        ["location", "loc_replace_with_real_id"],
        ["sweepConfig", createHashMapFromArray [
            ["archetype", "SR_OBSERVE"],
            ["completion", "OBSERVED"],
            ["observeRequired", 90],
            ["observeMax", 600],
            ["observeIdeal", 250],
            ["compromiseThreshold", 0.6],
            ["compromiseTicks", 2],
            ["markerStyle", "search_area"]
        ]]
    ]],
    ["singleShot", false],
    ["playerSpawn", "nearSite"],
    ["playerSpawnDistance", 450],
    ["timeOfDay", 5],
    ["freezeWeather", true],
    ["extraDebug", true]
];
[] call DSC_core_fnc_initTestScenario;
```

Two harness notes that are **requirements, not suggestions**:

- **`singleShot` MUST be `false`.** A single-shot debrief evaluates completion
  immediately, so `observedSeconds` would be 0 and the run would assert nothing.
  The spec adds a `WARNING` in the SWEEP path when `singleShot` is detected true.
- **`"c2"` is in `steps`.** Without it, no node is in reach, groups are never
  C2-stamped, and the convert path's "let C2 react organically" design has
  nothing to react — which reads in the RPT exactly like a broken convert hook
  (the documented three-causes-of-C2-silence gotcha).
- **`playerSpawnDistance`** is a new `fnc_initTestScenario` key (default 150,
  preserving today's behavior). The existing hardcoded 150m is far inside
  `observeMax` and would make the standoff/proximity dials untestable.

The same file carries a second commented block for the **convert** test:
`compromiseThreshold 0.2`, `compromiseTicks 1`, `convertOn "RAID"` — trivial to
provoke detection on purpose.

---

### 10. Gotchas to respect (on top of the session brief's list)

1. **Expose the compromise threshold at three levels, never inline a number** —
   `DSC_sweepCompromiseThreshold` global → archetype → template, resolved in
   that order and logged once at generation.
2. **Compromise must latch, and must require consecutive ticks.** A bare
   `knowsAbout >= x` check converts and un-converts on AI perception flicker.
   Streak-then-latch is the design; do not "simplify" it away.
3. **Only sample `alive` enemies.** `side`/`rating` are meaningless on a dead
   unit (documented) and `knowsAbout` on corpses is noise.
4. **Never gate a SWEEP on `AREA_CLEAR` or any AI state** (§13.2) — one defender
   stuck under a building would soft-lock the whole objective. All three new
   conditions read player-driven accumulators only.
5. **Spawn nothing** (§10). Sub-points are positions. The only entity a SWEEP may
   place is the optional PID target, and it goes through the existing raid
   entity-spec path, inside the AO budget.
6. **Parenthesise before dividing** — `((_p distance2D _pos) / _r)`. SQF binary
   operators bind looser than arithmetic; this exact bug shipped in the F.4
   Radio Feed panel.
7. **CBA log-macro comma trap** — hoist every inline array literal to a local
   before any `LOG_n`/`INFO_n`/`TRACE_n`. Max `_8`.
8. **Mutate `completionState` in place; never rebuild the mission hashmap.** The
   mission loop holds a *reference* to the same hashmap (`fnc_initServer` L579).
   Reassigning it in the monitor silently orphans every subsequent write — the
   same class of bug as the presence manager's `_q = _q - [_zone]` gotcha.
9. **The monitor MUST terminate.** Stamp `DSC_sweepRunId` at generation; the
   monitor bails on run-id mismatch, on `!missionInProgress`, on
   `DSC_missionAbortRequested`, and on a hard max-runtime. An orphaned monitor
   from mission *N* writing into mission *N+1*'s `completionState` is the
   nastiest available failure here and would be near-impossible to diagnose.
10. **Accumulate from measured `serverTime` deltas, not from the sleep
    constant.** Scheduler lag and `setAccTime` both make "tick length ==
    `dt`" false; a dwell timer that drifts under load is a bug the playtester
    will report as "OBSERVED never completes." Use `uiSleep` for scheduling,
    `serverTime` deltas for math.
11. **`completionState.intelGathered` is overloaded** — a BOOL for
    `ANY_INTERACTED`, an ARRAY for SWEEP. `fnc_buildMissionOutcome` already
    handles both, but never author a template that pairs `ANY_INTERACTED` with a
    SWEEP.
12. **`AREA_LAYOUT.subjectRef` must be the location id on both sides** (yield
    write and marker gate) or the markers never unlock and nothing errors.
13. **Do not call `fnc_advanceCampaign` mid-mission** (§10). Conversion reaches
    the series through `DSC_lastMissionOutcome` only.
14. **Do not add a bespoke enemy chase on convert.** C2 already handles it; a
    second response path would fight `fnc_c2Respond` and violate §12.2.
15. **LOS cost discipline.** `lineIntersectsSurfaces` once per *player* per tick
    is cheap; never per enemy unit. Enemy detection uses `knowsAbout` (a cheap
    engine lookup) over a `nearEntities`-bounded sample, not `allUnits`.
16. **Tablet Mission Gen panel** lists mission types for the queue — adding
    SWEEP there is a one-line UI data change, *out of scope* for this session;
    note it in the roadmap as a follow-up rather than widening the diff.

---

### 11. Open decisions requiring approval before the Sonnet build

1. **Conversion reports via the outcome, not by calling the arbiter mid-mission.**
   The brief's wording implies a live arbiter call; that would break §10's
   decoupling and `fnc_advanceCampaign`'s purity. Proposed: mutate the live
   mission, surface `converted`/`convertedTo` on `DSC_lastMissionOutcome`, let
   the series consume it at the normal OUTCOME seam. **Approved.**
2. **`"intel_gated"` markers ship opt-in, not as the RAID default.** Flipping the
   default changes the feel of all four existing mission types with no playtest
   behind it. Proposed: SWEEP uses it; RAID keeps `"compound"`; revisit after the
   Session 6 playtest. **Approved.**
3. **`AREA_SWEPT` is proximity-driven, not a held action** (§2 above). The
   alternative — making it an alias over `sitesCompleted` — is less code but
   duplicates `SITES_INTERACTED` and makes a 5-point sweep tedious.
   **Approved** the distinct, movement-based design.
4. **No minimum observation distance.** Closer = better yield *and* more
   detection risk, emergent rather than gated. **Approved.**
5. **`fnc_initTestScenario` gains `playerSpawnDistance`** (default 150, behavior-
   preserving). Small harness widening, but the standoff dials are untestable
   without it. **Approved.**
6. **Scope confirmation:** this session ships `SR_OBSERVE` / `SR_AREA_SWEEP` /
   `SR_PID` and two mission profiles. The §3 variety bank (infil method, dryhole
   chance, weather modifiers, alert posture) is explicitly **deferred** — it is
   template vocabulary, authored later, not plumbing. **Confirmed.**

---

## Results log

- Spec approved: **yes** — all 5 open decisions approved, decision 6 (scope
  confirmation: `SR_OBSERVE`/`SR_AREA_SWEEP`/`SR_PID` + two mission profiles,
  §3 variety bank deferred) confirmed · Build: **complete** (Sonnet) ·
  Tier-1: **33 assertions registered, expected to PASS** (`sweep` suite in
  `fnc_initServerDebug.sqf`) · Playtest/feel: _pending_ (Tier-2 human pass per
  the "Tier-2 playtest" section above — harness config committed at
  `docs/test_harness/05_tier2_altis_sweep_observe.sqf`, including a commented
  convert-path variant).
