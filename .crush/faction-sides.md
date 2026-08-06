# Faction Side Allocation — DSC

*Status: **RESOLVED.** July 2026. The mid-migration regression described in
earlier revisions of this document is fixed.*

## TL;DR

Arma diplomacy is **side-level**. There is no per-faction or per-group
relation — `setFriend` operates on sides. DSC has five combatant roles and
three usable combatant sides, so roles must share sides.

The rule, enforced by `fnc_resolveRoleSide`:

```
west        = bluFor + the player
independent = bluForPartner                        (allies)
east        = opFor + opForPartner + irregulars    (all hostile)
civilian    = civilians + environmentalActors
```

Sides are normalized **once**, in `fnc_initServer`, at the only point where a
faction profile enters runtime state. Nothing downstream needs to convert
anything.

## The underlying problem

The faction profile literals in `fnc_initServer` declare a "natural" side per
role. Those declarations were wrong in two independent ways.

**1. They double-booked `independent`.** Vanilla and RHS profiles put both
`bluForPartner` (the player's allies) *and* `irregulars` (the player's
enemies) on independent. "AAF is friendly to the player but Looters on the
same side are hostile" is not expressible in Arma. This is a genuine
structural conflict, not a tuning issue.

**2. They disagreed with each other.** The Aegis profile puts
`bluForPartner` on **west** while vanilla/RHS put it on **independent**.
Loading a different mod set silently changed the side model.

The old code papered over (1) with a blanket `east setFriend [independent, 1]`
so opFor and irregulars would cooperate. That also made the player's own
AAF/Gendarmerie friendly to CSAT, and nothing ever set `west <-> independent`
explicitly, so the player's actual relationship fell through to the
`mission.sqm` default. Observed symptom: **enemies engaged the player while
the player's own squad refused to return fire.**

## The fix

### 1. `fnc_resolveRoleSide` (faction/) — the rule

Maps a role key to the engine side it must actually spawn on. INDEPENDENT is
reserved for the player's side of the war; any hostile role whose declared
side is independent is forced to **east**.

Cooperation between opFor and irregulars then needs no diplomacy at all —
they are literally the same side.

### 2. Normalization at the boundary — `fnc_initServer`

Immediately after profile auto-detect, before the profile is published:

```sqf
{
    private _roleKey  = _x;
    private _roleData = _y;
    private _natural  = _roleData getOrDefault ["side", east];
    private _resolved = [_roleKey, _natural] call DSC_core_fnc_resolveRoleSide;
    if (_resolved isNotEqualTo _natural) then {
        INFO_3("Role side normalized: %1 %2 -> %3",_roleKey,_natural,_resolved);
    };
    _roleData set ["side", _resolved];
} forEach _selectedProfile;
```

**Why here and not at the ~10 spawn sites.** Every site that reads a role
side reads it from one of exactly two hashmaps:

- `missionNamespace getVariable "factionProfileConfig"` — the selected profile
- `missionNamespace getVariable "DSC_factionData"` — built by
  `fnc_initFactionData`, which copies `side` off the profile **verbatim**
  (`fnc_initFactionData.sqf` ~line 63)

Both derive from `_selectedProfile`. Normalizing it makes every downstream
read correct with zero further edits, and turns the model into an enforceable
invariant — *"no unresolved side exists in runtime state"* — rather than a
convention that ten call sites have to individually remember. The earlier
per-site migration attempt converted 3 of 10 and left the other 7 spawning
`irregulars` on independent against a now-strict diplomacy matrix, which made
opFor-aligned factions shoot each other on spawn. Half a migration was worse
than either end state.

Sites that are now correct without modification:

| File | What it reads |
|---|---|
| `presence/fnc_presenceHandlerPopulatedArea.sqf` | Military overlay + irregular garrison |
| `presence/fnc_presenceHandlerIsolatedCompound.sqf` | Microzone projection guard/patrol |
| `presence/fnc_presenceHandlerIndustrialSite.sqf` | Microzone projection guard/patrol |
| `presence/fnc_presenceHandlerInfrastructureNode.sqf` | Microzone projection guard/patrol |
| `presence/fnc_initPresenceManager.sqf` | Microzone controller precompute |
| `presence/fnc_resolveRovingHotspots.sqf` | Hotspot `_factionToSide` → rover sides |
| `init/fnc_initBases.sqf` | Eager base population at init |
| `c2/fnc_initC2Network.sqf` | Node `side` → `fnc_c2ResolveNode` matching |
| `missions/fnc_resolveMissionConfig.sqf` | Target + area side (also calls the resolver — harmless, idempotent) |
| `presence/fnc_presenceActivateMilitary.sqf` | Zone side (also calls the resolver — harmless, idempotent) |

