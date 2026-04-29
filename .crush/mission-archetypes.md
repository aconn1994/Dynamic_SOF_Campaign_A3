# Mission Archetypes — Design Doc

*Status: **COMPLETE** (April 29, 2026). Implementation shipped through all 9 steps; system is data-driven and live in the mission loop.*

## What Shipped

The raid system is now **data-driven**. Adding a new RAID variant is a content-authoring task — write a config, no new generator code. Currently four variants run end-to-end: `KILL_CAPTURE`, `SUPPLY_DESTROY`, `INTEL_GATHER`, `HOSTAGE_RESCUE`.

### Function Map (live)

| Layer | Function | Role |
|-------|----------|------|
| Data | `fnc_getEntityArchetypes` | Registry: OFFICER, BOMBMAKER, HOSTAGE |
| Data | `fnc_getObjectArchetypes` | Registry: INTEL_LAPTOP, INTEL_DOCUMENTS, SUPPLY_CACHE, BOMB_PARTS, WEAPONS_CRATE |
| Data | `fnc_getCompletionTypes` | Registry: KILL_CAPTURE, ALL_DESTROYED, ANY_INTERACTED, HOSTAGES_EXTRACTED, AREA_CLEAR |
| Data | `fnc_getBriefingFragments` | Registry: raid_kill_capture, raid_supply_destroy, raid_intel_gather, raid_hostage_rescue, raid_sabotage |
| Resolver | `fnc_resolveEntityClass` | Maps resolver keys (`officer`, `civilian`, `civilian_suit`, `civilian_labcoat`) → concrete classnames |
| Placement | `fnc_placeInDeepBuilding` | 3-path: bodyguard host → any structure → location center |
| Placement | `fnc_placeOnGround` | Sit/kneel/down stance, interior or building edge |
| Placement | `fnc_placeInterior` | Object spawn on building floor, optional Z offset |
| Placement | `fnc_placeOutdoorPile` | Object cluster around anchor, collision rejection |
| Placement | `fnc_placeObjects` | Dispatcher for object archetypes by `placement` key |
| Markers | `fnc_drawCompoundMarkers` | Contact_circle4 + alpha-numeric dots (cluster A1, A2, B1...) |
| Mission | `fnc_generateRaidMission` | Generic raid generator: entities → objects → markers → state |
| Mission | `fnc_evaluateCompletion` | Polling-based; supports named conditions + inline `completionExpr` |
| Mission | `fnc_buildMissionOutcome` | Standardized outcome schema |
| Mission | `fnc_addInteractionHandler` | addAction wiring for interactable objects (intel pickup) |
| Mission | `fnc_createMissionBriefing` | Composes title/objective/ROE from briefing fragment + entity/object archetypes |

### Mission Loop Integration

```
fnc_selectMission (template "type" picks variant)
  → fnc_resolveMissionConfig (location, factions, density)
    → fnc_generateMission (case dispatch on "type" → builds raid config)
      → fnc_generateRaidMission (entities, objects, markers, state)
        → fnc_createMissionBriefing (fragment + archetypes)
        → ...mission active...
        → fnc_evaluateCompletion (per-tick on completionState)
          → fnc_buildMissionOutcome (DSC_lastMissionOutcome)
            → fnc_updateInfluence (success/failure)
              → fnc_cleanupMission
```

## Core Insight

**Mission types are not generators. Mission types are configurations.**

A "kill/capture HVT" mission and a "destroy supplies" mission and a "hostage rescue" mission share 90% of their code: scan a location, populate it with garrison/guards/patrols/vehicles, place markers, brief the player, monitor for completion, clean up.

What differs is just:

1. **What entities** are placed (HVT? hostages? nobody?)
2. **What objects** are placed (intel? crates? nothing?)
3. **What condition** ends the mission (HVT down? objects destroyed? hostages extracted?)

All three are **data**. New mission types = content authoring, not engineering.

## Four Archetypes

