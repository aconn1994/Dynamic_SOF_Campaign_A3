# GAF Transport — Testing Framework

*Created April 24, 2026*

## Philosophy

SQF is not unit-testable in the traditional sense — there's no test runner, no mocking framework, and most logic depends on Arma engine state. The testing strategy instead relies on:

1. **Structured logging** with a consistent format that can be parsed rapidly from RPT files
2. **Layered validation** — catch problems at the earliest possible stage before handing off to AI
3. **Post-run summary blocks** that make bulk test analysis fast (paste log, get diagnosis)
4. **Visual debug markers** for spatial validation that would take minutes to read from logs

The goal is that after a test run, an RPT log can be parsed — manually or by AI — to immediately identify which phase failed, why, and where on the map.

---

## Log Format Specification

All GAF logging routes through `fnc_logConvoy`. Every line follows this format:

```
[DSC_GAF] [CATEGORY] [RUN_ID] message
```

Categories:
- `[ROUTE]` — pathfinding and waypoint generation
- `[CREW]` — vehicle crewing and group setup
- `[CONVOY]` — state machine transitions and runtime events
- `[STUCK]` — stuck detection and unstuck attempts
- `[CONTACT]` — enemy contact events
- `[VALIDATE]` — pre-flight validation checks
- `[SUMMARY]` — structured end-of-run block
- `[ERROR]` — unexpected states, fallbacks, failures

Run ID format: `GAF_YYYYMMDD_NNN` (e.g. `GAF_20250501_001`) — allows correlating all events from a single convoy run across a long log file.

---

## Layer 1: Route Validation

Runs before any vehicles move. Validates that `fnc_buildConvoyRoute` produced a usable path.

### Checks

**1A — Route exists and terminates**
```
[DSC_GAF] [ROUTE] [GAF_20250501_001] Origin: [12543.2, 14821.6, 0] Dest: [8234.1, 9156.3, 0]
[DSC_GAF] [ROUTE] [GAF_20250501_001] Straight-line dist: 6243m
[DSC_GAF] [ROUTE] [GAF_20250501_001] Road nodes sampled: 84
[DSC_GAF] [ROUTE] [GAF_20250501_001] Path found: true | waypoints in route: 24 | path dist: 8912m
[DSC_GAF] [ROUTE] [GAF_20250501_001] Path/straight ratio: 1.43 — ACCEPTABLE
```

**1B — Ratio flags**
- Ratio < 1.05: Suspiciously direct — possible cross-country path, not road-following
- Ratio 1.0–2.5: Acceptable (roads wind)
- Ratio 2.5–4.0: Warning — possible backtrack or inefficient route
- Ratio > 4.0: Fail — route is likely broken

```
[DSC_GAF] [ROUTE] [GAF_20250501_001] WARN ratio: 3.1 — possible backtrack, review route markers
[DSC_GAF] [ROUTE] [GAF_20250501_001] FAIL ratio: 5.7 — route rejected, no convoy dispatched
```

**1C — Dismount point resolution**
```
[DSC_GAF] [ROUTE] [GAF_20250501_001] Dismount pos: [8389.2, 9201.1, 0] | dist to dest: 127m — OK
[DSC_GAF] [ROUTE] [GAF_20250501_001] WARN dismount pos: 312m from dest — road network sparse near AO
[DSC_GAF] [ROUTE] [GAF_20250501_001] FAIL dismount — no road within 500m of dest, using last waypoint
```

**1D — Waypoint spacing check**
```
[DSC_GAF] [VALIDATE] [GAF_20250501_001] Waypoint spacing check: 24 waypoints
[DSC_GAF] [VALIDATE] [GAF_20250501_001] WP 04/24: spacing to prev 18m — WARN (below 25m min)
[DSC_GAF] [VALIDATE] [GAF_20250501_001] WP 14/24: spacing to prev 847m — WARN (above 600m max)
[DSC_GAF] [VALIDATE] [GAF_20250501_001] Spacing check complete: 1 warn, 0 fail
```

**1E — Water/terrain check on waypoints**
```
[DSC_GAF] [VALIDATE] [GAF_20250501_001] WP 09/24: water check FAIL — culled from route
[DSC_GAF] [VALIDATE] [GAF_20250501_001] WP 22/24: terrain check OK
```

