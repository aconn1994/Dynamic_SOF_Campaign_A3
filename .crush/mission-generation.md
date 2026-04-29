# Mission Generation — Design Document

*Live: mission config system (template + resolver). Next: archetype refactor — see `.crush/mission-archetypes.md` for the raid generator design.*

## Overview

The mission generation system selects a location, builds a mission config, populates the area with multi-faction forces, places an objective, briefs the player, and monitors for completion.

**Current state**: Templates with profiles drive selection and population (granular: garrison anchors, guard coverage, patrol count, vehicle count/armed ratio). Only `KILL_CAPTURE` mission type is implemented.

**Next refactor**: Generalize `generateKillCaptureMission` into a reusable **raid generator** driven by entity/object/completion archetypes. After that, new mission types (supply destroy, hostage rescue, dryhole, sabotage) become data-only additions. See `.crush/mission-archetypes.md`.

## Mission Config System

Mission configs are now produced by a **template → resolver** pipeline:

1. A **template** (partial hashmap) specifies constraints and overrides
2. A **mission profile** ("AFO", "DA") applies preset defaults where the template is silent
3. **`fnc_resolveMissionConfig`** fills all remaining fields from influence/faction data

Templates can come from: random generation (`fnc_selectMission`), a mission series, player choice, or intel discoveries.

### Template Fields (all optional)

```sqf
private _template = createHashMapFromArray [
    // --- Core ---
    ["type", "KILL_CAPTURE"],              // Mission type
    ["missionProfile", "AFO"],             // Profile preset name
    ["targetFaction", "OPF_G_F"],          // Specific faction override
    ["targetRoles", ["opForPartner"]],     // Which roles to draw targets from

    // --- Location Constraints ---
    ["location", _specificLocation],        // Skip selection, use this location
    ["requiredTags", ["isolated"]],        // At least one must match (OR)
    ["excludeTags", ["military"]],         // None can match
    ["regionCenter", _position],           // Search within this area
    ["regionRadius", 5000],                // Radius for region constraint
    ["minDistance", 3000],                 // Min distance from player base
    ["maxDistance", 15000],                // Max distance from player base
    ["minBuildingCount", 3],               // Minimum structures at location

    // --- Generation Parameters ---
    ["density", "light"],                  // AO population density
    ["areaPresenceChance", 0.3],           // Area faction per-slot chance
    ["qrfEnabled", false],                 // QRF toggle
    ["qrfDelay", [60, 120]]               // QRF delay range
];
```

### Priority Cascade

```
1. Explicit template values     (highest)
2. Profile defaults              (AFO, DA presets)
3. Auto-generated from influence (lowest)
```

### Mission Profiles (`fnc_getMissionProfiles`)

| Profile | Location Tags | Density | QRF | Area Presence | Target Roles |
|---------|--------------|---------|-----|---------------|-------------|
| **AFO** | isolated, low_density, settlement | light | disabled | 0.3 | opForPartner, irregulars |
| **DA** | medium_density, high_density, town, military | heavy | enabled (60-120s) | 0.9 | opFor |

### Resolved Config Object

The resolver outputs the same format consumed by `fnc_generateMission`:

```sqf
private _missionConfig = createHashMapFromArray [
    // === OBJECTIVE ===
    ["type", "KILL_CAPTURE"],
    ["missionProfile", "AFO"],
    ["targetFaction", "rhsgref_faction_chdkz"],
    ["targetSide", east],
    ["targetGroups", _classifiedGroupsForFaction],
    ["targetAssets", _assetsForFaction],

    // === LOCATION ===
    ["location", _enrichedLocationHashmap],
    ["locationType", "camp"],
    ["distanceFromBase", 8500],

    // === AREA CONTEXT (from influence) ===
    ["areaFaction", "OPF_F"],
    ["areaSide", east],
    ["areaInfluence", 0.7],
    ["areaGroups", _classifiedGroupsForAreaFaction],
    ["areaAssets", _assetsForAreaFaction],

    // === GENERATION PARAMETERS ===
    ["density", "light"],
    ["areaPresenceChance", 0.3],
    ["qrfEnabled", false],
    ["qrfDelay", [120, 180]],

    // === METADATA ===
    ["campaignProfile", "offensive"]
    // + any extra template fields passed through
];
```

## Generation Flow

