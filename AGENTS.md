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
│       ├── faction/         # Faction extraction + group/asset pipelines
│       ├── classification/  # Unit + group doctrine tagging
│       ├── ai/              # Population, guards, garrison, patrols, combat activation
│       ├── missions/        # Mission generation, briefing, cleanup
│       ├── base/            # Player actions: HALO, extraction, medic, helo transport
│       ├── data/            # Static data (structure type lists)
│       ├── validators/      # Group activity checks
│       └── debug/           # (empty — debug is inline via diag_log)
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
5. Mission generation loop — select (template → resolver) → generate → debrief → update influence → cleanup → repeat

**Client init** (`fnc_initPlayerLocal`):
- Waits for server globals
- Adds actions to `jointOperationCenter` flagpole: Debrief, HALO, Extract, Recruit Medic
- Sets up player down/revive (ACE or vanilla)
- Map Draw EH renders faction flag textures on bases/outposts

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
| Mission Generation | `fnc_generateMission` | Orchestrator: populate → objective → briefing → QRF → skill → UAV |
| AO Population | `fnc_populateAO` | Multi-faction: garrison → guards → vehicles → patrols. Auto-extracts assets if not in mission config |
| Kill/Capture | `fnc_generateKillCaptureMission` | HVT placement, SOF raid-style compound markers (Contact_circle4 + alpha-numeric dots) |
| Vehicles | `fnc_setupVehicles` / `fnc_setupVehiclePatrol` | Parked vehicles near garrison + motorized road patrols |
| Static Defenses | `fnc_setupStaticDefenses` | Military-only: towers, bunkers, static weapons with lookout fallback |
| Combat Activation | `fnc_addCombatActivation` | Units start frozen, activate on FiredNear EH |

## SQF Conventions

- Functions: `DSC_core_fnc_<name>` (via CBA PREP_SUB macros)
- Hashmaps everywhere — locations, groups, missions, AO data are all hashmaps
- `getOrDefault` used extensively for safety
- Debug markers behind `#ifdef DEBUG_MODE_FULL` in `addons/main/script_mod.hpp`
- `diag_log format ["DSC: ..."]` for all logging

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

## Detailed System Docs

- `.crush/architecture.md` — Init flow, addon structure, data flow between systems
- `.crush/faction-system.md` — Faction profiles, extraction pipeline, classification, doctrine tags
- `.crush/mission-system.md` — AO population, mission types, briefing, cleanup, combat activation
- `.crush/mission-generation.md` — Mission config object, multi-faction population, generation flow
- `.crush/vehicle-systems.md` — Parked vehicles, vehicle patrols, dismount cycle design (deferred)
- `.crush/grand-vision.md` — High-level project goals and inspiration
- `.crush/ao_populous_overhaul.md` — Garrison/guard/patrol overhaul design, playtest data, skill profiles
- `.crush/roadmap.md` — What's done, what's next, design philosophy
