# Architecture — DSC Core Systems

## Addon Structure

DSC is a HEMTT-built Arma 3 mod with two addons:

| Addon | PBO Prefix | Purpose |
|-------|-----------|---------|
| `main` | `z\DSC\addons\main` | Mod metadata, version, macros, `DEBUG_MODE_FULL` flag |
| `core` | `z\DSC\addons\core` | All gameplay functions (depends on `main`) |
| `maps` | `z\DSC\addons\maps` | Per-map missions (Eden-placed objects + init scripts) |

Functions are registered via CBA's `PREP_SUB` macro in `core/XEH_PREP.hpp` and become available as `DSC_core_fnc_<name>`.

## Init Flow

### Server (`fnc_initServer`)

```
┌─────────────────────────────────────────────┐
│ STEP 0: Set Globals                         │
│   factionProfileConfig (vanilla or RHS)     │
│   playerMainBase = "player_base_1"          │
│   missionState = "IDLE"                     │
│   missionInProgress = false                 │
│   initGlobalsComplete = true  ←── client    │
│                                    waits on │
├─────────────────────────────────────────────┤
│ STEP 1: fnc_scanLocations                   │
│   Anchor-based: named locations as anchors  │
│   Assigns structures to nearest anchor      │
│   Orphan recovery: unassigned structures    │
│   cluster at 150m → synthetic anchors       │
│   Military tier: base/outpost/camp          │
│   Functional tagging: residential,          │
│   commercial, industrial, etc.              │
│   Outputs location HASHMAPS directly        │
│   Stores → DSC_locations (missionNamespace) │
├─────────────────────────────────────────────┤
│ STEP 2: fnc_initFactionData                 │
│   Validates factions exist in loaded mods   │
│   Extracts groups via CfgGroups             │
│   Classifies with doctrine tags             │
│   Extracts vehicle assets via CfgVehicles   │
├─────────────────────────────────────────────┤
│ STEP 3: fnc_initInfluence                   │
│   Accepts location hashmaps (no conversion) │
│   Tiered occupation: base/outpost/camp      │
│   Bases = occupation zones (campaign profile)│
│   Outposts = satellites of nearby bases     │
│   Camps = contention points (mostly neutral)│
│   5km safe zone around playerMainBase       │
├─────────────────────────────────────────────┤
│ STEP 4: Mark bases + init base guards/veh   │
│   fnc_initBases → fnc_setupBase per base    │
│   fnc_setupStaticDefenses (towers/statics)  │
│   fnc_setupGuards (entry-point guards)      │
│   Helipads, motor pool, TOC vehicles        │
├─────────────────────────────────────────────┤
│ STEP 5: Mission Loop (LIVE)                 │
│   Select → populateAO → generate mission    │
│   → briefing → monitor → cleanup → repeat   │
└─────────────────────────────────────────────┘
```

**Current state**: All steps are active. Mission loop is live.

### Client (`fnc_initPlayerLocal`)

```
waitUntil { initGlobalsComplete }
    │
    ├── Add actions to jointOperationCenter:
    │     • Debrief Mission (checks group aliveness)
    │     • HALO Jump (map click → group jump)
    │     • Request Extraction (helo pickup)
    │     • Recruit Medic (persistent medic companion)
    │
    └── Setup player down/revive:
          • ACE Medical detected → ace_unconscious CBA event
          • Vanilla → HandleDamage EH
```

## Data Flow Between Systems