`fnc_setupContestedSkirmish` and `fnc_resolveIrregularOverlay` hardcode their
sides deliberately (west and east respectively) and are unaffected.

### 3. Diplomacy — one place, symmetric, never mutated

`fnc_initPresenceManager` only:

```sqf
west        setFriend [independent, 1];
independent setFriend [west, 1];
east        setFriend [independent, 0];
independent setFriend [east, 0];
west        setFriend [east, 0];
east        setFriend [west, 0];
```

`setFriend` is **directional** — both halves of every pair are required or
the AI's targeting and its threat evaluation disagree. The per-mission
`setFriend` calls that used to live in `fnc_populateAO` and
`fnc_cleanupMission` are removed. Do not re-add them: global state mutated
per mission is what made the original bug intermittent and hard to see.

## The second bug: friendly territory was fighting a private war

*Found August 2026, after side normalization shipped.*

Normalizing sides fixed the *mechanism* but exposed a *content* problem that
the old permissive diplomacy had been hiding for months.

### Symptom

"A mission with irregular forces and an OpFor officer, and they started to
kill each other. Some of the irregular forces were shooting at each other."

### What the RPT actually showed

```
initInfluence complete - OpFor: 577  BluFor: 268  Contested: 1  Neutral: 281
...
populateAO - factory (target: IND_C_F  area: OPF_R_F)        <- both east, correct
setupAnchoredPatrol - spawned 2 units patrolling (side=GUER) <- INDEPENDENT
activatePresenceZone [loc_754] - isolatedCompound (ctrl=bluFor inf=0.98)
```

The mission AO was internally consistent — Syndikat target and CSAT ambient,
both on east, zero realignments logged. The fighting came from **outside** it:
a `bluForPartner` guard detachment projected onto a bluFor-controlled compound,
spawned on `GUER`/independent, which strict diplomacy makes hostile to east.

`fnc_resolveMicrozoneProjection` is side-blind: it projects guards and patrols
from whatever installation is nearest, including **bluFor** ones. A bluFor
compound projects a `bluForPartner` detachment, which spawns on
**independent** — and strict diplomacy makes independent hostile to east.

With **268 bluFor-controlled locations** against 577 opFor, the presence
manager was standing up two mutually hostile ambient armies across the entire
terrain. They found each other and fought, continuously, with no player
involvement. AAF guards projected from a nearby friendly compound were
engaging the Syndikat garrison on the objective.

To the player, AAF, Gendarmerie, Syndikat and Looters all read as "local
irregulars" — so it looked like irregulars shooting each other. They were
actually allies and enemies that happen to wear similar kit.

**The old `east setFriend [independent, 1]` did not prevent this war. It just
made both armies refuse to shoot.** Strict diplomacy did not create the
problem; it revealed it.

### Fix 1 — friendly territory is quiet

Ambient military presence is now projected only from **opFor and contested**
installations. bluFor-controlled microzones and towns get civilians only.

- `fnc_resolveMicrozoneProjection` — zeroes `guardChance`/`patrolChance` for
  non-opFor control, which covers all four microzone handlers at once
- `fnc_presenceHandlerPopulatedArea` — gates its own military garrison block

Override with `DSC_ambientFriendlyForces = true` to restore the old behaviour.

Real bluFor **bases and outposts** still garrison normally via
`fnc_presenceActivateMilitary` — there were 4 of those, not 268, and an
installation with no defenders is worse than the war.

This is also just the right model for the mod: the player is SOF operating
**from** friendly territory **into** hostile territory. Friendly ground should
feel safe, and every guard not spawned there is budget spent where it counts.

#### ⚠ Suppress the CHANCES, never the STRENGTH

The first attempt at this fix zeroed `strength`, and made things **worse**.

