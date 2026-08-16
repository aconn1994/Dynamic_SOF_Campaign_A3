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
4b. `fnc_initBases` → eager population of player + military bases
4c. `fnc_initC2Network` → **communication layer.** Builds `DSC_c2Nodes` from influence data (base=COMMAND, outpost=RELAY, camp/town=OUTSTATION), precomputes link topology per faction comms archetype, assigns callsigns, wires signal sources (`EntityKilled` + client-fired relay), spawns a 10s tick (alert decay + roster hygiene + accountability + response dispatch). Must precede presence/roving so their group stamping lands. See `.crush/c2-network.md`.
4d. `fnc_initPresenceManager` → build zone registry from influence data (4 major zone types + 4 microzone types tag-dispatched from `_missionSites`), spawn worker + 8s tick loop. State machine populates the area around the player with civilians, military presence, contested skirmishes, anchored guards/patrols projected from controlling installations. See `.crush/presence-manager.md`.
4e. `fnc_initRovingManager` → sibling subsystem to presence (Sprint E). Five rover types: air (rotary + fixed-wing with transit/loiter mix), ground (motorized/mechanized road patrols), foot (infantry patrols), boats (coastal/water patrols, no-op on inland maps). Own 8s tick (phase-offset 4s from presence), own worker, own per-type budget (3 rotary + 2 fixed-wing + 4 ground + 2 foot + 2 boat). Nearest hotspot to player determines side/faction; spawn geometry independent of hotspot location. AWARE + `setCombatMode "GREEN"` + `disableAI "AUTOCOMBAT"` — ambient world, defends itself, does not hunt the player.
4f. `fnc_bftSnapshot` → Blue Force Tracker aggregator for the Commander's Tablet
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
| ~~Combat Activation~~ | **DOES NOT EXIST** | `fnc_addCombatActivation` is not implemented and not in `XEH_PREP.hpp` — only a stale comment references it. Presence guards/garrisons are **live from spawn**, not frozen. Verified August 2026. |
| Commander's Tablet | `DSC_ui_fnc_openTablet` (Ctrl+Shift+T) | Modal admin/debug UI. Mission Gen panel queues templates via `DSC_tablet_queueMission` CBA event; abort via `DSC_tablet_abortMission`. Server-side handlers in `fnc_initServerDebug`. Tabs: Mission Gen, BFT, **INTEL (C2 Radio Feed, F.4)**. |
| Mission Queue | `DSC_missionQueue` (array) + `DSC_missionAbortRequested` (bool) | Mission loop pulls queued template before falling back to random; abort flag breaks waitUntil and skips scoring. |
| C2 Network (Sprints F.1-F.4) | `fnc_initC2Network` / `fnc_c2StampGroup` / `fnc_c2Signal` / `fnc_c2ContactReport` / `fnc_c2NoiseEvent` / `fnc_c2Respond` / `fnc_c2ResponseRecall` / `fnc_c2ResponseQrf` / `fnc_c2ResolveNode` / `fnc_c2RaiseAlert` / `fnc_c2FeedAdd` / `fnc_c2InitSignalSources` / `fnc_getC2Archetypes` | Communication simulation. Node registry from influence data (base=COMMAND, outpost=RELAY, camp/town=OUTSTATION), link topology per faction comms archetype, stable phonetic callsigns, 10s tick (alert decay + roster hygiene + accountability + response evaluation). Every armed group stamped with `DSC_c2Parent` + deadlines + designated radioman. **Report timer is the core mechanic**: wipe a group before it transmits and no contact report goes out, but `SILENCE` still fires at its check-in deadline. Noise graded 75m (suppressed) → 3500m (vehicle kill). **F.3 dispatches responses**: recall (free, redirects existing groups) and QRF (real spawn + real travel), gated by `alert ladder ∩ tier capability` — beyond a node's reach nothing arrives at all. See `.crush/c2-network.md`. |
| C2 ISR + player-facing (Sprint F.4) | `fnc_c2IsrCoverage` / `fnc_c2IsrEntryTier` / `fnc_c2IsrBroadcast` / `fnc_c2Telegraph` / `fnc_c2ContactRegister` + `DSC_ui_fnc_panelRadio_*` | Makes the network perceivable. **Coverage tiers**: NONE / BASIC (player within 800m) / ENHANCED (ISR drone on station, weather-degraded radius) / FULL (F.5 SIGINT stub). Coverage is best-of {event position, node LKP, node position}. Live intercepted chatter via `systemChat`, throttled to 1 line per 2.5s. **Diegetic telegraphs, no coverage needed**: illum flare when a node hits RED, forced headlights when a QRF departs — both night-only and gated to 3km of a player. Tablet **Radio Feed** page on the INTEL tab: timestamped scrollback, per-source coloring, live coverage header, alerted-node strip, EARNED/ALL(DEBUG) filter. **Hostile contact fixes on the BFT**: SIGINT (radio DF on transmitting groups, ENHANCED-gated, 240s) + VISUAL (own-force observation, 90s) — snapshots that age, fade and expire, never live tracking. |

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
- **There is no combat-activation system** — `fnc_addCombatActivation` was documented for months but does not exist (not in `XEH_PREP.hpp`; the only reference is a stale comment in `fnc_setupAnchoredPatrol`). Presence guards and garrisons are live from the moment they spawn. Do not write code assuming units start frozen.
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
- **Aircraft spawn altitudes must be terrain-relative** — a desired flight altitude is *above ground*, but `setPosASL` and `addWaypoint` take *sea level*. Passing the raw value spawns the aircraft underground anywhere terrain exceeds it (most of the Altis interior for a 120m rotary). Always `(getTerrainHeightASL [x,y]) max 0` and add. The `max 0` matters: over water, terrain height is the sea bed. Also set velocity along the heading **after** `createVehicleCrew` — `createVehicle ... "FLY"` starts the aircraft moving but `setPosASL`/`setDir` don't rotate that momentum, and crew creation resets it.
- **`fnc_buildRoadRoute` returning `[]` means "retry", and a short route is a failure** — the nearest road to any position is frequently a stub (driveway, bridge ramp, isolated segment), so the walk tries several start candidates and backtracks out of dead ends. Critically, it refuses to return a route shorter than 25% of the requested distance: callers set a MOVE waypoint on the last point, and a degenerate route lands that waypoint where the vehicle already is, so arrival fires instantly and the patrol re-plans in place forever. Any new caller must treat `[]` as retry-with-a-new-direction, and must put a **timeout** on its arrival `waitUntil` — an unreachable destination otherwise hangs the patrol silently for the rest of the mission.
- **Presence manager state machine** — `_activateQueue` and `_despawnQueue` must be mutated **in place** (`deleteAt`). Reassigning the local (`_q = _q - [_zone]`) creates a new array, breaks the worker's reference, and silently leaks units. Same for ACTIVATING→DORMANT: if entities already exist on the zone, route through DESPAWNING or you orphan them.
- **Presence manager handler dispatch** (Sprint A) — when adding new zone types, register a handler with `fnc_registerPresenceHandler`. Do not add branches to `fnc_activatePresenceZone`. See `.crush/presence-manager.md`.
- **Presence zone `COMBAT` hold is driven by C2** — `fnc_c2Respond` sets `combatUntil` on the owning zone when it dispatches; the presence tick refuses `ACTIVE → DESPAWNING` while that deadline is in the future, so a QRF's parent garrison isn't deleted mid-response. The deadline expires on its own, so this can only delay teardown by a bounded window. Stat: `combatHeld`.
- **C2 init must run before presence + roving** — `fnc_initServer` STEP 4c builds `DSC_c2Nodes`; STEP 4d/4e stamp their spawned groups against it. Reordering silently drops all provenance (stamping no-ops when the registry is missing), and nothing errors.
- **C2 provenance is stamped at the dispatcher, not in setup functions** — `fnc_activatePresenceZone` stamps every armed group after the handler populates. Do NOT add stamping calls inside `fnc_setupPatrols`/`setupGuards`/etc; you'll double-register. New presence zone types get C2 coverage automatically. Rovers and `fnc_populateAO` stamp at their own spawn sites since they don't route through the dispatcher.
- **Civilian groups must never be C2-stamped** — microzone and populatedArea handlers append civilians to the same `zone.groups` array as armed groups. The dispatcher filters `side != civilian`; preserve that filter or the check-in scan will treat wandering farmers as missing patrols.
- **C2 roster hygiene must detect wiped groups before pruning them** — in the C2 tick, a group with all units dead but objects still present is a *destroyed element*; a group whose units are gone was *despawned by the presence manager*. Pruning first collapses the distinction and the player gets away with every clean wipe. Order is load-bearing.
- **🔴 `group createUnit` DOES NOT set the unit's side — always `joinSilent` after** — this was the root cause of every "same-faction AI killing each other" report. `createUnit` leaves the new unit on the side of its **`CfgFactionClasses` faction**, so spawning a Syndikat class (native GUER) into `createGroup [east]` produces `side _unit == GUER` while `side (group _unit) == EAST`. That mixed-side group is lethal: **AI hostility is evaluated observer-GROUP-side vs target-UNIT-side**, so east-group Syndikat fighters read their own GUER squadmates as enemy independents and open fire. A ten-man objective garrison wiped itself out in 90 seconds with no player present. Diagnostic signature is `side=GUER grpSide=EAST` / `SIDE!=EXPECTED UNIT!=GROUPSIDE`. **Every `createUnit` call must be followed by `[_unit] joinSilent _group;`** — wired in `fnc_spawnGroupYielding`, `fnc_setupGarrison`, `fnc_setupGuards`, `fnc_setupAnchoredGuard`, `fnc_setupAnchoredPatrol`, `fnc_setupStaticDefenses`, `fnc_setupMortarEmplacement`, `fnc_setupVehicles`, `fnc_setupCivilians`, `fnc_placeOnGround`, `fnc_placeInDeepBuilding`. This is also why FIA/CSAT objectives always worked and Syndikat/Looter objectives always fell apart: `OPF_G_F`/`OPF_F` are natively east, so there was no mismatch to trigger.
- **Side-validation passes must check UNIT sides, not group sides** — `createGroup [east]` always reports EAST, so `side _grp != _targetSide` can never catch the mismatch above. The realignment pass in `fnc_populateAO` ran for months, found nothing, logged nothing, and let mixed-side garrisons through. It now checks every unit against its own group and WARNs per offender.
- **⚠ `setCombatMode "BLUE"` means NEVER FIRE, not "hold fire"** — for "ambient patrol that won't start a fight but defends itself" the correct mode is **`GREEN`** (hold fire, defend only). All four rover spawners shipped `BLUE` *plus* `disableAI "TARGET"` *plus* `disableAI "AUTOTARGET"` — three independent locks on ever firing a shot — while their comments claimed "reacts only if fired upon". Playtest-confirmed result: a six-man CSAT patrol was wiped one man at a time over two minutes without returning fire. Keep `disableAI "AUTOCOMBAT"` (stays on its patrol route instead of hunting) but never disable targeting AI on anything expected to defend itself.
- **`side` and `rating` are MEANINGLESS on a dead unit** — the engine returns `side` = CIVILIAN and `rating` = 0 for any dead unit, regardless of what it was in life. An `EntityKilled` handler that reads `side _killed` will label every legitimate cross-side kill as friendly fire (this cost a full debugging round). Use `side (group _killed)` — the group object outlives the unit. Victim rating is not recoverable post-mortem.
- **⚠ Same-faction fratricide is the RATING system, not side resolution** — Arma flips a unit to **renegade** (hostile to every side including its own) once its `rating` falls below roughly -2000, and killing a friendly or a civilian costs a large penalty. `fnc_applySkillProfile` applies `addRating 1000000` to every unit it touches (it is the one path all DSC combat AI passes through), `fnc_setupPatrols` does the same for presence callers that never apply a skill profile, and `fnc_initPlayerLocal` covers `units group player` — the player's squad is Eden-placed, gets no other protection, and was measured at rating **-1040** after a single mission from civilian collateral. A renegade squadmate means the player's own squad turns on itself with no feedback explaining why.
- **Ambient military presence is only projected from opFor/contested installations** — `fnc_resolveMicrozoneProjection` zeroes the guard/patrol **chances** for bluFor-controlled zones, and `fnc_presenceHandlerPopulatedArea` gates its garrison block the same way. Friendly territory gets civilians only. This is not a tuning choice: the projection is side-blind, so bluFor zones spawned `bluForPartner` detachments on **independent**, which strict diplomacy makes hostile to east. With ~270 bluFor locations against ~580 opFor on a typical Altis seed, the presence manager was standing up two mutually hostile ambient armies across the whole terrain and they fought each other continuously with no player involvement. The old permissive `east setFriend [independent, 1]` had been hiding this by making both sides refuse to shoot. Override with `DSC_ambientFriendlyForces = true`. Real bluFor bases/outposts still garrison via `fnc_presenceActivateMilitary` — that is a handful of locations, not hundreds.
- **⚠ Microzone projection: suppress the CHANCES, never the STRENGTH** — `strength` is overloaded. Handlers read `strength <= 0` as **"this zone is unclaimed wilderness, roll a 65% EAST insurgent fireteam"** (`fnc_presenceHandlerIsolatedCompound`), and `strength > 0` as "a controller is in range" (`industrialSite`, `infrastructureNode`). Zeroing `strength` to quiet friendly territory therefore made it *louder*: bluFor compounds stopped getting independent detachments and started getting 4-5 man **east** patrols at 65% instead of ~10%, ~17 hostiles inside 1.2km of the player's west base. Signature in the RPT is `str=0.00 gC=0.00 pC=0.00` immediately followed by `setupAnchoredPatrol ... side=EAST`. Zero the chances and leave `strength` truthful; a `suppressed` flag is exposed for observability.
- **C2 node callsign rosters can span kilometres** — `fnc_c2ResolveNode` is reach-aware, and a COMMAND node's reach is large enough to claim both a mission objective and microzones near the player base simultaneously. All those groups then draw `Alpha 1-N` callsigns from one roster, so a rear-area firefight is indistinguishable from objective traffic in the radio feed. When debugging C2, cross-reference the **grid** in the report line, not the callsign.
- **Entity archetype `unitClassResolver` keys must exist in `fnc_resolveEntityClass`** — a typo'd key hits the `default` branch and silently returns the caller's literal fallback, which was `"O_officer_F"`. That is how a Syndikat objective got a CSAT officer as its HVT. Two shipped archetypes had this (`FINANCIER`→`"formal"`, `BOMBMAKER`→`"scientist"`; correct keys are `civilian_suit` / `civilian_labcoat`). The unknown-resolver branch now ERRORs and degrades to a unit promoted from the target faction, so the failure is loud and the mission stays faction-coherent. Valid keys: `officer`, `civilian`, `civilian_suit`, `civilian_labcoat`, `civilian_worker`, or a literal classname.
- **HVT classes are promoted from the target faction, never hardcoded** — `fnc_resolveEntityClass` "officer" falls back to a leadership-keyword unit from the faction's own man pool, then a plain rifleman, before ever touching the caller's literal fallback. Irregular factions (Syndikat, Looters, FIA) have no "officer" class at all, so this path is the normal case, not the exception.
- **The persistent ISR UAV must keep AUTOCOMBAT disabled** — the default class `B_UAV_02_dynamicLoadout_F` is an *armed* west Sentinel. With autocombat live it prosecutes the objective by itself on arrival, starting the firefight before the player is near the AO and firing unprompted contact reports into C2. `setCaptive true` does not prevent this — captive changes how others treat the drone, not whether it engages. The posture block in `fnc_persistentUAV` was found commented out; it must stay enabled.
- **Faction profile roles are cast by BEHAVIOUR, not by config side** — `bluForPartner` means "armed ally that fights alongside the player", and everything listed there spawns as a live combatant at every friendly-held location on the map. Keep it small. Insurgent/criminal factions belong in `irregulars` even when their config side is independent (Syndikat was miscast as `opForPartner` and became eligible to garrison military outposts). Police and peacekeepers belong in `environmentalActors`, not a partner role (Gendarmerie and the RHS UN faction were both miscast this way).
- **Role sides are normalized once at profile selection, in `fnc_initServer`** — the loop immediately after the profile auto-detect rewrites every role's `side` through `fnc_resolveRoleSide` before the profile is published to `missionNamespace`. Because `fnc_initFactionData` copies `side` verbatim onto role data, this makes both runtime sources (`factionProfileConfig` and `DSC_factionData`) correct by construction, and **all ~10 downstream read sites need no conversion**. The rule: INDEPENDENT is reserved for `bluForPartner`, so hostile roles (`opFor`/`opForPartner`/`irregulars`) all collapse onto **east**. Do NOT re-introduce per-site resolution, and do not trust the `side` values written in the profile literals — they are inputs to the normalizer, nothing more. See `.crush/faction-sides.md`.
- **Side diplomacy is set once in `fnc_initPresenceManager`, symmetrically, and never mutated per-mission** — `setFriend` is directional and global. The old per-mission calls in `fnc_populateAO`/`fnc_cleanupMission` left the matrix in a different state after mission one and caused enemies to engage while the player's squad held fire. Those calls are removed; do not re-add them.
- **C2 decision latency is an absolute deadline (`responseDueAt`), not elapsed-since-alert** — cleared only on a real alert-level change. Gating on `alertSince` meant sustained contact refreshed the clock faster than it advanced and nodes never dispatched.
- **C2 signal grades carry an `echo` window** — a repeat of the same signal type at the same node inside the window records LKP + feed but does NOT re-raise or re-walk relays. Without it, fifteen groups in one firefight produce fifteen full propagation passes. `SILENCE` and accountability signals are never echoed.
- **C2 `SILENCE` deadlines must be clamped forward** — a group that dies just after its check-in came due would otherwise schedule SILENCE in the past and fire it the same tick. Past-due rolls to the next check-in cycle.
- **C2 `SILENCE` is scheduled at the moment of the wipe, in `fnc_c2ContactReport`** — NOT from the tick's wiped-group scan. That scan needs bodies + group object to still exist, and `fnc_rovingDespawnSweep` deletes a wiped foot rover within ~8s, so the tick loses the race and the SILENCE is silently dropped. The tick branch is a backstop for groups that die without ever entering contact. Deadline snapshots are `[callsign, lastPos, dueTime]` so they survive deletion.
- **C2 `SILENCE` is deferred to the element's check-in deadline, not raised on death** — raising it immediately made a clean silent wipe worth ~2 seconds and defeated the report timer. Don't "fix" the delay.
- **C2 noise must exclude engine-bookkeeping "vehicles"** — a deployed parachute is `ParachuteBase` → `Air` → `AllVehicles` and is *destroyed* on landing, so it graded as a 3500m `VEHICLE_KILL` and made every HALO insertion alert the whole area. `fnc_c2InitSignalSources` keeps a `_silentClasses` exclusion list; add to it rather than special-casing downstream.
- **C2 RTB deadlines are only for deployed roles** — `DSC_c2RtbEta` is stamped only for `rover`/`patrol`. A garrison is not due back anywhere; stamping it made every static defender in a city fire `OVERDUE_RTB` in one burst a fixed interval after zone activation.
- **C2 accountability signals must not refresh the alert decay clock** — signal grades carry a `refresh` flag. Live sensory events (contact/explosion/gunfire) refresh so sustained fighting holds an area hot; `MISSED_CHECKIN`/`OVERDUE_RTB`/`SILENCE` do not, or a wave of bookkeeping re-arms the timer forever and the node never returns to GREEN.
- **C2 check-in has a success path** — a live group at its deadline reports OK and reschedules silently. `MISSED_CHECKIN` fires only when a group *cannot transmit* (radioman dead). Without the success path every healthy garrison alerts forever on a 600s cycle.
- **C2 responders must have combat AI re-enabled** — roving spawns `disableAI` AUTOCOMBAT/TARGET/AUTOTARGET to stay ambient. `fnc_c2ResponseRecall` and `fnc_c2ResponseQrf` re-enable them; without that a QRF drives to the objective and refuses to engage.
- **C2 mounted responses must not use LAMBS `taskHunt`** — it starts a search pattern immediately, so vehicles mill near their spawn instead of travelling. Mounted elements get a plain move-and-engage order (also what lets the player see a response coming). Also note `taskHunt`'s position arg is index **4**, not 2, and it must be `spawn`ed.
- **Mounted QRF must use `BIS_fnc_spawnGroup`, not `fnc_spawnGroupYielding`** — the yielding spawner only does `createUnit` and cannot create vehicles. The single-frame burst is accepted because a QRF is a rare player-triggered event; foot QRF still uses the yielding spawner.
- **Dispatched QRFs must be deleted at mission cleanup** — they spawn outside the presence budget and no zone tracks them, so nothing else cleans them up and they'd survive into the next mission as orphans.
- **⚠ SQF binary operators bind LOOSER than arithmetic — parenthesise `distance2D` before dividing** — `a distance2D _pos / 100` parses as `a distance2D (_pos / 100)`, which divides a position **array** by a number and throws `Error /: Type Array, expected Number`. Write `((a distance2D _pos) / 100)`. This shipped in the F.4 Radio Feed panel and spammed the RPT every 2s refresh. Applies to `distance`, `distance2D`, `getDir`, `vectorDistance` — any binary command feeding an arithmetic expression.
- **C2 signal absence has three independent causes — don't conflate them** — when nothing alerts, check which gate fired: (1) **suppressed fire** produces *no signal at all* (`SUPPRESSED` has `signal = ""`, so `fnc_c2NoiseEvent` exits before even incrementing `noiseEvents`); (2) **no node in reach** means groups are never C2-stamped, so `fnc_c2ContactReport` exits on the empty `DSC_c2Parent` and the report timer never starts — look for `No C2 node in reach` / `C2 stamped 0 groups (N isolated)`; (3) **the report timer actually beat** — the only one that logs `REPORT SUPPRESSED`. A silent engagement is usually (1) or (2), not (3). Testing the report timer requires an objective *with* a node in reach and *unsuppressed* fire.
- **⚠ Enemy BFT markers are FIXES, not tracking — every one must age and expire** — `fnc_c2ContactRegister` records hostile contacts from exactly two sources, each mapping to a real capability: **SIGINT** (radio direction finding on a group that actually transmitted a contact report — gated at ENHANCED coverage evaluated *once at the moment of emission*, TTL 240s) and **VISUAL** (own-force observation via engine `knowsAbout >= 0.5` within 1500m, TTL 90s, refreshed while observed). The marker sits where the element *was*; it never follows. The label states the age (`ALPHA 1-3 SIGINT 2m`), the icon is `o_unknown` not a NATO type symbol, and alpha fades to 0.35 across the TTL. Do NOT add a source that reveals unobserved, silent enemies — that turns the feature into a wallhack and destroys the report-timer mechanic, whose whole point is that a group wiped before it transmits never appears on the map at all.
- **⚠ ISR coverage is best-of {event position, node LKP, node position} — never node-only** — a C2 node is usually kilometres from the event it is reporting, so grading coverage at the node silently withheld firefights happening *next to the player*. Playtest signature: an opFor-vs-AAF engagement 200m away produced a full set of INTERCEPT feed lines that never reached the intel screen because the reporting node was 3km off. `fnc_c2IsrEntryTier` is the single shared resolver for this and **both** read surfaces (`fnc_c2IsrBroadcast` live chat, `fnc_panelRadio_refresh` tablet) must call it — computing coverage separately makes the two surfaces disagree about what the player knows. Feed entries carry `eventPos` for this; pass it from any new `fnc_c2FeedAdd` call site that has a position.
- **`fnc_presenceHandlerPopulatedArea` has THREE independent military blocks** — the `_wantMil` controlling garrison, the ungated irregular indoor garrison, and the military overlay patrol. All three must be considered when changing ambient-force policy; gating one is not enough. The irregular garrison is *deliberately* ungated (EAST insurgents can appear in any town, including friendly ones — good content, the player deals with it). The other two are gated to opFor/contested unless `DSC_ambientFriendlyForces` is set, because a bluFor town running both the overlay *and* the irregular garrison spawned a mutually hostile `EAST` + `GUER` pair in one village that fought with no player involvement. Diagnostic signature: `[presenceZone] ... ctrl=bluFor -> sides=["EAST","GUER"]`.
- **`setCaptive true` makes `side _unit` report CIVILIAN** — regardless of the unit's group. Hostages and surrendered HVTs correctly read `side=CIV grpSide=EAST`; that is not the `createUnit` side-inheritance defect. Any side-validation code must exclude captives or it produces false positives.
- **C2 player-facing delivery hooks at `fnc_c2FeedAdd`, not at call sites** — every C2 line already flows through that one function, so `fnc_c2IsrBroadcast` is called from its tail and all feed writers became player-facing with zero edits. New signal types get coverage automatically. Do NOT add per-call-site chatter. — every C2 line already flows through that one function, so `fnc_c2IsrBroadcast` is called from its tail and all six feed writers became player-facing with zero edits. New signal types get coverage automatically. Do NOT add per-call-site chatter.
- **C2 `LOST` feed lines must never reach the player** — a transmission that did not arrive is exactly the information the report timer exists to withhold. Showing `(not received)` tells the player they got away with a clean wipe, which is the *reward* for good play, not a status readout. Suppressed in `fnc_c2IsrBroadcast` and in the tablet's `EARNED` filter; visible only under `ALL (DEBUG)`.
- **C2 coverage is filtered at READ time in two places against one rule** — `DSC_c2Feed` stores everything the enemy said, including unearned lines. The live surface filters in `fnc_c2IsrBroadcast`, the tablet scrollback in `fnc_panelRadio_refresh`; both compare `fnc_c2IsrCoverage` at the node's position against the entry's `grade`. Keep them consistent or the two surfaces disagree about what the player knows. Writing pre-filtered buffers instead would make the omniscient debug view impossible.
- **C2 telegraphs are diegetic and deliberately ungated** — if the player needed a drone to understand why they were being flanked, the system would be invisible without one. Illum flare on RED transition (transition only — a node holding RED must not spam flares) and forced vehicle headlights on QRF departure. Both night-only (`sunOrMoon > 0.35` aborts) and gated to 3km of a player, or dozens of simultaneous node alerts light up the whole terrain.
- **C2 live chatter is throttled to 1 line / 2.5s** — `systemChat` has no rate limit and a busy network will bury the player's own squad and mission feedback. Dropped lines remain in the tablet scrollback, which is the whole reason that page exists.
- **C2 callsigns must be globally unique** — assigned in a second pass after all nodes are built, from one running index sorted by (faction, tier). Per-faction counters produced multiple nodes named `BRAVO` and feed lines reading `BRAVO -> BRAVO`.
- **C2 signal sources are server-side handlers, not per-unit EHs** — one `EntityKilled` mission EH plus one `Fired` EH per player. Do not add per-unit `FiredNear` handlers for C2 purposes; the presence manager can have 150 units standing at once. Suppressor state must be read client-side (`fnc_initPlayerLocal`) because muzzle accessory data is unreliable for remote units.
- **`exitWith` inside a `while` body is avoided in C2 code** — ambiguity about whether it breaks the loop or returns from the function makes post-loop accounting unreliable. `fnc_c2ContactReport` uses an explicit `_running` flag instead; follow that pattern in F.3+.
- **Dynamic simulation is enabled globally** — `enableDynamicSimulationSystem true` in `fnc_initServer` Step 0. Category distances: Group=1500m, Vehicle=2000m, EmptyVehicle=500m, Prop=300m. Every presence-spawned group MUST opt in via `enableDynamicSimulation true` (already wired in setupCivilians, setupGarrison, setupPatrols, setupStaticDefenses, setupMortarEmplacement, setupVehicles, setupGuards, setupVehiclePatrol). NOTE: `setDynamicSimulationDistanceCoef` is a **global** setter (takes a class String, not a Group/Object); there is no per-entity coef in stock Arma — to vary AI ranges per role, tune the global category distances instead.
- **CBA log macro arg counting** — HEMTT's preprocessor counts commas inside `[]` as macro arg separators, even when nested inside `()`. Any inline array literal in a `LOG_n`/`INFO_n`/`WARNING_n`/`ERROR_n`/`TRACE_n` arg breaks the build with "function call with incorrect number of arguments". Hoist to a local first: `private _ct = count (_x getOrDefault ["units", []]); LOG_2("...", _id, _ct);`. Same trap for `["a","b"] select X`. For >8 args, use `private _msg = format [...]; LOG(_msg);`. See `.crush/logging.md`.

