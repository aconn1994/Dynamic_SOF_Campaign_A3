# Ground Assault Force (GAF) Transport — Design Document

*Created April 24, 2026*

## Overview

The GAF system provides AI-driven ground convoy transport for players between the player base and mission AOs. It is the first of three transport pillars (GAF / HAF / BAF). Players who don't want to drive can request a convoy; the system handles routing, crew, lifecycle, and failure recovery automatically.

Design philosophy: **"Good enough to be useful, honest about its limits."** Arma AI ground drivers will never be perfect. The goal is a system that routes well, handles common failure cases, and degrades gracefully — not one that pretends the AI is human.

---

## Integration Context

GAF plugs into two existing systems:

**Base Registry** (`DSC_baseRegistry`): The motor pool zone at `player_base_1_motorpool` already has parked ground vehicles placed by `fnc_setupBase`. GAF uses these as its vehicle pool instead of spawning from thin air. This mirrors the transport helo pattern from `base-initialization.md`.

**`fnc_buildRoadRoute`**: Already implemented and tested by the enemy vehicle patrol system. GAF reuses this function directly for route generation. It walks `roadsConnectedTo`, avoids U-turns, and thins waypoints. No road pathfinding code needs to be written from scratch.

---

## Scope

### In Scope (Phase 2 — Transport Sprints)
- Player requests a ground convoy from base to mission AO
- Convoy drives route, players ride as passengers
- Convoy drops players at a dismount point near the AO
- Convoy waits or returns to base (player choice)
- Basic stuck detection and unstuck behavior
- Post-mission extraction convoy (same system, reversed)

### Out of Scope Now (Future)
- Convoy escort missions (player protects AI convoy)
- Resupply convoys between bases
- Contested route selection (avoiding known enemy areas)
- Dynamic route re-planning mid-convoy after contact

---

## Data Structures

### Convoy Config (input)

```sqf
private _convoyConfig = createHashMapFromArray [
    ["origin",          _originPos],          // player base position
    ["destination",     _destinationPos],      // mission AO or LZ
    ["vehiclePool",     _motorPoolVehicles],   // from DSC_baseRegistry motor pool
    ["vehicleCount",    2],                    // 1-3 vehicles
    ["side",            west],
    ["faction",         "BLU_F"],
    ["dismountRadius",  150],                  // how close to dest before dismount
    ["waitAtDest",      true],                 // wait for players or return to base
    ["waitTimeout",     1200],                 // 20 min wait before auto-return
    ["callbackComplete", {}]                   // code to run on convoy return/cleanup
];
```

### Convoy Registry Entry (output / live state)

```sqf
// DSC_GAF_activeConvoys: array of active convoy hashmaps
private _convoyEntry = createHashMapFromArray [
    ["id",              _convoyId],            // unique string e.g. "GAF_001"
    ["state",           "STAGING"],            // see state machine below
    ["vehicles",        []],                   // vehicle objects in order
    ["groups",          []],                   // crew groups per vehicle
    ["crew",            []],                   // all crew units (driver/gunner/cmdr)
    ["passengers",      []],                   // player units currently riding
    ["route",           []],                   // array of waypoint positions from fnc_buildRoadRoute
    ["routeIndex",      0],                    // current waypoint index
    ["origin",          _originPos],
    ["destination",     _destinationPos],
    ["dismountPos",     objNull],              // resolved at route-build time (nearest road to dest)
    ["stuckTimer",      0],                    // seconds at near-zero speed
    ["stuckAttempts",   0],                    // number of unstuck nudges tried
    ["startTime",       time],
    ["waitAtDest",      true],
    ["waitTimeout",     1200],
    ["runId",           _runId]                // for log correlation
];
```

---

## State Machine

