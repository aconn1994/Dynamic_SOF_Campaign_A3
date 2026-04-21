# Vehicle Systems — Design Document

*Covers parked vehicles at mission areas and motorized patrol behavior*

## Part 1: Parked Vehicles (`fnc_setupVehicles`)

### Overview

Spawn faction vehicles parked near garrisoned building clusters. Some armed vehicles
get a gunner to act as a mounted sentry. Unarmed vehicles are ambient presence and
serve as future hooks (HVT flee, player hijack, reinforcement transport).

### Parking Position Logic

Adapted from archived `fn_findRoadsideParking.sqf` and `fn_findPerimeterParking.sqf`.
Both used marker-based input — we convert to position + radius input.

**Position finding** (per garrison anchor cluster):
1. Find nearby roads within 50m of the cluster center (`nearRoads`)
2. For each road segment, try both sides (offset 3-5m perpendicular)
3. Score each candidate:
   - +2 for wall/fence openings (gap in perimeter = natural parking)
   - +1 for proximity to structures (near compound entrance)
   - Reject if underwater, inside buildings, or obstructed by trees/walls within 3m
4. Align vehicle direction to road direction (±10° for natural look)
5. Weighted random selection from scored candidates

**Fallback** (no roads nearby):
- Find flat ground 10-20m from cluster center
- Face toward the cluster
- Obstacle check only (no road alignment)

### Vehicle Selection

From faction's extracted assets:
- **Unarmed trucks/cars**: Most common, ambient presence (60%)
- **Armed cars/MRAPs**: Less common, get a gunner from guards group (30%)
- **Military locations**: Higher chance of armed vehicles, possible static on truck bed (10%)

### Spawn Config

```sqf
// Per cluster: 0-2 vehicles depending on cluster size and density
private _vehiclesPerCluster = switch (_density) do {
    case "light":  { [0, 1] };
    case "medium": { [1, 1] };
    case "heavy":  { [1, 2] };
};
```

### Armed Vehicle Behavior

- Gunner manned via `moveInGunner`
- `disableAI "PATH"` on the vehicle — it stays parked
- Combat activation: same FiredNear EH as infantry guards
- When activated, gunner engages but vehicle stays put

### Future Hooks

- **HVT Flee**: If HVT's building has a nearby parked vehicle, HVT can `moveInDriver`
  and attempt to flee along roads. Players must disable vehicle or intercept.
- **Player Use**: Parked vehicles can be commandeered by players for extraction.
- **Reinforcement**: QRF infantry could mount a parked vehicle to respond faster.

### Output

Vehicles stored in AO result `"vehicles"` array alongside static weapons.
New `"parkedVehicles"` key for downstream systems (flee logic, cleanup).

---

## Part 2: Vehicle Patrols (`fnc_setupVehiclePatrol`)

### Overview

Motorized/mechanized patrol groups drive along roads, stop at waypoints, dismount
infantry for local patrols, remount, and repeat. QRF-capable at any phase.

### State Machine

```
┌─────────────────────────────────────────────┐
│              DRIVING                         │
│  Vehicle follows road waypoints              │
│  Infantry mounted                            │
│  Speed: LIMITED or NORMAL                    │
│                                              │
│  Transition: last waypoint reached           │
├────────────────────┬────────────────────────┤
│                    ▼                         │
│              DISMOUNTING                     │
│  Vehicle stops (commandStop)                 │
│  Infantry doGetOut                           │
│  Wait until all infantry out                 │
│                                              │
│  Transition: all infantry dismounted         │
├────────────────────┬────────────────────────┤
│                    ▼                         │
│           FOOT_PATROL                        │
│  Infantry patrols 50-100m radius             │
│  Vehicle crew stays with vehicle             │
│  Duration: 90-180 seconds                    │
│                                              │
│  Transition: timer expires                   │
├────────────────────┬────────────────────────┤
│                    ▼                         │
│              REMOUNTING                      │
│  Infantry ordered back to vehicle            │
│  orderGetIn true                             │
│  Retry logic: re-order every 15s if stuck    │
│  Timeout: 60s → force teleport to vehicle    │
│                                              │
│  Transition: all infantry mounted            │
├────────────────────┬────────────────────────┤
│                    ▼                         │
│         DRIVING (new waypoints)              │
│  Generate new road route                     │
│  Loop restarts                               │
└─────────────────────────────────────────────┘

    ◆ QRF INTERRUPT (from any state) ◆
    ├─ Set state = QRF
    ├─ If DRIVING: redirect vehicle to objective
    ├─ If FOOT_PATROL/DISMOUNTING:
    │    Close to objective (<300m): infantry + vehicle respond separately
    │    Far from objective (>300m): remount first, then drive
    ├─ On arrival near objective: dismount, infantry engages
    └─ Vehicle crew provides fire support or stays with vehicle
```

### Road Pathfinding

```sqf
// Build a route of connected road segments from start position
// toward a general direction, target distance of 200-800m per leg

private _fnc_buildRoadRoute = {
    params ["_startPos", "_targetDistance"];

    private _nearestRoad = [_startPos, 200] call BIS_fnc_nearestRoad;
    // Walk connected roads, preferring forward direction
    // Avoid U-turns (check angle between segments)
    // Stop when cumulative distance >= targetDistance
    // Return array of road positions for waypoints
};
```

