# Session 5 — Interaction-Site Primitive + `INTERACTION_SITE` + Universal Search→Token

**Phase:** 1 (vertical slice) · **Model:** **Opus spec → approve → fresh Sonnet
build** · **Ships:** the first real intel *producer* — SSE/search becomes an
action→token, feeding the ledger.

> ⚠ This is a **scope brief**, not a finished spec. Session 1 starts with Opus
> producing the mini-spec (signatures + test plan + gotchas). You approve it, then
> a fresh Sonnet session builds it. Do not let it write code against an unapproved
> approach.

---

## Why now

`campaign-overhaul.md` **§13** (interaction sites over scattered objects —
owner-approved), **§13.4** ("body/site search on any encounter *is the same
interaction-site pattern*" — build it once, get mission-site SSE *and*
world-encounter SSE from one code path), **§13.5** ("fold into the §8 foundation
alongside SWEEP and the Intel Ledger"), **§4.3 #2** (body/site search as an
intel source). Prereqs: Sessions 1–4 (especially the ledger). SWEEP (Session 6)
consumes this, so it comes first.

---

## The design to implement (from §13.2 / §13.3)

An **interaction site** = a trigger/area sized to a structure or site **plus a
player action**, leaning on Arma's robust primitives (triggers, `addAction`,
distance checks) instead of the fragile ones (`buildingPos`, object collision,
polled object state). Shape (§13.2):

```
interactionSite = createHashMapFromArray [
  ["pos", _sitePosition], ["radius", _r],
  ["action", "Conduct SSE"], ["duration", [20, 60]],
  ["onComplete", { /* grant intel token / mark destroyed */ }],
  ["dressing", ""], ["requireCount", [1, 1]]
]
```

Key rules the spec must honor:
- **Action on the player, gated by distance** (`player distance _site < radius`),
  not on a placed object (§13.3). No spawned entity required.
- **Timed** hold/"searching…" window (20–60s) — tension + lets QRF/C2 matter
  (§13.3). Not instant pickup.
- **No completion gate / no AREA_CLEAR precondition** — availability is distance
  only; clearing enemies first is the smart play, never a scripted lock
  (§13.2). We never let AI state soft-lock progress.
- **Completion is "action fired"** (event-driven, clean), routed through the
  existing `completionExpr` + `buildMissionOutcome` (§13.2).
- **N-of-M sites** via `requireCount` for movement missions (§13.3) — one trigger
  per site, no prop scatter.
- **Three optional tangibility tiers** (§13.3): abstract (default) → focal prop
  (single hero object) → composition (Eden/Zeus `dressing`). Build tier 1; leave
  clean opt-in hooks for 2 and 3 (the demoted `fnc_placeInterior`/`placeOnGround`
  become the focal-prop tier).
- **Markers tie to intel** (§13.3): with `AREA_LAYOUT` intel → precise "search
  here" marker; without → broad "SSE somewhere in this area" circle. (Wire the
  hook; the SWEEP/DA sessions exercise it.)

---

## Likely deliverables (Opus to finalize in the mini-spec)

- **`DSC_core_fnc_createInteractionSite`** — builds + arms a site (distance-gated
  player action, timed hold, `onComplete` callback). Reuses the pattern in
  `fnc_addInteractionHandler.sqf` but **player-side + distance-gated**, not
  object-`addAction`.
- **`INTERACTION_SITE` objective/completion archetype** — added to
  `fnc_getCompletionTypes` (a `SITES_INTERACTED`/`N_OF_M` condition) and routed
  from the raid generator's archetype dispatch, so `SUPPLY_DESTROY` /
  `INTEL_GATHER` / SSE tack-ons flow through it (§13.5). Small addition, not a
  rework — the generator already dispatches by archetype.
- **`onComplete` → `fnc_intelAdd`** — the standard SSE completion grants a token
  (type/subject/confidence per the mission context). This is the seam that makes
  "search" feed the ledger.
- **Universal "Search" on any encounter** (§4.3 #2 / §13.4) — a `createInteractionSite`
  spawned on dead groups / points of interest from presence + roving, yield
  scaling with the searched group's relevance (random patrol → low-confidence AREA
  token; mission/thread-faction group → targeted SERIES token). **Must not spawn
  extra entities** (§10) — it attaches to groups the world already spawned.
