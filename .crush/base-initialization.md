# Base Initialization System — Design Plan

*Created April 22, 2026*

## Overview

Expand Step 4 of `fnc_initServer` from marker-only into a full **base initialization pipeline** that gives every military installation (player, bluFor, opFor) a living presence using dynamic simulation for performance. The system produces a `DSC_baseRegistry` — a hashmap of all initialized bases keyed by ID — that downstream systems (missions, QRF, transport, campaign series) can query.

## Architecture

### New Init Flow (Step 4 becomes Step 4a + 4b)

```
STEP 4a: Mark Military Installations (existing — unchanged)
    └── Publishes DSC_baseMarkerData / DSC_outpostMarkerData for client map draw

STEP 4b: Initialize Bases  ← NEW
    ├── fnc_initBases (orchestrator)
    │     ├── Build base registry from influence data + player base markers
    │     ├── For each base → call fnc_setupBase
    │     └── Publish DSC_baseRegistry globally
    │
    └── fnc_setupBase (per-base worker)
          ├── Scan structures (reuse from location data or scan marker area)
          ├── setupGuards (towers, static weapons, perimeter)
          ├── Place helipad vehicles (transport/attack per side)
          ├── Place ambient parked vehicles
          ├── Enable dynamic simulation on ALL spawned entities
          └── Return base hashmap with entity references
```

### Base Registry Schema

```sqf
// DSC_baseRegistry: HashMap keyed by base ID
// Each entry:
{
    "id":            "player_base_1",        // or location ID from influence
    "type":          "playerBase",           // "playerBase" | "bluFor" | "opFor"
    "side":          west,
    "faction":       "BLU_F",
    "position":      [x, y, z],
    "name":          "Salt Flats Airstrip",
    "radius":        500,
    "units":         [],                     // all spawned units (for cleanup)
    "vehicles":      [],                     // all spawned vehicles (across all zones)
    "groups":        [],                     // all spawned groups
    "structures":    [],                     // building objects in base area
    "influenceId":   "",                     // link back to influence system (empty for player base)

    // Zone data (player base only — bluFor/opFor use flat structure)
    "zones": {
        "heliport":  { "markers": [], "pads": [], "vehicles": [] },  // visible helipads → helicopters
        "airstrip":  { "markers": [], "pads": [], "vehicles": [] },  // invisible pads → aircraft/rotary
        "motorpool": { "markers": [], "pads": [], "vehicles": [] },  // invisible pads → ground vehicles
        "toc":       { "markers": [], "pads": [], "vehicles": [] }   // invisible pads → utility vehicles
    }
}
```

**Zone marker naming**: `{baseId}_{zoneName}_{index}` — e.g., `player_base_1_heliport_0`, `player_base_1_motorpool_1`. Multiple markers per zone tile together to cover irregular shapes. The zone name is parsed from the marker name by stripping the base prefix and trailing `_N` index.

---

## Part 1: Player Base (`player_base_1`)

### 1A. Structure Scan via Markers

The player base is editor-placed and excluded from `fnc_scanLocations`. Use the existing `player_base_*` marker pattern plus new sub-area markers to find structures.

**New marker convention** (placed in Eden per map):

| Marker | Purpose |
|--------|---------|
| `player_base_1` | Main area boundary (already exists) |
| `player_base_1_heliport` | Helipad zone — scan for `HeliH` / `Land_HelipadSquare_F` etc. |
| `player_base_1_motorpool` | (Future) Vehicle staging area |
| `player_base_1_toc` | (Future) Tactical ops center zone |

**Implementation:**
1. Collect all markers matching `player_base_1_*` prefix
2. For the main marker, get its area (`getMarkerSize`) and scan for all structures inside using `nearObjects`
3. For `_heliport` sub-marker, scan specifically for helipad objects (`HeliH`, `Land_HelipadSquare_F`, `Land_HelipadCircle_F`, `Land_HelipadRescue_F`, etc.)
4. Classify structures using existing `fnc_getStructureTypes` lists to find guard towers, bunkers, etc.

### 1B. Guards — Tower Sentries & Static Weapons

Scan the **main `player_base_1` marker** (full base boundary) for all structures, then feed them to `fnc_setupGuards`. Guard towers and patrol towers are scattered across the entire base — not confined to any sub-zone.

