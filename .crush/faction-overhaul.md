# Faction Overhaul — Plan A (Two-Pole Model)

*Status: **APPROVED, NOT STARTED.** Instrumentation phase in progress.
August 2026.*

Supersedes the side model in `.crush/faction-sides.md`. Read that document for
the history of what went wrong; read this one for where we are going.

## Why we are overhauling rather than patching

Three consecutive sessions attributed same-faction fratricide to three
different causes, fixed all three, and the symptom did not change. Each fix
addressed a real bug with real log evidence — and none of them was *the* bug.

The reason is structural: **DSC has two independent layers both trying to
decide a unit's side.**

1. **Config layer** — the faction profile literals in `fnc_initServer` declare
   a `side` per role.
2. **Spawn layer** — `fnc_resolveRoleSide`, the normalization pass, the
   realignment pass in `fnc_populateAO`, and hardcoded forced-east overrides in
   `fnc_resolveIrregularOverlay` / `fnc_setupContestedSkirmish`.

When those disagree the result is silent. There is no error, no warning, and
the only observable is AI behaviour several minutes later. That is not
debuggable, and it is why every diagnosis so far has been an inference rather
than a measurement.

**Plan A deletes the second layer entirely.**

## Engine ground truth

Established facts, so nobody has to re-derive them:

### Sides

| Side | Combatant | Notes |
|---|---|---|
| `west` | yes | BLUFOR |
| `east` | yes | OPFOR |
| `independent` / `resistance` | yes | GUER — genuine third pole |
| `civilian` | no | shootable, does not fight; friendly to all by default |
| `sideEnemy` | yes | **renegade — hostile to everything, including other renegades** |
| `sideLogic`, `sideUnknown`, `sideFriendly`, `sideAmbientLife`, `sideEmpty` | no | bookkeeping only |

**Three usable combatant sides. That is a hard ceiling.**

### Two rules that caused most of our pain

- **A unit's side comes from its GROUP, not its class.**
  `createGroup [east]` + `createUnit "I_C_Soldier_Bandit_F"` produces an
  *east* bandit — cosmetically independent, functionally east.
- **Relations are SIDE-level only.** No per-faction, per-group or per-unit
  relations exist. `setFriend` takes two sides and a 0–1 value; `>= 0.6` reads
  as friendly. It is **directional** — both halves of a pair must be set.

### How the engine treats independent

**Independent has no built-in allegiance.** Its relationship to west and east
is a *scenario setting*, not an engine constant. It is not "closer to" either
side — it is a configurable third faction.

Verified for this project:

- `west` ↔ `east` is hostile by default, always, and cannot be usefully changed.
- `west` ↔ `independent` and `east` ↔ `independent` come from the scenario's
  independent-allegiance attribute.
- **`addons/maps/DSC_Altis.Altis/mission.sqm` contains NO allegiance key**, so
  the value is the Eden/engine default: **independent friendly to BLUFOR**,
  hostile to OPFOR. This matches what `fnc_initPresenceManager` sets at
  runtime, so — importantly — **there is no mission.sqm-vs-runtime conflict.**
  That theory is ruled out.

### Sub-side friendliness primitives (the complete list)

The only ways to make two combatants not shoot each other, short of sharing a
side:

- **Same group.** Units in one group never engage each other, and Arma
  deconflicts line of fire *within* a group only.
- **`setCaptive true`.** Removes a unit from targeting entirely. Correct tool
  for hostages, surrendered HVTs, non-combatant actors.
- **`disableAI "AUTOTARGET"` / `setCombatMode "BLUE"`.** Behavioural, not
  relational — a unit that will not initiate but will return fire.

That is all of them. There is no per-faction relation to be found.

## The model

**Rule: never override a faction's native side.**

Every faction already has a side from `CfgFactionClasses >> side`. If we only
ever spawn a faction on its own native side, every override, resolver and
realignment pass in the codebase becomes dead code.

