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
│   playerMainBase = "player_base_0"           │
│   missionState = "IDLE"                     │
│   missionInProgress = false                 │
│   initGlobalsComplete = true  ←── client    │
│                                    waits on │
├─────────────────────────────────────────────┤
│ STEP 1: fnc_scanLocations                   │
│   Anchor-based: named locations as anchors   │
│   Assigns structures to nearest anchor       │
│   Military tier: base/outpost/camp           │
│   Excludes player_base markers + airbases    │
│   Stores → DSC_locations (missionNamespace)  │
├─────────────────────────────────────────────┤
│ STEP 2: fnc_initFactionData                  │
│   Validates factions exist in loaded mods    │
│   Extracts groups via CfgGroups             │
│   Classifies with doctrine tags             │
│   Extracts vehicle assets via CfgVehicles   │
├─────────────────────────────────────────────┤
│ STEP 3: fnc_initInfluence                    │
│   Tiered occupation: base/outpost/camp       │
│   Bases = occupation zones (campaign profile) │
│   Outposts = satellites of nearby bases       │
│   Camps = contention points (mostly neutral)  │
│   5km safe zone around playerMainBase        │
│   Debug markers show influence on map         │
├─────────────────────────────────────────────┤
│ STEP 4: Mission Loop          [NOT YET WIRED]│
│   Select location → populateAO → generate    │
│   mission → briefing → monitor → cleanup     │
└─────────────────────────────────────────────┘
```

**Current state**: Steps 0-3 are active. Step 4 (mission loop) is not yet wired.

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
    ├──→ Array of anchor arrays (DSC_locations)
    │        [position, name, locType, isMilitary,
    │         assignedStructures, militaryTier]
    │        militaryTier: "base"/"outpost"/"camp"/""
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
    ├──→ Enriches anchors into location hashmaps
    │    influenceMap: locationId → { controlledBy, influence, type, faction }
    │    bases[], outposts[], camps[], populatedAreas[], missionSites[]
    │    locations[] (enriched hashmaps for downstream use)
    │
    ▼
fnc_populateAO (per mission)
    │
    ├──→ AO hashmap:
    │        location, groups[], units[], vehicles[],
    │        defenderUnits[], patrolGroups[], garrisonUnits[], tags[]
    │
    ▼
fnc_generateKillCaptureMission
    │
    ├──→ Mission hashmap:
    │        type, location, entity (HVT), groups[], units[],
    │        marker, startTime, status
    │
    ▼
fnc_createMissionBriefing
    │
    ├──→ Arma task with intel-style briefing text
    │
    ▼
fnc_cleanupMission
         Deletes all units, vehicles, groups, markers
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
| `DSC_currentMission` | HashMap | generateKillCapture | cleanupMission, debrief |
| `DSC_hasACEMedical` | Bool | initPlayerLocal | handlePlayerDown |

## Faction Profile Configs

Two profiles are hardcoded in `fnc_initServer`:

- **`_factionProfileConfigVanilla`** — NATO, CSAT, AAF, FIA, Syndikat, IDAP
- **`_factionProfileConfigRhs`** — SOCOM/Army/USMC, VDV/VMF/MSV, CDF/SAF, ChDKZ

Currently defaults to vanilla. The RHS profile exists but must be selected manually by changing the variable assignment.

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
