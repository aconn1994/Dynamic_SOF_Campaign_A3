# Roadmap — DSC

*Updated June 2, 2026*

## Phase 1: Mission Area Generation — COMPLETE

### Done
- [x] **Location Scanner** (`fnc_scanLocations`) — anchor-based with orphan recovery: assigns structures to named locations, clusters orphaned structures at 150m, functional tagging (residential/commercial/industrial/agricultural/medical/religious/infrastructure/port/airport/law_enforcement), non-occupiable structure scanning, outputs location hashmaps directly
- [x] **Structure Classification** (`fnc_getStructureTypes`) — curated main/side/military structure lists + functional categories with occupiable/non-occupiable sublists + reverse lookup hashmaps for O(1) scanning
- [x] **Map Structures** (`fnc_getMapStructures`) — engine-level spatial query wrapper
- [x] **Group Classifier** (`fnc_classifyUnit` → `fnc_classifyGroup` → `fnc_classifyGroups`) — full doctrine tag system with confidence scoring
- [x] **Faction Extraction** (`fnc_extractGroups`, `fnc_extractAssets`, `fnc_initFactionData`) — mod-agnostic pipeline from CfgGroups/CfgVehicles
- [x] **Guards** (`fnc_setupGuards`) — exterior placement at building fronts: road-anchored (urban) / building-facing / cluster-outward (fallback). Individual units from faction pool, cqb_baseline skill profile
- [x] **Static Defenses** (`fnc_setupStaticDefenses`) — military-only: towers, bunkers get static weapons (HMG/GMG/AT/AA) or lookout soldiers with open-sky checks. Separated from guard logic.
- [x] **Garrison** (`fnc_setupGarrison`) — individual groups per unit for independent CQB behavior. Unit classes from faction pool (weighted by template composition). Structure-count scaling table, per-building caps (main: 3, side: 2), cqb_baseline skill profile
- [x] **Foot Patrols** (`fnc_setupPatrols`) — dynamic radius, special group chance (AT/AA teams)
- [x] **Parked Vehicles** (`fnc_setupVehicles`) — faction vehicles near garrison clusters, armed get gunner with combat activation
- [x] **Vehicle Patrols** (`fnc_setupVehiclePatrol`) — motorized/mechanized groups drive road loops, hold at waypoints, combat interrupt releases AI (dismount cycle deferred)
- [x] **Parking Position Finder** (`fnc_findParkingPosition`) — roadside scoring with wall openings + compound proximity, flat-ground fallback
- [x] **Road Route Builder** (`fnc_buildRoadRoute`) — walks road network graph, avoids U-turns, thins waypoints
- [x] **Static Emplacements** — HMG, GMG, AT, AA placed in guard structures with open-sky checks
- [x] **AO Population** (`fnc_populateAO`) — multi-faction: target faction at objective, area faction ambient presence (areaPresenceChance × areaInfluence per slot)
- [x] **Kill/Capture Mission** (`fnc_generateKillCaptureMission`) — HVT placement with bodyguards, SOF raid-style compound intel markers
- [x] **Mission Briefing** (`fnc_createMissionBriefing`) — intel-style with fuzzy troop estimates and threat warnings
- [x] **Mission Cleanup** (`fnc_cleanupMission`) — full teardown of units, vehicles, groups, markers; resets side diplomacy
- [x] **Combat Activation** (`fnc_addCombatActivation`) — FiredNear trigger with reaction delay
- [x] **Patrol Convergence** (`fnc_convergePatrols`) — QRF behavior when combat starts
- [x] **Mission Selection** (`fnc_selectMission`) — weighted location selection, target vs area faction, influence-aware
- [x] **Mission Generation** (`fnc_generateMission`) — orchestrator: populate → objective → briefing → QRF → skill → UAV
- [x] **Mission Loop** — initServer Step 5: select → generate → wait for debrief → score → update influence → cleanup → repeat
- [x] **HALO Jump** — map-click group insertion
- [x] **Helo Transport/Extraction** — request pickup from anywhere
- [x] **Persistent Medic** — recruitable companion for playtesting
- [x] **AI Skill Profiles** (`fnc_applySkillProfile`, `fnc_getSkillProfile`) — cqb_baseline/moderate/hard/realism. cqb_baseline tuned for garrison/guard CQB (low accuracy, moderate spotting, creates reaction window)
- [x] **Persistent UAV** — always-available drone support
- [x] **ACE Integration** — medical system detection, unconscious handling
- [x] **Player Down/Revive** — works with ACE or vanilla damage model
- [x] **Multi-Map Support** — Altis, Livonia, Malden, Stratis, Tanoa all have mission folders