| Archetype | Footprint | Player Role | Examples |
|-----------|-----------|-------------|----------|
| **RAID** | Single AO | Attacker | HVT kill/capture, supply destroy, hostage rescue, sabotage, intel gathering, dryholes, capture POW |
| **SWEEP** | Multi-AO | Observer / scout | Recon, surveillance, search & cordon, patrol area |
| **DEFEND** | Single AO | Defender | Hold position, protect VIP, repel attack waves |
| **MOVEMENT** | Path | Escort / mover | Convoy escort, infil-as-mission, package extract |

**~80% of planned mission types are RAID variants.** That's why generalizing the raid generator is the highest-leverage refactor.

---

## RAID Archetype Architecture

### Generic Raid Generator

```sqf
// fnc_generateRaidMission.sqf
//
// Consumes:
//   _location  - enriched location hashmap
//   _ao        - populated AO from fnc_populateAO
//   _config    - raid config:
//                "entities": [entity archetype hashmaps]
//                "objects":  [object archetype hashmaps]
//                "completion": { type: "...", state: {...} }
//                "markerStyle": "compound" | "search_area" | "none"
//                "briefingArchetype": "raid_kill_capture" | "raid_supply_destroy" | ...
//
// Produces:
//   Mission hashmap with standardized outcome schema
```

### Entity Archetypes (data)

```sqf
private _entityArchetypes = createHashMapFromArray [

    // === HVT Variants ===
    ["OFFICER", createHashMapFromArray [
        ["unitClassResolver", "auto"],          // Picks officer/commander class from faction
        ["placement", "DEEP_BUILDING"],         // Inner room with bodyguards
        ["hasBodyguards", true],
        ["fleeable", true],
        ["surrenderable", true],
        ["briefingTitle", "Enemy Commander"],
        ["briefingDesc", "A senior officer coordinating local operations"]
    ]],

    ["BOMBMAKER", createHashMapFromArray [
        ["unitClassResolver", "civilian_suit"],
        ["placement", "DEEP_BUILDING"],
        ["attachment", "suicide_vest"],          // Special: explosive vest hooks
        ["hasBodyguards", true],
        ["fleeable", false],                     // Stays put — explosive failsafe
        ["surrenderable", false],                // Detonates if cornered
        ["briefingTitle", "IED Facilitator"],
        ["briefingDesc", "Builds devices for the cell. Approach with caution — possible suicide vest."]
    ]],

    ["SCIENTIST", createHashMapFromArray [
        ["unitClassResolver", "civilian_labcoat"],
        ["placement", "DEEP_BUILDING"],
        ["hasBodyguards", true],
        ["fleeable", true],
        ["surrenderable", true],
        ["briefingTitle", "Chem/Bio Specialist"],
        ["briefingDesc", "Suspected of weapons program involvement. High-value capture target."]
    ]],

    ["FINANCIER", createHashMapFromArray [
        ["unitClassResolver", "civilian_suit"],
        ["placement", "DEEP_BUILDING"],
        ["hasBodyguards", true],
        ["fleeable", true],
        ["surrenderable", true],
        ["briefingTitle", "Cell Financier"],
        ["briefingDesc", "Funds operations across the network. Capture for interrogation."]
    ]],

    // === Civilian Variants ===
    ["HOSTAGE", createHashMapFromArray [
        ["unitClassResolver", "civilian"],
        ["placement", "GROUND_SIT"],            // Sitting on ground
        ["animation", "Acts_AidlPercMstpSnonWnonDnon01"],
        ["behavior", "captive"],                // setCaptive true, no AI
        ["attachment", "blindfold"],
        ["briefingTitle", "Hostage"],
        ["briefingDesc", "Confirmed PID. Extract alive."]
    ]],

    ["INTEL_SOURCE", createHashMapFromArray [   // Friendly informant on-site
        ["unitClassResolver", "civilian"],
        ["placement", "GROUND_KNEEL"],
        ["behavior", "captive"],
        ["briefingTitle", "Asset"],
        ["briefingDesc", "Friendly informant. Recover alive for debrief."]
    ]]
];
```