```
┌──────────────────────────────────────────────────────────────────┐
│                          STAGING                                  │
│  Crew spawns + boards vehicles in motor pool                      │
│  Route is generated via fnc_buildRoadRoute                        │
│  Players notified: "Convoy ready at motor pool"                   │
│  Wait for players to board (or timeout + auto-proceed)            │
│                                                                   │
│  Transition: players boarded OR staging_timeout (60s)             │
├─────────────────────────────┬────────────────────────────────────┤
│                             ▼                                     │
│                          TRANSIT                                  │
│  Vehicles drive route waypoints                                   │
│  Speed: NORMAL on roads, LIMITED at corners/towns                 │
│  Formation: COLUMN on roads                                       │
│  Behavior: SAFE (switches to AWARE if fired upon)                 │
│  Stuck watchdog running                                           │
│                                                                   │
│  Transition: lead vehicle within dismountRadius of dismountPos    │
├─────────────────────────────┬────────────────────────────────────┤
│                             ▼                                     │
│                         DISMOUNTING                               │
│  Vehicles stop (commandStop)                                      │
│  Players notified: "Dismount here — AO is Xm [direction]"        │
│  Crew stays mounted (they are NOT dismounts)                      │
│  Wait until players have exited vehicles                          │
│                                                                   │
│  Transition: no players in any convoy vehicle                     │
├────────────────┬────────────────────────┬─────────────────────────┤
│                ▼                        ▼                         │
│           WAITING                  RETURNING                      │
│  (waitAtDest = true)           (waitAtDest = false)               │
│  Vehicles hold position        Vehicles drive route in reverse    │
│  waitTimeout ticking           Same transit logic, reversed       │
│  Players can re-board          Stuck watchdog running             │
│  for extraction                                                   │
│                                                                   │
│  Transition (WAITING):                                            │
│    players re-board → EXTRACT_TRANSIT                             │
│    timeout reached → RETURNING                                    │
│                                                                   │
│  Transition (RETURNING): arrive at motor pool                     │
├────────────────┬────────────────────────────────────────────────┤
│                ▼                                                  │
│         EXTRACT_TRANSIT                                           │
│  (players re-boarded for extraction)                              │
│  Drive reversed route back to base                                │
│  Same as TRANSIT logic                                            │
│                                                                   │
│  Transition: arrive at base motor pool                            │
├────────────────┬────────────────────────────────────────────────┤
│                ▼                                                  │
│            COMPLETE                                               │
│  Vehicles park at motor pool positions                            │
│  Crew despawns                                                    │
│  Vehicles re-registered as available in DSC_baseRegistry          │
│  Convoy entry removed from DSC_GAF_activeConvoys                  │
└──────────────────────────────────────────────────────────────────┘

  ◆ CONTACT INTERRUPT (from TRANSIT or WAITING) ◆
  ├─ State stays TRANSIT/WAITING but behavior shifts
  ├─ Vehicles: setCombatMode "RED", setBehavior "COMBAT"
  ├─ Crew defends in place (do NOT attempt to drive through contact)
  ├─ Players notified: "Convoy taking fire — dismount and clear"
  └─ Resume transit after no enemy in 200m for 30s

  ◆ ABORT (from any state) ◆
  ├─ Triggered by: all crew dead, vehicle destroyed, manual player cancel
  ├─ Players notified: "Convoy unable to continue"
  └─ Cleanup: despawn surviving crew, mark vehicles as unavailable
```

---

## Route Generation

GAF reuses `fnc_buildRoadRoute` directly. The function already exists and is validated by vehicle patrol testing. No changes needed to the function itself.

```sqf
// Build route from base motor pool to a road position near the AO
private _routeStart = getPos (selectRandom (_convoyConfig get "vehiclePool"));
private _routeEnd   = [_destination, 300] call DSC_core_fnc_nearestRoadPos;

private _route = [_routeStart, _routeEnd, 250, 1500] call DSC_core_fnc_buildRoadRoute;
// args: startPos, targetPos, minSegmentLength, maxTotalDistance
```

### Dismount Point Resolution

The dismount point is the last waypoint in the route — the closest navigable road position to the AO. It is resolved at route-build time and stored in the convoy entry.

```sqf
// Nearest road to destination, within dismountRadius
private _dismountPos = [_destination, _dismountRadius] call BIS_fnc_nearestRoad;
if (isNull _dismountPos) then {
    // fallback: last waypoint in route
    _dismountPos = last _route;
};
```

This means the player gets off at a road position ~150m from the AO edge — a natural "drop zone" — rather than driving into the compound.

---

## Crew Spawning

Convoy vehicles come from the motor pool (already parked, already in `DSC_baseRegistry`). The pattern mirrors transport helo crewing from `base-initialization.md`:

