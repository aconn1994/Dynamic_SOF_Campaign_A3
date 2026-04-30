# Commander's Tablet — Design & Architecture

*Live as of April 30, 2026. Phase A (debug-first) shipped.*

## Purpose

A modal admin/debug UI bound to **Ctrl+Y** that lets the player/admin drive
mission generation without restarting the mission. Built first as a
playtest-focused debug tool, designed to grow into a full in-mission
commander interface (supports, BFT, squad, intel) without rework.

**Phase A goal**: replace the "edit code → restart Arma → test → repeat" loop
with "open tablet → tweak parameters → queue → play → tweak → queue".

## Phasing

| Phase | Status | Scope |
|---|---|---|
| **A — Debug-first** | DONE | Mission Gen panel, Standard + Advanced views, server queue/abort, debug HUD overlay |
| **B — Supports** | planned | Move flagpole actions (HALO, Extraction, Recruit Medic) into a Supports panel; UAV control; air support |
| **C — In-mission UI** | planned | BFT panel (live unit positions on map control), Squad panel (`units group player`), Intel panel (reads `DSC_currentMission >> intelTokens`) |

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

## Future Hooks

The dialog architecture supports these without restructuring:

- **Supports panel** — duplicate the MissionGen approach: controls group,
  init function, action functions, all under `addons/ui/functions/tablet/`
  (or new subfolder per panel as it grows).
- **BFT panel** — uses `RscMapControl`. Position units via Map Draw EH
  reading `units` / `vehicles` arrays. Update interval should be slow (~1s)
  or it'll cost FPS.
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