### Visual Debug (Sprint T1)

During Sprint T1 (route-only testing), enable visual debug markers:
- Blue line markers between each waypoint
- Yellow marker at dismount point
- Red marker at any culled/failed waypoint
- Text label on each marker showing WP index and spacing

Toggled via debug action: `"Show GAF Route Debug"` — adds/removes markers without restarting.

---

## Layer 2: Crew Validation

Runs after crewing vehicles, before TRANSIT begins.

```
[DSC_GAF] [CREW] [GAF_20250501_001] Motor pool query: 4 vehicles available
[DSC_GAF] [CREW] [GAF_20250501_001] Selected: 2 vehicles for convoy
[DSC_GAF] [CREW] [GAF_20250501_001] Vehicle 1: B_MRAP_01_F | driver: OK | gunner: OK | cmdr: NONE (no cmdr seat)
[DSC_GAF] [CREW] [GAF_20250501_001] Vehicle 2: B_Truck_01_transport_F | driver: OK | gunner: NONE (unarmed)
[DSC_GAF] [CREW] [GAF_20250501_001] Crew total: 3 units across 2 groups
[DSC_GAF] [CREW] [GAF_20250501_001] Dynamic sim enabled on 3 crew units
[DSC_GAF] [CREW] [GAF_20250501_001] WARN: Vehicle 2 has no gunner — unarmed transport OK if intended
[DSC_GAF] [CREW] [GAF_20250501_001] Convoy entry built — ID: GAF_20250501_001 | state: STAGING
```

Failure cases to log:
```
[DSC_GAF] [CREW] [GAF_20250501_001] ERROR: Motor pool has 0 available vehicles — convoy aborted
[DSC_GAF] [CREW] [GAF_20250501_001] ERROR: Driver slot null on Vehicle 1 after moveInDriver — retry
[DSC_GAF] [CREW] [GAF_20250501_001] ERROR: Vehicle 1 destroyed before convoy start — abort
```

---

## Layer 3: Runtime Convoy Health

Runs throughout TRANSIT and RETURNING states. Emitted by `fnc_convoyLoop` and `fnc_stuckWatchdog`.

### State Transitions
```
[DSC_GAF] [CONVOY] [GAF_20250501_001] t=0 State: STAGING
[DSC_GAF] [CONVOY] [GAF_20250501_001] t=38 State: TRANSIT | players boarded: 4 | route WPs: 24
[DSC_GAF] [CONVOY] [GAF_20250501_001] t=38 WP progress: 0/24 | lead pos: [12501.3, 14798.2, 0]
[DSC_GAF] [CONVOY] [GAF_20250501_001] t=98 WP progress: 4/24 | avg speed: 38 km/h
[DSC_GAF] [CONVOY] [GAF_20250501_001] t=218 WP progress: 11/24 | avg speed: 41 km/h
[DSC_GAF] [CONVOY] [GAF_20250501_001] t=334 State: DISMOUNTING | dist to dismountPos: 43m
[DSC_GAF] [CONVOY] [GAF_20250501_001] t=352 Players dismounted: 4/4 | State: WAITING
[DSC_GAF] [CONVOY] [GAF_20250501_001] t=1612 Wait timeout reached — State: RETURNING
[DSC_GAF] [CONVOY] [GAF_20250501_001] t=1884 State: COMPLETE | arrived at motor pool
```

### Stuck Events
```
[DSC_GAF] [STUCK] [GAF_20250501_001] t=155 Lead speed: 0 km/h | stuck timer: 15s
[DSC_GAF] [STUCK] [GAF_20250501_001] t=170 Lead speed: 0 km/h | stuck timer: 30s — threshold reached
[DSC_GAF] [STUCK] [GAF_20250501_001] t=170 Unstuck attempt 1 — skipping waypoint 8/24
[DSC_GAF] [STUCK] [GAF_20250501_001] t=185 Lead speed: 28 km/h — stuck resolved (attempt 1)
```