```sqf
// For each convoy vehicle:
// 1. Pick appropriate crew group from bluFor faction data
//    - Prefer MOTORIZED or classified groups with isCrew units
//    - Fall back to any infantry group if none found (driver AI works regardless)
// 2. Spawn group near vehicle
// 3. moveInDriver, moveInGunner (if armed), moveInCommander
// 4. Mark vehicle as "in use" in DSC_baseRegistry
// 5. Store crew group in convoy entry

private _crewGroup = createGroup [west, true];
private _driver    = _crewGroup createUnit [_driverClass, _vehiclePos, [], 0, "NONE"];
_driver moveInDriver _convoyVehicle;

if (count (weapons (gunner _convoyVehicle)) > 0) then {
    private _gunner = _crewGroup createUnit [_crewClass, _vehiclePos, [], 0, "NONE"];
    _gunner moveInGunner _convoyVehicle;
};
```

**Why not createVehicleCrew?** `createVehicleCrew` populates based on vehicle config and doesn't give us clean handles to individual crew. Manual spawning gives us the references needed for the stuck watchdog and cleanup.

---

## Waypoint Assignment

Rather than using the Arma group waypoint system (which can cause issues with multi-vehicle groups), each vehicle in the convoy gets waypoints assigned through its own group. The lead vehicle sets the pace; following vehicles are set to formation COLUMN.

```sqf
{
    private _veh     = _x;
    private _grp     = group (driver _veh);
    private _wpRoute = _route; // same route for all vehicles

    // Clear any existing waypoints
    while { (count waypoints _grp) > 0 } do {
        deleteWaypoint [_grp, 0];
    };

    // Add waypoints along route
    {
        private _wp = _grp addWaypoint [_x, 10];
        _wp setWaypointType "MOVE";
        _wp setWaypointSpeed "NORMAL";
        _wp setWaypointBehaviour "SAFE";
        _wp setWaypointFormation "COLUMN";
        _wp setWaypointCompletionRadius 25;
    } forEach _wpRoute;

    // Final waypoint at dismount position — HOLD
    private _finalWp = _grp addWaypoint [_dismountPos, 10];
    _finalWp setWaypointType "HOLD";

} forEach _convoyVehicles;
```

Speed modifiers are applied per-waypoint based on road type detected at route-build time (stored as metadata alongside each waypoint position).

---

## Stuck Detection Watchdog

Runs as a separate spawned script alongside the convoy loop. Checks every 15 seconds during TRANSIT.

```sqf
// DSC_GAF_fnc_stuckWatchdog
params ["_convoyEntry"];

while { (_convoyEntry get "state") in ["TRANSIT", "EXTRACT_TRANSIT", "RETURNING"] } do {
    sleep 15;

    private _leadVehicle = (_convoyEntry get "vehicles") select 0;
    private _speed       = speed _leadVehicle; // km/h

    if (_speed < 2) then {
        private _stuckTimer = (_convoyEntry get "stuckTimer") + 15;
        _convoyEntry set ["stuckTimer", _stuckTimer];

        // Log every tick while stuck
        [_convoyEntry, format ["Lead speed: %1 km/h | stuck timer: %2s",
            round _speed, _stuckTimer]] call DSC_GAF_fnc_logConvoy;

        if (_stuckTimer >= 30) then {
            [_convoyEntry] call DSC_GAF_fnc_unstuck;
        };
    } else {
        // Moving — reset
        if ((_convoyEntry get "stuckTimer") > 0) then {
            [_convoyEntry, "Stuck resolved — convoy moving"] call DSC_GAF_fnc_logConvoy;
        };
        _convoyEntry set ["stuckTimer", 0];
    };
};
```

### Unstuck Procedure (in priority order)

```sqf
// DSC_GAF_fnc_unstuck
params ["_convoyEntry"];

private _attempts   = (_convoyEntry get "stuckAttempts") + 1;
private _leadVeh    = (_convoyEntry get "vehicles") select 0;
private _nextWpIdx  = (_convoyEntry get "routeIndex") + 1;
private _nextWpPos  = (_convoyEntry get "route") select _nextWpIdx;

_convoyEntry set ["stuckAttempts", _attempts];

switch (_attempts) do {
    case 1: {
        // Attempt 1: Delete current waypoint, force move to next
        deleteWaypoint [group (driver _leadVeh), 0];
        [_convoyEntry, "Unstuck attempt 1 — skipping waypoint"] call DSC_GAF_fnc_logConvoy;
    };
    case 2: {
        // Attempt 2: Stop vehicle, teleport slightly forward toward next waypoint
        private _nudgePos = _leadVeh getPos [10, _leadVeh getDir _nextWpPos];
        _leadVeh setPos _nudgePos;
        [_convoyEntry, "Unstuck attempt 2 — nudge forward"] call DSC_GAF_fnc_logConvoy;
    };
    default {
        // Attempt 3+: Teleport lead vehicle to next waypoint on road
        private _safePos = [_nextWpPos, 5] call BIS_fnc_nearestRoad;
        if (!isNull _safePos) then {
            _leadVeh setPos (getPos _safePos);
            [_convoyEntry, format ["Unstuck attempt %1 — teleport to next waypoint", _attempts]]
                call DSC_GAF_fnc_logConvoy;
        } else {
            // No road nearby — this route segment is unnavigable, abort convoy
            [_convoyEntry, "UNSTUCK FAILED — no road near waypoint — ABORT"] call DSC_GAF_fnc_logConvoy;
            [_convoyEntry] call DSC_GAF_fnc_abortConvoy;
        };
    };
};

// Reset stuck timer after each attempt
_convoyEntry set ["stuckTimer", 0];
```