### Object Archetypes (data)

```sqf
private _objectArchetypes = createHashMapFromArray [

    ["SUPPLY_CACHE", createHashMapFromArray [
        ["classnames", ["Box_NATO_Ammo_F", "Box_East_AmmoVeh_F"]],
        ["count", [3, 8]],
        ["placement", "INTERIOR_FLOOR"],         // Cluster on building floor
        ["destroyable", true],
        ["interactable", false],
        ["briefingDesc", "Weapons and ammunition cache"]
    ]],

    ["INTEL_LAPTOP", createHashMapFromArray [
        ["classnames", ["Land_Laptop_unfolded_F"]],
        ["count", 1],
        ["placement", "ON_TABLE"],
        ["destroyable", false],
        ["interactable", true],                  // Action menu: "Recover Intel"
        ["interactionResult", "GATHER_INTEL"],
        ["briefingDesc", "Computer terminal — recover for intel"]
    ]],

    ["INTEL_DOCUMENTS", createHashMapFromArray [
        ["classnames", ["Land_File1_F", "Land_File2_F"]],
        ["count", [2, 5]],
        ["placement", "ON_TABLE"],
        ["destroyable", false],
        ["interactable", true],
        ["interactionResult", "GATHER_INTEL"],
        ["briefingDesc", "Documents — recover for intel"]
    ]],

    ["BOMB_PARTS", createHashMapFromArray [
        ["classnames", ["Land_Workbench_01_F"]], // Explosive workbenches
        ["count", [1, 3]],
        ["placement", "INTERIOR_FLOOR"],
        ["destroyable", true],
        ["interactable", false],
        ["briefingDesc", "Bombmaking equipment"]
    ]],

    ["WEAPONS_CRATE", createHashMapFromArray [
        ["classnames", ["Box_East_WpsLaunch_F"]],
        ["count", [1, 3]],
        ["placement", "OUTDOOR_PILE"],
        ["destroyable", true],
        ["interactable", false],
        ["briefingDesc", "Weapons crate"]
    ]],

    // Eden composition for visual richness — placed via composition spawner
    ["BOMB_FACTORY_INTERIOR", createHashMapFromArray [
        ["compositionPath", "compositions/bomb_factory_interior"],
        ["placement", "BUILDING_REPLACE"],       // Replaces interior of selected building
        ["destroyable", true],
        ["briefingDesc", "Bomb assembly workshop"]
    ]]
];
```

### Placement Strategy Functions

Each strategy is a small function — write once, reuse across all archetypes and mission types.

| Strategy | Purpose | Used By |
|----------|---------|---------|
| `placeInDeepBuilding` | Inner room of selected building, bodyguards optional | HVT variants |
| `placeOnGround` | Open ground at building edge, sitting/kneeling anim | Hostages, captives |
| `placeOnTable` | Search building for furniture, place on top | Laptops, documents |
| `placeInterior` | Cluster on building floor, random rotation | Crates, supplies |
| `placeOutdoorPile` | Outside cluster, near garrison anchor | Weapons crates |
| `placeInVehicle` | Inside parked vehicle (cargo or seat) | Flee escapes, vehicle-bound supplies |
| `spawnComposition` | Eden composition at building/area | Bomb factory, intel office |

```sqf
// Example signature
[_archetype, _location, _ao, _state] call DSC_core_fnc_placeInDeepBuilding;
// Returns: object/unit reference, building used, position used
```

### Completion Conditions

A condition is a code block returning bool, plus a state hashmap with what it watches.