- Register everything in `XEH_PREP.hpp`. Demote (don't delete) the object-placement
  strategies to the focal-prop/legacy tier (§13.5).

---

## Definition of done

- [ ] Mini-spec produced (Opus) and approved **before** any code.
- [ ] `createInteractionSite` + `INTERACTION_SITE` completion/archetype + the
      universal Search hook written, headered, `PREP_SUB`'d.
- [ ] SSE `onComplete` grants a schema-valid token via `fnc_intelAdd`.
- [ ] `hemtt check` clean.
- [ ] Tier-1 suite `interaction_site` covering the pure parts: site config
      defaults, N-of-M completion logic (`requireCount`), the token the
      `onComplete` composes given a mock context (test the token-builder as a pure
      helper, not the `addAction`).
- [ ] `DSC_testConfig` block committed (harness site with one SSE interaction).
- [ ] `AGENTS.md` + `roadmap.md` updated; object-scatter demotion noted.

---

## Tier-2 playtest (human — this is where it gets real)

1. Harness a single INTERACTION_SITE mission near you. Confirm: the "Conduct SSE"
   action appears **only** within `radius`, runs a visible timed window, and on
   completion (a) fires the completion event and (b) drops a token into
   `DSC_intelLedger`.
2. Boot presence/roving in the harness, kill an ambient group, confirm the
   universal "Search" action appears on the bodies and yields a lower-confidence
   token — and that **no extra entities were spawned** to support it.
3. Behavioral notes (does the action radius feel right? is the timer tense or
   tedious?) → `docs/playtest_notes/<date>/`. These *feel* dials are yours, not
   the agent's.

## Gotchas to hand the agent

- `setCaptive`/dead-unit `side` quirks if the Search attaches to bodies (a dead
  unit reports `side = CIVILIAN` — use `side (group _x)`; see AGENTS.md).
- Yield convention if the Search ever iterates many bodies at once.
- Do **not** gate the site behind AREA_CLEAR or object-destroyed polling (§13.2).
- Universal Search attaches to **already-spawned** groups — no new spawns (§10).

---

## Paste-ready prompt (Opus, for the spec)

```
Read docs/campaign_overhaul/WORKFLOW_RULES.md,
docs/campaign_overhaul/session_05_interaction_site.md, and
.crush/campaign-overhaul.md §13 (all of it) + §4.3. Produce a mini-spec for the
interaction-site primitive: function signatures (createInteractionSite, the
INTERACTION_SITE completion/archetype, the universal Search hook, the
onComplete→intelAdd token builder), the Tier-1 test plan, the harness
DSC_testConfig, and the list of gotchas to respect. Reuse the distance-gated
action pattern (not object-addAction) and route completion through the existing
completionExpr/buildMissionOutcome. Do NOT write implementation code yet —
produce the spec for approval. Opus scope.
```

Then, after approval, in a fresh Sonnet session:

```
Implement the approved interaction-site mini-spec from
docs/campaign_overhaul/session_05_interaction_site.md. Register in XEH_PREP.hpp,
add the interaction_site Tier-1 suite, commit the harness DSC_testConfig, keep
hemtt check clean, meet every Definition-of-Done checkbox, and fold any new
engine gotcha into AGENTS.md. Sonnet scope — build the approved spec, don't
redesign it.
```

## Mini-Spec (Opus draft — awaiting approval)

*Read: `.crush/campaign-overhaul.md` §13 (all), §4.3; `fnc_addInteractionHandler`,
`fnc_getCompletionTypes`, `fnc_evaluateCompletion`, `fnc_buildMissionOutcome`,
`fnc_intelAdd`, `fnc_generateRaidMission`, `fnc_initPlayerLocal`,
`fnc_c2InitSignalSources`, `fnc_rovingDespawnSweep`, `fnc_initTestScenario`,
`fnc_runTests`. No code written below — signatures + shapes only.*

### 0. Module layout

New folder `addons/core/functions/interaction/` (+ `script_component.hpp`
mirroring `ai/script_component.hpp`), holding everything in §1–§3 and §6 below.
Two exceptions stay in their existing home folders because they extend
existing registries, not the new primitive:
- `fnc_getInteractionSiteArchetypes` → `data/` (alongside `getObjectArchetypes`,
  `getCompletionTypes`).
- `fnc_buildIntelTokenFromSite` → `intel/` (alongside `intelAdd`; it only knows
  the token schema, nothing about sites).

Add a new `// Interaction Sites` block to `AGENTS.md`'s folder table once built.

### 1. Canonical site shape

```
interactionSite = createHashMapFromArray [
    ["id",              "<uid>"],
    ["pos",             [x,y,z]],
    ["radius",          10],
    ["action",          "Conduct SSE"],
    ["duration",        [20, 60]],          // [min,max] seconds, rolled once at creation
    ["onComplete",      {}],                // code, called SERVER-SIDE only, params [_site, _firingUnit]
    ["dressing",        ""],                // optional composition/focal-prop key
    ["tangibility",     "abstract"],        // "abstract" | "focalProp" | "composition"
    ["requireCount",    [1, 1]],            // [min,max] INSTANCES generated from one archetype spec
    ["state",           "ARMED"],           // "ARMED" | "COMPLETE" | "REMOVED"
    ["completedBy",     objNull],
    ["markerLocationId","" ]                // optional — feeds the intel-gated marker hook (§7)
]
```

**⚠ Naming collision to resolve on approval:** §13.2's sample hashmap uses
`requireCount` for two different concepts across the source docs — "how many
instances of this site to generate" (this table, consistent with the existing
object-archetype `count: [min,max]` convention) vs. "how many of the generated
sites must be completed" (§13.3's "search 2 of 3 buildings"). This spec keeps
`requireCount` as the **instance-count** meaning and introduces a separate
completion-side field, `sitesRequired` (see §4), for the N-of-M threshold.
**Flag if this reading is wrong** — cheap to rename now, not after Sonnet builds
against it.

