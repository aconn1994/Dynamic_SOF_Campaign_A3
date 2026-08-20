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

## Results log

- Spec approved: _pending_ · Build: _pending_ · Tier-1: _pending_ · Playtest: _pending_