```sqf
private _completionTypes = createHashMapFromArray [

    ["KILL_CAPTURE", createHashMapFromArray [
        ["check", { params ["_state"]; !alive (_state get "hvt") || captive (_state get "hvt") }],
        ["successMsg", "HVT eliminated"],
        ["partialMsg", "HVT escaped"]
    ]],

    ["ALL_DESTROYED", createHashMapFromArray [
        ["check", { params ["_state"]; ({ alive _x } count (_state get "objects")) == 0 }],
        ["successMsg", "All objects destroyed"],
        ["partialMsg", "Objects remain intact"]
    ]],

    ["ANY_INTERACTED", createHashMapFromArray [
        ["check", { params ["_state"]; (_state get "intelGathered") }],
        ["successMsg", "Intel recovered"],
        ["partialMsg", "Intel lost"]
    ]],

    ["HOSTAGES_EXTRACTED", createHashMapFromArray [
        ["check", { params ["_state"];
            private _h = _state get "hostages";
            (_h findIf { !alive _x }) == -1 &&
            (_h findIf { _x distance2D (_state get "extractPos") > 100 }) == -1
        }],
        ["successMsg", "All hostages extracted"],
        ["partialMsg", "Hostages lost or stranded"]
    ]],

    ["AREA_CLEAR", createHashMapFromArray [
        ["check", { params ["_state"];
            ({ alive _x } count (_state get "defenders")) < 3
        }],
        ["successMsg", "Area secured"],
        ["partialMsg", "Resistance still active"]
    ]]
];
```

The mission monitor polls `check` until it returns true, or the mission is canceled. Compound conditions are trivial:

```sqf
// "HVT dead AND intel gathered"
{ params ["_s"];
    !alive (_s get "hvt") &&
    (_s get "intelGathered")
}
```

### Mission Outcome Schema (standardized)

Every mission returns the same shape so series, influence, and next-mission briefings can consume it without per-type logic.

```sqf
createHashMapFromArray [
    ["success", true],                          // Bool
    ["completionType", "KILL_CAPTURE"],         // Which condition triggered
    ["partialResult", false],                   // Mission ended on timeout/abort
    ["entitiesEliminated", [<unit refs>]],      // HVTs killed/captured
    ["entitiesEscaped", []],                    // HVTs that fled
    ["objectsDestroyed", [<obj refs>]],
    ["objectsInteracted", [<obj refs>]],
    ["intelGathered", [<intel data>]],          // From INTEL interactions — feeds next mission
    ["casualties", 0],
    ["enemiesKilled", 24],
    ["duration", 1840],                         // Seconds
    ["evasionRatio", 0.7],                      // Combat-free time / total time
    ["seriesId", "bombmaker_hunt"],             // If part of a series
    ["seriesIndex", 1]
]
```

### Briefing as Composition

Each archetype carries a briefing fragment. Briefing builder composes from mission config.

```sqf
// Fragment system:
//   "raid_kill_capture":
//     "Eliminate {entityTitle} at {locationName}.\n{entityDesc}\n\n{areaContext}\n{threatBlock}"
//
// At briefing time:
//   {entityTitle} → _entityArchetypes get "BOMBMAKER" >> "briefingTitle"  → "IED Facilitator"
//   {entityDesc}  → _entityArchetypes get "BOMBMAKER" >> "briefingDesc"
//   {areaContext} → derived from location tags + area faction influence
//   {threatBlock} → derived from AO doctrine tags (AT teams, AA, etc.)
```

Adding a new HVT archetype = adding a hashmap entry. The briefing writes itself.

### Marker Library

Extract reusable marker drawers from `fnc_generateKillCaptureMission`:

| Function | Draws | Used By |
|----------|-------|---------|
| `fnc_drawCompoundMarkers` | Contact_circle4 + alpha-numeric dots on cluster buildings | All RAID missions |
| `fnc_drawSearchArea` | Translucent ellipse + grid label | SWEEP missions |
| `fnc_drawWaypointSequence` | Numbered dots + connecting lines | MOVEMENT missions |
| `fnc_drawDefendArea` | Colored ellipse with hold-direction arrow | DEFEND missions |

---

## Example Mission Configs (RAID variants)