### 2. Core primitive — server-authoritative, builder split from side effects

**`DSC_core_fnc_buildInteractionSiteConfig`** (PURE)
- Args: `0: _rawConfig <HASHMAP>` — any subset of the shape in §1.
- Fills every default (generates `id`, clamps `duration` to a `[min,max]`
  pair, defaults `tangibility` to `"abstract"`, `requireCount` to `[1,1]`,
  `state` to `"ARMED"`).
- Returns: `<HASHMAP>` — the canonical site (no globals touched, no rolled
  random values yet — see next function for why).
- Tier-1 target: defaults + clamping, pure input→output.

**`DSC_core_fnc_createInteractionSite`** (SIDE-EFFECTING, server-only)
- Args: `0: _rawConfig <HASHMAP>` (same as above).
- Calls the pure builder, rolls the actual hold duration from the
  `[min,max]` pair, registers the result into the global registry
  `DSC_interactionSites` (hashmap `id -> site`), using the existing
  `missionNamespace setVariable ["DSC_interactionSites", _sites, true]`
  JIP-safe broadcast idiom already used for `DSC_currentMission` /
  `missionState` — **no new sync mechanism**, reuse the established pattern.
- Also fires `["DSC_interactionSite_changed", [_id, "ARMED"]] call
  CBA_fnc_globalEvent` so already-connected clients arm the action
  immediately instead of waiting on a rescan.
- Returns: `<STRING>` — the site id.

**`DSC_core_fnc_removeInteractionSite`**
- Args: `0: _id <STRING>`.
- Deletes the entry from `DSC_interactionSites`, re-broadcasts the global,
  fires `DSC_interactionSite_changed [_id, "REMOVED"]`.
- Callers: `fnc_cleanupMission` (mission-scoped sites), the universal search
  hook's own housekeeping (§6), and `fnc_despawnPresenceZone` /
  `fnc_rovingDespawnSweep` if a zone/rover tears down with a live site still
  attached (see gotcha list).
- Return: `<BOOL>` — false if id was not found (idempotent, does not error).

**`DSC_core_fnc_interactionSiteFire`** (SERVER-ONLY completion entrypoint —
this is the actual "action fired" completion referenced by §13.2, not the
client-side timer UI)
- Args: `0: _id <STRING>`, `1: _unit <OBJECT>` (the player who completed the
  hold).
- Re-validates server-side (site still `ARMED`, `_unit` still within
  `radius` — race guard against a client that fired late): if invalid,
  no-ops.
- Marks the site `COMPLETE`, increments the owning mission's
  `completionState.sitesCompleted` (read-mutate-write-back on
  `DSC_currentMission`, same pattern as `fnc_addInteractionHandler`) if the
  site carries a `missionId`/is mission-scoped; standalone sites (universal
  search) skip this step.