---

## Player Interface

### Request Convoy (action on `jointOperationCenter` flagpole)

```
"Request Ground Convoy"
  → Only available when: missionInProgress && convoy not already active
  → Opens map click to set pickup point (defaults to motor pool)
  → Convoy stages, hint to player: "Convoy forming at motor pool"
```

### Boarding

Players walk to the convoy vehicles and use ACE interaction (or vanilla action if ACE not loaded) to board as passengers. No special code needed — Arma's built-in `moveInCargo` via player action handles this.

### En Route Hints

Key state transitions broadcast a hint to all players:

| State Change | Hint |
|---|---|
| STAGING → TRANSIT | "Convoy moving out. ETA ~Xm" |
| Stuck detected | "Convoy navigating obstacle..." |
| TRANSIT → DISMOUNTING | "Approaching AO. Prepare to dismount." |
| WAITING timeout | "Convoy returning to base." |
| COMPLETE | "Convoy returned to base." |
| ABORT | "Convoy unable to continue. Crew lost." |

---

## Motor Pool Integration

GAF modifies the base registry pattern from `base-initialization.md` to track vehicle availability:

```sqf
// Add to motor pool zone entry in DSC_baseRegistry:
"available": true    // false when vehicle is assigned to an active convoy
"convoyId":  ""      // ID of the convoy currently using this vehicle
```

When requesting a convoy:
1. Query `DSC_baseRegistry` → player base → motor pool vehicles where `available == true`
2. Select `vehicleCount` vehicles (prefer armed lead + unarmed transport)
3. Mark them `available = false`, set `convoyId`
4. On convoy COMPLETE or ABORT: reset to `available = true`, clear `convoyId`

This prevents the same vehicle being assigned to two convoys and ensures the motor pool visually empties as convoys depart.

---

## Contact Handling

The convoy is NOT a combat unit. The design philosophy is **get the players to the fight, not fight its way there**. On contact:

```sqf
// FiredNear EH on lead vehicle
_leadVehicle addEventHandler ["FiredNear", {
    params ["_vehicle", "_shooter", "_distance", "_projectile"];

    // Switch convoy to defensive posture
    {
        setCombatMode [group (driver _x), "RED"];
        setBehaviour [group (driver _x), "COMBAT"];
    } forEach (_convoyEntry get "vehicles");

    // Notify players
    ["Convoy taking fire! Dismount and clear the area."] remoteExec ["hint", 0];

    // Start 30s clear timer — resume transit if no nearby enemy
    [_convoyEntry] spawn DSC_GAF_fnc_waitForClear;
}];
```

The convoy does not route around threats or attempt to flee. It stops, crew defends, and players are expected to dismount and handle the contact. This is intentional — it keeps the AI behavior simple and predictable.

---

## Performance Considerations

- **Dynamic simulation on all crew**: `{ _x triggerDynamicSimulation true } forEach _allCrewUnits` — follows same pattern as base entities
- **Max concurrent convoys**: 1 per player group is sufficient; no need for multiple simultaneous GAF convoys
- **Sleep intervals**: Transit monitor loop sleeps 10s, stuck watchdog sleeps 15s, no per-frame logic
- **Waypoint cleanup**: All waypoints deleted on convoy COMPLETE/ABORT — no dangling AI goals
- **Crew despawn on complete**: Crew units deleted at COMPLETE; vehicles returned to motor pool (empty, dynamic sim, near-zero cost)

---

## Function Breakdown