```sqf
// Scan ALL structures inside the main base marker boundary
private _baseStructures = [_baseMarkerPos, _baseMarkerArea] call ...; // nearObjects within marker

// Feed the full structure list to setupGuards
[_basePos, "military", _bluForFaction, west, createHashMapFromArray [
    ["structures", _baseStructures],  // full base scan — catches all towers everywhere
    ["assets", _bluForAssets],
    ["maxStatics", 4],
    ["staticChance", 0.7],
    ["maxPerimeter", 5]
]] call DSC_core_fnc_setupGuards;
```

`setupGuards` already handles:
- Finding guard towers/bunkers → static weapons or lookouts on top positions
- Perimeter sentry pairs with concealment seeking
- Combat activation via `fnc_addCombatActivation`

**No code changes needed to `fnc_setupGuards`** — just pass appropriate config overrides. The key is feeding it structures from the entire `player_base_1` marker area so it finds every tower across the base.

**Dynamic simulation**: After spawning, loop all units and enable:
```sqf
{ _x triggerDynamicSimulation true } forEach _units;
// Dynamic sim activates within ~500m of players by default
```

### 1C. Zone Vehicle Placement

Each sub-zone uses its helipad objects (visible or invisible) as precise spawn anchors. The vehicle type placed depends on the zone.

**Heliport** (`player_base_1_heliport_*`):
- Scan for **visible** helipad objects inside marker area
- Place transport helicopters (from `fnc_extractAssets` → `helicopters.transport`)
- Empty, unlocked — these are the pool for `fnc_spawnTransportHelo` / extraction
- Don't crew them. Crew spawns on demand when player requests transport.

**Airstrip** (`player_base_1_airstrip_*`):
- Scan for **invisible** helipads (`Land_HelipadEmpty_F`) in front of hangars
- Place rotary-wing or fixed-wing aircraft depending on available assets
- Empty, parked — future use for CAS requests, recon flights, etc.

**Motor Pool** (`player_base_1_motorpool_*`):
- Scan for **invisible** helipads in parking formation
- Place ground vehicles: trucks, armed cars, APCs, MRAPs (from `fnc_extractAssets` → `cars`, `trucks`, `apcs`)
- Empty, unlocked — ambient props now, player-usable logistics vehicles later

**TOC** (`player_base_1_toc_*`):
- Scan for **invisible** helipads
- Place light utility vehicles: quad bikes, Prowlers, open-door HMMWVs (from `fnc_extractAssets` → `cars.unarmed`)
- Player-accessible for moving around the base

**Placement logic** (same for all zones):
```sqf
// For each helipad found in zone:
//   1. Get pad position + direction
//   2. Pick vehicle class appropriate to zone type
//   3. createVehicle at pad position, set direction to match pad
//   4. Register in base registry under zone-specific key
```

**Key detail**: No crew on any of these. All sit empty with dynamic sim. When a system needs a vehicle (transport request, QRF, player action), it crews on demand.

**Modify `fnc_spawnTransportHelo`** (or create wrapper `fnc_activateBaseHelo`):
- Accept optional `"vehicle"` key in config — if provided, crew the existing vehicle instead of spawning new
- Look up `DSC_baseRegistry` → player base → `helipadVehicles` for available helos
- After mission/extraction complete, fly back to pad, despawn crew, vehicle stays

---

## Part 2: BluFor Partner Bases

These come from `_influenceData get "bases"` where `controlledBy == "bluFor"`. They already have location data from the scan (structures, position, radius, military tier).

### Setup (lighter than player base)

```
Per bluFor base:
├── setupGuards (military mode, default config — 2-3 statics, 3-5 perimeter)
├── 1-2 parked transport helos IF helipads found in structures
├── 1-2 parked vehicles near structures
└── Dynamic simulation on everything
```

**Guard config**: Use defaults from `fnc_setupGuards` — no overrides needed. The existing function already scales appropriately for military locations.

**Helipad scan**: Check the base's `assignedStructures` for helipad-type objects. Bases near airfields may have them; many won't. Only place helos where pads exist.

**Future hooks** (no code now, just data in registry):
- Mission series: "Stage out of FOB Kavala for 3-mission arc" — base ID in mission config
- Resupply: Player can visit bluFor bases to rearm (action on ammo crate / vehicle)
- QRF source: BluFor reinforcements spawn from nearest friendly base
- Under-attack missions: Pick a bluFor base from registry, spawn attacking opFor, player responds

### Performance Note