```
[DSC_GAF] [STUCK] [GAF_20250501_001] t=602 Unstuck attempt 2 — nudge forward
[DSC_GAF] [STUCK] [GAF_20250501_001] t=617 Lead speed: 0 km/h — nudge failed
[DSC_GAF] [STUCK] [GAF_20250501_001] t=617 Unstuck attempt 3 — teleport to WP 19/24
[DSC_GAF] [STUCK] [GAF_20250501_001] t=632 Lead speed: 35 km/h — stuck resolved (attempt 3)
```

```
[DSC_GAF] [STUCK] [GAF_20250501_001] t=802 UNSTUCK FAILED — no road near WP 22/24 — ABORT
```

### Contact Events
```
[DSC_GAF] [CONTACT] [GAF_20250501_001] t=445 FiredNear at [9234.1, 10821.3, 0] | dist: 87m
[DSC_GAF] [CONTACT] [GAF_20250501_001] t=445 Convoy switched to COMBAT posture
[DSC_GAF] [CONTACT] [GAF_20250501_001] t=483 No enemy within 200m for 30s — resuming TRANSIT
```

---

## Layer 4: Post-Run Summary Block

Emitted at COMPLETE or ABORT. This is the primary block for bulk analysis.

```
[DSC_GAF] [SUMMARY] [GAF_20250501_001] =========================================
[DSC_GAF] [SUMMARY] [GAF_20250501_001] Run ID:          GAF_20250501_001
[DSC_GAF] [SUMMARY] [GAF_20250501_001] Map:             Altis
[DSC_GAF] [SUMMARY] [GAF_20250501_001] Origin->Dest:    12543,14821 -> 8234,9156
[DSC_GAF] [SUMMARY] [GAF_20250501_001] Straight dist:   6243m
[DSC_GAF] [SUMMARY] [GAF_20250501_001] Path dist:       8912m (ratio 1.43)
[DSC_GAF] [SUMMARY] [GAF_20250501_001] Vehicles:        2 (1 MRAP, 1 truck)
[DSC_GAF] [SUMMARY] [GAF_20250501_001] Players carried: 4
[DSC_GAF] [SUMMARY] [GAF_20250501_001] Duration:        5m 14s
[DSC_GAF] [SUMMARY] [GAF_20250501_001] Avg speed:       39 km/h
[DSC_GAF] [SUMMARY] [GAF_20250501_001] WP progress:     24/24
[DSC_GAF] [SUMMARY] [GAF_20250501_001] Stuck events:    1 | Resolved: 1 | Unresolved: 0
[DSC_GAF] [SUMMARY] [GAF_20250501_001] Contact events:  0
[DSC_GAF] [SUMMARY] [GAF_20250501_001] Vehicles lost:   0
[DSC_GAF] [SUMMARY] [GAF_20250501_001] Crew lost:       0
[DSC_GAF] [SUMMARY] [GAF_20250501_001] Result:          SUCCESS
[DSC_GAF] [SUMMARY] [GAF_20250501_001] =========================================
```

Failed run example:
```
[DSC_GAF] [SUMMARY] [GAF_20250501_003] =========================================
[DSC_GAF] [SUMMARY] [GAF_20250501_003] Run ID:          GAF_20250501_003
[DSC_GAF] [SUMMARY] [GAF_20250501_003] Map:             Altis
[DSC_GAF] [SUMMARY] [GAF_20250501_003] Origin->Dest:    12543,14821 -> 4821,6234
[DSC_GAF] [SUMMARY] [GAF_20250501_003] Straight dist:   9841m
[DSC_GAF] [SUMMARY] [GAF_20250501_003] Path dist:       ROUTE_FAIL (ratio N/A)
[DSC_GAF] [SUMMARY] [GAF_20250501_003] Result:          ABORT | Reason: ROUTE_GENERATION_FAILED
[DSC_GAF] [SUMMARY] [GAF_20250501_003] =========================================
```

---

## Test Scenarios

These are the specific scenarios to run during Sprint T1 and T2 testing. Run each at least twice (route generation has randomness) and collect RPT logs.

### Scenario Set A: Route Quality (Sprint T1 — no vehicles, visual debug only)

