# AGENTS.md — Dynamic SOF Campaign (DSC)

An Arma 3 mod that dynamically generates Special Operations Forces missions using whatever faction mods are loaded. Built with CBA XEH + HEMTT.

## Quick Reference

| Command | Description |
|---------|-------------|
| `hemtt launch` | Build + launch (CBA_A3 only, vanilla factions) |
| `hemtt launch developer` | Launch with dev tools (ADT, Zeus Enhanced) |
| `hemtt launch developer_factions` | Launch with RHS faction mods |
| `hemtt launch play_test_factions` | Full playtest loadout (RHS + QoL mods) |
| `hemtt build` | Build PBOs without launching |

## Project Structure

```
addons/
├── main/                    # Mod metadata, version, macros
│   ├── script_mod.hpp       # DEBUG_MODE_FULL flag lives here
│   └── script_version.hpp
├── core/                    # All gameplay logic (CBA functions)
│   ├── config.cpp
│   ├── XEH_PREP.hpp         # Function registry (PREP_SUB macros)
│   ├── XEH_preInit.sqf
│   └── functions/
│       ├── init/            # Server + client initialization
│       ├── locations/       # World scanning, influence system
│       ├── faction/         # Faction extraction + group/asset pipelines + entity class resolver
│       ├── classification/  # Unit + group doctrine tagging
│       ├── ai/              # Population, guards, garrison, patrols, combat activation
│       ├── presence/        # World simulation manager: zones, state machine, lifecycle, + roving entities subsystem (Sprint E) (see .crush/presence-manager.md)
│       ├── missions/        # Raid generator, mission orchestrator, briefing, completion, outcome, cleanup, interaction
│       ├── placement/       # Strategy library: deep-building, ground, interior, outdoor-pile, object dispatcher
│       ├── markers/         # Compound marker drawer
│       ├── base/            # Player actions: HALO, extraction, medic, helo transport
│       ├── data/            # Static data (structure types, mission profiles, entity/object/completion archetypes, briefing fragments)
│       ├── validators/      # Group activity checks
│       └── debug/           # (empty — debug is inline via diag_log)
├── ui/                      # Commander's Tablet UI (`DSC_ui_fnc_*`)
│   ├── config.cpp           # CfgPatches + CfgDialogs (DSC_Tablet)
│   ├── XEH_PREP.hpp         # Tablet function registry
│   ├── dialog/              # idc.hpp (SQF-safe IDCs), defines.hpp (config-only base classes), tablet.hpp
│   ├── functions/tablet/    # openTablet, closeTablet, switchPanel, panelMissionGen_*
│   └── data/                # tablet_horizontal.paa
└── maps/                    # Per-map mission folders
    ├── DSC_Altis.Altis/     # Default test map
    ├── DSC_Livonia.enoch/
    ├── DSC_Malden.Malden/
    ├── DSC_Stratis.Stratis/
    ├── DSC_Tanoa.Tanoa/
    └── MissionDescription/
        └── master.hpp       # Shared description.ext includes
```

## Development Workflow

1. Edit SQF in `addons/core/functions/`
2. Register new functions in `addons/core/XEH_PREP.hpp`
3. Launch: `hemtt launch developer_factions` (or `play_test_factions`)
4. Check RPT logs: `C:\Users\Adam\AppData\Local\Arma 3\arma3_x64_*.rpt`
5. All DSC log lines are prefixed with `DSC:`

## Active Map

Configured in `.hemtt/launch.toml` — currently `DSC_Altis.Altis`. Other maps are commented out but functional.

## Architecture Overview

See `.crush/architecture.md` for the full init flow and system relationships.