Roles stop being "things that pick a side" and become **descriptive labels for
mission logic** — who is the target, who is ambient, who garrisons. The side is
whatever the faction natively is.

### Role table (vanilla)

| Role | Required native side | Vanilla candidates |
|---|---|---|
| `bluFor` | west | NATO (`BLU_F`) |
| `bluForPartner` | **west** | NATO Pacific (`BLU_T_F`), FIA-west (`BLU_G_F`), CTRG |
| `opFor` | east | CSAT (`OPF_F`), CSAT Pacific (`OPF_T_F`) |
| `opForPartner` | east | Spetsnaz (`OPF_R_F`) |
| `irregulars` | east | FIA-east (`OPF_G_F`) |
| `civilians` | civilian | `CIV_F` |
| `environmentalActors` | civilian | IDAP, Gendarmerie, UN |

**Independent is not used for combatants at all.**

### Diplomacy

Stock `west` ↔ `east` hostility. **Nothing else set. All `setFriend` calls
removed.** The `mission.sqm` allegiance value becomes irrelevant because
nothing spawns on independent.

### Validation replaces debugging

One load-time validator: *a faction whose native side does not match its
role's required side is rejected with an ERROR at init.* Invalid
configurations become **impossible** rather than **debugged**. This is the
whole point of the plan.

## What this costs

- AAF (`IND_F`), Syndikat (`IND_C_F`), Looters (`IND_L_F`) are unusable as
  combatants in **vanilla**. They remain available as `environmentalActors`.
- Enemy cosmetic variety in vanilla drops to ~4 east factions.
- In modded setups (RHS, CUP, CFP) the cost is near zero — they ship plenty of
  east-native factions.

Accepted deliberately. The variety was never worth an unfalsifiable bug.

## What we keep for free

- **Unlimited factions per role, same side.** Ten east factions can garrison
  ten locations, look completely different, and never fight. Side-sharing costs
  nothing visually.
- **Equipment and appearance variety** comes from CfgGroups / CfgVehicles and is
  entirely side-independent.
- **Behavioural variety is side-agnostic** and is where the real texture lives:
  `setCombatMode`, `setBehaviour`, skill profiles, `disableAI "AUTOTARGET"`. An
  ambient patrol that will not start a fight and a hunting QRF can be the same
  faction on the same side.
- **`setCaptive`** for non-combatant actors.

What we genuinely cannot have: **two mutually hostile hostile-blocs *plus*
armed allies.** Three poles, three uses — pick three from three. Engine
limitation, not a design failure.

## Deferred alternatives

Recorded so they are not re-litigated:

- **B1 — independent = the player's allies.** AAF as host nation; all hostiles
  east. Buys the host-nation fantasy, costs Syndikat/Looters.
- **B2 — independent = the hostile irregular bloc.** Insurgents on independent,
  conventional enemy on east, **mutually hostile** — CSAT-vs-insurgent becomes
  an emergent feature, genuinely good for the SOF setting. Costs armed allies
  entirely.

Both are coherent; both are strictly more fragile than A because they need
`setFriend` to be correct *and* to agree with `mission.sqm`. Revisit **B2**
after C2 is finished, as a deliberate feature with its own testing budget.

---

# Phase 0 RESULTS — first instrumented run (2026-08-06 09:58)

**The side system is not broken.** Measured, not inferred.

## What the data proved

Mission AO was `opForPartner` / FIA (`OPF_G_F`), 4 units, sampled at
T+0 / T+45 / T+75 / T+120:

```
side=EAST  grpSide=EAST  rating=2e+06  nativeFac=OPF_G_F
SUMMARY  alive=4 expected=EAST | sides=[[EAST,4]] | factions=[[OPF_G_F,4]]
         mismatched=0  renegade=0  negRating=0
SIDES-PRESENT [EAST]
```

Stable across the full two-minute window. Therefore:

