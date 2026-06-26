# Commander's Tablet — Design & Architecture

*Live as of April 30, 2026. Phase A (debug-first) shipped.*

## Purpose

A modal admin/debug UI bound to **Ctrl+Shift+T** that lets the player/admin drive
mission generation without restarting the mission. Built first as a
playtest-focused debug tool, designed to grow into a full in-mission
commander interface (supports, BFT, squad, intel) without rework.

**Phase A goal**: replace the "edit code → restart Arma → test → repeat" loop
with "open tablet → tweak parameters → queue → play → tweak → queue".

## Phasing

| Phase | Status | Scope |
|---|---|---|
| **A — Debug-first** | DONE | Mission Gen panel, Standard + Advanced views, server queue/abort, debug HUD overlay |
| **B — Blue Force Tracker** | ACTIVE (next build) | Live friendly-force map page + high-command capacity. First *player-facing* (non-debug) feature. See "Blue Force Tracker — Design & Build Plan" below. |
| **C — Supports** | DEFERRED | Move flagpole actions (HALO, Extraction, Recruit Medic) into a Supports panel; UAV control; air support. **Deferred** — an external support mod currently covers this. Revisit after BFT ships. |
| **D — In-mission UI (rest)** | planned | Squad panel (`units group player`), Intel panel (reads `DSC_currentMission >> intelTokens`) |

## Code Structure

```
addons/ui/                          ← NEW PBO (DSC_ui)
├── config.cpp                      # CfgPatches + dialog includes
├── XEH_PREP.hpp                    # Tablet function registry
├── CfgEventHandlers.hpp
├── XEH_preInit.sqf / XEH_preStart.sqf
├── dialog/
│   ├── idc.hpp                     # IDC numeric defines (SAFE for SQF include)
│   ├── defines.hpp                 # DSC_Rsc* base classes (config-only, inherits BIS bases)
│   ├── tablet.hpp                  # class DSC_Tablet (top-level, NOT under CfgDialogs)
│   └── debug_hud.hpp               # class RscTitles >> DSC_DebugHud
├── functions/tablet/
│   ├── fnc_openTablet.sqf
│   ├── fnc_closeTablet.sqf
│   ├── fnc_switchPanel.sqf         # tab dispatcher (mission/supports/bft/squad/intel)
│   ├── fnc_panelMissionGen_init.sqf
│   ├── fnc_panelMissionGen_switchView.sqf
│   ├── fnc_panelMissionGen_sliderLabel.sqf
│   ├── fnc_panelMissionGen_readTemplate.sqf
│   ├── fnc_panelMissionGen_submit.sqf
│   ├── fnc_panelMissionGen_abort.sqf
│   ├── fnc_panelMissionGen_refreshState.sqf
│   └── fnc_toggleDebugHud.sqf
└── data/
    └── tablet_horizontal.paa       # Bezel image — currently UNUSED in dialog (planned: re-link when bezel is authored to fit UI)
```

Functions registered as `DSC_ui_fnc_<name>` via `PREP_SUB(tablet, ...)`.

## Server Debug Layer

`fnc_initServerDebug` (called after `fnc_initServer`) initializes globals
and registers CBA event handlers used by the tablet:

| Global | Type | Purpose |
|---|---|---|
| `DSC_missionQueue` | ARRAY | FIFO queue of partial template hashmaps; mission loop pulls from this before random generation |
| `DSC_missionAbortRequested` | BOOL | Set true → mission loop breaks waitUntil, skips scoring, jumps to cleanup, resets flag |

| CBA Event | Payload | Server Behavior |
|---|---|---|
| `DSC_tablet_queueMission` | `[_template, _uid, _name]` | Pushes template onto `DSC_missionQueue`, logs sender |
| `DSC_tablet_abortMission` | `[_uid, _name]` | Sets `DSC_missionAbortRequested = true` if mission in progress |

**No admin gating** in Phase A — open to any player. Future: UID allowlist
in `fnc_initServerDebug` if multiplayer needs it.

## Client Debug Layer

`fnc_initPlayerLocalDebug` (called after `fnc_initPlayerLocal`) registers
CBA keybinds (rebindable in CBA Settings → Addon Options → "DSC Debug"):

| Key | Action | Function |
|---|---|---|
| **Ctrl+Y** | Open Commander's Tablet | `DSC_ui_fnc_openTablet` |
| **Ctrl+Shift+F** | Toggle Debug HUD overlay | `DSC_ui_fnc_toggleDebugHud` |