**Server init pipeline** (`fnc_initServer`):
1. Set globals (faction profile, mission state, `playerMainBase` marker)
2. `fnc_scanLocations` → anchor-based scan + orphan recovery, assigns structures to locations, functional tagging (residential/commercial/industrial/etc.), outputs location hashmaps directly
3. `fnc_initFactionData` → extract groups + assets per role
4. `fnc_initInfluence` → tiered military occupation (base/outpost/camp), 5km safe zone around player base
4b. Mark military installations on map — faction flag textures + 800m danger zones on bases
4c. `fnc_initPresenceManager` → build zone registry from influence data (4 major zone types + 4 microzone types tag-dispatched from `_missionSites`), spawn worker + 8s tick loop. State machine populates the area around the player with civilians, military presence, contested skirmishes, anchored guards/patrols projected from controlling installations. See `.crush/presence-manager.md`.
4d. `fnc_initRovingManager` → sibling subsystem to presence (Sprint E). Five rover types: air (rotary + fixed-wing with transit/loiter mix), ground (motorized/mechanized road patrols), foot (infantry patrols), boats (coastal/water patrols, no-op on inland maps). Own 8s tick (phase-offset 4s from presence), own worker, own per-type budget (3 rotary + 2 fixed-wing + 4 ground + 2 foot + 2 boat). Nearest hotspot to player determines side/faction; spawn geometry independent of hotspot location. AWARE + autocombat disabled (ambient world, not forced encounter).
5. Mission generation loop (spawned) — select (template → resolver) → generate (raid config → archetype dispatch) → debrief (evaluateCompletion → buildMissionOutcome) → update influence → cleanup → repeat. Pulls from `DSC_missionQueue` if non-empty, else random; honors `DSC_missionAbortRequested` for tablet-driven aborts.

**Server debug layer** (`fnc_initServerDebug`, called after initServer):
- Initializes `DSC_missionQueue` and `DSC_missionAbortRequested`
- Registers CBA events `DSC_tablet_queueMission` and `DSC_tablet_abortMission`
- Home for future server-side debug tooling

**Client init** (`fnc_initPlayerLocal`):
- Waits for server globals
- Adds actions to `jointOperationCenter` flagpole: Debrief, HALO, Extract, Recruit Medic
- Sets up player down/revive (ACE or vanilla)
- Map Draw EH renders faction flag textures on bases/outposts

**Client debug layer** (`fnc_initPlayerLocalDebug`, called after initPlayerLocal):
- Registers CBA keybind Ctrl+Y → `DSC_ui_fnc_openTablet`
- Home for future client-side debug tooling

## Key Systems

