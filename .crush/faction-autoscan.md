# Faction Autoscan — DSC

*Status: **DESIGNED, NOT STARTED.** Deferred behind C2 Network completion
(F.4–F.5). July 2026.*

## Why this exists

Today a faction profile is a hardcoded hashmap literal in `fnc_initServer` —
one each for vanilla, RHS, and Aegis — selected by an all-or-nothing presence
check. That has four concrete problems:

1. **Every new mod needs a code change.** CUP, CFP, 3CB, GM, Vietnam, SOG PF,
   Global Mobilization — all unusable until someone writes another 60-line
   literal.
2. **Detection is brittle.** `fnc_initServer` requires *every* faction in the
   Aegis list to exist. One renamed classname in a mod update silently drops
   the player to the vanilla profile with no error.
3. **Profiles disagree with each other.** Aegis puts `bluForPartner` on west;
   vanilla and RHS put it on independent. This was a live bug until side
   normalization landed (see `.crush/faction-sides.md`).
4. **The scan direction forces a maintenance table.**
   `fnc_extractGroups.sqf` hardcodes `BLU_G_F`→`Guerilla`,
   `BLU_GEN_F`→`Gendarmerie`, `rhs_faction_socom`→`rhs_faction_socom_marsoc`.
   That table grows with every mod and can only be discovered by a mission
   failing to populate.

The stated design goal in `.crush/faction-system.md` is already *"discover and
use factions from any loaded mods without hardcoding."* This is the work that
actually delivers it.

## Design principle

**Discovery is automatic. Role assignment is suggested, then confirmed by the
player.**

Role classification is a judgement call — is Syndikat an `opForPartner` or an
`irregulars`? Is the UN an `environmentalActors` or a `bluForPartner`? No
heuristic gets that right every time, and it does not need to. The system
should get it 80% right automatically and make the remaining 20% a ten-second
drag-and-drop, not a code edit.

---

## Phase 0 — Delete `side` from profile literals

*Small, do this first, unblocks nothing but prevents regression.*

Side normalization (shipped) rewrites every role's `side` through
`fnc_resolveRoleSide` at profile selection. The `["side", ...]` entries in the
literals are therefore **dead input** — they are read once and immediately
overwritten.

They are also actively misleading: they look authoritative, they disagree with
each other across profiles, and as long as `["side", independent]` is typeable
someone will type it and assume it means something.

**Work:**
- Remove `["side", ...]` from all three profile literals in `fnc_initServer`.
- Change `fnc_resolveRoleSide` to take only the role key — drop the `_natural`
  fallback parameter entirely, so there is no bypass.
- Change the normalization loop to `_roleData set ["side", _x call
  DSC_core_fnc_resolveRoleSide]`.
- Update the two sites that pass `_natural` (`fnc_resolveMissionConfig`,
  `fnc_presenceActivateMilitary`) — or delete their resolver calls outright,
  since normalization already made their reads correct.

**Result:** a role's bloc becomes a code constant with exactly one definition,
which is what it always was semantically.

---

## Phase 1 — Invert the CfgGroups scan

*This is the change that kills the desync table permanently.*

### Current direction (fragile)

```
CfgFactionClasses >> <factionClass>          (authoritative name)
        │
        ▼   assumes the same string appears here
CfgGroups >> <SideName> >> <factionClass>    (often a DIFFERENT string)
```

When those strings differ, extraction returns nothing and the faction silently
contributes no groups. The only fix available is a hardcoded remap.

### Inverted direction (self-correcting)

```
CfgGroups >> <SideName> >> <node> >> <category> >> <group> >> <unit>
        │
        ▼   getText (_unit >> "vehicle")
CfgVehicles >> <unitClass> >> "faction"
        │
        ▼
the authoritative CfgFactionClasses name
```

