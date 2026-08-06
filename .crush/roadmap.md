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

### Known Bugs (backlog)
- [ ] **QRF element size is unbounded — one dispatch spawned 17 units** — `c2 QRF DISPATCHED [UNIFORM] - 17 mounted units`. `fnc_c2ResponseQrf` takes whatever the CfgGroups entry contains, so a full motorized infantry group arrives as a single "QRF element". QRFs deliberately ignore the presence budget (rare, player-triggered) but 17 units is a small army, and three concurrent dispatches were observed in one engagement. Needs a per-element unit cap with trimming, or a preference for smaller CfgGroups entries.
- [ ] **QRF can dispatch to an LKP a few metres from its own node** — `QRF DISPATCHED [DELTA-2] - 4 foot units toward LKP 7m out`. Responders spawn essentially on top of their destination and arrive instantly, so the response reads as a garrison shuffle rather than a reinforcement. Add a minimum travel distance below which the node should recall instead of dispatching.
- [ ] **Roving foot rovers occasionally spawn ~21 km from the player and despawn 8s later** — observed `roving spawned [foot] BUS_InfSentry src=base/loc_65 spawn=21110m` followed 8s later by `roving despawned dist=21108m`. The spawn-position search in `fnc_rovingSpawnFoot` is picking a point far outside the despawn ring, so the whole spawn is wasted work and briefly consumes rover budget. Clamp the search to the despawn radius, or reject and retry before spawning.
- [ ] **`fnc_buildRoadRoute` returns 0m on airfield concrete** — ground rovers spawning near `player_base_0` / an airbase log `start candidate 0-3 unusable (0m dead-end)` on every attempt, because runway and taxiway segments are `Road` objects that carry no `roadsConnectedTo` graph links. Self-recovers via the "3 route failures → move toward patrol center" fallback, so this is log noise rather than a stall — but ground rovers arguably should not pick airfield spawn points at all.
- [x] **Side allocation regression (`.crush/faction-sides.md`)** — FIXED. Rather than convert the ~10 individual side-resolution call sites (the partial migration that caused the regression), role sides are now normalized **once** in `fnc_initServer` at profile selection, before the profile reaches `missionNamespace`. Since `fnc_initFactionData` copies `side` verbatim, both runtime sources are correct by construction and no downstream site needs changing. Follow-up cleanup (deleting the now-dead `side` entries from the profile literals) is tracked as Phase 0 in `.crush/faction-autoscan.md`.
- [x] **`fnc_buildRoadRoute` frequently returned a single stationary waypoint** — FIXED. Three causes: (1) the walk started from the single nearest road, which is often a driveway/bridge-ramp/isolated stub with no graph neighbours, so it died on iteration one — now tries up to 4 nearest roads as start candidates; (2) any dead end terminated the whole route — now backtracks (bounded DFS, 12 pops) and tries another branch; (3) a 1-point route at the caller's own position was returned as success, and both patrol loops then set a MOVE waypoint the vehicle was already inside, fired arrival instantly, and re-planned in place forever — routes shorter than 25% of target now return `[]` so the caller retries. `roadsConnectedTo` is also filtered for nulls and self-references. Termination reason is logged.
- [x] **Rotary rovers dying seconds after spawn** — FIXED. `fnc_rovingSpawnAir` computed a desired *above-ground* altitude (rotary 100-150m) and passed it straight to `setPosASL` as a sea-level coordinate, so helicopters spawned underground anywhere terrain exceeded that — which is most of the Altis interior. Spawn altitude and all waypoint altitudes are now `getTerrainHeightASL + altitude` (clamped at 0 for water). Also: initial velocity is now set along the heading after crew creation (`setPosASL` + `setDir` don't rotate the momentum `createVehicle ... "FLY"` starts with, so rotaries wallowed and settled into terrain), and the transit/loiter roll was inverted against its own doc comment — `random 1 < 0.05` gave ~95% loiter, meaning nearly every rotary orbited low and slow near the player instead of transiting. Now 55% transit as documented.

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
### Faction Configuration
- [ ] **Player-selectable factions** — currently hardcoded vanilla/RHS profiles
- [ ] **Civilians** — neutral population spawning
- [ ] **Environment actors** — IDAP, UN, contractors with presence
- [ ] **🔧 Faction config rework — Plan A two-pole model** (Design: `.crush/faction-overhaul.md`). Approved, deferred until after C2. Never override a faction's native side: roles become descriptive labels for mission logic and a faction may only be cast into a role whose required side matches its `CfgFactionClasses` side. Independent stops being used for combatants entirely, all `setFriend` calls are deleted, and one load-time validator rejects invalid configs so the whole class of side bugs becomes unrepresentable instead of debuggable. **Net deletion of code** — removes `fnc_resolveRoleSide`, the normalization pass, the realignment pass, and the forced-east overrides. Costs AAF/Syndikat/Looters as vanilla combatants (near-zero cost under RHS/CUP).
  - [ ] Sub-task: rename the `"side"` key collision — `fnc_extractGroups` stores a NUMBER under `"side"` on group hashmaps while `fnc_initFactionData` stores a SIDE object under the same key on role hashmaps
  - [ ] Sub-task: repair `factionClass` provenance in `fnc_extractGroups` — the CfgGroups desync workaround overwrites `_factionClass` before storing it, so groups carry the CfgGroups node name (`"Guerilla"`) rather than the real faction class, silently breaking every downstream role lookup
  - [ ] Sub-task: fix garrison grouping — `fnc_setupGarrison` creates one group per unit (16 groups for 16 units observed), so Arma applies no line-of-fire deconfliction between defenders in the same building. Needs `disableAI "PATH"` + `setUnitPos` before merging or units abandon firing positions to form up
  - [ ] Sub-task: remove the `DSCDIAG` instrumentation (see Cleanup in `.crush/faction-overhaul.md`)
- [ ] **Faction autoscan** (Design: `.crush/faction-autoscan.md`) — follows the rework. Inverted CfgGroups walk to kill the desync table, faction catalog + role-scoring heuristics, tablet Campaign Setup panel

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

### C2 Network + ISR — F.1 + F.2 + F.3 SHIPPED (Design: `.crush/c2-network.md`)

Adds the missing "communication" layer: AI forces belong to installations,
report contact, miss check-ins, and generate proportionate responses. ISR
is the player's read-access to the same network. Sibling subsystem to
presence + roving; own registry, own tick (10s, third phase offset), own
reaction budget.

**Locked scope decisions**: real QRF spawn + travel within node reach;
telegraphs always visible with detail ISR-gated; alert state resets on
mission cleanup; **ambient from day one** (not mission-only); all
factions including `bluForPartner` (simplified); difficulty emergent from
tier + distance + influence + archetype; text-only chatter; QRF may
exceed the presence budget cap.

- [x] **F.1 — Provenance + registry** — `DSC_c2Nodes` built at init (base=COMMAND, outpost=RELAY, camp/town=OUTSTATION), link topology precomputed per faction comms archetype (conventional/partner hierarchical, irregular mesh), stable per-faction phonetic callsigns, provenance stamped (`DSC_c2Parent`/`DSC_c2Role`/`DSC_c2NextCheckIn`/`DSC_c2RtbEta`/`DSC_c2Radioman`), 10s alert-decay tick with LOD, alert ratchet + reset on mission cleanup. **Log-only, zero gameplay delta.**
- [x] **F.2 — Signals + propagation** — report timer with leader (1.8×) / radioman (2.5×) modifiers, gunfire + explosion noise events graded by radius (75m suppressed → 3500m vehicle kill), check-in/RTB/SILENCE accountability, breadth-first relay hops with per-hop reliability rolls + grade degradation, LKP confidence decay, radio feed ring buffer. Direct attacks on installations escalate to BLACK. **Still dispatches nothing.**
- [x] **F.3 — Response ladder** — recall (redirect existing mobile groups, zero spawn cost) + QRF (real spawn at the node, real travel to LKP, ignores presence budget), capability gated by `ladder ∩ tier` so a town recalls but cannot QRF, per-episode decision latency, per-level dispatch cooldown, search radius scaled by LKP confidence, LAMBS `taskHunt` soft dependency for foot elements, presence `COMBAT` hold so responding zones don't tear down mid-response.
- [x] **F.4 — ISR + player-facing** — coverage tiers (NONE / BASIC = player within 800m / ENHANCED = ISR drone on station with fog+rain degrading the orbit radius / FULL = F.5 SIGINT stub), coverage evaluated best-of {event position, node LKP, node position} via the shared `fnc_c2IsrEntryTier`, live intercepted chatter via `systemChat` throttled to 1 line per 2.5s, dispatch notifications with bearing + element type + ETA gated at ENHANCED (the reason keeping the drone alive matters), diegetic ungated telegraphs (illum flare on RED transition, forced headlights on QRF departure — both night-only, 3km player gate), tablet **Radio Feed** page on the INTEL tab with timestamped scrollback, per-source coloring, live coverage header, alerted-node strip, and EARNED/ALL(DEBUG) filter, plus **hostile contact fixes on the Blue Force Tracker** — SIGINT radio-direction-finding on groups that actually transmitted (ENHANCED-gated at the moment of emission, 240s TTL) and VISUAL own-force observation (`knowsAbout >= 0.5`, 90s TTL, refreshed while watched), drawn as ageing/fading `o_unknown` markers that state their own staleness. **`LOST` lines never reach the player** — that would reveal whether a clean wipe worked, which is the reward the report timer exists to protect. Likewise no contact marker for a group killed before it transmits.
- [ ] **F.5 — Counterplay** — radioman targeting, comms infra archetypes (hack / quiet-disable / destroy), jamming, `heat` persistence

**F.1 implementation notes**: provenance is stamped at
`fnc_activatePresenceZone` (one choke point covering all 8 zone types and
any future handler) rather than inside each setup function; civilian-side
groups are excluded from node rosters; nodes resolve per side so contested
skirmish patrols don't report to the installation they're attacking.

**F.2 implementation notes**: signal sources are two server-side handlers
(`EntityKilled` + a client-fired CBA relay) plus a tick backstop, rather
than per-unit `FiredNear` EHs — the presence manager can have 150 units
standing and per-unit handlers wouldn't scale. AMBER-grade signals never
relay, which is what keeps alert state meaningful. Roster hygiene detects
wiped elements *before* pruning them, otherwise `SILENCE` could never fire.
Suppressor state is classified client-side because muzzle accessory data
isn't reliable for remote units.

**Free hooks still unused**: `fnc_generateMission` has a vestigial
commented-out `qrfEnabled` block to be replaced by registering the mission
AO as a transient C2 node. (The presence `COMBAT` state and
`fnc_convergePatrols` are now both consumed by F.3.)

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

**C2 Network** — Sprints F.1-F.4 shipped (August 2026). AI groups belong to
installations, run a contact-report timer, miss check-ins, propagate signals
through a relay topology with last-known-position, and dispatch recall/QRF
responses gated by tier capability and node reach. F.4 made all of it
perceivable: coverage-tiered intercepted chatter, ISR dispatch warnings with
bearing and ETA, diegetic night telegraphs, and a tablet Radio Feed scrollback.
Three playtests drove eleven bug fixes; the mechanics (report timer, radioman
multiplier, reach gate, echo suppression) are confirmed working in-game. F.4
awaits playtest. F.5 (counterplay) is designed but not started. See
`.crush/c2-network.md`.

---

## Next up

**1. Playtest F.4.** Eight validation tests are written up in
`.crush/c2-network.md` ("Validating F.4 in game"). The important ones: chatter
appears with no assets (BASIC), the ISR dispatch line with bearing + ETA appears
only with the drone alive (ENHANCED), and `LOST` lines never surface under the
EARNED filter.

**2. Garrison grouping fix.** `fnc_setupGarrison` creates one group per unit,
so defenders in the same building have no line-of-fire deconfliction and
friendly-fire each other. No longer a fratricide *cause* (that was
`createUnit` side inheritance, now fixed) but still a real quality problem.

**3. C2 F.5 — Counterplay.** Radioman targeting, comms infrastructure
archetypes (hack / quiet-disable / destroy), jamming, `heat` persistence. The
network now has both a voice and an audience, which is the prerequisite for
attacking it being meaningful.

**4. Faction config rework — Plan A.** See `.crush/faction-overhaul.md`.
Hardening rather than a bug fix: it makes the entire class of side bugs
unrepresentable. Worth doing, not urgent.

### Resolved

- ~~Side-allocation regression~~ — the real root cause was **`group createUnit`
  does not set the unit's side**. A Syndikat class (native GUER) spawned into
  `createGroup [east]` produced a unit on GUER inside an EAST group, and since
  AI hostility is evaluated observer-group-side vs target-unit-side, every
  fighter read its own squadmates as enemy independents. Fixed with
  `joinSilent` at all 11 `createUnit` sites. Three earlier diagnoses (side
  normalization, microzone projection, rating/renegade) each fixed a real but
  different bug. Full write-up in `.crush/faction-overhaul.md`.
- ~~Road-route + rotary-rover bugs~~ — fixed; see Known Bugs above.
- ~~Rovers unable to return fire~~ — all four rover spawners used
  `setCombatMode "BLUE"` (never fire) plus `disableAI "TARGET"`/`"AUTOTARGET"`,
  three independent locks on ever shooting. Now `GREEN` (hold fire, defend
  only) with `AUTOCOMBAT` disabled.