`strength` is overloaded. Handlers read it two ways:

```sqf
// fnc_presenceHandlerIsolatedCompound
private _useIrregularFallback = (_proj get "strength") <= 0;
// fnc_presenceHandlerIndustrialSite / InfrastructureNode
private _hasController = (_proj get "strength") > 0;
```

`strength <= 0` does not mean "spawn nothing" — it means **"this compound is
out in unclaimed wilderness, roll a 65% chance of a 4-5 man EAST insurgent
fireteam"**. So zeroing strength made every bluFor microzone look like empty
terrain, and the rear area went from *"bluForPartner detachments on
independent, hostile to east"* to *"EAST insurgent patrols"* — more hostile
than before, and at 65% instead of ~10%.

The RPT showed it plainly:

```
activatePresenceZone [loc_754] - isolatedCompound: 6u (ctrl=bluFor inf=0.96 str=0.00 gC=0.00 pC=0.00)
setupAnchoredPatrol - spawned 4 units patrolling r=300 (side=EAST skill=garrison_light)
```

Projection strength zero, both chances zero, **and four east units anyway.**
Four such zones activated within 1.2 km of the player's west base (42 units
plus tower snipers), producing ~17 east insurgents in the rear area and an
immediate firefight.

The correct fix leaves `strength` reporting the true projection — so
"a controller IS in range" stays true and the wilderness fallback stays
disabled — and zeroes only `guardChance` / `patrolChance`. A `suppressed`
flag is exposed on the result for observability.

Wilderness encounters are preserved: a genuinely uncontrolled zone still has
`strength == 0` naturally and still rolls its insurgent fireteam.

#### Why it read as "objective AI killing each other"

The rear-area firefight was ~7 km from the objective, but the C2 feed made it
look local. `fnc_c2ResolveNode` is reach-aware, and the mission node
(`loc_94` / **WHISKEY**) had enough reach to claim both the objective *and*
the microzones near the player base:

```
8:41:40  c2 stamp: _cs=WHISKEY, _role=mission, _uc=1   <- objective groups
8:41:48  c2 stamp: _cs=WHISKEY, _role=guard,   _uc=4   <- rear-area insurgents
```

All eight groups drew `Alpha 1-N` / `Alpha 2-N` callsigns from WHISKEY's single
roster, so contact reports from the rear-area fight were indistinguishable in
the log from objective traffic. This is arguably correct node behaviour, but it
is worth knowing during C2 debugging: **a node's callsign roster can span
several kilometres, and group callsigns alone do not tell you where a
firefight is.** Cross-reference the grid in the report line.

### Fix 2 — role casting in the vanilla profile

Three factions were cast by their config side rather than their behaviour:

| Faction | Was | Now | Why |
|---|---|---|---|
| `IND_C_F` Syndikat | `opForPartner` | `irregulars` | Criminal insurgents, not a military auxiliary. As a partner they were eligible to hold military outposts — the RPT showed *two* opFor outposts garrisoned by Syndikat. |
| `IND_L_F` Looters | `irregulars` | `irregulars` (unchanged) | Correct already. |
| `BLU_GEN_F` Gendarmerie | `bluForPartner` | `environmentalActors` | A **west**-config law-enforcement faction cast as an independent field ally. Mixed west-config units into independent groups and put riot police in the line of battle. |
| `rhssaf_faction_un` UN | `bluForPartner` (RHS) | `environmentalActors` | Peacekeepers are observers. Anything in a partner role spawns as a live combatant across all friendly territory. |

**The casting rule, now stated in the profile literals:** cast by *behaviour*,
not by config side. `bluForPartner` specifically means "armed ally that fights
alongside the player" — anything listed there becomes a combatant at every
friendly-held location on the map, so it must stay small and deliberate.

## The third bug: it was never a side bug at all

*Found August 2026. This one is important because it is **indistinguishable
from a side bug** and cost two rounds of misdiagnosis.*

### Symptom

Objective defenders killing each other while all being the same faction —
after side normalization, after the projection fix, with the RPT showing
`target: IND_L_F` / `area: OPF_F` (both east) and **zero side realignments**.

### Cause: the rating / renegade system