| System | Entry Point | Details |
|--------|------------|---------|
| Location Scanner | `fnc_scanLocations` | Anchor-based + orphan recovery, functional tagging, outputs hashmaps with tags[] and functionalProfile{} |
| Faction Pipeline | `fnc_initFactionData` → `fnc_extractGroups` → `fnc_classifyGroups` | Mod-agnostic group extraction + doctrine tagging |
| Asset Extraction | `fnc_extractAssets` | Auto-classifies vehicles, statics, aircraft per faction |
| Influence | `fnc_initInfluence` / `fnc_updateInfluence` | Tiered military occupation, base→outpost propagation, safe zone |
| Mission Config | `fnc_resolveMissionConfig` | Template → profile → auto-generation. Filters locations by tags/region/distance. |
| Mission Profiles | `fnc_getMissionProfiles` | AFO (light/isolated) and DA (heavy/fortified) presets |
| Mission Selection | `fnc_selectMission` | Thin wrapper: accepts optional template, delegates to resolver |
| Mission Generation | `fnc_generateMission` | Orchestrator: dispatch on type → build raid config → call raid generator → briefing → QRF → skill → UAV |
| Raid Generator | `fnc_generateRaidMission` | Generic raid: iterates entity/object specs, dispatches placement strategies, draws markers, builds completion state |
| Entity Archetypes | `fnc_getEntityArchetypes` + `fnc_resolveEntityClass` | OFFICER, BOMBMAKER, HOSTAGE; resolver maps keys (officer/civilian/civilian_suit/civilian_labcoat) to classnames |
| Object Archetypes | `fnc_getObjectArchetypes` + `fnc_placeObjects` | INTEL_LAPTOP, INTEL_DOCUMENTS, SUPPLY_CACHE, BOMB_PARTS, WEAPONS_CRATE; dispatcher routes to placement strategy |
| Placement Strategies | `fnc_placeInDeepBuilding`, `fnc_placeOnGround`, `fnc_placeInterior`, `fnc_placeOutdoorPile` | Reusable spawn logic for entities/objects |
| Completion Conditions | `fnc_getCompletionTypes` + `fnc_evaluateCompletion` | KILL_CAPTURE, ALL_DESTROYED, ANY_INTERACTED, HOSTAGES_EXTRACTED, AREA_CLEAR; supports compound `completionExpr` |
| Mission Outcome | `fnc_buildMissionOutcome` → `DSC_lastMissionOutcome` | Standardized result schema for series/influence consumers |
| Briefing | `fnc_createMissionBriefing` + `fnc_getBriefingFragments` | Composes title/objective/ROE/targets from fragment + entity/object archetypes |
| Compound Markers | `fnc_drawCompoundMarkers` | Contact_circle4 + alpha-numeric dot markers, scale-aware |
| Interaction Handler | `fnc_addInteractionHandler` | addAction wiring for interactable objects; populates intelTokens on active mission |
| AO Population | `fnc_populateAO` | Multi-faction: garrison → guards → vehicles → patrols. Auto-extracts assets if not in mission config |
| Presence Manager | `fnc_initPresenceManager` / `fnc_activatePresenceZone` / `fnc_despawnPresenceZone` | World simulation around the player: 8s tick state machine (DORMANT→ACTIVATING→ACTIVE→PAUSED→DESPAWNING), civilians, base/outpost/camp/town zones + microzones (industrial / isolated compound / infrastructure / agricultural), contested skirmishes, indoor garrisons, mission AO arbitration, budget cap, instrumentation. See `.crush/presence-manager.md`. Sprint D.5 + E.1 shipped. |
| Roving Manager (Sprint E) | `fnc_initRovingManager` / `fnc_rovingSpawnAir` / `fnc_rovingSpawnGround` / `fnc_rovingSpawnFoot` / `fnc_rovingSpawnBoat` / `fnc_rovingGroundPatrolLoop` / `fnc_rovingDespawnSweep` / `fnc_resolveRovingHotspots` | Sibling subsystem to presence — ambient air (rotary + fixed-wing, transit/loiter mix) + ground (motorized/mechanized) + foot patrols + boats. Own tick (8s, phase-offset 4s), own worker, own per-type budget (3 rotary + 2 fixed-wing + 4 ground + 2 foot + 2 boat concurrently). Nearest hotspot to player determines side / faction (opFor territory → opFor rovers); spawn geometry is independent of hotspot location. Boats silently no-op on inland maps via `surfaceIsWater` check. AWARE + disableAI AUTOCOMBAT (ambient). |
| Microzone Projection | `fnc_resolveMicrozoneProjection` | Shared helper: reads precomputed nearest-controller data + handler's `military` block, returns guard/patrol chance based on `influence × distance-falloff × typeMultiplier`. Drives "controlling faction projects outward into surrounding compounds" gradient. |
| Anchored Guard / Patrol | `fnc_setupAnchoredGuard` / `fnc_setupAnchoredPatrol` | Lightweight cluster + patrol helpers for microzones. Guard = SENTRY waypoint + combat activation. Patrol = BIS_fnc_taskPatrol, PATH stays enabled (dyn-sim handles dormant cost). Both yield via `uiSleep 0.1` per createUnit. `garrison_light` skill profile. |
| Civilians | `fnc_setupCivilians` | Wandering civilian peds with CARELESS waypoints, cached classname pool from `DSC_factionData.civilians.manPool`; accepts weighted `classMix` for tag-driven flavor |
| Civilian Mix Resolver | `fnc_resolveCivilianMix` | Maps location tags + primaryFunction → weighted resolver-key mix for `setupCivilians` |
| Indoor Garrison | `fnc_setupGarrison` / `fnc_setupLightMilitaryGarrison` | Anchor + satellite buildings, units placed at building positions; light-mil wrapper drives populatedArea indoor encounters (combat-activated, `garrison_light` skill) |
| Contested Skirmish | `fnc_setupContestedSkirmish` | West-side opposing patrol on contested zones — east + west naturally hostile, engagement on contact |
| Yielding Spawner | `fnc_spawnGroupYielding` | Drop-in for `BIS_fnc_spawnGroup` with `uiSleep` between unit creates to spread the cost across frames |
| Vehicles | `fnc_setupVehicles` / `fnc_setupVehiclePatrol` | Parked vehicles near garrison + motorized road patrols |
| Static Defenses | `fnc_setupStaticDefenses` | Military-only: towers, bunkers, static weapons with lookout fallback |
| Combat Activation | `fnc_addCombatActivation` | Units start frozen, activate on FiredNear EH |
| Commander's Tablet | `DSC_ui_fnc_openTablet` (Ctrl+Y) | Modal admin/debug UI. Mission Gen panel queues templates via `DSC_tablet_queueMission` CBA event; abort via `DSC_tablet_abortMission`. Server-side handlers in `fnc_initServerDebug`. |
| Mission Queue | `DSC_missionQueue` (array) + `DSC_missionAbortRequested` (bool) | Mission loop pulls queued template before falling back to random; abort flag breaks waitUntil and skips scoring. |