| ID | Description | What to Check |
|----|-------------|---------------|
| A1 | Base to nearby camp (~2km, mostly road) | Ratio <1.5, all WPs on road |
| A2 | Base to far mission site (~8km, cross-map) | Ratio <2.5, no cross-country jumps |
| A3 | Base to coastal town (road + bridge) | Bridge WPs present, no water culls |
| A4 | Base to mountain area (sparse roads) | Graceful fallback, dismount WP reasonable |
| A5 | Base to nearby location (< 500m) | Short route handled, minimum WP count |

For each: enable visual markers, screenshot the route, note any visual anomalies alongside the log ratio.

### Scenario Set B: Convoy Transit (Sprint T2)

| ID | Description | What to Watch |
|----|-------------|---------------|
| B1 | Clean run on good road (A1 route) | Full transit, no stuck, clean summary |
| B2 | Long run cross-map (A2 route) | Speed consistency, WP progress rate |
| B3 | Bridge crossing (A3 route) | Stuck watchdog fires? How many attempts? |
| B4 | Run with 4 players riding | Boarding detection, dismount detection |
| B5 | Run with 1 vehicle (solo driver) | Minimum config works |
| B6 | Run with 3 vehicles | Formation cohesion, rear vehicle keeps up? |

### Scenario Set C: Failure Recovery (Sprint T4)

| ID | Description | Expected Outcome |
|----|-------------|-----------------|
| C1 | Kill convoy driver mid-transit | ABORT triggered, players notified |
| C2 | Destroy lead vehicle mid-transit | ABORT triggered, cleanup runs |
| C3 | Deliberately block road with editor object | Stuck watchdog fires, teleport attempt |
| C4 | AO in area with no roads within 300m | Dismount fallback to last WP |
| C5 | Request convoy with empty motor pool | Graceful refusal, no crash |

---

## RPT Log Analysis Guide

When pasting a log for analysis, grep for these patterns first:

```bash
# All GAF events from a specific run
grep "GAF_20250501_001" arma3server.rpt

# All SUMMARY blocks
grep "\[SUMMARY\]" arma3server.rpt

# All failures and errors
grep -E "\[ERROR\]|\[STUCK\].*FAIL|Result:.*ABORT" arma3server.rpt

# All stuck events
grep "\[STUCK\]" arma3server.rpt

# Route ratios only
grep "ratio" arma3server.rpt
```

When providing a log for AI analysis, paste the full RPT output (or at minimum all `[DSC_GAF]` lines). The summary blocks allow rapid triage:
- `Result: SUCCESS` + `Stuck events: 0` → clean run, no action needed
- `Result: SUCCESS` + `Stuck events: N` → working but fragile, review stuck locations
- `Result: ABORT` + reason → targeted fix based on reason field
- Multiple runs with stuck at same WP index → that route segment is a known problem area

---

## `fnc_logConvoy` Implementation

All logging routes through this single function for consistency. The run ID is always attached.

```sqf
/*
 * fnc_logConvoy
 * Arguments:
 *   0: Convoy entry hashmap (for run ID + context)
 *   1: Category string (e.g. "ROUTE", "STUCK")
 *   2: Message string
 */
params ["_convoyEntry", "_category", "_message"];

private _runId = _convoyEntry getOrDefault ["runId", "GAF_UNKNOWN"];

diag_log format ["[DSC_GAF] [%1] [%2] t=%3 %4",
    _category,
    _runId,
    floor (time - (_convoyEntry getOrDefault ["startTime", 0])),
    _message
];
```

For SUMMARY blocks, a dedicated `fnc_convoyRunSummary` function formats and emits the full block using the convoy entry data accumulated during the run.

---

## What Good Looks Like

After 10 test runs across Scenario Sets A and B, a healthy system should show:

- All A-series routes complete with ratio < 2.5
- B1/B2 runs complete with 0 stuck events
- B3 (bridge) runs complete with ≤2 stuck events (resolved)
- All stuck events resolved within 3 attempts
- No ABORT results except in C-series intentional failure scenarios
- Summary blocks parseable in < 30 seconds of log review

If stuck events cluster at the same WP index across multiple B3 runs, that waypoint position is a problem area to investigate — either the `fnc_buildRoadRoute` segment thinner needs adjustment, or that specific bridge needs a manual override waypoint.