### AO Population Overhaul
- [x] **Garrison overhaul** — individual groups per unit, unit class pool from templates, structure-count scaling, config block for all tunable parameters
- [x] **Guard overhaul** — exterior road-anchored placement, separated static defenses into own function
- [x] **Marker overhaul** — nearby building clearance radius (30m) around garrison clusters, no overlap between cluster markers
- [x] **populateAO asset extraction** — auto-extracts faction assets if mission config doesn't provide them

### Deferred
- [ ] **Vehicle patrol dismount cycle** — drive → staggered dismount → foot patrol → staggered remount → repeat. Architecture exists in `fnc_vehiclePatrolLoop` but AI mount/dismount behavior needs refinement. Design doc in `.crush/vehicle-systems.md`

## Phase 2: Faction & Map Layer — IN PROGRESS

### Influence System
- [x] `fnc_initInfluence` — tiered military occupation (base/outpost/camp), campaign profiles
- [x] `fnc_updateInfluence` — mission result feedback loop with ripple propagation
- [x] **Wire influence into initServer** — Steps 1-4 active, Step 5 is live mission loop
- [x] **Influence debug markers** — type-specific icons + color-coded area ellipses (commented out, available)
- [x] **Military tier system** — bases generate influence, outposts are satellites, camps are contention points
- [x] **5km safe zone** — no opFor bases near playerMainBase marker
- [x] **Wire influence into mission selection** — `fnc_selectMission` filters by faction control, weights by distance
- [x] **Faction-aware AO population** — multi-faction model: target at objective, area faction ambient
- [x] **Base/outpost map markers** — faction flag textures from CfgFactionClasses via map Draw EH, 800m danger zones on bases
- [x] **Side diplomacy** — `setFriend` ensures opFor + irregulars cooperate during missions, reset at cleanup
- [ ] **Special zones** (logistics, factories, resources, ports) owned by faction

### Base Initialization (Design: `.crush/base-initialization.md`)
- [x] **`fnc_initBases` + `fnc_setupBase`** — orchestrator + per-base worker, base registry pattern
- [x] **Player base guards** — `fnc_setupStaticDefenses` for tower statics + `fnc_setupGuards` for entry guards
- [x] **Player base helipads** — scan `player_base_1_heliport` marker, place transport helos on pads
- [x] **BluFor/OpFor base population** — iterate influence bases, side-appropriate guard configs + vehicles
- [ ] **Transport helo from pad** — modify `fnc_spawnTransportHelo` + `fnc_requestExtraction` to use base registry (Sprint 2)
- [ ] **Helo return to base** — `fnc_returnHeloToBase`, post-mission fly-back + crew despawn (Sprint 4)
- [ ] **QRF from opFor bases** — QRF spawns from nearest opFor base in registry (Sprint 4)
- [ ] **Dynamic simulation** — all base entities get `triggerDynamicSimulation true` for zero idle cost

### Faction Configuration
- [ ] **Player-selectable factions** — currently hardcoded vanilla/RHS profiles
- [ ] **Civilians** — neutral population spawning
- [ ] **Environment actors** — IDAP, UN, contractors with presence

### Mission Markers
- [x] **SOF raid-style intel** — Contact_circle4 on garrison cluster anchors, black dot markers with alpha-numeric callouts (A1, A2, B1...)
- [x] **Scale-aware marking** — large locations (cities/towns) mark only buildings within 30m of anchor; small/isolated locations mark all buildings in cluster

## Phase 3: Intel & Campaign Loop — PLANNED

### Intel System
- [ ] Intelligence shapes follow-on missions
- [ ] Intel objects discoverable at mission sites
- [ ] Intel as currency — every location has potential intel

### Map Influence Dynamics
- [x] Mission results shift influence via `fnc_updateInfluence`
- [ ] Dynamic front lines from cumulative results (visual)