| Function | Purpose | File |
|---|---|---|
| `fnc_requestGAF` | Player-facing: validate, select vehicles, build config, start convoy | `functions/transport/fnc_requestGAF.sqf` |
| `fnc_spawnConvoyCrew` | Crew vehicles from motor pool, build convoy entry | `functions/transport/fnc_spawnConvoyCrew.sqf` |
| `fnc_convoyLoop` | Spawned state machine: manages full convoy lifecycle | `functions/transport/fnc_convoyLoop.sqf` |
| `fnc_buildConvoyRoute` | Thin wrapper around `fnc_buildRoadRoute` with dismount resolution | `functions/transport/fnc_buildConvoyRoute.sqf` |
| `fnc_stuckWatchdog` | Parallel stuck detection + unstuck logic | `functions/transport/fnc_stuckWatchdog.sqf` |
| `fnc_abortConvoy` | Cleanup on failure: notify players, despawn crew, release vehicles | `functions/transport/fnc_abortConvoy.sqf` |
| `fnc_completeConvoy` | Cleanup on success: park vehicles, despawn crew, update registry | `functions/transport/fnc_completeConvoy.sqf` |
| `fnc_logConvoy` | Structured logging — all convoy events through one function | `functions/transport/fnc_logConvoy.sqf` |

**Reused without modification:**
- `fnc_buildRoadRoute` — road graph walker (already complete)
- `fnc_setupBase` / base registry — vehicle pool source
- `fnc_addCombatActivation` — crew combat response

---

## Implementation Order

### Sprint T1 — Route Only (no vehicles, test pathfinding)
1. Create `fnc_buildConvoyRoute` wrapping `fnc_buildRoadRoute`
2. Add debug action: "Test GAF Route" → generates route to current mission AO, draws markers
3. Visually validate routes on Altis across 5-10 origin/destination pairs
4. Tune `fnc_buildRoadRoute` parameters if needed (segment length, max distance)
5. **Output**: Confidence in road pathfinding before any vehicles involved

### Sprint T2 — Convoy Core
1. `fnc_spawnConvoyCrew` — crew motor pool vehicles, build convoy entry
2. `fnc_convoyLoop` — STAGING → TRANSIT → DISMOUNTING → WAITING
3. `fnc_stuckWatchdog` — basic stuck detection + skip-waypoint unstuck
4. Wire `fnc_requestGAF` to JOC action
5. **Output**: Players can request and ride a convoy to the AO

### Sprint T3 — Return + Extraction
1. RETURNING state in `fnc_convoyLoop`
2. EXTRACT_TRANSIT state (players re-board for return trip)
3. `fnc_completeConvoy` — park vehicles, despawn crew, update registry
4. Motor pool availability tracking in base registry
5. **Output**: Full round-trip convoy lifecycle

### Sprint T4 — Hardening
1. `fnc_abortConvoy` — handle crew death, vehicle destruction
2. Teleport unstuck (attempt 3+) in `fnc_stuckWatchdog`
3. Contact handling (FiredNear EH, defensive posture)
4. Player hints for all state transitions
5. **Output**: System is playtest-ready

---

## Known AI Limitations (Honest Assessment)

These are accepted limitations, not bugs to fix:

- **Bridge navigation**: Narrow bridges cause vehicles to clip or stop. Mitigation: stuck watchdog teleports through after 45s.
- **Formation cohesion on curves**: Trailing vehicles may cut corners. Acceptable — they catch up.
- **Uneven terrain off-road**: Dismount point is on a road; the AO approach is the player's problem.
- **Reversing**: AI reversal is terrible. Never issue reverse orders. RETURNING uses a forward route.
- **3+ vehicles**: Convoy cohesion degrades with more than 3 vehicles. `vehicleCount` is capped at 3.

---

## Future Hooks

These are not in scope but the architecture accommodates them without restructuring:

- **HAF integration**: Same state machine pattern, different vehicle type (helicopter). `fnc_convoyLoop` logic can be abstracted into a shared transport state machine.
- **Contested routing**: `fnc_buildConvoyRoute` can accept an exclusion zone list (known opFor positions from influence data) to try alternate roads.
- **Multi-stop convoy**: Route array already supports arbitrary waypoints — adding a "collect players at waypoint B then continue to C" is a config change.
- **Escort missions**: Set `waitAtDest = false` and add a cargo vehicle to the convoy — players protect it en route.