BluFor bases are in the "safe zone" or friendly territory — players may visit but won't always be near them. Dynamic simulation means zero CPU cost when players are >500m away. A base with 10-15 units and 3-4 vehicles costs nothing until approached.

---

## Part 3: OpFor Bases

These come from `_influenceData get "bases"` where `controlledBy == "opFor"`.

### Setup (similar to bluFor but enemy)

```
Per opFor base:
├── setupGuards (military mode, slightly heavier config)
│     maxStatics: 3-4, staticChance: 0.6, maxPerimeter: 4-6
├── 1-2 helicopters on helipads (if found) — these ARE the QRF pool
├── 2-3 parked military vehicles (armed cars, APCs near motor pool areas)
└── Dynamic simulation on everything
```

**QRF Integration**: When a mission generates QRF (`fnc_generateMission` already does this), instead of spawning QRF from nothing, check `DSC_baseRegistry` for nearest opFor base:
- If base has helipad vehicles → QRF arrives by helo (crew spawns, flies to AO)
- If base has ground vehicles → QRF drives from base
- If neither → fall back to current spawn-from-distance behavior

**Proximity Engagement**: OpFor bases with dynamic sim already handle this naturally — if a player gets within ~500m, units activate and will engage. The 800m danger zone markers (already implemented in Step 4a) warn players. No additional code needed for the "avoid these areas" behavior.

**HVT Flee Target**: Mission system can reference `DSC_baseRegistry` to pick a nearby opFor base as flee destination. HVT gets waypoint to base position if they escape the AO.

---

## Part 4: Performance Strategy

### Dynamic Simulation (Core Mechanism)

Every entity spawned by the base system gets `triggerDynamicSimulation true`. This is Arma's built-in LOD system for AI:

| Player Distance | Behavior |
|----------------|----------|
| >500m (default) | **Frozen** — zero CPU, units exist but don't simulate |
| <500m | **Active** — full AI, pathfinding, combat |

**Why this is ideal for bases:**
- Player base: Units only simulate when player is home (which is when you want the "alive" feeling)
- BluFor bases: Simulate only when player visits (rare, intentional)
- OpFor bases: Simulate only when player approaches (combat encounter or nearby mission)
- Estimated cost: **0 FPS impact** for 90% of play time

### Entity Budget Per Base Type

| Base Type | Units | Vehicles | Total Objects |
|-----------|-------|----------|---------------|
| Player Base | 12-18 (guards + lookouts + perimeter) | 8-15 (heliport helos + airstrip + motorpool + toc utility) | ~25-30 |
| BluFor Base | 8-12 | 2-3 | ~12 |
| OpFor Base | 10-15 | 3-5 | ~15 |

With ~4-6 bases per side on Altis, that's roughly **80-150 entities** total, all frozen via dynamic sim. Trivial.

### What NOT to Spawn

- No foot patrols on bases at init (save for mission AOs)
- No garrisoned buildings (save for mission population)
- No vehicle patrols (save for mission AOs)
- Guards + static weapons + parked vehicles = minimum viable "alive" feel

---

## Part 5: `fnc_setupBase` — The Per-Base Worker

This is the main new function. Pseudocode:

```sqf
/*
 * Arguments:
 *   0: Base config hashmap
 *      "id", "type" (playerBase/bluFor/opFor), "position", "radius",
 *      "side", "faction", "structures" (optional), "markers" (optional)
 *
 * Returns:
 *   Base registry entry hashmap
 */

// 1. Scan structures
//    - If type == "playerBase":
//        a. Get main marker (player_base_1) area → nearObjects for ALL structures
//        b. Parse sub-markers by zone: group player_base_1_*_N markers into zones
//           (heliport, airstrip, motorpool, toc)
//        c. For each zone: scan marker areas for helipad objects
//           - Visible helipads (Land_HelipadSquare_F etc.) → helicopter spawn points
//           - Invisible helipads (Land_HelipadEmpty_F) → vehicle spawn anchors
//    - Else: use structures from location/influence data

// 2. Setup guards (uses main marker scan, NOT zone scans)
//    - Pass ALL structures from step 1a to fnc_setupGuards
//    - This catches every tower/bunker across the entire base footprint
//    - Player base: heavy config (maxStatics 4, staticChance 0.7, maxPerimeter 5)
//    - BluFor: default config
//    - OpFor: medium-heavy config

// 3. Place zone vehicles (player base only)
//    For each zone with found pads:
//    - heliport pads → transport helicopters (from extractAssets helicopters.transport)
//    - airstrip pads → aircraft or additional rotary (from extractAssets helicopters/planes)
//    - motorpool pads → ground vehicles (from extractAssets cars, trucks, apcs)
//    - toc pads → light utility (from extractAssets cars.unarmed — quads, prowlers, HMMWVs)
//    All vehicles: empty, no crew, placed at pad position + direction

// 4. Place vehicles for bluFor/opFor bases (non-player)
//    - Scan structures for helipad objects → place helos if found
//    - Use fnc_findParkingPosition near structures for 1-3 ground vehicles

// 5. Enable dynamic simulation on ALL entities
//    { _x triggerDynamicSimulation true } forEach (_units + _vehicles);

// 6. Build and return registry entry with zone data
```