## Detailed System Docs

- `.crush/campaign-overhaul.md` — **⭐ MVP master plan** for the deployment / mission-series / simulated-intel / dynamic-briefing / basing overhaul. Full scope-of-vision reference: unifying data model, the six foundational seams to build "now", per-pillar variety banks, phased build order, integration landmines. Read before any campaign-layer work.
- `.crush/architecture.md` — Init flow, addon structure, data flow between systems
- `.crush/logging.md` — **Logging + debug mode reference**: CBA macro cheat sheet, three-tier mode policy, marker/systemChat gating, HEMTT macro-arg-count gotcha
- `.crush/faction-system.md` — Faction profiles, extraction pipeline, classification, doctrine tags
- `.crush/faction-overhaul.md` — **⚠ READ FIRST for anything side-related.** Plan A (two-pole model, approved), engine ground truth on sides/independent/setFriend, Phase 0 instrumentation + how to read `DSCDIAG` output, known landmines, order of work
- `.crush/faction-sides.md` — Side allocation history: the three failed diagnoses and what each one actually fixed. Context only; Plan A supersedes the model described there
- `.crush/faction-sides.md` — **Side allocation model** (resolved): why five roles share three engine sides, the normalize-once-at-`initServer` fix, diplomacy matrix, validation steps
- `.crush/faction-autoscan.md` — **Faction autoscan** (designed, deferred behind C2 F.4-F.5): inverted CfgGroups walk to kill the desync table, faction catalog + role scoring heuristics, tablet Campaign Setup panel
- `.crush/mission-system.md` — AO population, mission types, briefing, cleanup, combat activation
- `.crush/mission-generation.md` — Mission config system (template + resolver), profile population params
- `.crush/mission-archetypes.md` — **Raid system reference** (live as of April 2026): generic raid generator, entity/object archetypes, completion conditions, briefing fragments, configuration reference
- `.crush/presence-manager.md` — **Presence Manager reference** (live as of June 2026): world simulation around the player. State machine, zone types, instrumentation, perf findings, Sprint A/B/C plan, future Sprint D (structure-archetype zone types) and Sprint E (roving entities)
- `.crush/c2-network.md` — **C2 Network + ISR** (Sprints F.1-F.3 shipped, F.4-F.5 designed): communication simulation. Node registry, faction comms archetypes, report timer, signal propagation with last-known-position, response ladder, ISR as read-access to the enemy network, Radio Feed, counterplay
- `.crush/faction-sides.md` — **⚠ Side allocation model (ACTIVE REGRESSION)**: why independent is double-booked, the `fnc_resolveRoleSide` convention, the unfinished migration, exact list of remaining call sites, and two options to resolve
- `.crush/commander-tablet.md` — Commander's Tablet UI (Ctrl+Y), Standard/Advanced views, debug HUD, server queue/abort, dialog architecture
- `.crush/vehicle-systems.md` — Parked vehicles, vehicle patrols, dismount cycle design (deferred)
- `.crush/grand-vision.md` — High-level project goals and inspiration
- `.crush/ao_populous_overhaul.md` — Garrison/guard/patrol overhaul design, playtest data, skill profiles
- `.crush/roadmap.md` — What's done, what's next, design philosophy