- Calls `_site get "onComplete"` with `[_site, _unit]`.
- Calls `fnc_removeInteractionSite`.
- Return: `<BOOL>` — whether it actually completed (false = rejected by
  re-validation).

### 3. Client-local arming — the distance-gated action, not object-addAction

**`DSC_core_fnc_initInteractionSites`** (client-local, called once from
`fnc_initPlayerLocal`, same place the other player-local wiring lives —
JIP-safe by construction since every client, including late joiners, runs
`fnc_initPlayerLocal`)
- Walks the current `DSC_interactionSites` and arms one `player addAction`
  per `ARMED` entry; registers a `DSC_interactionSite_changed` CBA handler
  for incremental arm/disarm without a full rescan.
- **Action added to `player`, not to any placed object** — condition string
  is built with `format` so `pos`/`radius`/`id` are baked in literally
  (mirrors the existing `"_target distance _this < 5"` idiom, just without a
  `_target` object):
  `format ["player distance %1 < %2 && (...site still ARMED...)", str (_site get "pos"), _site get "radius"]`
- On activation: starts the timed hold (§13.3 — 20–60s "searching…" window).
  Hold implementation (progress bar vs. repeated hint countdown) is a build
  detail, not an architecture decision, but the **contract** is fixed:
  cancel the hold if the player moves outside `radius`, if the player dies,
  or if the site's `state` changes away from `ARMED` mid-hold (another
  player finished it first, or the site was removed by cleanup). On natural
  completion, fires `["DSC_interactionSite_fire", [_id]] call
  CBA_fnc_serverEvent` (or equivalent server-targeted CBA event) — the
  server is what actually calls `fnc_interactionSiteFire`.

### 4. `SITES_INTERACTED` completion type

New entry in `fnc_getCompletionTypes`:

```
["SITES_INTERACTED", createHashMapFromArray [
    ["check", {
        params ["_state"];
        (_state getOrDefault ["sitesCompleted", 0]) >= (_state getOrDefault ["sitesRequired", 1])
    }],
    ["successMsg", "Site(s) exploited"],
    ["partialMsg", "Site(s) not exploited"],
    ["stateKeys", ["sitesCompleted", "sitesRequired"]]
]]
```

No new completion dispatch machinery — this drops straight into the existing
`fnc_evaluateCompletion` named-type path, evaluated at Debrief exactly like
`ANY_INTERACTED` today (confirmed: this codebase's "monitor" is the player's
Debrief action at the flagpole calling `fnc_evaluateCompletion` once, not a
polling loop — `fnc_initServer.sqf` ~line 611). `fnc_interactionSiteFire`
(§2) is what maintains `sitesCompleted`; nothing needs to poll site state.

### 5. Raid generator integration (small addition, per §13.5)

`fnc_generateRaidMission` gains one more spec array on its config, parallel
to the existing `"entities"` / `"objects"` arrays: `"interactionSites"
<ARRAY>` of specs like `{"archetype": "SSE_INTEL", ...overrides}`.

**`DSC_core_fnc_getInteractionSiteArchetypes`** (new, `data/`, same shape
family as `fnc_getObjectArchetypes`) — registry entries: `SSE_INTEL`,
`SUPPLY_DESTROY_SITE`, `CACHE_VERIFY`, `SABOTAGE_SITE`. Each carries default
`action` text, `duration`, `tangibility`, and a token-context template
(`type`/`source`/`confidence`/`scope` defaults) consumed by §6.

For each spec, the generator resolves the archetype, resolves a position via
the location's existing structure/anchor data (reuse whatever the current
object-placement code already uses to pick a building center — **no new
`buildingPos` dependency**, this is exactly what §13.1 argues against), and
calls `createInteractionSite`. Accumulates ids into `mission.interactionSites`
and seeds `completionState.sitesCompleted = 0` /
`completionState.sitesRequired` = the archetype spec's completion threshold
(defaults to total instances generated — i.e. "all of them" unless the
mission config asks for fewer, the N-of-M case).

This is additive to the existing entity/object loops — do not touch them.

### 6. `onComplete` → intel — the shared token builder

**`DSC_core_fnc_buildIntelTokenFromSite`** (PURE, `intel/`)
- Args: `0: _tokenContext <HASHMAP>` — partial token
  (`type`/`subjectKind`/`subjectRef`/`confidence`/`source`/`scope`/`payload`,
  same fields `fnc_intelAdd` accepts), `1: _site <HASHMAP>` (for
  payload defaults — grid/pos, site id).