## SQF Conventions

- Functions: `DSC_core_fnc_<name>` (via CBA PREP_SUB macros)
- Hashmaps everywhere — locations, groups, missions, AO data are all hashmaps
- `getOrDefault` used extensively for safety
- Debug markers + spammy systemChats live behind `#ifdef DEBUG_MODE_FULL`
- **Use CBA log macros, never `diag_log`** (see `.crush/logging.md` for the full convention)
  - `ERROR(msg)` / `ERROR_n(msg, a1..aN)` — bad input, missing required data, unrecoverable. Always logs.
  - `WARNING(msg)` / `WARNING_n(...)` — degraded but operational (fallback, missing optional). Logs in `DEBUG_MODE_NORMAL` and above.
  - `INFO(msg)` / `INFO_n(...)` — init banners, mission START/SUCCESS/INCOMPLETE, "X initialized". Logs in `DEBUG_MODE_NORMAL` and above.
  - `LOG(msg)` / `LOG_n(...)` — per-event detail (per-zone, per-archetype, per-tick). Logs in `DEBUG_MODE_FULL` only.
  - `TRACE_n(msg, v1..vN)` — variable inspection on per-event detail. Logs in `DEBUG_MODE_FULL` only.
  - Drop the `"DSC: "` prefix — CBA macros prepend `[DSC] (component) LEVEL:` automatically.
  - Max `_8` suffix for all `_n` variants. For longer arg lists, build the string first: `private _msg = format [...]; LOG(_msg);`
  - Any macro arg containing an inline array literal (`getOrDefault ["k", v]`, `["a","b"] select X`, `_x getVariable ["k", d]`) MUST be hoisted to a `private _tmp = …;` first — HEMTT's preprocessor counts commas inside `[]` and miscounts macro args otherwise.
  - Files that use any log macro must `#include "..\..\script_component.hpp"` (or local `"script_component.hpp"` for subfolders that have one).
- Player-facing `systemChat` (mission feedback, base actions) stays unconditional. Developer-probe `systemChat` (zone counts, tick summaries, stats) gets gated behind `#ifdef DEBUG_MODE_FULL`.
- Debug markers (presence ELLIPSE state markers, scanLocations dot markers) are gated behind `#ifdef DEBUG_MODE_FULL`. Gameplay markers (base/outpost flag icons + danger zones, HALO drop, extraction LZ, compound markers) stay unconditional.

## Debug Modes

Set exactly **one** of these in `addons/main/script_mod.hpp`:

| Mode | Use case | What survives |
|---|---|---|
| `DEBUG_MODE_MINIMAL` | Live play / release | `ERROR()`, `ERROR_WITH_TITLE()`, player-facing systemChats, gameplay markers |
| `DEBUG_MODE_NORMAL`  | Playtest builds      | + `INFO()` + `WARNING()`, mission outcome systemChat |
| `DEBUG_MODE_FULL`    | Developer debug      | + `LOG()` + `TRACE_n()`, debug markers, per-tick instrumentation systemChats |

CBA preprocesses the disabled tiers to no-ops so live builds pay zero cost. Lower tiers are always subsumed (e.g. `DEBUG_MODE_FULL` implies `NORMAL` and `MINIMAL`).