```
initServer Step 5: Mission Loop
│
└─ while { true } do {
    │
    ├─ 1. fnc_selectMission
    │     Builds the mission config from influence + faction data.
    │     │
    │     ├─ Pick mission type
    │     │   Only KILL_CAPTURE for now.
    │     │   Future: weighted by available intel, recent history, location tiers.
    │     │
    │     ├─ Filter valid locations for type
    │     │   KILL_CAPTURE → camps, missionSites, populated areas
    │     │   Exclude bluFor-controlled locations
    │     │   Exclude locations too close to player base (min distance)
    │     │   Weight by distance (farther = rarer but harder)
    │     │
    │     ├─ Select location → read influence data
    │     │   areaFaction = whoever controls this area (from influenceMap)
    │     │   areaInfluence = how strongly held
    │     │
    │     ├─ Pick target faction
    │     │   Weighted toward different from area faction for variety.
    │     │   Same-faction missions still happen naturally.
    │     │   Pool: opFor + opForPartner + irregulars
    │     │   Weight: same-as-area 30%, different 70%
    │     │
    │     ├─ Determine density
    │     │   Base density from location tier (camp=light, outpost=medium, etc.)
    │     │   Modified by areaInfluence and distance from player base
    │     │
    │     └─ Return mission config hashmap
    │
    ├─ 2. fnc_generateMission(config)
    │     Orchestrator — calls subsystems in order.
    │     │
    │     ├─ // Randomize time/weather (commented out for now)
    │     │
    │     ├─ populateMissionArea(config)
    │     │   See "Multi-Faction Population" below.
    │     │
    │     ├─ placeObjective(config, ao)
    │     │   Currently: HVT placement (generateKillCaptureMission logic)
    │     │   Future: sabotage target, intel cache, hostage, etc.
    │     │
    │     ├─ createBriefing(config, ao, mission)
    │     │
    │     ├─ setupQRF(config, mission)
    │     │   QRF pulls from areaFaction — "CSAT responds to gunfight
    │     │   at ChDKZ compound" creates the alive-world feeling.
    │     │
    │     ├─ setupUAV(mission)
    │     │
    │     ├─ applySkillProfiles(mission, config)
    │     │
    │     └─ Return mission hashmap
    │
    ├─ 3. Mission active
    │     missionInProgress = true
    │     Wait for player debrief at flagpole
    │
    ├─ 4. Score + update influence
    │     fnc_updateInfluence(influenceData, locationId, result, type)
    │
    ├─ 5. Cleanup
    │     fnc_cleanupMission(mission)
    │
    └─ 6. Sleep → next iteration
    }
```

## Multi-Faction Population

The core new capability. The mission area has two layers of faction presence:

### Target Layer (the objective)
- Garrison the specific compound/cluster where the objective lives
- Uses `targetFaction` groups from the mission config
- Guards + statics around the objective structures
- HVT / objective entity placed here

### Area Layer (the surrounding environment)
- Patrols and garrison in the broader location (other building clusters, roads)
- Uses `areaFaction` groups from the mission config
- Presence is **probabilistic**, not guaranteed:
  ```
  effectiveChance = areaPresenceChance × areaInfluence
  ```
- Each patrol/garrison slot rolls independently
- High influence (0.9) → ~63% chance per slot → dense area presence
- Low influence (0.3) → ~21% chance per slot → sparse, might not see them at all

### Example: Kill ChDKZ HVT in Kavala (CSAT-controlled, influence 0.7)

```
Compound (target cluster):
  ├─ Garrison: ChDKZ infantry groups (targetFaction)
  ├─ Guards: ChDKZ sentries + statics
  └─ HVT: ChDKZ officer

Surrounding Kavala:
  ├─ Patrols: CSAT foot patrols (areaFaction)
  │   Each slot: 70% × 0.7 = 49% chance of spawning
  ├─ Garrison: CSAT infantry in other building clusters
  │   Same per-slot roll
  └─ QRF: CSAT motorized from nearest outpost
      Triggered on FiredNear, delayed 120-180s
```

The player might infiltrate clean and never see CSAT. Or they might walk into a CSAT patrol on approach. Every playthrough is different.

### Population Split in populateMissionArea

```sqf
// 1. Identify the target cluster
//    Nearest anchor structures to the objective position,
//    or if the location IS the target, use its main structures.

// 2. Garrison target cluster with targetFaction
//    fnc_setupGarrison with targetGroups, scoped to target structures only

// 3. Guards at target cluster with targetFaction
//    fnc_setupGuards with targetAssets

// 4. Area patrols with areaFaction (probabilistic)
//    For each patrol slot:
//      if (random 1 < areaPresenceChance * areaInfluence) then spawn with areaGroups

// 5. Area garrison in remaining clusters with areaFaction (probabilistic)
//    For each non-target structure cluster:
//      if (random 1 < areaPresenceChance * areaInfluence) then garrison with areaGroups

// 6. QRF setup with areaFaction
//    Patrol groups from area faction respond to combat
```

## Mission Type → Location Tier Mapping

| Mission Type | Valid Location Tiers | Notes |
|---|---|---|
| `KILL_CAPTURE` | camp, missionSite, populated area | HVT hiding in smaller installations or urban compounds |
| `RECON` (future) | enemy base, outpost | Observe and report, too fortified for direct action |
| `SABOTAGE` (future) | outpost, camp | Destroy equipment, disable comms |
| `DIRECT_ACTION` (future) | outpost, camp | Full assault, clear the position |
| `DEFEND` (future) | bluFor outpost, bluFor base | Repel enemy attack |
| `HOSTAGE_RESCUE` (future) | camp, missionSite, populated area | Similar to kill/capture but extract alive |
| `CACHE_DESTROY` (future) | missionSite, camp | Find and destroy weapons/supplies |