### Mission Config System
- [x] **`fnc_resolveMissionConfig`** — template-based resolver: accepts partial config, fills from profile → influence → defaults
- [x] **`fnc_getMissionProfiles`** — AFO (isolated/light/no QRF) and DA (fortified/heavy/fast QRF) presets
- [x] **`fnc_selectMission` refactor** — thin wrapper, accepts optional template, delegates to resolver
- [x] **Template fields** — type, missionProfile, targetFaction, targetRoles, requiredTags, excludeTags, regionCenter/Radius, minDistance/maxDistance, density, areaPresenceChance, qrfEnabled, qrfDelay
- [x] **Profile population params** — garrisonAnchors, garrisonSatellites, guardCoverage, guardsPerBuilding, patrolCount, maxVehicles, vehicleArmedChance flow through to populateAO
- [x] **Priority cascade** — explicit template > profile defaults > auto-generated
- [x] **Extra field passthrough** — template fields not consumed by resolver carry through to downstream

### Mission Archetype Refactor — COMPLETE
*Design doc: `.crush/mission-archetypes.md`*

Mission types are configurations, not generators. A "raid" is a population pattern; what makes it kill/capture vs hostage rescue vs supply destroy vs intel gather is just **entities placed**, **objects placed**, and **completion condition**. All three are data.

- [x] **Generic Raid Generator** (`fnc_generateRaidMission`) — consumes entity/object/completion config; iterates with count expansion; dispatches placement by archetype key
- [x] **Entity Archetype System** (`fnc_getEntityArchetypes` + `fnc_resolveEntityClass`) — OFFICER, BOMBMAKER, HOSTAGE; resolver handles `officer`/`civilian`/`civilian_suit`/`civilian_labcoat`/literal classnames
- [x] **Object Archetype System** (`fnc_getObjectArchetypes` + `fnc_placeObjects`) — INTEL_LAPTOP, INTEL_DOCUMENTS, SUPPLY_CACHE, BOMB_PARTS, WEAPONS_CRATE
- [x] **Placement Strategy Library** — `fnc_placeInDeepBuilding`, `fnc_placeOnGround` (sit/kneel/down), `fnc_placeInterior`, `fnc_placeOutdoorPile`
- [x] **Completion Condition System** (`fnc_getCompletionTypes` + `fnc_evaluateCompletion`) — KILL_CAPTURE, ALL_DESTROYED, ANY_INTERACTED, HOSTAGES_EXTRACTED, AREA_CLEAR; supports compound `completionExpr`
- [x] **Marker Library** (`fnc_drawCompoundMarkers`) — config-driven Contact_circle4 + alpha-numeric dots
- [x] **Briefing Fragment System** (`fnc_getBriefingFragments` + refactored `fnc_createMissionBriefing`) — composes title/objective/ROE/targets from fragments + entity/object archetype descriptions
- [x] **Mission Outcome Schema** (`fnc_buildMissionOutcome` → `DSC_lastMissionOutcome`) — standardized result hashmap for series/influence/next-mission consumers
- [x] **Interaction Handler** (`fnc_addInteractionHandler`) — addAction wiring for interactable objects; populates `intelTokens` array on the active mission
- [x] **3 New RAID Variants** — SUPPLY_DESTROY, INTEL_GATHER, HOSTAGE_RESCUE — each ~15 lines of config in `fnc_generateMission`, no new generator code
- [ ] **Eden Composition Integration** (deferred force-multiplier) — archetype `compositionPath` field for hand-crafted scenes

### Commander's Tablet — Phase A COMPLETE
*Design doc: `.crush/commander-tablet.md`*

A modal admin/debug UI bound to Ctrl+Y for queueing missions and tweaking
parameters live without restarting Arma. Designed as a debug tool first;
will grow into the in-mission commander interface (supports/BFT/squad/intel).

- [x] **`addons/ui/` PBO** — separate addon, depends on main + core
- [x] **`DSC_Tablet` dialog** — top-level config class, modal createDialog target
- [x] **Standard view** — Type, Profile, Density, Faction, Min/Max distance, Anchor, QRF, Replace
- [x] **Advanced view toggle** — overlays Location/Population/Mission Feel sections
- [x] **Population sliders** — Veh Armed %, Area Pres %, Guard Cov % (snap to 10)
- [x] **Tag filters** — required/exclude tags via comma-separated text inputs
- [x] **`fnc_initServerDebug`** — DSC_missionQueue + DSC_missionAbortRequested globals, CBA event handlers
- [x] **`fnc_initPlayerLocalDebug`** — CBA keybinds Ctrl+Y (tablet) and Ctrl+Shift+F (debug HUD)
- [x] **Mission loop refactor** — spawned, pulls from queue before random, honors abort flag
- [x] **`skillProfile` template field** — generateMission now respects per-mission AI skill override
- [x] **Debug HUD overlay** — RscTitles cutRsc with FPS/state/counts/custom slot, CBA per-frame updater
- [x] **BIS-base inheritance** — `DSC_Rsc*` classes inherit from `RscButton`/`RscCombo`/etc., eliminating "missing required property" runtime errors
- [ ] **Bezel image** — temporarily removed; re-add when commissioned to fit UI
- [ ] **Phase B — Supports panel** — move flagpole actions onto tablet, add UAV control
- [ ] **Phase C — BFT/Squad/Intel panels** — live unit positions, squad commands, intel browser
- [ ] **Mission preset save/load** — store favorite playtest configs in profileNamespace