```
fnc_scanLocations
    │
    ├──→ Array of location HASHMAPS (DSC_locations)
    │        id, position, name, locType, isMilitary,
    │        militaryTier, structures, mainStructures,
    │        sideStructures, buildingCount, radius,
    │        tags[], functionalProfile{}
    │
    ▼
fnc_initFactionData
    │
    ├──→ Per-role hashmap:
    │        factions[], side, groups{}, assets{}
    │        └── groups keyed by faction → classified group arrays
    │        └── assets keyed by faction → vehicle/static categorization
    │
    ▼
fnc_initInfluence
    │
    ├──→ Passes through location hashmaps (scanner already builds them)
    │    influenceMap: locationId → { controlledBy, influence, type, faction }
    │    bases[], outposts[], camps[], populatedAreas[], missionSites[]
    │    locations[] (enriched hashmaps for downstream use)
    │
    ▼
fnc_selectMission (or direct template)
    │
    ├──→ Accepts optional template (partial config with constraints)
    │    Delegates to fnc_resolveMissionConfig
    │
    ▼
fnc_resolveMissionConfig
    │
    ├──→ Template → Profile defaults → Auto-generation
    │    Filters locations by tags, region, distance
    │    Resolves faction, density, QRF from influence
    │    Outputs complete mission config hashmap
    │
    ▼
fnc_populateAO (per mission)
    │
    ├──→ Extracts assets from faction if not in mission config
    │    Garrison → Guards → Vehicles → Patrols (in order)
    │
    ├──→ AO hashmap:
    │        location, groups[], units[], vehicles[],
    │        defenderUnits[], patrolGroups[], garrisonUnits[],
    │        garrisonClusters[], tags[]
    │
    ▼
fnc_generateMission (case dispatch on type)
    │
    ├──→ Builds raid config (entities, objects, completion, markerStyle, briefingArchetype)
    │
    ▼
fnc_generateRaidMission
    │
    ├──→ Iterates entity specs:
    │      fnc_resolveEntityClass → fnc_placeInDeepBuilding | fnc_placeOnGround
    │      Apply behavior (captive), animation, combat activation
    │
    ├──→ Iterates object specs:
    │      fnc_placeObjects → fnc_placeInterior | fnc_placeOutdoorPile
    │      Wire fnc_addInteractionHandler if interactable
    │
    ├──→ fnc_drawCompoundMarkers (markerStyle "compound")
    │
    ├──→ Mission hashmap:
    │        type, archetype="RAID", completion, completionState{},
    │        briefingArchetype, entities[], objects[], objectMeta[],
    │        groups[], units[], markers[], startTime, status
    │
    ▼
fnc_createMissionBriefing
    │
    ├──→ Loads briefing fragment + entity/object archetype descs
    ├──→ Composes title/objective/targets/intel/threats/ROE
    ├──→ Arma task with composed text
    │
    ▼
...mission active...
    │
    ▼
fnc_evaluateCompletion (per-tick on completionState)
    │
    ▼
fnc_buildMissionOutcome → DSC_lastMissionOutcome
    │
    ▼
fnc_updateInfluence (success/failure)
    │
    ▼
fnc_cleanupMission
         Deletes all units, vehicles, objects, groups, markers
```

## Global Variables (missionNamespace)

| Variable | Type | Set By | Read By |
|----------|------|--------|---------|
| `initGlobalsComplete` | Bool | initServer | initPlayerLocal |
| `playerMainBase` | String | initServer | initInfluence (safe zone) |
| `factionProfileConfig` | HashMap | initServer | initFactionData |
| `missionState` | String | initServer | — |
| `missionInProgress` | Bool | initServer / debrief action | initPlayerLocal (action condition) |
| `missionComplete` | Bool | debrief action | — |
| `DSC_locations` | Array | initServer | initInfluence, mission generation |
| `DSC_factionData` | HashMap | initServer | populateAO, initInfluence |
| `DSC_influenceData` | HashMap | initServer | mission selection, updateInfluence |
| `DSC_currentMission` | HashMap | generateRaidMission | cleanupMission, debrief, addInteractionHandler |
| `DSC_lastMissionOutcome` | HashMap | initServer (debrief) | series framework (future), influence consumers |
| `DSC_hasACEMedical` | Bool | initPlayerLocal | handlePlayerDown |

## Faction Profile Configs

Two profiles in `fnc_initServer` with auto-detection:

- **`_factionProfileConfigVanilla`** — NATO, CSAT, AAF, FIA, Syndikat, IDAP
- **`_factionProfileConfigRhs`** — SOCOM/Army/USMC, VDV/VMF/MSV, CDF/SAF, ChDKZ

Auto-detects RHS by checking all faction classes in CfgFactionClasses. Falls back to vanilla if any are missing.

## Map Missions

Each map folder contains:
- `mission.sqm` — Eden editor file with player spawn, `jointOperationCenter` flagpole, `player_base` marker
- `initServer.sqf` → calls `DSC_core_fnc_initServer`
- `initPlayerLocal.sqf` → calls `DSC_core_fnc_initPlayerLocal`
- `description.ext` → includes `master.hpp` for shared config (respawn, CBA settings)

## CBA Integration

- **XEH_preStart.sqf** / **XEH_preInit.sqf** — Standard CBA function prep
- **CfgEventHandlers.hpp** — Registers XEH handlers
- **PREP_SUB(subfolder, name)** — Registers `functions/subfolder/fnc_name.sqf` as `DSC_core_fnc_name`
- ACE detected at runtime via `isClass (configFile >> "CfgPatches" >> "ace_medical")`