Default Ctrl+Y conflicts with Zeus, so users with Zeus enabled may need to
rebind one or the other. CBA persists rebinds across sessions.

## Mission Loop Integration

`fnc_initServer` Step 5 was refactored:

1. **Spawned** instead of inline `while {true}` so initServer returns and
   the debug init can run after.
2. **Pulls from queue** before falling back to random:
   ```sqf
   private _template = if (count DSC_missionQueue > 0) then {
       DSC_missionQueue deleteAt 0
   } else { createHashMap };

   private _config = [_influenceData, _factionData, _template] call DSC_core_fnc_selectMission;
   ```
3. **Honors abort flag**:
   ```sqf
   waitUntil {
       sleep 1;
       !(missionInProgress) || DSC_missionAbortRequested
   };
   if (_aborted) { skip scoring; just cleanup };
   ```
4. **Resets abort flag** at end of each cycle.

`fnc_generateMission` now also reads `skillProfile` from the mission config
(template field), falling back to the global `DSC_skillProfile`. Lets the
tablet override AI difficulty per mission without changing the global.

## Dialog Architecture

### `class DSC_Tablet`

Top-level config class (NOT inside `CfgDialogs` — the engine looks up
`createDialog` targets at the configFile root). IDD `9000`.

Layout:
- **Full-screen dim** (alpha 0.55)
- **Centered floating panel** (66% × 78% of safezone, opaque dark)
- **Header** (DSC // COMMANDER) + **Tab bar** (MISSION GEN active; SUPPORTS/BFT/SQUAD/INTEL stubbed)
- **Mission Gen host** controls group containing Standard core + Advanced overlay + Status + Actions
- **Footer** with live state line

### Standard vs Advanced View

Single host RscControlsGroup. View toggle `[ STANDARD ] [ ADVANCED ]`
(top-right of host) calls `fnc_panelMissionGen_switchView` which:
- Flips `ctrlShow` on the Advanced overlay group (`DSC_TABLET_IDC_MGEN_ADV_PANEL`)
- Updates button background colors so active mode is visible
- Stores `DSC_mgenView` on the display namespace so submit knows which fields to read

**Standard view fields** (always visible, "core"):
- Mission Type, Profile, Density, Target Faction
- Min Distance, Max Distance, Anchor toggle
- QRF enabled, Replace current

**Advanced view adds three sections**:

| Section | Controls | Template Keys |
|---|---|---|
| **LOCATION** | Required Tags (text), Exclude Tags (text), Min Buildings | `requiredTags[]`, `excludeTags[]`, `minBuildingCount` |
| **POPULATION** | Garrison anchors min/max, Patrols, Max Vehicles, Veh Armed % slider, Area Pres % slider, Guard Cov % slider | `garrisonAnchors[2]`, `patrolCount[2]`, `maxVehicles`, `vehicleArmedChance`, `areaPresenceChance`, `guardCoverage` |
| **MISSION FEEL** | AI Skill combo, QRF Delay min/max | `skillProfile`, `qrfDelay[2]` |

Sliders: 0-100 range, snap to 10, live readout label updated by
`onSliderPosChanged → DSC_ui_fnc_panelMissionGen_sliderLabel`.

### Submit Flow

1. `fnc_panelMissionGen_readTemplate` builds a partial hashmap, only
   including fields the user explicitly set (empty edits/combos are
   omitted, so the resolver's profile/auto-fill cascade still applies).
2. Reads core controls always; reads advanced ONLY if `DSC_mgenView == "advanced"`.
3. If "Replace current" + mission active → fires `DSC_tablet_abortMission`.
4. Always fires `DSC_tablet_queueMission` with the template.
5. Updates the panel status line + systemChat with field summary.
6. Schedules `refreshState` after 1s for visual confirmation.

## Specific Location combo (REMOVED Phase A)

Tested but cut: populating ~120 named locations into a combo on dialog open
caused FPS drops. Engine reconciles all entries per frame even when the
combo is collapsed.

If reintroduced later, scope to **Stage 2 named anchors only** (skip
`Orphan_*` synthetic clusters) — that's ~30-40 entries instead of 1100+.

Min/Max distance + tag filters + anchor-to-position covers ~all playtest
use cases anyway. Every named location is already an anchor (Stage 2 of
`scanLocations`), so distance-from-position is functionally equivalent to
specific-location for nearby targets.

## Debug HUD Overlay

`fnc_toggleDebugHud` shows/hides a corner overlay via `cutRsc` /
`RscTitles >> DSC_DebugHud` (input-passive — doesn't grab focus or pause
gameplay). Updated 2× per second by a CBA per-frame handler.

**Lines**:
1. **FPS / frame time** — color-coded (green ≥50, yellow ≥30, red below)
2. **Mission state** — `state / inProg / queue length`
3. **Entity counts** — `units / groups / vehicles` (totals)
4. **Custom slot** — anything written to `missionNamespace getVariable "DSC_debugHudCustom"`

The custom slot is the diagnostic hook for future heavy systems (BFT,
presence manager, etc.):

```sqf
DSC_debugHudCustom = format ["loop tick: %1ms", _elapsed];
```

## Required Property Avoidance — UI Inheritance Pattern

Arma's UI engine validates required properties at runtime, not build time.
HEMTT can't preflight them. Original DSC base classes declared from scratch
hit cascading "No entry … colorXxx" errors as different control types
demanded different properties.

**Solution**: forward-declare BIS base classes (`RscButton`, `RscCombo`,
`RscEdit`, `RscCheckBox`, `RscPicture`, `RscControlsGroupNoScrollbars`,
`RscXSliderH`, `RscListBox`) and inherit from them. The engine's own
defaults satisfy required properties; we only override styling.

```cpp
class RscCombo;            // forward-declare
class DSC_RscCombo : RscCombo {
    style = ST_LEFT;
    colorText[] = COLOR_TEXT;
    colorBackground[] = { 0.10, 0.13, 0.16, 0.95 };
    // ... only style/color overrides, no required-property scaffolding
};
```

Convention going forward: **always inherit from a BIS base class** for any
new control type added to the tablet. This eliminates the entire class of
"missing property" runtime errors.

## Bezel Image — Deferred

`tablet_horizontal.paa` is built into the PBO but NOT referenced in the
dialog. Two ChatGPT-generated bezel images (v1, v2) were tested but didn't
fit the UI proportions cleanly. Decision: nail down the panel layout/content
first, then commission a bezel authored to match. Re-link when ready.

## Performance Notes

Phase A FPS investigation found:
- Dialog itself is cheap.
- Specific Location combo populating 1100+ entries was a major hit → removed.
- Persistent UAV + Zeus mods (3den Enhanced + Eden Enhanced) suspected for
  baseline drops, not yet confirmed culprit. Diagnostic toggles available
  via debug HUD.

The mission loop spawn pattern (vs inline) is intentional — keeps the
mission loop's `sleep` / `waitUntil` from blocking server boot.

## Function Reference

| Function | Type | Purpose |
|---|---|---|
| `DSC_core_fnc_initServerDebug` | server | Init queue/abort globals, register CBA events |
| `DSC_core_fnc_initPlayerLocalDebug` | client | Register CBA keybinds (Ctrl+Y, Ctrl+Shift+F) |
| `DSC_ui_fnc_openTablet` | client | createDialog "DSC_Tablet" with init guards |
| `DSC_ui_fnc_closeTablet` | client | closeDialog wrapper |
| `DSC_ui_fnc_switchPanel` | client | Tab dispatcher (Phase A: only Mission Gen) |
| `DSC_ui_fnc_panelMissionGen_init` | client | Populates combos (Type/Profile/Density/Faction/Skill), inits sliders, sets default Standard view |
| `DSC_ui_fnc_panelMissionGen_switchView` | client | Show/hide Advanced overlay, store view state |
| `DSC_ui_fnc_panelMissionGen_sliderLabel` | client | onSliderPosChanged handler — snaps to 10, updates companion label |
| `DSC_ui_fnc_panelMissionGen_readTemplate` | client | Build partial template from controls (returns `[_template, _replace]`) |
| `DSC_ui_fnc_panelMissionGen_submit` | client | Read template, fire CBA events, update status |
| `DSC_ui_fnc_panelMissionGen_abort` | client | Fire DSC_tablet_abortMission |
| `DSC_ui_fnc_panelMissionGen_refreshState` | client | Render mission state to status + footer |
| `DSC_ui_fnc_toggleDebugHud` | client | Show/hide debug HUD overlay, manage CBA per-frame handler |

## Blue Force Tracker — Design & Build Plan

*Phase B. First player-facing feature. Goal: a live map page in the tablet
that shows friendly forces in real time and lets the player employ nearby
friendlies in a high-command capacity (actively attach to the player's
mission, or stage as QRF).*

### Vision

When the player is running a mission (e.g. hunt an HVT in a large town),
the BFT page answers two questions:

1. **Situational awareness** — what friendly forces are near me / near my
   objective right now, and where are they moving?
2. **Employment** — can I task a nearby friendly group to support this
   mission, either actively (move in / attach) or as QRF (stage and react)?

### What counts as "friendly"

Friendly = anything on the player's side or allied to it, as defined by the
faction roles in `fnc_initServer` (line ~19). Concretely:

- **`bluFor`** role (`side west`) — the player faction.
- **`bluForPartner`** role (`independent` or `west` depending on profile) —
  partner forces (AAF/Gendarmerie/CDF/SAF/UN/etc.).

Resolve at runtime against `side player` rather than hard-coding `west`:
a track is friendly if `(side _grp) getFriend (side player) >= 0.6`. This
keeps the BFT correct across the Vanilla / RHS / Aegis profiles and through
`setFriend` diplomacy swings during missions.

### Data sources (all already globally broadcast — read directly)

Every system the BFT needs to mirror already publishes its state with
`setVariable [..., true]`, so a client can read them without new plumbing.
A track can originate from any of:

| Source global | Shape | Friendly subset to surface |
|---|---|---|
| `units group player` | client-local | Player's own squad — always live, no broadcast needed |
| `DSC_presenceZones` | array of zone hashmaps; each has `groups[]`, `position`, `controlledBy`, `faction`, `side`, `type`, `state` | Garrisons / patrols in `controlledBy=="bluFor"` zones (and any zone whose spawned `groups` resolve friendly) |
| `DSC_rovingActive` | array of records: `{id,type,vehicle,group,side,origin,destination,spawnTime}` | Records where `side` is friendly — air (rotary/fixed-wing), ground, foot, boat rovers in friendly territory |
| `DSC_activeUAV` / `DSC_activeUAVGroup` | object / group | The persistent ISR drone — always friendly, special "asset" track |
| `DSC_currentMission` | hashmap with `groups[]`/`units[]`/`vehicles[]` | Mostly enemy (raid targets) — **filter to friendly only**; usually empty, but future friendly mission attachments show here |

Note: presence-spawned and roving groups are **server-owned**. Group/object
references are network-transferable, but issuing orders must happen where the
group is local (the server) — see High Command below.

### Track schema

The BFT works off a normalized track list rather than re-deriving from raw
globals every draw. One track:

```sqf
// hashmap per friendly entity worth showing
[
    ["id",        "roving_ground_bluFor_1234.5"], // stable key
    ["category",  "ground"],   // squad|garrison|patrol|air|ground|foot|boat|uav|mission
    ["group",     _grp],       // group ref (may be grpNull for UAV-as-asset)
    ["vehicle",   _veh],       // objNull if foot
    ["netId",     "2:34"],     // groupNetId for cross-machine commands
    ["position",  [x,y,z]],
    ["dir",       145],
    ["side",      west],
    ["faction",   "rhs_faction_socom"],
    ["label",     "GND PATROL"],
    ["strength",  4],          // alive unit count
    ["commandable", true]      // server-owned + alive + not player's own squad
]
```

### Architecture — snapshot aggregator + client map

Two pieces:

1. **Server aggregator `fnc_bftSnapshot`** (new, `addons/core/functions/...`):
   a slow loop (~2–3 s, phase-offset from presence/roving ticks) that walks
   the data sources above, filters to friendly + alive, builds the track
   list, and broadcasts `DSC_bftTracks` (public). Keeps clients from
   iterating every zone/rover each frame and sidesteps remote-group read
   timing. Player's own squad is appended **client-side** (always local,
   no need to round-trip the server).

   - Reuse the existing "snapshot broadcast" pattern (cf. `_baseMarkerData`
     in `fnc_initServer` Step 4).
   - Skip when no player is within tracking range to keep it cheap.

2. **Client BFT panel** (new functions under `addons/ui/functions/tablet/`):
   an `RscMapControl` hosted in the panel host (tab IDC `9013`,
   `DSC_TABLET_IDC_TAB_BFT`, already reserved). A `"Draw"` event handler
   renders one icon per track from `DSC_bftTracks` + the local squad. The
   Draw EH must stay cheap (icons only, no per-frame allocation); the data
   itself refreshes on the 2–3 s snapshot cadence, **not** per frame
   (mirrors the existing "update interval should be slow or it'll cost FPS"
   guidance in Future Hooks / Performance Notes).

### Map control notes

- New base classes: forward-declare `RscMapControl` (and `RscMapControl`'s
  required sub-entries) and inherit, per the "always inherit from a BIS
  base class" convention in this doc. Map controls are property-heavy —
  copying a stock map config (e.g. `RscMapControl` from `RscDiary` /
  `RscDisplayCurator`'s map) is the safe starting point.
- Center on player on open; expose simple zoom (mouse wheel default) and a
  "recenter" button.
- Icon set per category: squad (`b_inf`), garrison (`b_installation`),
  patrol/ground (`b_armor`/`b_mech_inf`), air (`b_air`), foot (`b_inf`),
  boat (`b_naval`), UAV (`b_uav`), with side-colored tint
  (`ColorWEST`/`ColorGUER`). Reuse the side→color maps already in
  `fnc_initServer` Step 4.
- Draw the player objective/mission AO marker too (from `DSC_currentMission
  >> location`) so "friendlies near my objective" reads at a glance.

### High Command capacity

This is the employment half of the feature and the only part that needs a
new server-side execution path (server-owned groups can only be ordered
where they're local).

- **Selection**: click a commandable track on the map → selection state +
  a context action strip (or side info panel): *Take Command*, *Move to My
  Position*, *Move to Objective*, *Set as QRF*, *Release*.
- **Command channel**: client fires a CBA event
  `DSC_bft_command` with `[_netId, _action, _params, _uid]`. Server handler
  (register in `fnc_initServerDebug` alongside the existing
  `DSC_tablet_queueMission` / `DSC_tablet_abortMission`) resolves the group
  via `groupFromNetId` and applies the order on the server where the group
  is local.
- **Take Command**: use the BIS High Command framework — `BIS_fnc_addCommander`
  on the player once (lazily, first time they take command), then `hcSetGroup`
  the selected group to the player. This gives the player the stock HC map
  interface for fine control in addition to the tablet quick-orders.
- **Move orders**: `Move to My Position` / `Move to Objective` →
  `_grp move _pos` (or a fresh MOVE waypoint) executed server-side. For
  roving groups, first re-enable what the roving manager disabled
  (`enableAI "AUTOCOMBAT"`, raise behaviour to `AWARE`/`COMBAT`) so they
  actually fight when committed.
- **Set as QRF**: tag the group (`_grp setVariable ["DSC_bftRole","QRF",true]`),
  stage it near the mission AO, and arm it (combat enabled, react on contact).
  Optionally hook the mission system so a QRF-tagged friendly group reacts to
  the active `DSC_currentMission` AO. Keep MVP simple: QRF = move to a hold
  point just outside the AO + combat-enabled.
- **Release**: hand the group back to its owning system (`hcRemoveGroup`,
  clear the role var). For roving groups, re-disable AUTOCOMBAT and let the
  roving despawn sweep reclaim them; for presence groups, they remain under
  presence lifecycle.

### Coordination with owning systems (don't double-manage)

A group taken under high command is still tracked by its source system
(`DSC_rovingActive` record / presence zone `groups[]`). Two rules:

1. **Despawn protection** — `fnc_rovingDespawnSweep` and the presence
   despawn path must **skip groups flagged `DSC_bftRole`** (commandeered),
   or the player will watch a group they just tasked evaporate. Add a guard
   check in both sweeps.
2. **Snapshot continuity** — the aggregator keeps emitting the track (now
   tagged with its BFT role) so the icon stays on the map and reflects the
   player's order.

### Build sub-sprints

| Sub-sprint | Deliverable | Status |
|---|---|---|
| **BFT-1 — Read-only tracker** | `fnc_bftSnapshot` aggregator + `DSC_bftTracks` broadcast; BFT tab wired in `fnc_switchPanel`; `RscMapControl` + Draw EH + category icons + legend; player squad overlaid client-side; objective marker. No commands yet. | ✅ shipped |
| **BFT-2 — Selection & info** | Click-to-select a track; side info panel (category, strength, distance to player, distance to objective, faction). Right-justified sidebar. | ✅ shipped |
| **BFT-3 — High command** | `DSC_bft_command` CBA event + server executor; *Take Command* (BIS HC + NATO type icons via `addGroupIcon`), *Move to My Position*, *Move to Objective*, *Release*. Despawn-protection guards in roving + presence sweeps. Smart per-state button enable/disable + 1 Hz info-card refresh. | ✅ shipped |
| **BFT-4 — QRF / mission employment** | *Set as QRF* moves the group to a road-snapped staging position 500-800 m off the objective (via `fnc_bftQrfStaging`) instead of dropping them in the kill box. Per-group reactor (`fnc_bftQrfReact`) ticks every 8 s, pushes the group in on first detected enemy presence near the AO (`role = "QRF"` → label `QRF→`), and auto-releases the group (clears role tag, drops HC icons) when the mission ends. Yellow ring on BFT marker for staged QRFs, orange-red for triggered. | ✅ shipped |
| **BFT-5 — Polish** | BFT-vs-HC marker dedupe (skip our drawIcon for commanded tracks since the HC system already paints them on every map control via `addGroupIcon`). MINE / ALL clutter filter button in the chrome row — when MINE is active, hides ambient garrisons / roving / mission attachments / ISR and keeps only the player, squad, objective, and commanded groups. Snapshot interval is now live-tunable via `DSC_bftSnapshotInterval` (default 2.5 s, clamped 0.5–10 s) — debug-console settable, no restart needed. Tabs reordered so BFT is the default landing tab and "MISSION DEBUG" sits at the far right. | ✅ shipped |

### Open questions / decisions to confirm before BFT-3

- **HC vs. lightweight orders**: full BIS High Command (rich, stock map UI,
  more moving parts) vs. tablet-only quick-orders (simpler, fully owned).
  Recommendation: ship BFT-3 with tablet quick-orders first; layer BIS HC
  in as an optional "Take Command" escalation.
- **Command scope**: any friendly group on the map, or only those within N
  metres of the player/objective? Recommendation: gate `commandable` on a
  range (e.g. ≤ 4 km) so the player isn't micromanaging the whole island.
- **MP / admin gating**: Phase A left server events ungated. If BFT ships to
  non-admin players in MP, gate `DSC_bft_command` on a UID allowlist in
  `fnc_initServerDebug` (same hook noted under Future Hooks → Admin gating).

### New functions (anticipated)

| Function | Type | Purpose |
|---|---|---|
| `DSC_core_fnc_bftSnapshot` | server | Aggregate friendly tracks from presence/roving/UAV/mission, broadcast `DSC_bftTracks` on a slow loop |
| `DSC_core_fnc_bftIsFriendly` | shared | `(side _grp) getFriend (side player) >= 0.6` helper (side-relative friendly test) |
| `DSC_core_fnc_bftExecuteCommand` | server | `DSC_bft_command` handler — resolve `groupFromNetId`, apply HC / move / QRF / release |
| `DSC_ui_fnc_panelBft_init` | client | Build/host map control, attach Draw EH, seed state |
| `DSC_ui_fnc_panelBft_draw` | client | Draw EH — render track icons + squad + objective each frame (cheap) |
| `DSC_ui_fnc_panelBft_refresh` | client | Pull `DSC_bftTracks`, merge local squad, update selection/info on snapshot cadence |
| `DSC_ui_fnc_panelBft_select` | client | Map-click hit-test → set selected track, show action strip |
| `DSC_ui_fnc_panelBft_command` | client | Fire `DSC_bft_command` for the selected track + action |

## Future Hooks

The dialog architecture supports these without restructuring:

- **Supports panel** — duplicate the MissionGen approach: controls group,
  init function, action functions, all under `addons/ui/functions/tablet/`
  (or new subfolder per panel as it grows).
- **BFT panel** — now an active build (Phase B). See "Blue Force Tracker —
  Design & Build Plan" above for the full spec (data sources, snapshot
  aggregator, map control, high-command channel, sub-sprints).
- **Squad panel** — `RscListBox` of `units group player`, addAction-style
  per-unit commands.
- **Intel panel** — read `DSC_currentMission >> intelTokens`, render as
  list with descriptions from object archetypes.
- **Admin gating** — when needed, gate `DSC_tablet_queueMission` /
  `DSC_tablet_abortMission` server handlers on UID allowlist defined in
  `fnc_initServerDebug`.
- **Mission templates / presets** — save current panel state to a hashmap,
  store in `profileNamespace`, list as combo. Load button restores all
  fields. Useful once you have favorite playtest configs.