| Theory | Verdict |
|---|---|
| Sides not what we requested | **RULED OUT** — `mismatched=0`, unit side == group side |
| Renegade / rating cascade | **RULED OUT** — `rating=2e+06` flat, `renegade=0` |
| `addRating` guard not applying | **RULED OUT** — it is applying and holding |
| Diplomacy asymmetric on combatant pairs | **RULED OUT** — west/east/indep all symmetric |
| mission.sqm vs runtime conflict | **RULED OUT** — no allegiance key in the .sqm; runtime matches default |
| Role side normalization broken | **RULED OUT** — every role reads the expected side, `type=SIDE` |

## The probe itself was reporting false positives

Ten `*** FRATRICIDE-ALLIED ***` lines appeared. **All ten were wrong, and the
bug was in the diagnostic.**

Inside `EntityKilled` the victim is already dead, and for a dead unit the
engine returns **`side` = CIVILIAN** and **`rating` = 0**, regardless of what
it was in life. Every victim therefore printed as `CIV`, and since
`east getFriend civilian == 1`, the verdict logic labelled every legitimate
west-kills-east engagement as allied fratricide.

Re-read correctly, all ten kills are ordinary combat:

```
killer=O_G_Soldier_TL_F(EAST)  victim=B_Soldier_SL_F   <- FIA killed the player's SL
killer=B_HeavyGunner_F(WEST)   victim=O_G_officer_F    <- squad killed the HVT
killer=B_soldier_AAR_F(WEST)   victim=O_soldierU_*(x6) <- squad wiped a CSAT patrol
```

**Zero AI-vs-AI fratricide occurred in this run.**

Fixed: the probe now reads `side (group _killed)`, which survives the unit's
death because the group object outlives it. Victim rating is not recoverable
post-mortem and is no longer printed. Killer rating *is* meaningful (usually
still alive) and is retained.

Lesson worth keeping: **`side` and `rating` are meaningless on a dead unit.**

## The actual bug: rovers cannot fight back

Reported symptom — *"a CSAT patrol walked up on us, my squad engaged, and the
patrol completely ignored us."* The log shows exactly that: six
`O_soldierU_*` (CSAT, `OPF_F`, group `Bravo 4-2`) killed one at a time between
10:16:41 and 10:18:26, never returning fire.

Cause, identical in all four rover spawners:

```sqf
_group setCombatMode "BLUE";     // = NEVER FIRE (not "hold fire")
_x disableAI "AUTOCOMBAT";       // won't switch to combat behaviour
_x disableAI "TARGET";           // won't aim at a target
_x disableAI "AUTOTARGET";       // won't acquire a target
```

Three independent locks on ever firing a shot. The doc comments claimed
*"ambient, no engagement unless fired upon"* and *"they react only if fired
upon"* — both impossible with that combination. The intent was right; the
engine settings did not express it.

Correct mapping of intent to settings:

| Intent | Setting |
|---|---|
| Alert but not in combat | `setBehaviour "AWARE"` |
| **Won't initiate, WILL defend itself** | `setCombatMode "GREEN"` |
| Stays on its patrol route, doesn't go hunting | `disableAI "AUTOCOMBAT"` |
| Can see and shoot whoever shoots it | leave targeting AI **enabled** |

Applied to `fnc_rovingSpawnFoot`, `fnc_rovingSpawnGround`,
`fnc_rovingSpawnBoat`, `fnc_rovingSpawnAir`.

Air is the sharpest case — an armed gunship that returns fire is a real threat
spike — but it is gated behind the player shooting first, and a helicopter that
placidly absorbs fire is worse.

## Bonus finding: the player's own squad is a renegade risk

Live killer ratings in the log: `-1040`, then `-840`, `-640`, `-440` (each
enemy kill is +200). A **player squadmate** was over half way to the ~-2000
renegade threshold after one mission.

The player's squad is Eden-placed, so it never passes through
`fnc_applySkillProfile` and had no `addRating` protection. The presence manager
populates towns with civilians, so collateral in a firefight is routine and a
civilian kill is a large single penalty.

A squadmate crossing the threshold goes renegade — hostile to west included —
so **the player's own squad turns on itself**, with no feedback explaining why.
`fnc_initPlayerLocal` now applies `addRating 1000000` to
`units group player`.