### Mission Series Framework (NEXT — foundation now in place)
- [ ] **`fnc_initMissionSeries`** — register a series of templates with branching logic
- [ ] **`DSC_activeSeries`** — mission loop checks active series before random generation
- [ ] **Series state hashmap** — `DSC_lastMissionOutcome` already provides standardized inputs; series consumes them
- [ ] **Conditional branching** — template selection based on prior outcome (HVT escaped → chase mission)
- [ ] **Series briefing** — overarching narrative beyond individual mission briefings
- [ ] **Intel as currency** — `intelTokens` already populated by interaction handler; selector reads them to seed next template

### Mission Archetypes (live)
- [x] **RAID** archetype — single AO, attacker
  - [x] Kill/capture HVT (KILL_CAPTURE)
  - [x] Capture/destroy supplies (SUPPLY_DESTROY)
  - [x] Hostage rescue (HOSTAGE_RESCUE)
  - [x] Intel gathering / dryhole (INTEL_GATHER)
  - [ ] Sabotage (briefing fragment exists; needs config + Eden composition support)
  - [ ] Capture POW (entities=[hvt with surrender flag], completion=ALIVE_AND_EXTRACTED)
- [ ] **SWEEP** archetype — multi-AO, light pop, observe-or-engage
  - Recon/surveillance, search & cordon, patrol area
- [ ] **DEFEND** archetype — single AO, defender role, attack waves
  - Hold position, protect VIP, repel attack
- [ ] **MOVEMENT** archetype — point A → B with attached entity/object
  - Convoy escort, infil-as-mission, package extract

### Campaign Flow
- [x] Mission generation loop (live in initServer Step 5)
- [ ] Player-selected missions — present 2-3 options
- [ ] Intel-driven mission selection
- [ ] Campaign threads — track faction engagement history

### World Simulation — Presence Manager (Design: `.crush/presence-manager.md`)

**Sprints 1-8 shipped** — full world population system around the player.

- [x] **`fnc_initPresenceManager`** — server-spawned 20s tick, zone state machine, queue + worker
- [x] **Zone state machine** — `DORMANT → ACTIVATING → ACTIVE → DESPAWNING → DORMANT`, async worker pacing, ACTIVATING-abandonment cleanup
- [x] **OpFor + bluFor bases / outposts / camps** — static defenders, marksmen, mortars, parked vehicles (Sprints 2, 7)
- [x] **Civilian populated areas** — influence-scaled density, always-present floor (Sprints 3-4)
- [x] **Military overlay on populated zones** — patrol from controlling side, recce-filtered (Sprint 5)
- [x] **Mission AO arbitration** — military zones suspend when overlapping active mission AO, civilians stay (Sprint 6)
- [x] **Global entity budget** — 100u/30v cap, closest-first prioritization (Sprint 6)
- [x] **Contested-zone dual-faction skirmishes** — east + west patrols on opposite sides, natural engagement (Sprint 8)
- [x] **Instrumentation** — per-zone activation latency, periodic STATS report, debug map markers, speed sampling

**Performance findings (June 2026, 15-min helicopter test)**
- 100% completion rate but **22% of activations abandoned** (spawned then immediately torn down at speed)
- Avg latency 20s = one tick exactly. Tick interval dominates the metric.
- Budget cap is **not** the bottleneck (5% skip rate)
- Root cause: useful engagement band (activation→despawn) is 400m for populated areas. At 70 m/s player crosses it in 5.7s, well under the 20s tick.