## Target Faction Selection

Pool of candidate factions depends on mission type and area:

```
For KILL_CAPTURE:
  candidates = opFor factions + opForPartner factions + irregular factions
  
  if (areaFaction in candidates):
    weight same-as-area: 30%
    weight different: 70% (split among remaining candidates)
  else:
    equal weight among all candidates
```

This creates natural variety:
- Most missions send you after a **different** faction than the area controller
- Following a faction's trail across the map into harder territory happens organically
- Same-faction missions (CSAT HVT at CSAT outpost) still occur ~30% of the time

## Difficulty Scaling

Population density is driven by location and influence. Skill profile is a separate playtest setting, not tied to mission parameters.

| Factor | Effect |
|---|---|
| **Location tier** | Camp = light base density, outpost = medium, populated = varies |
| **Area influence** | Higher = more area faction presence, denser patrols |
| **Distance from base** | Farther = longer travel, more exposure to area patrols en route |

Skill profile is set globally in the mission loop (currently hardcoded, e.g. `"hard"`). It applies uniformly to all spawned AI and is intended as a playtest dial, not a per-mission variable. Future iterations may tie it to faction identity (e.g. opFor regulars vs irregulars) but that's not in scope now.

## Influence Feedback

After each mission:
```sqf
// Success: bluFor gains influence at mission location + ripple to nearby
// Failure: opFor strengthens at location + ripple
[_influenceData, _locationId, _result, _missionType] call DSC_core_fnc_updateInfluence;
```

Already implemented in `fnc_updateInfluence`. The ripple radius (2km) and shift amounts scale by location tier (control points shift more than mission sites).

Over multiple missions, the influence map evolves based on player performance.

## Function Changes Required

| Function | Status | Change |
|---|---|---|
| `fnc_populateAO` | **DONE** | Multi-faction model. Garrison → guards → vehicles → patrols. Auto-extracts assets if not in config. |
| `fnc_generateKillCaptureMission` | **DONE** | Consumes mission config + AO. HVT with bodyguards. SOF raid markers with nearby clearance radius. |
| `fnc_createMissionBriefing` | **DONE** | Intel-style briefing from mission config. |
| `fnc_setupPatrols` | **DONE** | Target faction + area faction patrols (probabilistic per slot). |
| `fnc_setupGarrison` | **OVERHAULED** | Individual groups per unit, unit class pool from templates, structure-count scaling, cqb_baseline profile. |
| `fnc_setupGuards` | **OVERHAULED** | Exterior road-anchored placement. Separated from static defenses. |
| `fnc_setupStaticDefenses` | **NEW** | Extracted from old guards. Military tower/bunker static weapons + lookouts. |
| `fnc_selectMission` | **REFACTORED** | Thin wrapper: accepts optional template, delegates to resolver. Backward compatible. |
| `fnc_resolveMissionConfig` | **NEW** | Template-based resolver: profile application → location filtering → faction resolution → config output. |
| `fnc_getMissionProfiles` | **NEW** | AFO and DA profile definitions (data function). |
| `fnc_generateMission` | **DONE** | Orchestrator: populate → objective → briefing → QRF → skill → UAV. |

## Time/Weather Randomization (Deferred)

From the old loop — will be re-enabled later:
```sqf
// private _hour = selectRandom [0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22];
// private _minute = floor random 60;
// setDate [date select 0, date select 1, date select 2, _hour, _minute];
// 0 setOvercast (random 1);
// 0 setFog ([random 0.3, 0, 0] select (random 1 > 0.7));
// 0 setRain 0;
// forceWeatherChange;
// sleep 1;
// 0 setRain (if (overcast > 0.5) then { random 0.4 } else { 0 });
```

## Next Steps

### Dryhole Variant (next implementation)
A kill/capture mission where the HVT isn't there. Same AO population, but:
- `hvtPresent: false` in template → generator skips HVT placement
- `intelObject: true` → places laptop/documents/phone as interaction target
- `completionType: "INTEL_GATHER"` → mission completes on intel pickup
- Intel object returns data that can feed the next mission template

### Mission Series Framework
- Series definition: array of templates with branching logic
- `fnc_initMissionSeries` → stores active series in `DSC_activeSeries`
- Mission loop checks: active series? Pull next template. Otherwise random.
- Series carry state hashmap between missions (e.g. "bombmaker identified")
- Completion of mission N triggers mission N+1 with state-dependent template mods

### Future Hooks

The template→resolver architecture supports these without restructuring:

- **Intel-driven missions**: Intel pool seeds templates for `fnc_resolveMissionConfig`. No changes to resolver needed.
- **Player-selected missions**: Generate N templates, present to player, resolve the chosen one.
- **Layered objectives**: Template gains `secondaryObjectives` array. `fnc_generateMission` resolves each.
- **World simulation layer**: Reads influence data, injects patrols/civilians. Independent of mission config.
- **Campaign threads**: Track faction engagement history. Weight series/template selection toward continuing narratives.
- **HVT variants**: Flee (scripted escape trigger), surrender (interrogation action yields intel for next template).
