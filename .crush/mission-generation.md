# Mission Generation — Design Document

*Planned implementation for the mission generation loop (initServer Step 5)*

## Overview

The mission generation system selects a location, builds a mission config, populates the area with multi-faction forces, places an objective, briefs the player, and monitors for completion. It replaces the hardcoded single-faction loop from the backup initServer.

## Mission Config Object

The config is the single source of truth for everything downstream. Built by `fnc_selectMission`, consumed by `fnc_generateMission`.

```sqf
private _missionConfig = createHashMapFromArray [
    // === OBJECTIVE ===
    ["type", "KILL_CAPTURE"],
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
    ["density", "medium"],
    ["areaPresenceChance", 0.7],
    ["qrfEnabled", true],
    ["qrfDelay", [120, 180]],

    // === METADATA ===
    ["seed", floor random 99999],
    ["campaignProfile", "offensive"]
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
| `fnc_populateAO` | Refactor | Accept two faction group sets (target + area). Target fills objective cluster, area fills surroundings probabilistically. |
| `fnc_generateKillCaptureMission` | Refactor | Accept mission config instead of bare location + AO. HVT class from targetFaction. |
| `fnc_createMissionBriefing` | Refactor | Read config for richer context (area faction, distance, influence level, difficulty). |
| `fnc_setupPatrols` | Minor | Support optional faction override per patrol slot (area faction patrols). |
| `fnc_setupGarrison` | Minor | Support scoped garrison (target cluster only vs full location). |
| `fnc_selectMission` | **NEW** | Build mission config from influence data + faction data. Location filtering, faction selection, parameter derivation. |
| `fnc_generateMission` | **NEW** | Orchestrator: calls populate → objective → briefing → QRF → skill. Returns mission hashmap. |

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

## Future Hooks (Not Implemented Yet)

These are architectural placeholders — the mission config and generation flow are designed to accommodate them without restructuring:

- **Intel-driven missions**: `fnc_selectMission` checks an intel pool before random selection. Intel items found at previous missions seed the pool.
- **Player-selected missions**: Present 2-3 configs to the player, they pick one. `fnc_selectMission` generates N candidates instead of 1.
- **Layered objectives**: Mission config gains an `["secondaryObjectives", [...]]` array. `fnc_generateMission` populates additional sites nearby. Intel from previous missions creates these.
- **World simulation layer**: Separate from mission generation. Real-time patrol injection, encounter forcing, QRF from nearby bases. Reads influence data but doesn't modify mission state.
- **Campaign threads**: Track which factions the player has engaged. Weight future missions toward continuing the "story" (following ChDKZ leadership deeper into CSAT territory).