### Kill/Capture Bombmaker (current style + archetype)
```sqf
private _config = createHashMapFromArray [
    ["type", "RAID"],
    ["missionProfile", "AFO"],
    ["entities", [createHashMapFromArray [["archetype", "BOMBMAKER"]]]],
    ["objects", [createHashMapFromArray [["archetype", "BOMB_PARTS"], ["count", [2, 4]]]]],
    ["completion", "KILL_CAPTURE"],
    ["markerStyle", "compound"],
    ["briefingArchetype", "raid_kill_capture"]
];
```

### Destroy Supply Cache
```sqf
private _config = createHashMapFromArray [
    ["type", "RAID"],
    ["missionProfile", "AFO"],
    ["requiredTags", ["has_industrial", "has_commercial"]],
    ["entities", []],                            // No HVT
    ["objects", [
        createHashMapFromArray [["archetype", "SUPPLY_CACHE"], ["count", [4, 8]]],
        createHashMapFromArray [["archetype", "WEAPONS_CRATE"], ["count", [1, 3]]]
    ]],
    ["completion", "ALL_DESTROYED"],
    ["markerStyle", "compound"],
    ["briefingArchetype", "raid_supply_destroy"]
];
```

### Dryhole + Intel
```sqf
private _config = createHashMapFromArray [
    ["type", "RAID"],
    ["missionProfile", "AFO"],
    ["entities", []],                            // Nobody home
    ["objects", [
        createHashMapFromArray [["archetype", "INTEL_LAPTOP"]],
        createHashMapFromArray [["archetype", "INTEL_DOCUMENTS"], ["count", [2, 4]]]
    ]],
    ["completion", "ANY_INTERACTED"],
    ["markerStyle", "compound"],
    ["briefingArchetype", "raid_intel_gather"]
];
```

### Hostage Rescue
```sqf
private _config = createHashMapFromArray [
    ["type", "RAID"],
    ["missionProfile", "AFO"],
    ["entities", [
        createHashMapFromArray [["archetype", "HOSTAGE"], ["count", 3]]
    ]],
    ["objects", []],
    ["completion", "HOSTAGES_EXTRACTED"],
    ["markerStyle", "compound"],
    ["briefingArchetype", "raid_hostage_rescue"]
];
```

### Sabotage (destroy specific equipment + intel grab)
```sqf
private _config = createHashMapFromArray [
    ["type", "RAID"],
    ["missionProfile", "DA"],
    ["entities", []],
    ["objects", [
        createHashMapFromArray [["archetype", "BOMB_FACTORY_INTERIOR"]], // Eden composition
        createHashMapFromArray [["archetype", "INTEL_LAPTOP"]]
    ]],
    ["completion", "COMPOUND"],                  // Compound condition
    ["completionExpr", { params ["_s"];
        ({ alive _x } count (_s get "objects")) == 0 &&
        (_s get "intelGathered")
    }],
    ["markerStyle", "compound"],
    ["briefingArchetype", "raid_sabotage"]
];
```

---

## Force-Multiplier Reforms (deferred — independent of raid system)

These are not part of the raid refactor. They multiply its value but each is a self-contained future feature.

### Eden Composition Library
- Save scenes as compositions in Eden (`.sqe` exports)
- Object archetype field: `compositionPath`
- Spawner reads composition file, instantiates objects relative to placement point
- Massive visual variety boost — cache rooms, intel offices, hostage holding areas, bombmaking workshops feel hand-crafted

### Animation/Behavior Templates
- `civilian_sitting_blindfolded`, `civilian_kneeling_handcuffed`, `worker_using_table`, `guard_smoking`, `surrendered_hands_up`
- Each is a hashmap: anim loop classname, AI state (`disableAI`, `setCaptive`), interaction handler
- Currently HOSTAGE archetype declares a single static animation; this would generalize the pattern

### Event-Driven Mission Monitor
Currently `fnc_evaluateCompletion` is polled by the mission loop. Better: completion conditions register event handlers (`Killed`, `HandleDamage`, `Hit`, custom `DSC_intelGathered`), monitor reacts immediately. Reduces overhead and supports complex compound conditions cleanly.