- Returns: `<HASHMAP>` — a schema-valid partial token, NOT yet written to the
  ledger (caller still calls `fnc_intelAdd`). Kept pure and separate from
  `intelAdd` for the same reason `buildMissionOutcome` is kept separate from
  the retrofit bridge (§8 item 1 precedent).
- Both call sites below build their `onComplete` as a code block that closes
  over a `_tokenContext` built at site-creation time, calls this builder,
  then `[_token] call DSC_core_fnc_intelAdd` — server-side only, per §2.

Call site A — mission SSE (`SSE_INTEL` archetype default `onComplete`):
`source: "SSE"`, `scope: "LOCATION"` or `"SERIES"` if the mission carries a
`seriesId`, confidence from the archetype default (tunable later).

Call site B — universal search (§7): `source: "BODY_SEARCH"`,
scope/confidence from `fnc_resolveSearchYield`.

### 7. Universal "Search" hook (§4.3 #2 / §13.4)

**`DSC_core_fnc_resolveSearchYield`** (PURE)
- Args: `0: _victimFactionRole <STRING>` (the dead group's resolved faction
  role, e.g. `"opFor"`/`"irregulars"`), `1: _activeSeriesFactionRole
  <STRING>` (`""` if no active series/thread).
- Returns: `<HASHMAP>` — `["scope", "AREA"|"SERIES"]` +
  `["confidence", <NUMBER>]`. `SERIES` + higher confidence only when
  `_victimFactionRole` matches `_activeSeriesFactionRole` and both are
  non-empty; otherwise low-confidence `AREA`.
- Tier-1 target: the whole match/no-match/empty-input matrix, no globals.

**`DSC_core_fnc_initUniversalSearch`** (impure, server-only, called once from
`fnc_initServer` after C2 signal sources — same "small number of server-side
handlers, not per-unit EHs" principle as `fnc_c2InitSignalSources`)
- Adds ONE more check inside the *existing* `EntityKilled` mission handler
  in `fnc_c2InitSignalSources` (do not add a second competing
  `EntityKilled` handler) — **or**, if that function is judged out of scope
  to touch this session, an `initUniversalSearch`-owned `EntityKilled`
  handler that only does this one job. **Preference: extend the existing
  handler**, since it already computes `group _killed` and already excludes
  the silent-class false positives (parachutes, weapon holders) — flag if
  approval prefers the separate-handler route instead.
- On a kill, checks: victim's group is not `civilian` side (mirrors the
  "civilian groups must never be C2-stamped" gotcha), not already flagged
  (`_group getVariable ["DSC_searchSiteCreated", false]`), and now has zero
  living units (`(units _group) findIf {alive _x} == -1`).
- On match: reads the group's faction role + `DSC_activeSeries`'s subject
  faction role, calls `fnc_resolveSearchYield`, then `createInteractionSite`
  with `action: "Search Body"`, a short `duration` (10–20s, lighter than
  mission SSE), `pos` = death position **captured now**, not re-derived
  later (see gotcha below), and an `onComplete` per §6 call site B.
- Sets `_group setVariable ["DSC_searchSiteCreated", true]` to prevent
  duplicate sites when multiple unit deaths in the same tick all satisfy the
  "zero alive" check.
- **Spawns nothing** — attaches only to the death position. Satisfies §10's
  "must not spawn extra entities."

### 8. Tangibility tiers / demotion (§13.5)

No code change required this session beyond the `tangibility` field existing
on the site shape (§1) and being read by the raid generator (§5) to
optionally call the pre-existing `fnc_placeInterior` / `fnc_placeOnGround` /
`fnc_placeOutdoorPile` for a single **non-interactable** dressing object when
`tangibility != "abstract"`. The interaction mechanism is *always* the
site's own distance-gated action — a focal-prop object is scenery only, it
does not get `fnc_addInteractionHandler` attached (that would reintroduce
the object-addAction path this session is designed to replace). Leave the
`"composition"` tier as a documented no-op hook (`dressing` field wired,
nothing consumes it yet) — explicitly deferred, matches session brief.

### 9. Marker hook (deferred, per session brief — wire, don't build)

`createInteractionSite` accepts the optional `markerLocationId` field (§1).
This session only needs the **hook to exist** — a single call point (can be
a stub that always draws the broad circle) where a future SWEEP/DA session
plugs in `fnc_intelBest(markerLocationId, "AREA_LAYOUT")` to choose
precise-marker vs. broad-circle. Do not build the differentiated marker
logic now.