## Faction Roles

| Role | Side | Purpose |
|------|------|---------|
| `bluFor` | west | Player faction |
| `bluForPartner` | independent | Partner forces (AAF, Gendarmerie, CDF) |
| `opFor` | east | Primary enemy |
| `opForPartner` | east | Enemy auxiliaries (militia, nationalist) |
| `irregulars` | independent | Insurgents, armed civilians |
| `civilians` | civilian | Neutral population |
| `environmentalActors` | civilian | IDAP, UN, contractors |

## Doctrine Tags (Group Classification)

Groups are tagged by the classifier for downstream filtering:

**Size**: `FIRETEAM`, `INFANTRY_SQUAD`, `PLATOON_ELEMENT`
**Weapons**: `ANTI_ARMOR`, `AT_TEAM`, `ANTI_AIR`, `AA_TEAM`, `WEAPONS_SQUAD`, `SUPPORT_BY_FIRE`, `SNIPER_TEAM`, `MORTAR_SECTION`, `INDIRECT_FIRE`
**Role**: `COMMAND_ELEMENT`, `MEDICAL_TEAM`, `ENGINEER_TEAM`, `SCOUT_RECON`, `VEHICLE_CREW`, `AIR_CREW`
**Mobility**: `FOOT`, `MOTORIZED`, `MECHANIZED`, `ARMORED`, `ARMOR`, `AIRBORNE`, `AIR_ASSAULT`, `AMPHIBIOUS`, `NAVAL`, `FIXED_WING`, `STATIC`, `GARRISON`
**Quality**: `ELITE`, `MILITIA`, `CONSCRIPTS`, `NIGHT_CAPABLE`
**Behavior**: `PATROL`

## Frame-Spike Avoidance (yield convention)

Any code path that spawns multiple units, vehicles, or large
quantities of objects in a single scheduler slot will cause a visible
frame stutter. The mod has a standing convention:

- **Use `fnc_spawnGroupYielding` instead of `BIS_fnc_spawnGroup`** for
  all AI group spawns. It walks the `CfgGroups` entry one unit at a
  time with `uiSleep 0.1` between `createUnit` calls so the renderer
  can interleave frames.
- **Insert `uiSleep` (not `sleep`) between repeated heavy ops** —
  `createUnit`, `createVehicle`, building-position iteration, large
  marker draws. The setup family already does this:
  `fnc_setupCivilians` (0.15), `fnc_setupGarrison` (0.1),
  `fnc_setupGuards` (0.15), `fnc_setupStaticDefenses` (0.1),
  `fnc_setupVehicles` (0.2), `fnc_setupMortarEmplacement` (0.2).
- **`uiSleep` vs `sleep`**: `uiSleep` is real-time and unaffected by
  `setAccTime`, making it correct for spreading per-frame cost.
  `sleep` is sim-time scaled — fine for game-logic delays, wrong for
  frame-spike avoidance (under 4× accelerated sim, a `sleep 0.1`
  becomes 25ms and no longer yields a frame).
- **Mass deletion** also spikes — `fnc_missionCleanup` uses
  `sleep 0.05` between deletions. Same pattern applies to any new
  cleanup code.
- **Worker pattern**: the presence manager's worker scope drains its
  activate/despawn queues one zone per cycle with a `uiSleep` between
  zones. Any new subsystem with bursty spawn work should follow the
  same single-cycle-with-yield design rather than a tight forEach.

When adding new spawn or teardown code: if it creates more than ~3
entities at once, it needs a yield. Validate at 1× sim speed (see the
gotcha below about `setAccTime`).

## Gotchas