This is a plausible cause of at least some of the earlier "free-for-all"
reports and is worth re-testing specifically.

## Stale documentation found

`AGENTS.md` documents `fnc_addCombatActivation` as a live system ("units start
frozen, activate on FiredNear EH"). **The function does not exist** — it is not
in `XEH_PREP.hpp` and the only reference is a stale comment in
`fnc_setupAnchoredPatrol`. Presence guards/garrisons are therefore *not*
combat-activated; they are live from spawn. Corrected in AGENTS.md.

## Garrison defect confirmed in the wild

```
loc_49 populatedArea -> 16 armed groups, 16 units
loc_40 populatedArea -> 17 armed groups, 18 units
```

One group per unit, exactly as predicted. Arma deconflicts line of fire
*within* a group only, so these units shoot through each other. Still the top
remaining fix.

## Revised order of work

1. ~~Instrument~~ — **done, side model exonerated**
2. **Fix garrison grouping** — now the highest-value remaining fix
3. Rename the `"side"` key collision; repair `factionClass` provenance
4. Migrate to Plan A — still worth doing, but as *simplification*, not as a
   bug fix. It removes a whole class of future failure rather than a present one.
5. C2 F.4


---

# ROOT CAUSE FOUND — run 2 (2026-08-06 10:35, Syndikat)

**`group createUnit` does not set the unit's side.** That is the whole bug, and
it had been in every spawn path since the beginning.

## The evidence

Syndikat (`IND_C_F`) objective, observed via Zeus with the player far away:

```
T+0  side=GUER  grpSide=EAST  cls=I_C_Soldier_Bandit_4_F  nativeFac=IND_C_F
     SIDE!=EXPECTED UNIT!=GROUPSIDE
SUMMARY  alive=9 expected=EAST | sides=[[CIV,1],[GUER,8]] | mismatched=9
```

Then, with no player involvement:

```
10:35:52  FRATRICIDE-SAMESIDE  Bandit_3 -> Bandit_4   (both grp=Alpha 1-6)
10:35:53  FRATRICIDE-SAMESIDE  Bandit_5 -> Bandit_3
10:35:53  FRATRICIDE-SAMESIDE  Bandit_1 -> Bandit_5
10:35:58  FRATRICIDE-SAMESIDE  Para_1   -> Bandit_6
10:36:01  FRATRICIDE-SAMESIDE  Bandit_4 -> Para_3
10:36:25  FRATRICIDE-SAMESIDE  Para_6   -> Bandit_1
10:37:08  FRATRICIDE-SAMESIDE  Para_1   -> Bandit_4
10:37:26  FRATRICIDE-SAMESIDE  Para_6   -> Para_1
```

Nine units at T+0 → four at T+45 → two survivors. `rating=2e+06` throughout,
`renegade=0`. **Not the rating system. Not diplomacy. Not our side resolution.**

## The mechanism

`group createUnit [class, ...]` puts the unit *in* the group but leaves it on
the side of its **`CfgFactionClasses` faction**. So:

```sqf
private _grp = createGroup [east];                     // group side: EAST
private _u = _grp createUnit ["I_C_Soldier_Bandit_4_F"]; // unit side: GUER (!)
```

The unit is in an east group and is itself independent.

**AI hostility is evaluated observer-GROUP-side against target-UNIT-side.**
Each bandit's group is EAST; each *other* bandit is GUER; `east getFriend
independent == 0`. So every Syndikat fighter classified every other Syndikat
fighter as an enemy independent and engaged. The garrison annihilated itself.

## Why this evaded three sessions of diagnosis

- **Every log line we had reported the GROUP side**, which was always correct.
  `populateAO`'s realignment pass checked `side _grp != _targetSide` — a test
  structurally incapable of detecting the fault. It ran every mission, found
  nothing, logged nothing.
- **It is faction-dependent, not code-dependent.** `OPF_G_F` (FIA) and `OPF_F`
  (CSAT) are natively **east**, so there was no mismatch and those objectives
  behaved perfectly. Only independent-native factions — Syndikat, Looters — and
  civilian-native HVT classes triggered it. That is exactly the pattern in the
  reports: *"OpFor partner objective worked fine… the Syndikat one killed each
  other."*
- **The old permissive `east setFriend [independent, 1]` masked it completely.**
  Making diplomacy strict did not create this war either; it made an
  eight-month-old latent bug lethal. Same story as the microzone projection
  finding.
- **`addRating` could never have helped.** These were not renegades. They were
  correctly-rated units on genuinely opposed sides.

## The fix

`[_unit] joinSilent _group;` immediately after every `createUnit`. `joinSilent`
re-parents the unit and forces its side to match the group — it is the only
reliable way; setting the group's side afterwards does not retroactively fix
units already in it.

Applied at all eleven sites: `fnc_spawnGroupYielding`, `fnc_setupGarrison`,
`fnc_setupGuards`, `fnc_setupAnchoredGuard`, `fnc_setupAnchoredPatrol`,
`fnc_setupStaticDefenses`, `fnc_setupMortarEmplacement`, `fnc_setupVehicles`,
`fnc_setupCivilians`, `fnc_placeOnGround`, `fnc_placeInDeepBuilding`.

`fnc_populateAO`'s validation pass now checks **unit** sides against their own
group and WARNs per offender, so a future spawn path that forgets `joinSilent`
fails loudly instead of silently.

## Secondary finding: HVT classes hit the same trap

```
side=CIV  grpSide=EAST  cls=C_scientist_01_formal_F  nativeFac=CIV_F
```

`BOMBMAKER` / `FINANCIER` resolve `CIV_F` classes, so the HVT was sitting on
the **civilian** side inside its own east bodyguard group. Fixed by the same
`joinSilent` in `fnc_placeInDeepBuilding`.

## What this means for Plan A

Plan A would have **prevented this by construction** — if a faction only ever
spawns on its native side, `createUnit`'s behaviour is harmless and the
mismatch cannot exist. That is a strong independent argument for it.

But the priority changes: Plan A is now a *robustness* migration, not a bug
fix. The bug is fixed. Do C2 F.4 first.

## Revised order of work

1. ~~Instrument~~ — done
2. ~~Find root cause~~ — **done: `createUnit` side inheritance**
3. **Re-test**: Syndikat + Looters objectives, and an HVT (`BOMBMAKER`)
4. **Fix garrison grouping** (16 groups for 16 units) — still real, now a
   quality issue rather than a fratricide source
5. **C2 F.4** — unblocked
6. Plan A migration + the `"side"` key rename + `factionClass` provenance, as
   hardening


Kept for the next time something needs measuring rather than guessing. The
probes are still in the tree; see Cleanup at the bottom.

---

# Phase 0 — Instrumentation reference

Kept for the next time something needs measuring rather than guessing. The
probes are still in the tree; see Cleanup at the bottom.

## What was added

| Location | What it dumps |
|---|---|
| `debug/fnc_diagSideDump.sqf` | Orchestrator: diplomacy matrix, role side table, then samples at **T+0 / T+45 / T+75 / T+120** |
| `debug/fnc_diagSideSample.sqf` | Per-unit: `side`, group side, `rating`, class, native faction, native side, groupId, captive, plus side histogram and cross-side hostility matrix |
| `fnc_generateMission` | Calls the dump on all mission AO units, **after** `applySkillProfile` (so it also verifies the `addRating` guard actually stuck) |
| `fnc_c2InitSignalSources` | **Fratricide detector** in the `EntityKilled` handler — names killer and victim with real sides at every death |
| `fnc_initPresenceManager` | Reads the diplomacy matrix back **after** its `setFriend` writes |
| `fnc_activatePresenceZone` | Real sides of every armed group a presence zone produced, vs. the control it thought it was populating for |

All output uses raw `diag_log` with a **`DSCDIAG`** prefix — deliberately not
the CBA macros, so it appears regardless of debug tier and greps cleanly out of
a noisy RPT.

## How to run it

```
hemtt launch
```

Let one KILL_CAPTURE mission generate, fly to the objective, engage, and let
the fighting run for ~2 minutes. Then:

```
findstr /C:"DSCDIAG" "%LOCALAPPDATA%\Arma 3\arma3_x64_<newest>.rpt"
```

## How to read it — decision table

The whole point is that these outcomes are **mutually exclusive**, so exactly
one theory survives:

| Output | Conclusion |
|---|---|
| `SINGLE-SIDE (EAST)` + `KILL ... FRATRICIDE-SAMESIDE` | Not a side bug. Cause is renegade state or scripted engagement. |
| Any unit shows `*** RENEGADE ***` or `side=ENEMY` | Rating/renegade confirmed. `addRating` is being applied too late, reset, or bypassed on some spawn path. |
| `rating` starts high at T+0 then falls negative | Renegade cascade confirmed in progress. |
| `rating` stays high **and** fratricide continues | Renegade **ruled out**. Look at scripted targeting / `doTarget` / group merging. |
| `SIDE!=EXPECTED` on any unit | A spawn path is overriding the requested side. Names the exact class and group. |
| `NATIVE=GUER` on east units | Confirms the cosmetic/functional split — expected today, eliminated by Plan A. |
| `DIPLOMACY ... ASYMMETRIC` | A `setFriend` pair disagrees with itself. |
| `FRATRICIDE-ALLIED` | Two supposedly-allied sides killing each other → asymmetric diplomacy. |
| `killer=NULL` on most deaths | Collateral / explosives / falling damage, **not** AI targeting. Would invalidate the entire fratricide framing. |

## Known landmines to fix during migration

Found while reading the code; both are real bugs independent of the side model.

1. **`"side"` key type collision.** `fnc_extractGroups` writes
   `["side", <NUMBER 0-3>]` on **group** hashmaps; `fnc_initFactionData` writes
   `["side", <SIDE>]` on **role** hashmaps. Same key, same codebase, silently
   different types, and group hashmaps are passed around constantly. Rename to
   `configSideNumber` and `spawnSide`.

2. **`fnc_extractGroups` destroys faction provenance.** The CfgGroups desync
   workaround reassigns `_factionClass` (`BLU_G_F` → `"Guerilla"`) *before*
   writing `_groupData set ["factionClass", _factionClass]`. Group data
   therefore carries the CfgGroups **node name**, not the real faction class, so
   any downstream "which role owns this group's faction?" lookup fails to match
   the profile list and silently falls through to a default.

## The garrison defect — the top remaining fix

`fnc_setupGarrison` calls `createGroup` **inside** its per-position loop, so
every garrison unit is a one-man group, and those units are then packed onto
`buildingPos` slots in the same small building. Confirmed live: a populatedArea
zone produced **16 armed groups for 16 units**.

Arma deconflicts line of fire **within a group only**. Separate groups shoot
through each other by design, producing friendly fire → rating loss → (absent
the `addRating` guard) renegade → free-for-all.

Fix: one group per building, with `disableAI "PATH"` + `setUnitPos` on every
unit so they hold their firing positions instead of forming up on a leader
(which is why the naive merge was not done originally).

## Cleanup

All instrumentation is tagged `TEMPORARY DIAGNOSTIC (August 2026)`. Remove at
step 4:

- `addons/core/functions/debug/fnc_diagSideDump.sqf`
- `addons/core/functions/debug/fnc_diagSideSample.sqf`
- Both `PREP_SUB(debug,...)` lines in `XEH_PREP.hpp`
- Call site in `fnc_generateMission`
- Fratricide block in `fnc_c2InitSignalSources`
- Read-back block in `fnc_initPresenceManager`
- Zone dump in `fnc_activatePresenceZone`

`findstr /S /C:"DSCDIAG" addons\*.sqf` finds all of it.