---

## Tier-1 test plan — suite `interaction_site`

Registered in `fnc_initServerDebug.sqf` next to `intel_ledger`, same
`_results pushBack [label, bool]` pattern. All of these are pure-function
tests — no world objects, no addAction, no network:

1. **`buildInteractionSiteConfig` defaults**
   - Empty input → `id` non-empty, `radius` > 0, `duration` is a 2-element
     ascending pair, `tangibility == "abstract"`, `requireCount == [1,1]`,
     `state == "ARMED"`.
   - Caller-supplied fields are preserved verbatim (not overwritten by
     defaults).
2. **`SITES_INTERACTED` completion logic** (via `fnc_evaluateCompletion`
   directly, same as the existing suite tests other named types)
   - `sitesCompleted 0 / sitesRequired 1` → incomplete.
   - `sitesCompleted 1 / sitesRequired 1` → complete.
   - `sitesCompleted 2 / sitesRequired 3` → incomplete (N-of-M, not yet met).
   - `sitesCompleted 3 / sitesRequired 3` → complete.
   - Missing keys (empty state) → incomplete, does not error (uses
     `getOrDefault` defaults of `0`/`1`).
3. **`buildIntelTokenFromSite`**
   - Given a mock `_tokenContext` (`type: "HVT_LOCATION"`, `source: "SSE"`,
     `confidence: 0.6`) + mock `_site` (`id`, `pos`) → returns a hashmap
     with those fields intact and `payload` seeded from the site's `pos`.
   - Confidence out-of-range input still comes through unclamped here
     (clamping is `intelAdd`'s job, not the builder's — test that this
     function does NOT double-clamp, keeping responsibilities separate).
4. **`resolveSearchYield`**
   - Matching non-empty faction roles → `scope == "SERIES"`, confidence
     above the AREA baseline.
   - Mismatched roles → `scope == "AREA"`, low confidence.
   - Empty `_activeSeriesFactionRole` (no active series) → always `AREA`,
     regardless of victim role.

Definition of done for this suite: all of the above `PASS`, following the
existing `intel_ledger` suite's structure so `fnc_runTests` output stays
uniform.

---

## Harness `DSC_testConfig` addition

One block for a single mission-site SSE (Tier-2, human plays it):

```
DSC_testConfig = createHashMapFromArray [
    ["factionProfile", "vanilla"],
    ["steps", ["globals", "locations", "factions", "influence"]],
    ["missionTemplate", createHashMapFromArray [
        ["type", "RAID"],
        ["completion", "SITES_INTERACTED"],
        ["raidConfig", createHashMapFromArray [
            ["interactionSites", [
                createHashMapFromArray [["archetype", "SSE_INTEL"]]
            ]]
        ]]
    ]],
    ["singleShot", false],
    ["playerSpawn", "nearSite"],
    ["timeOfDay", 6],
    ["freezeWeather", true]
];
```

