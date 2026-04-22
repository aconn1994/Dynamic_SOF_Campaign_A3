# Roadmap — DSC

*Updated April 21, 2026*

## Phase 1: Mission Area Generation — COMPLETE

### Done
- [x] **Location Scanner** (`fnc_scanLocations`) — anchor-based: assigns structures to named locations, excludes player bases + airbases, military tier tagging (base/outpost/camp)
- [x] **Structure Classification** (`fnc_getStructureTypes`) — curated main/side/military structure lists for vanilla + mod maps
- [x] **Map Structures** (`fnc_getMapStructures`) — engine-level spatial query wrapper
- [x] **Group Classifier** (`fnc_classifyUnit` → `fnc_classifyGroup` → `fnc_classifyGroups`) — full doctrine tag system with confidence scoring
- [x] **Faction Extraction** (`fnc_extractGroups`, `fnc_extractAssets`, `fnc_initFactionData`) — mod-agnostic pipeline from CfgGroups/CfgVehicles
- [x] **Guards** (`fnc_setupGuards`) — military: static weapons in towers + perimeter ring; civilian: compound security tight around garrison clusters
- [x] **Garrison** (`fnc_setupGarrison`) — anchor/satellite building model with density profiles, exposes cluster data for mission markers
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
- [x] **AI Skill Profiles** (`fnc_applySkillProfile`, `fnc_getSkillProfile`) — moderate/hard/realism
- [x] **Persistent UAV** — always-available drone support
- [x] **ACE Integration** — medical system detection, unconscious handling
- [x] **Player Down/Revive** — works with ACE or vanilla damage model
- [x] **Multi-Map Support** — Altis, Livonia, Malden, Stratis, Tanoa all have mission folders

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
- [ ] **`fnc_initBases` + `fnc_setupBase`** — orchestrator + per-base worker, base registry pattern
- [ ] **Player base guards** — `fnc_setupGuards` with heavy config, tower sentries + perimeter (Sprint 1)
- [ ] **Player base helipads** — scan `player_base_1_heliport` marker, place transport helos on pads (Sprint 2)
- [ ] **BluFor/OpFor base population** — iterate influence bases, side-appropriate guard configs + vehicles (Sprint 3)
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

### Mission Expansion
- [ ] Additional mission types (beyond Kill/Capture)
  - AFO (Advanced Force Operations) — recon/surveillance
  - DA (Direct Action) — assault/sabotage
  - SR (Special Reconnaissance)
  - Hostage rescue
  - Sabotage/destruction objectives
- [ ] Mission type selection logic (architecture exists in `fnc_selectMission`)
- [ ] Location-to-mission-type mapping (design doc in `.crush/mission-generation.md`)

### Campaign Flow
- [x] Mission generation loop (live in initServer Step 5)
- [ ] Player-selected missions — present 2-3 options
- [ ] Intel-driven mission selection
- [ ] Campaign threads — track faction engagement history

### World Simulation — Presence Manager (Design: `.crush/base-initialization.md`)
- [ ] **`fnc_presenceManager`** — sleep-loop (15-30s) checking player position against influence/base data
- [ ] **Zone state machine** — `DORMANT → ACTIVATING → ACTIVE → DESPAWNING → DORMANT` per zone, prevents double-spawn
- [ ] **OpFor base activation** — guards + garrison spawn when player within ~1.5km, despawn at ~2.5km
- [ ] **BluFor base activation** — friendly ambient troops spawn on player approach
- [ ] **Forced encounters** — if player in opFor territory with no combat for X min, inject patrol near position
- [ ] **Civilian/ambient life** — populate towns with civilians when player approaches
- [ ] **QRF from bases** — opFor bases spawn QRF toward active mission AO
- [ ] Environmental immersion layer separate from mission system

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

The full mission loop is live: scan map → extract factions → assign influence → mark bases on map → select mission (influence-aware, multi-faction) → populate AO (target + area faction) → place HVT with raid-style markers → briefing → play → debrief → update influence → cleanup → repeat. All 5 initServer steps are active. Vehicle patrols drive road loops; dismount cycle is deferred. Parked vehicles spawn near garrison clusters. Phase 1 is complete. Next focus: Phase 2 faction configuration and Phase 3 intel/campaign systems.