### `fnc_initBases` — The Orchestrator

```sqf
// Runs in initServer after Step 4a

// 1. Build player base configs from player_base_* markers
// 2. Build bluFor base configs from influenceData bases where controlledBy == "bluFor"
// 3. Build opFor base configs from influenceData bases where controlledBy == "opFor"
// 4. For each config → call fnc_setupBase
// 5. Store results in DSC_baseRegistry (missionNamespace, publicVariable)
```

---

## Part 6: Transport Helo Integration

### Current State
- `fnc_spawnTransportHelo` spawns a Chinook from thin air at a given position
- `fnc_requestExtraction` uses it, spawning 2km away from pickup LZ in direction of `jointOperationCenter`

### Target State
- Helo sits on a pad at player base (visible, immersive)
- Player requests transport → crew spawns, boards helo on pad, engines start, lifts off
- Helo flies to pickup/destination as normal
- After mission, helo returns to pad, crew despawns, helo stays

### Changes Needed

**`fnc_spawnTransportHelo`** — Add alternate mode:
```sqf
// New optional config keys:
// "vehicle": existing vehicle object to crew (skip createVehicle)
// "startOnGround": true = engine startup sequence instead of air spawn
```

**`fnc_requestExtraction`** — Modify spawn logic:
```sqf
// Instead of:
//   _spawnPos = 2km away, spawn in air
// Do:
//   Check DSC_baseRegistry → playerBase → helipadVehicles
//   If available helo: crew it on the pad, taxi + takeoff
//   Else: fallback to current air spawn (degraded but functional)
```

**New: `fnc_returnHeloToBase`** — After passengers disembark:
```sqf
// Fly back to player base heliport
// Land on original pad
// Despawn crew
// Mark vehicle as available in registry
```

### Heliport Marker Workflow (Eden Setup)

1. Place `player_base_1_heliport` area marker over your helipad cluster in Eden
2. At init, `fnc_setupBase` scans that area for helipad objects
3. Places 1-2 transport helos on found pads
4. Registers them in base registry under `helipadVehicles`

---

## Implementation Order (Recommended)

### Sprint 1: Player Base Guards (smallest useful increment)
1. Place `player_base_1_heliport` marker in Eden on Altis salt flats
2. Create `fnc_setupBase` — just the structure scan + guard setup portion
3. Create `fnc_initBases` — just handles player base initially
4. Wire into `fnc_initServer` Step 4b
5. Test: launch, walk around base, see guards in towers + perimeter sentries
6. Verify dynamic simulation works (walk away, come back — units should deactivate/reactivate)

### Sprint 2: Player Base Helipads
1. Add helipad scanning to `fnc_setupBase`
2. Place transport helos on found pads
3. Modify `fnc_spawnTransportHelo` to accept existing vehicle
4. Modify `fnc_requestExtraction` to use pad helo
5. Test: see helos on pads, request extraction, helo lifts off from pad

### Sprint 3: Presence Manager (replaces static base spawning)

BluFor/opFor base population is **deferred** — not spawned at init. Instead, a presence manager handles dynamic spawning based on player proximity and game state.

**`fnc_presenceManager`** — spawned from initServer, runs a sleep loop (15-30s):

```
while { true } do {
    sleep 20;

    // For each zone (bases, influence areas, towns):
    //   Check player distance + zone state
    //   Transition state machine as needed

    // Zone states:
    //   DORMANT     → no entities, no cost
    //   ACTIVATING  → player within activation radius, spawning in progress
    //   ACTIVE      → entities live, player nearby
    //   DESPAWNING  → player left, cleanup after grace period (avoid pop-in/out)
    //   COMBAT      → player engaged, never despawn mid-fight
};
```