`singleShot: false` is deliberate — the human needs the mission left `ACTIVE`
to walk up and trigger the action live, per the harness's own documented
`false` behavior ("leaves the generated mission ACTIVE for a human to play
out manually"). Exact `missionTemplate`/`raidConfig` key nesting should be
double-checked against whatever `fnc_resolveMissionConfig` currently expects
for a forced `RAID` type at build time — this harness block is illustrative
of intent, not necessarily the final verified key path.

A second harness variant for the universal Search hook needs `"presence"`
and/or `"roving"` in `steps` (ambient groups to kill) instead of a forced
mission — call this out to the Sonnet build session as a second
`DSC_testConfig` example to commit, not just the mission-site one.

---

## Gotchas to respect (new, on top of the session brief's list)

- **Roving foot-rover corpses vanish within one ~8s tick of the last man
  dying** — `fnc_rovingDespawnSweep`'s `"group dead"` branch for `type ==
  "foot"` has no distance/age gate, so it culls on the very next sweep
  regardless of player proximity. This is fine *mechanically* because the
  interaction site is position-anchored, not object-anchored (§13.2/§13.3) —
  the "Search Body" action still works with no corpse present. It is a
  **feel** question (searching an empty patch of ground) for the Tier-2
  human playtest, not something to solve in code this session. Do not add
  despawn-sweep exceptions to "protect" the corpse unless the playtest
  flags it as bad — that would be scope creep against a problem that may
  not exist.
  **UPDATE (Tier-2 playtest, August 2026): the playtest DID flag it as
  bad** — a roving patrol wiped near the objective despawned its corpses
  before the player could reach the "Search Body" site. Confirmed real,
  deliberately deferred rather than hotfixed on the spot (needs the
  despawn sweep to hold the body/zone alive while an unfired interaction
  site still references its death position, releasing only once the
  player has left the area — presence/roving teardown timing, not just
  this primitive). Tracked in `.crush/roadmap.md` known bugs and
  AGENTS.md gotchas for a future session.
- **Capture the death position at the moment of the kill, not later** — do
  not re-derive `getPosATL _victim` from a body reference that
  `fnc_rovingDespawnSweep`/`fnc_despawnPresenceZone` may delete before the
  interaction site's own housekeeping runs.
- **Civilian groups must never get a search site** — same filter C2 already
  applies (`side (group _x) != civilian`); a dead civilian farmer is not an
  intel source and searching one would read as a bug.
- **`side`/`rating` are meaningless on a dead unit** — if any new code reads
  the victim's faction role, go through `group _killed`, never `_killed`
  directly (existing AGENTS.md gotcha, directly relevant here since this
  hook lives inside `EntityKilled`).
- **Don't add a second `EntityKilled` mission handler if avoidable** — see
  §7's explicit preference to extend the existing one in
  `fnc_c2InitSignalSources`, consistent with "server-side handlers, not
  per-unit EHs... scales flat regardless of how busy the world is."
- **`joinSilent` is irrelevant here** — this primitive creates no units, so
  the createUnit-side-inheritance gotcha does not apply. Do not add
  defensive code for it.
- **No `AREA_CLEAR`/completion gate on availability, ever** — §13.2's core
  rule. The only availability condition is distance; do not let a future
  session bolt on "must clear defenders first" as a config option that
  defaults to on.
- **CBA log-macro comma trap** — any inline array literal
  (`_state getOrDefault ["sitesCompleted", 0]`, `["a","b"] select X`) inside
  a `LOG_n`/`WARNING_n`/etc. call must be hoisted to a `private` local first.
  This primitive will log per-site creation/completion, so it will hit this
  immediately.
- **Distance-gated `addAction` conditions are baked strings, not closures**
  — `str (_site get "pos")` must be interpolated into the condition string
  at arm-time (`format [...]`); do not try to reference `_site` as a live
  local inside the condition string, it will not resolve.
- **`fnc_cleanupMission` must call `fnc_removeInteractionSite` for every
  mission-scoped site id** — otherwise a mission-generated site outlives
  the mission and its addAction stays armed on every client with a dangling
  `missionId` reference into a mission hashmap that's already gone.

---

## Open decisions requiring approval before Sonnet build

1. **RESOLVED** — `requireCount` semantic split (§1) confirmed: `requireCount`
   stays the instance-count meaning on the site shape; `sitesRequired` (on
   `completionState`) is the separate completion-count field.
2. **RESOLVED** — extended `fnc_c2InitSignalSources`'s existing `EntityKilled`
   handler for the universal search hook rather than adding a second listener.
3. **RESOLVED** — the harness's `raidConfig` (with `"completion"` and
   `"interactionSites"`) nests INSIDE `missionTemplate.raidConfig`, consumed by
   a new generic `"RAID"` case in `fnc_generateMission` that forwards it
   straight to `fnc_generateRaidMission`. `fnc_resolveMissionConfig` doesn't
   need to know about `raidConfig` at all — it's an opaque extra template
   field that already rides through its "carry through extra template
   fields" pass. See `docs/test_harness/03_tier2_altis_interaction_site_sse.sqf`.

---

## Results log

- Spec drafted (Opus, this section) — awaiting engineer approval before any
  code is written.
- Spec approved: **yes** (with the three open decisions resolved as above) ·
  Build: **complete** (Sonnet, August 2026) · Tier-1: **all assertions
  registered and expected to PASS** (`interaction_site` suite in
  `fnc_initServerDebug.sqf`) · Playtest: _pending_ (Tier-2 human pass per the
  "Tier-2 playtest" section above — harness configs committed at
  `docs/test_harness/03_tier2_altis_interaction_site_sse.sqf` and
  `docs/test_harness/04_tier2_altis_universal_search.sqf`).