### Intel as Currency
`fnc_addInteractionHandler` already populates `DSC_currentMission >> intelTokens` with hashmap tokens (`{type, object, pos, time}`). Future hook: next-mission selector reads tokens to seed templates.
- `{ type: "next_location", target: <loc> }` → seeds region constraint of next template
- `{ type: "hvt_identity", archetype: "BOMBMAKER" }` → seeds entity of next template
- `{ type: "supply_route", path: [...] }` → seeds SWEEP mission

### Mission Series Framework
- Series definition: array of templates with branching logic
- `fnc_initMissionSeries` → stores active series in `DSC_activeSeries`
- Mission loop checks: active series? Pull next template. Otherwise random.
- Series carry state hashmap between missions (e.g. "bombmaker identified")
- Outcome of mission N (already standardized) feeds template of mission N+1

---

## Configuration Reference

For testing and tuning, the following files contain the data behind the raid system:

| File | Contents |
|------|----------|
| `addons/core/functions/missions/fnc_selectMission.sqf` | Default template — change `"type"` here to swap mission variant |
| `addons/core/functions/missions/fnc_generateMission.sqf` | Per-type raid configs (`case` blocks build entities/objects/completion inline) |
| `addons/core/functions/data/fnc_getEntityArchetypes.sqf` | OFFICER, BOMBMAKER, HOSTAGE definitions |
| `addons/core/functions/data/fnc_getObjectArchetypes.sqf` | Object classnames, counts, placement, interaction flags |
| `addons/core/functions/data/fnc_getCompletionTypes.sqf` | Condition check blocks + success/partial messages |
| `addons/core/functions/data/fnc_getBriefingFragments.sqf` | Title/objective/ROE/icon per mission type |
| `addons/core/functions/data/fnc_getMissionProfiles.sqf` | AFO / DA population presets |

---

## Implementation Order — COMPLETE

All 9 steps shipped April 2026.

1. ✅ **Extract placement strategies** — `fnc_placeInDeepBuilding` (3-path: bodyguard / structure / center)
2. ✅ **Extract marker drawer** — `fnc_drawCompoundMarkers`, config-driven
3. ✅ **Build entity archetype data** — OFFICER, BOMBMAKER, HOSTAGE + `fnc_resolveEntityClass`
4. ✅ **Build object archetype data + placement strategies** — INTEL_LAPTOP, INTEL_DOCUMENTS, SUPPLY_CACHE, BOMB_PARTS, WEAPONS_CRATE + `fnc_placeInterior`, `fnc_placeOutdoorPile`, `fnc_placeObjects` dispatcher
5. ✅ **Build completion condition system** — `fnc_getCompletionTypes` (5 conditions) + `fnc_evaluateCompletion` (polling, supports compound `completionExpr`)
6. ✅ **Refactor `generateKillCaptureMission` → `generateRaidMission`** — clean cut; old function deleted; mission dispatch lives in `fnc_generateMission` `case` blocks
7. ✅ **Briefing fragment system** — `fnc_getBriefingFragments` (5 fragments); `fnc_createMissionBriefing` composes title/objective/ROE/targets from fragment + archetypes
8. ✅ **Standardized outcome schema** — `fnc_buildMissionOutcome` published to `DSC_lastMissionOutcome` for downstream consumers
9. ✅ **Validate by adding 3 new RAID variants** — SUPPLY_DESTROY, INTEL_GATHER, HOSTAGE_RESCUE all live; each is ~15 lines of config in `fnc_generateMission`. Plus bonus infrastructure: `fnc_placeOnGround` (hostage placement), `fnc_addInteractionHandler` (intel pickup wiring), entity count expansion in raid generator, auto-resolved `extractPos` from `jointOperationCenter`.

## Force-Multiplier Reforms (deferred — independent of raid system)

These are not part of the raid refactor. They multiply its value but each is a self-contained future feature.