**Sprint A: Handler Registry Refactor (NEXT)**
- [ ] **`addons/core/functions/presence/handlers/`** — new directory, one handler per zone type
- [ ] **`fnc_registerPresenceHandler`** — adds to `DSC_presenceHandlers` hashmap
- [ ] **Handler contract** — hashmap with `activateRadius`, `despawnRadius`, `despawnGrace`, `budgetUnits`, `budgetVehicles`, `populate`, optional `despawn`, optional `lifecycle` ("delete" | "pause")
- [ ] **`fnc_activatePresenceZone` becomes thin dispatcher** — looks up handler by `_zone get "type"`, calls its populate slot
- [ ] **`fnc_despawnPresenceZone` becomes thin dispatcher** — same pattern, default to entity-list delete if no handler.despawn
- [ ] **Builtin handlers extracted**: `populatedArea`, `base`, `outpost`, `camp` — mechanical move, no new behavior
- [ ] **Acceptance**: 15-min helicopter test produces identical (or trivially close) `DSC_presenceStats`

**Sprint B: Per-Handler Performance Tuning**
- [ ] **Drop main tick to 8s** (probably — re-measure)
- [ ] **Per-type radii**: populated areas get wider despawn (Option C), bases keep tight
- [ ] **Re-run helicopter test**, target abandoned < 5%
- [ ] Decide on speed-scaled radius (Option B) only if numbers still show issues

**Sprint C: Pause-Instead-of-Delete Lifecycle**
- [ ] **`PAUSED` sub-state** — `disableSimulation` + `disableAI "ALL"` on grace start
- [ ] **Extended second grace** (~120s) — full delete only after this
- [ ] **Re-entry during pause** — `enableSimulation true; enableAI "ALL"`, no `createUnit` cost
- [ ] **Roll out order**: populated areas → camps + outposts → bases

**Sprint D (separate feature)**: Structure archetype data → new zone types
- Rural compounds, factories/warehouses, checkpoints, etc.
- Each becomes one handler registration under the refactored architecture
- Depends on structure-archetype data layer (user-owned design)

**Sprint E (separate subsystem)**: Roving entities
- Civilian vehicles wandering between towns
- Military motorized/mechanized patrols on roads
- Built as sibling to zone manager, not a new zone type

**Deferred**: Forced encounters (forced patrol injection when no combat for X minutes in opFor territory). Out of presence manager scope — would be a separate immersion system.

## Design Philosophy

- **Soft objectives** — tasks guide, not dictate
- **Intel as currency** — every location has potential intel
- **Resource pressure** — forces player tradeoffs
- **Layered truth** — briefing is best-guess, reality may differ
- **Arma task system** as display layer only, not control flow
- **Mod-agnostic** — works with whatever faction mods are loaded
- **"Skilled Zeus in a box"** — singleplayer campaign immersion + coop replayability
- **Fluid variety** — multi-faction presence, probabilistic spawning, weighted selection over strict rules

## Current State Summary

The full mission loop is live: scan map (with functional tagging + orphan recovery) → extract factions → assign influence → mark bases → select mission (influence-aware, multi-faction) → populate AO (garrison → guards → vehicles → patrols) → build raid config (entities + objects + completion) → place via archetype dispatcher → markers + briefing → play → standardized outcome → update influence → cleanup → repeat. All 5 initServer steps are active.

AO population overhauled: garrison uses individual groups per unit with cqb_baseline profile for independent CQB behavior. Guards placed at building exteriors anchored to nearest road (urban) or building facing direction. Static defenses separated into own function. Location scanner outputs rich hashmaps with functional tags (has_residential, has_industrial, etc.) and non-occupiable structure detection.

Phase 1 is complete. Mission config system + mission archetype refactor both shipped. Four RAID variants live (KILL_CAPTURE, SUPPLY_DESTROY, INTEL_GATHER, HOSTAGE_RESCUE), each driven by ~15 lines of config in `fnc_generateMission`. New mission types of the RAID family are now content authoring tasks.

**Presence Manager** — Sprints 1-8 shipped. World simulation populates the area around the player with civilians, military patrols, base garrisons, static defenses, mortars, and contested-zone skirmishes. Mission AO arbitration coordinates with the mission system. Instrumented with per-zone activation latency, periodic STATS reports, debug markers. A 15-minute helicopter performance test surfaced a 22% activation-abandonment rate at speed — the next sprints (A: handler registry refactor, B: per-type perf tuning, C: pause-instead-of-delete) address this before new presence content (Sprint D: structure archetype data; Sprint E: roving entities) lands. See `.crush/presence-manager.md` for the full state.

Next up: **Sprint A — Presence Manager Handler Registry Refactor**. Mechanical extraction of zone-type populate/despawn logic into discrete handler functions, registered with the manager loop. No behavior change; sets the stage for performance tuning (B), pause-instead-of-delete lifecycle (C), and the much larger variety of zone types (D) that the long-term vision needs.