Walk `CfgGroups` once, resolve each node's faction from the units it actually
contains (majority vote across the node's units — a handful of attached
specialists from another faction shouldn't reassign the node), and build:

```sqf
DSC_cfgGroupsNodeForFaction  // factionClass -> [sideName, cfgGroupsNode]
```

**This is correct for every mod, forever, with no maintenance table.**
`rhs_faction_socom` resolves to `rhs_faction_socom_marsoc` because the units
inside that node declare `faction = "rhs_faction_socom"`. Same mechanism
handles `Guerilla` and `Gendarmerie`.

It also gives a correct usability filter for free: a faction with no
`CfgGroups` presence cannot be used by DSC (nothing to spawn), and the walk
simply never emits it — instead of emitting it and failing at spawn time.

**Work:**
- New `fnc_buildCfgGroupsIndex` (faction/) — the inverted walk, run once.
- `fnc_extractGroups` takes the node name from the index instead of guessing.
- Delete the remap block at `fnc_extractGroups.sqf` ~lines 56–62.
- Delete the "Known CfgGroups Desync Workarounds" table from
  `.crush/faction-system.md`.

**Cost note:** this walks every group of every loaded faction. Measure it —
with RHS + CUP loaded this is a large config traversal. If it exceeds ~1s,
fold it into the Phase 2 cache rather than running it per session.

---

## Phase 2 — Faction catalog + role scoring

### Stage A: Catalog (fully automatic, reliable)

From the Phase 1 walk, emit one record per usable faction:

| Field | Source |
|---|---|
| `factionClass` | resolved authoritative name |
| `displayName` | `CfgFactionClasses >> displayName` |
| `sideNumber` | `CfgFactionClasses >> side` |
| `sourceMod` | `configSourceMod` on the faction entry |
| `flagTexture` | `CfgFactionClasses >> flag` |
| `categories` | category names under its CfgGroups node |
| `groupCount` / `unitCount` | from the walk |
| `assets` | `fnc_extractAssets` (already exists) |

Cache to `profileNamespace` keyed by a fingerprint of `getLoadedModsInfo`, so
the scan only re-runs when the mod set actually changes. Expose as
`DSC_factionCatalog`.

### Stage B: Role suggestion (heuristic, scored, NOT authoritative)

Everything needed to score "conventional army vs. irregular force" is already
extracted by the existing pipeline:

| Signal | Source | Infers |
|---|---|---|
| `side` number | `CfgFactionClasses >> side` | bloc (hard constraint) |
| `configSourceMod` | config entry | mod family grouping |
| Categories present (`Armored`, `Mechanized`, `Air`, `Support`, `Artillery`) | CfgGroups walk | conventional army |
| Air + armor asset counts | `fnc_extractAssets` | force tier |
| Mean unit `cost` / `threat` | CfgVehicles | equipment quality |
| `ELITE` / `MILITIA` / `CONSCRIPTS` tag density | `fnc_classifyGroups` (already runs) | doctrine quality |
| displayName keywords (`Militia`, `Insurgent`, `Police`, `Guerrilla`, `Nationalist`, `UN`, `Syndikat`) | CfgFactionClasses | direct role hint |

Compute a **conventional score** per faction, then rank within each engine
side:

- Highest-scoring east → `opFor`
- Remaining east → `opForPartner`
- Keyword-matched or lowest-scoring irregular-flavoured → `irregulars`
- Highest-scoring west → `bluFor`
- Remaining west + independent → `bluForPartner`
- `civilian` side, no weapons → `civilians`
- `civilian` side, keyword `IDAP`/`UN`/`Red Cross`/contractor → `environmentalActors`

Emit a **confidence value** alongside each assignment so the UI can flag
low-confidence guesses for player attention.

**Validation strategy:** before trusting this, run it with RHS loaded and with
Aegis loaded, and log its output against the existing hardcoded profiles.
Iterate on the scoring until it reproduces the hand-written profiles. Those
literals become the test oracle, then the fallback.

---

## Phase 3 — Player confirmation UI

The Commander's Tablet already exists (`DSC_ui_fnc_openTablet`, Ctrl+Y). Add a
**Campaign Setup** panel:

- **Left:** the catalog, grouped by source mod, with flag + display name +
  group count.
- **Right:** seven role buckets, pre-filled from Stage B, low-confidence
  entries visually flagged.
- Player drags factions between buckets, or clears a bucket entirely.
- Persist to `profileNamespace` keyed by the mod fingerprint.

**Resolution order at init becomes:**

```
saved player profile (matching mod fingerprint)
    └─ else → autoscan suggestion
        └─ else → hardcoded vanilla preset
```

This demotes `_factionProfileConfigVanilla` / `Rhs` / `Aegis` from *the
system* to *presets* — a curated starting point the player can load and then
tweak. It also removes the all-or-nothing detection block in `fnc_initServer`
(~lines 165–204) that currently drops to vanilla when a single Aegis faction
is missing.

Note this panel must run **before** `fnc_initFactionData`, which means either a
pre-init lobby step or a "restart campaign with these factions" flow. The
simpler first cut: apply on next mission start, not live.

---

## Ordering + dependencies

| Phase | Depends on | Size | Risk |
|---|---|---|---|
| 0 — delete `side` from literals | side normalization (shipped) | XS | none |
| 1 — invert CfgGroups scan | — | M | perf of the walk |
| 2 — catalog + scoring | Phase 1 | L | heuristic accuracy |
| 3 — tablet setup panel | Phase 2 | L | init ordering |

Phases 0 and 1 are independently valuable and low-risk — Phase 1 alone means
new mods work without a code change to the desync table. Phases 2 and 3 are
the ones that need real playtesting across several mod sets, which is why this
is parked behind C2 F.4–F.5.

## Non-goals

- **Per-faction diplomacy.** Not expressible in Arma. See
  `.crush/faction-sides.md`.
- **Auto-detecting map-appropriate factions** (e.g. "Livonia should use
  CSAT Pacific"). Interesting, separate, needs a map→region table.
- **Mixing mods within a single role.** Already supported — roles take faction
  *arrays*. No work needed.