**Activation rules:**

| Zone Type | Activate | Deactivate | Spawns |
|-----------|----------|------------|--------|
| OpFor base | Player <1.5km | Player >2.5km, no combat | Guards + garrison via fnc_setupBase |
| BluFor base | Player <1.5km | Player >2.5km | Friendly guards + ambient vehicles |
| OpFor influence area | Player enters | Player leaves + buffer | Patrols, checkpoints |
| BluFor influence area | Player enters | Player leaves + buffer | Friendly patrols |
| Town/populated area | Player <800m | Player >1.2km | Civilians, ambient life |

**Forced encounters:**
- Track `DSC_lastCombatTime` (updated by FiredNear/killed EHs)
- If player in opFor territory and `time - DSC_lastCombatTime > threshold` (5-10 min):
  - Spawn patrol 300-500m from player, moving toward them
  - Or spawn vehicle patrol on nearest road
- Threshold scales with influence — deeper in enemy territory = shorter timer

**State machine prevents issues:**
- `COMBAT` state locks the zone — no despawning during engagement
- `ACTIVATING` checks prevent double-spawn if loop fires twice before spawn completes
- Grace period on `DESPAWNING` (60-90s) prevents pop-in/out if player is circling zone edge

**Data backbone** (already exists):
- `DSC_baseRegistry` — what to spawn at each base
- `DSC_influenceData` — who controls each area, influence strength
- `DSC_locations` — structure data for garrison/patrol spawning
- `fnc_setupBase` / `fnc_setupGuards` / `fnc_populateAO` — spawning functions already built

**Key difference from mission AO population:**
- Mission AOs are one-shot: populate → play → cleanup
- Presence zones are persistent: activate → deactivate → reactivate
- Presence zones track their spawned entities for cleanup but reuse them if player returns before despawn completes

### Sprint 4: QRF Integration + Transport Return
1. Create `fnc_returnHeloToBase` for post-mission helo return
2. Modify QRF spawning to pull from nearest opFor base registry
3. Wire HVT flee to nearest opFor base
4. Test: complete mission, watch helo return; trigger QRF, see it come from a real base

### Future Sprints (Phase 3 territory)
- "Base under attack" mission type using registry
- Mission series staging from bluFor bases
- Resupply/rearm actions at friendly bases
- Ambient sounds/lighting at bases (low-cost immersion: campfire light, generator sound)
- Motor pool marker zones for ground vehicle staging

---

## Files to Create/Modify

| File | Action | Sprint |
|------|--------|--------|
| `functions/init/fnc_initBases.sqf` | **NEW** — orchestrator | 1 |
| `functions/init/fnc_setupBase.sqf` | **NEW** — per-base worker | 1 |
| `XEH_PREP.hpp` | Register new functions | 1 |
| `fnc_initServer.sqf` | Add Step 4b call | 1 |
| Eden: `DSC_Altis.Altis/mission.sqm` | Add heliport marker | 1 |
| `functions/base/fnc_spawnTransportHelo.sqf` | Add "vehicle" config key | 2 |
| `functions/base/fnc_requestExtraction.sqf` | Use base registry helo | 2 |
| `functions/base/fnc_returnHeloToBase.sqf` | **NEW** — post-mission return | 4 |
| `functions/missions/fnc_generateMission.sqf` | QRF from base registry | 4 |

---

## Key Design Decisions

1. **Dynamic sim over distance checks** — Arma's built-in system is cheaper than scripted distance-based spawn/despawn. Let the engine handle it.

2. **Empty vehicles on pads** — Don't crew idle helos. Crew on demand. An empty vehicle with dynamic sim costs almost nothing.

3. **Registry pattern** — Every downstream system (missions, QRF, transport, campaign) queries `DSC_baseRegistry` instead of scanning the world. Single source of truth.

4. **Reuse `fnc_setupGuards`** — It already does exactly what's needed for towers + perimeter. Just pass config overrides for density.

5. **Player base is special but not unique** — Same `fnc_setupBase` function handles all three types. The player base just gets heavier config + sub-markers for zones. This means bluFor bases can trivially become "forward staging bases" in future missions by applying player-base-level config to them.

6. **Marker-based zones for player base** — Eden markers define functional areas (heliport, motor pool, TOC). This is flexible per map and doesn't require code changes when base layout differs between maps.