Arma tracks a per-unit `rating`. Killing a friendly applies a large negative
penalty, and once a unit's rating drops below roughly **-2000** the engine
flips it to **renegade** — hostile to every side *including its own*.

DSC walks into this constantly because of how defenders are structured:

```
populateAO - Garrison (target): 2 units in 2 groups
populateAO - Garrison (target): 3 units in 3 groups
```

`fnc_setupGarrison` calls `createGroup` **inside** its per-position loop, so
every garrison unit is its own one-man group, and those units are then packed
onto `buildingPos` slots inside the same small building.

**Arma only deconflicts line of fire within a group.** Separate groups shoot
through and past each other freely. So the moment the player engages:

```
friendly-fire hit -> rating drops -> unit flips renegade
  -> it now deliberately engages its own faction
  -> more friendly kills -> more renegades -> ...
```

The compound tears itself apart with no player involvement, and every death
fires real `EntityKilled` C2 signals — which is precisely what made the
network untestable.

### Why it was misdiagnosed twice

From outside the engine this is *identical* to a side-allocation bug:
same-faction units fighting, no diplomacy explanation. Both previous fixes
(side normalization, projection suppression) were real bugs with real
evidence, and fixing them removed real cross-side fighting — but neither one
was this. The tell that separates them:

| Observation | Side bug | Rating bug |
|---|---|---|
| RPT shows differing sides / `side=GUER` on an east AO | ✅ | ❌ |
| `Realigned N groups` in populateAO | ✅ | ❌ |
| All groups east, zero realignments, still fighting | ❌ | ✅ |
| Fighting starts only *after* the player engages | ❌ | ✅ |
| Escalates over time rather than firing on spawn | ❌ | ✅ |

### Fix

`addRating 1000000` on every spawned combat unit, which puts the renegade
threshold out of reach. It changes no targeting, accuracy or behaviour — it
only prevents the flip.

Applied in two places:

- **`fnc_applySkillProfile`** — the single path *every* combat unit passes
  through (garrison, guards, statics, anchored guard/patrol, mortar, QRF, and
  all mission AO units via `fnc_generateMission`)
- **`fnc_setupPatrols`** — the presence-manager callers
  (`presenceActivateMilitary`, `contestedSkirmish`, `resolveIrregularOverlay`)
  never apply a skill profile, so patrols would otherwise be unprotected

### Deferred root cause

One-group-per-unit garrisons are the actual defect. Merging them into a
per-building group would give the AI real fire deconfliction, but it requires
`disableAI "PATH"` + `setUnitPos` on every unit first — garrison units
currently have neither, so grouping them makes them form up on their leader
and abandon their firing positions. That belongs in the mission/AI overhaul.

## Accepted consequence

**opFor and irregulars can never fight each other.** They share a side. This
is a deliberate trade — the alternative (independent for irregulars) costs
the player's own partner forces, which is far more visible.

If hostile-bloc-vs-hostile-bloc warfare is ever wanted, the only remaining
slot is `sideEnemy` (renegade — hostile to everyone including each other),
which has degraded AI grouping behaviour. Not recommended.

## Validation

1. Start a mission where the AO faction and target faction differ
   (`opFor` + `opForPartner`, or anything involving `irregulars`).
   **Nothing hostile-to-the-player should fight anything else
   hostile-to-the-player.**
2. Walk into a `bluFor`-controlled town that also rolls an irregular overlay.
   Those two *should* fight — allies vs. enemies. That is correct behaviour
   under this model.
3. Player squad must return fire at anything that shoots at them. This is the
   original bug and the regression test that matters most.
4. `fnc_initBases` runs at init and populates bluFor + opFor bases. Confirm
   base garrisons don't turn on each other on load.
5. Check the RPT at startup for `Role side normalized:` lines. Under vanilla
   you should see exactly one (`irregulars independent -> east`); under Aegis
   you should additionally see `bluForPartner west -> independent`.

## Known follow-up

The `["side", ...]` entries in the profile literals are now **inputs to the
normalizer, not authoritative**. They are misleading and should be deleted
outright — a role's bloc is a property of the role (a code constant), not of
the faction list (configuration). As long as `["side", independent]` is
typeable in a profile literal, someone will type it.

Tracked in `.crush/faction-autoscan.md` as Phase 0.