Key considerations:
- Use `roadsConnectedTo` to walk the road graph
- Track direction to avoid U-turns (reject segments >120° from current heading)
- Dead-end detection: if road ends, use as dismount point
- Minimum 3 road waypoints per driving leg
- Road type affects speed: main road = NORMAL, track = LIMITED

### Crew vs Infantry Separation

Critical for the mount/dismount cycle:

```sqf
// On spawn, identify roles
private _vehicle = vehicle (leader _group);
private _crew = [];      // driver, gunner, commander — stay with vehicle
private _dismounts = [];  // everyone else — does foot patrols

{
    if (_x in crew _vehicle) then {
        _crew pushBack _x;
    } else {
        _dismounts pushBack _x;
    };
} forEach units _group;
```

Store as group variables:
```sqf
_group setVariable ["DSC_vehPatrol_vehicle", _vehicle];
_group setVariable ["DSC_vehPatrol_crew", _crew];
_group setVariable ["DSC_vehPatrol_dismounts", _dismounts];
_group setVariable ["DSC_vehPatrol_state", "DRIVING"];
_group setVariable ["DSC_vehPatrol_qrf", false];
```

### Remount Reliability

AI remounting is unreliable in Arma. Mitigation:

1. **Order**: `{_x orderGetIn true; _x assignAsCargo _vehicle} forEach _dismounts`
2. **Retry**: Every 15s, re-order anyone not mounted
3. **Timeout**: After 60s, teleport stragglers: `_x moveInCargo _vehicle`
4. **Validation**: `waitUntil { {vehicle _x != _vehicle} count _dismounts == 0 }`

### QRF Integration

The vehicle patrol's QRF response is richer than foot patrols:

```
On QRF trigger:
  _group setVariable ["DSC_vehPatrol_qrf", true];
  
  switch (state) do {
    case "DRIVING": {
      // Already mounted — redirect to objective
      Clear existing waypoints
      Add MOVE waypoint to objective area (nearest road to target)
      Set speed FULL
      On arrival: dismount infantry, engage
    };
    case "FOOT_PATROL": {
      if (leader _group distance2D _objective < 300) then {
        // Close enough — infantry responds on foot
        Clear foot patrol waypoints
        [_dismounts group, _objective] call BIS_fnc_taskAttack;
        // Vehicle drives to nearest road position to objective
      } else {
        // Far — remount first, then drive
        Set state = REMOUNTING
        On remount complete: drive to objective
      };
    };
    case "REMOUNTING": {
      // Already remounting — just redirect destination after mount
    };
  };
```

### Spawn Parameters

```sqf
// In populateAO or generateMission:
private _vehPatrolConfig = createHashMapFromArray [
    ["patrolCenter", _locationPos],
    ["patrolRadius", [400, 800]],    // how far driving legs go
    ["dismountRadius", [50, 100]],   // foot patrol radius at stops
    ["dismountDuration", [90, 180]], // seconds of foot patrol
    ["speed", "LIMITED"],
    ["groupTemplate", _selectedGroup] // mechanized/motorized classified group
];
```

### Group Template Selection

From classified groups, filter for vehicle patrol candidates:
```
Tags: MOTORIZED or MECHANIZED
Exclude: ARMOR, ARMORED, NAVAL, FIXED_WING
Prefer: groups with 4+ infantry dismounts
```

### Performance Considerations

- **Max concurrent vehicle patrols**: 2-3 per mission area
- **Road waypoint generation**: Cache road network around mission area once
- **State machine**: Single spawned script per group (not per frame)
- **Sleep between state checks**: 5s in driving, 10s in foot patrol, 3s in remounting
- **Cleanup**: On mission cleanup, delete vehicle + all crew/dismounts

### Function Breakdown

| Function | Purpose |
|---|---|
| `fnc_setupVehiclePatrol` | Spawn group, identify crew/dismounts, start state machine |
| `fnc_vehiclePatrolLoop` | Spawned script: state machine driving → dismount → patrol → remount |
| `fnc_buildRoadRoute` | Generate connected road waypoints from a start position |
| `fnc_findParkingPosition` | Adapted from archives: find roadside/perimeter parking spots |

### Integration with Existing Systems

- **populateAO**: Adds 1-2 vehicle patrols based on density + location tier
- **Combat activation**: Vehicle patrols start with PATH disabled like other units? Or always active since they're mobile? **Recommendation**: Always active — they're MOVING, disabling PATH defeats the purpose
- **QRF convergence**: `fnc_convergePatrols` needs to handle vehicle patrol groups (set QRF flag instead of direct waypoint)
- **Cleanup**: `fnc_cleanupMission` already deletes vehicles in the AO result array

### Implementation Order

1. `fnc_findParkingPosition` — adapt archive functions to position-based input
2. `fnc_setupVehicles` — parked vehicles at garrison clusters (Part 1)
3. `fnc_buildRoadRoute` — road pathfinding utility
4. `fnc_setupVehiclePatrol` + `fnc_vehiclePatrolLoop` — the state machine (Part 2)
5. Wire into `fnc_populateAO` and QRF system