- `CfgGroups` faction class names sometimes differ from `CfgFactionClasses` (e.g., `BLU_G_F` → `Guerilla`). Workarounds are in `fnc_extractGroups`.
- `editorSubcategory` reliability varies by mod (RHS excellent, CFP less so)
- Structure `buildingPos -1` returns empty array for non-enterable buildings — always check
- Combat activation uses `FiredNear` EH with cleanup after trigger
- All 5 initServer steps are active; mission loop is live
- The `jointOperationCenter` object is placed in each map's `mission.sqm` via Eden editor
- Airbase/airfield named locations are excluded from scanning — manually configured in 3den
- Player base markers (`player_base_*`) exclude structures and locations from automated systems
- `playerMainBase` global determines the 5km opFor-free safe zone
- HEMTT renames Eden markers (e.g. `player_base` → `player_base_0`) — use prefix matching
- Use `hemtt check` for SQF linting; HEMTT parser requires parens around unary commands in comparisons
- Use `select` instead of `if/then/else` for constant-value assignments (HEMTT L-S05 warning)
- `setFriend` manages east/independent diplomacy during missions, reset at cleanup
- Vehicle patrol dismount cycle is deferred — current implementation drives road loops only
- **Presence manager state machine** — `_activateQueue` and `_despawnQueue` must be mutated **in place** (`deleteAt`). Reassigning the local (`_q = _q - [_zone]`) creates a new array, breaks the worker's reference, and silently leaks units. Same for ACTIVATING→DORMANT: if entities already exist on the zone, route through DESPAWNING or you orphan them.
- **Presence manager handler dispatch** (Sprint A) — when adding new zone types, register a handler with `fnc_registerPresenceHandler`. Do not add branches to `fnc_activatePresenceZone`. See `.crush/presence-manager.md`.
- **Dynamic simulation is enabled globally** — `enableDynamicSimulationSystem true` in `fnc_initServer` Step 0. Category distances: Group=1500m, Vehicle=2000m, EmptyVehicle=500m, Prop=300m. Every presence-spawned group MUST opt in via `enableDynamicSimulation true` (already wired in setupCivilians, setupGarrison, setupPatrols, setupStaticDefenses, setupMortarEmplacement, setupVehicles, setupGuards, setupVehiclePatrol). Combat activation (FiredNear EH) is unaffected by dyn-sim state. NOTE: `setDynamicSimulationDistanceCoef` is a **global** setter (takes a class String, not a Group/Object); there is no per-entity coef in stock Arma — to vary AI ranges per role, tune the global category distances instead.
- **CBA log macro arg counting** — HEMTT's preprocessor counts commas inside `[]` as macro arg separators, even when nested inside `()`. Any inline array literal in a `LOG_n`/`INFO_n`/`WARNING_n`/`ERROR_n`/`TRACE_n` arg breaks the build with "function call with incorrect number of arguments". Hoist to a local first: `private _ct = count (_x getOrDefault ["units", []]); LOG_2("...", _id, _ct);`. Same trap for `["a","b"] select X`. For >8 args, use `private _msg = format [...]; LOG(_msg);`. See `.crush/logging.md`.

## Detailed System Docs

- `.crush/architecture.md` — Init flow, addon structure, data flow between systems
- `.crush/logging.md` — **Logging + debug mode reference**: CBA macro cheat sheet, three-tier mode policy, marker/systemChat gating, HEMTT macro-arg-count gotcha
- `.crush/faction-system.md` — Faction profiles, extraction pipeline, classification, doctrine tags
- `.crush/mission-system.md` — AO population, mission types, briefing, cleanup, combat activation
- `.crush/mission-generation.md` — Mission config system (template + resolver), profile population params
- `.crush/mission-archetypes.md` — **Raid system reference** (live as of April 2026): generic raid generator, entity/object archetypes, completion conditions, briefing fragments, configuration reference
- `.crush/presence-manager.md` — **Presence Manager reference** (live as of June 2026): world simulation around the player. State machine, zone types, instrumentation, perf findings, Sprint A/B/C plan, future Sprint D (structure-archetype zone types) and Sprint E (roving entities)
- `.crush/commander-tablet.md` — Commander's Tablet UI (Ctrl+Y), Standard/Advanced views, debug HUD, server queue/abort, dialog architecture
- `.crush/vehicle-systems.md` — Parked vehicles, vehicle patrols, dismount cycle design (deferred)
- `.crush/grand-vision.md` — High-level project goals and inspiration
- `.crush/ao_populous_overhaul.md` — Garrison/guard/patrol overhaul design, playtest data, skill profiles
- `.crush/roadmap.md` — What's done, what's next, design philosophy
