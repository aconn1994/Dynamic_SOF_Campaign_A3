# Logging & Debug Modes

DSC uses **CBA log macros** instead of raw `diag_log`. The active set of macros is selected at compile time by which `DEBUG_MODE_*` flag is defined in `addons/main/script_mod.hpp`. The other macros expand to empty no-ops, so disabled tiers carry **zero runtime cost**.

This doc is the single source of truth for:
- which macro to reach for in any given situation
- how the three debug modes map to player builds vs. playtest vs. developer debug
- what gets gated behind `#ifdef DEBUG_MODE_FULL` (markers, dev systemChats)
- the HEMTT macro-arg-counting trap that breaks builds and how to work around it

## The three modes

Set exactly one of these in `addons/main/script_mod.hpp`:

```cpp
// #define DEBUG_MODE_MINIMAL   // live play
#define DEBUG_MODE_NORMAL       // playtest (current default)
// #define DEBUG_MODE_FULL      // developer debug
```

| Mode | Use case | What survives |
|---|---|---|
| `DEBUG_MODE_MINIMAL` | Live play / Workshop release | `ERROR`, `ERROR_WITH_TITLE`, player-facing systemChats, gameplay markers |
| `DEBUG_MODE_NORMAL`  | Playtest builds              | + `INFO`, `WARNING`, mission outcome systemChat |
| `DEBUG_MODE_FULL`    | Developer debug              | + `LOG`, `TRACE_n`, debug markers, per-tick instrumentation systemChats |

Lower tiers are subsumed automatically. `DEBUG_MODE_FULL` implicitly defines `DEBUG_MODE_NORMAL`, which implicitly defines `DEBUG_MODE_MINIMAL`. There is no extra setup; just pick one.

## Macro cheat sheet

CBA provides five tiers of macros, each with a single-arg form and an `_n` suffixed form (max `_8`) that formats the message with `%1..%n` placeholders.

| Tier | Macros | When to log | Mode threshold |
|---|---|---|---|
| Error | `ERROR(msg)`, `ERROR_n(msg, a1..aN)`, `ERROR_WITH_TITLE(title, msg)` | Bad input, missing required data, createVehicle failed, invalid args | Always |
| Warning | `WARNING(msg)`, `WARNING_n(...)` | Degraded but operational — fallback path, missing optional data, unknown profile, empty pool | `DEBUG_MODE_NORMAL`+ |
| Info | `INFO(msg)`, `INFO_n(...)` | Lifecycle milestones — init banners, mission START/SUCCESS/INCOMPLETE, "X initialized", per-faction asset summary | `DEBUG_MODE_NORMAL`+ |
| Log | `LOG(msg)`, `LOG_n(...)` | Per-event detail — per-zone activation/despawn, per-archetype skip, per-tick presence/roving summary, base/outpost marking, worker BEGIN/END timings | `DEBUG_MODE_FULL` |
| Trace | `TRACE_n(msg, v1..vN)` | Variable inspection on per-event detail — pretty-prints names + values | `DEBUG_MODE_FULL` |

### Output format

All CBA macros funnel through `LOG_SYS` which prepends a structured header:

```
[DSC] (core) INFO: Mission ACTIVE - DA_BOMBMAKER at Kavala
[DSC] (core) WARNING: setupGarrison - No structures found
[DSC] (core) ERROR: fnc_extractAssets - No faction provided
[DSC] (core) LOG: presence [base_zaros] DORMANT -> ACTIVATING (type=base dist=1840m speed=22m/s budget=12u/3v est=20u/4v)
```

Drop the `"DSC: "` prefix in your message — it is already prepended.

### Picking the right tier — examples

```sqf
// Bad input / unrecoverable → ERROR
if (_faction == "") exitWith {
    ERROR("fnc_extractAssets - No faction provided");
    createHashMap
};

// Fallback path → WARNING
if (_footGroups isEqualTo []) then {
    WARNING_2("activatePresenceZone [%1] - faction %2 not in any role, will borrow", _id, _faction);
};

// Milestone → INFO
INFO("========== Initializing Military Bases ==========");
INFO_2("Mission ACTIVE - %1 at %2", _missionType, _locationName);

// Per-event detail → LOG
LOG_3("presence worker[%1] BEGIN despawn [%2] (qD=%3 qA=%4)", _iter, _id, count _dq, count _aq);

// Variable inspection → TRACE_n
TRACE_4("Marked base", _locName, _controlledBy, _faction, _flagTexture);
TRACE_5("tablet keybind pressed", _ready, _hasFaction, _hasInfluence, _hasLocations, _mState);
```

### `_n` argument cap

CBA's tiered macros only go up to `_8` (eight format args). For longer arg lists, build the format string first and pass it to the plain macro:

```sqf
private _tickMsg = format ["presence tick — active:%1 activating:%2 paused:%3 despawning:%4 dormant:%5 sus:%6 (of %7) | qA=%8 qD=%9 | used %10u/%11v of %12u/%13v | speed avg=%14 max=%15%16",
    _activated, _activatingCt, _pausedCt, _despawned, _dormant, _suspended, count _zones,
    count _activateQueue, count _despawnQueue,
    _curUnits, _curVehicles, _budgetUnits, _budgetVehicles,
    round _avgPlayerSpeed, round _maxPlayerSpeed,
    _missionLabel];
LOG(_tickMsg);
```

### Required include

Every file that uses any log macro needs the component include at the top (after `params`):

```sqf
params [["_zone", createHashMap, [createHashMap]]];

#include "..\..\script_component.hpp"

// ... rest of file
```

Some subfolders (`ai/`, `faction/`, `presence/`, `data/`) ship a local `script_component.hpp` shim that re-exports the core one. In those folders you can use either path — `"script_component.hpp"` or `"..\..\script_component.hpp"`. Mixed usage is fine; the convention varies by file age.

## `systemChat` gating

`systemChat` broadcasts to the player(s). Split by audience:

**Keep unconditional** (player-facing feedback):
- `"Extraction inbound to pickup LZ."` (requestExtraction)
- `"ISR drone on station in approximately 5 minutes."` / `"ISR drone has been shot down. Replacement in 30 minutes."` (persistentUAV)
- `"Combat Medic assigned to %1."` (recruitMedic)
- `"%1 is down!"` (handlePlayerDown — remoteExec broadcast)
- `"Intel recovered: %1"` (interactionHandler)

**Gate behind `#ifdef DEBUG_MODE_NORMAL`** (playtester wants to see, live player doesn't):
- Mission SUCCESS/INCOMPLETE chats — there's already a `hint` for the player; the systemChat is a secondary playtester signal.
- Mission aborted-by-admin (tablet) chat.

**Gate behind `#ifdef DEBUG_MODE_FULL`** (developer instrumentation):
- `"DSC presence: N zones registered, tick loop starting"` (initPresenceManager)
- `"DSC - Initializing military bases..."` (initServer, base init banner)
- Per-tick `"DSC presence: A:N ~A:N D-:N ..."` summary (initPresenceManager tick)
- 60s STATS broadcast `"DSC stats: act=N done=N timed=N..."` (initPresenceManager periodic)
- Worker-stale alert `"DSC presence: WORKER STALE Ns qA=N qD=N"` (initPresenceManager health check)
- Per-transition broadcasts `"DSC presence: %1"` and `"+%1 more transitions"` (initPresenceManager tick)
- Per-zone activation broadcasts `"DSC presence: ACTIVATED Name — Nu Nv"` (presenceActivateMilitary, presenceHandlerPopulatedArea)

Pattern for `remoteExec` chats:

```sqf
#ifdef DEBUG_MODE_FULL
(format ["DSC presence: ACTIVATED %1 — %2u %3v",
    _zone get "name",
    count (_zone get "units"),
    count (_zone get "vehicles")
]) remoteExec ["systemChat", 0];
#endif
```

## Marker gating

Markers split the same way: gameplay vs. debug.

**Keep unconditional** (gameplay UI, players need them):
- Base/outpost faction flag textures (`DSC_baseMarkerData` / `DSC_outpostMarkerData` rendered by the client map-draw EH in `fnc_initPlayerLocal`)
- Base 800m danger zone ellipses (`dsc_base_zone_*` in initServer Step 4)
- Player base outline markers (`player_base_*` style overrides in initBases)
- HALO drop marker (`dsc_drop_*` in initPlayerLocal HALO action)
- Extraction pickup marker (`dsc_extraction_pickup` in requestExtraction)
- Compound mission markers (`fnc_drawCompoundMarkers` — Contact_circle4 + alpha-numeric dots)
- Dynamic respawn marker (`respawn_west_dynamic` — invisible, not really a marker the player sees, but needed for the respawn template)

**Gate behind `#ifdef DEBUG_MODE_FULL`** (developer-only visualization):
- Presence zone state ellipses (`dsc_presence_*`) — created in `fnc_initPresenceManager` and recolored per-state in the tick loop. The entire creation block AND both color-update sites are gated.
- scanLocations location dots and area ellipses (`dsc_loc_*` / `dsc_loc_*_area`) — gated via the existing `_debug` flag, which `fnc_scanLocations` force-sets to `true` when `DEBUG_MODE_FULL` is defined.

Pattern for marker blocks:

```sqf
#ifdef DEBUG_MODE_FULL
{
    private _mName = format ["dsc_presence_%1", _zoneId];
    private _m = createMarker [_mName, _zPos];
    _m setMarkerShapeLocal "ELLIPSE";
    // ...
} forEach (keys _zones);
#endif
```

Pattern for updating already-gated markers from a tick loop:

```sqf
if (_newState != _state) then {
    _zone set ["state", _newState];

    #ifdef DEBUG_MODE_FULL
    private _mName = _zone get "marker";
    if (!isNil "_mName") then {
        private _color = _stateColor getOrDefault [_newState, "ColorGrey"];
        _mName setMarkerColorLocal _color;
        _mName setMarkerText format ["%1 [%2]", _zone get "name", _newState];
    };
    #endif

    LOG_7("presence [%1] %2 -> %3 (...)", _zoneId, _state, _newState, ...);
};
```

## The HEMTT macro-arg-counting trap

**This is the #1 thing that breaks the build when adding new log calls.**

HEMTT's preprocessor counts commas inside `[]` as macro-argument separators, even when the brackets are nested inside `()`. This means any **inline array literal** inside a `LOG_n` / `INFO_n` / `WARNING_n` / `ERROR_n` / `TRACE_n` call causes a build failure:

```
error[PE9]: function call with incorrect number of arguments
  LOG_3("foo - %1 / %2 / %3", _a, _b, count (_x getOrDefault ["units", []]));
  ^^^^^ called with 5 arguments
        defined with 3 arguments
```

The preprocessor sees the comma in `["units", []]` and treats it as an arg separator. Same trap for:
- `_x getOrDefault ["key", default]`
- `_x getVariable ["DSC_role", ""]`
- `_x get "k"` is fine; `_x getOrDefault [...]` is not
- `["foo", "bar"] select _i`
- `missionNamespace getVariable ["DSC_state", "<unset>"]`
- nested `format [...]` calls
- any `["a", "b", "c"]` literal

**Fix**: hoist the problematic expression into a `private` first, then reference the variable in the log call:

```sqf
// BROKEN
LOG_3("foo - %1 / %2 / %3", _a, _b, count (_x getOrDefault ["units", []]));

// FIXED
private _ct = count (_x getOrDefault ["units", []]);
LOG_3("foo - %1 / %2 / %3", _a, _b, _ct);
```

```sqf
// BROKEN
LOG_5("outpost '%1': %2 / %3 (inf %4, near %5)", _name, _ctrl, _fac, _inf, ["none", "yes"] select (_nb != ""));

// FIXED
private _nbLabel = ["none", "yes"] select (_nb != "");
LOG_5("outpost '%1': %2 / %3 (inf %4, near %5)", _name, _ctrl, _fac, _inf, _nbLabel);
```

```sqf
// BROKEN  (also: more than 8 args — needs format hoist regardless)
LOG(format ["tick stats: a=%1 b=%2 c=%3", _stats getOrDefault ["a", 0], _stats getOrDefault ["b", 0], _stats getOrDefault ["c", 0]]);

// FIXED
private _a = _stats getOrDefault ["a", 0];
private _b = _stats getOrDefault ["b", 0];
private _c = _stats getOrDefault ["c", 0];
LOG_3("tick stats: a=%1 b=%2 c=%3", _a, _b, _c);
```

Wrapping the expression in parens (`(_x getOrDefault [...])`) does **not** help — HEMTT still counts the inner commas. The only reliable fix is to hoist.

### How to detect the trap before building

Visually scan any new `LOG_n` / `INFO_n` / etc. line for:
- `[` followed by anything that contains a `,` before the matching `]`

If you see one, hoist it to a `private` first. `hemtt check` (or any `hemtt build` / `hemtt launch`) will catch any you miss; the error message names the file and line.

## Adding new code — checklist

When writing a new function that needs logging:

1. **Add the include** at the top of the file (after `params`):
   ```sqf
   #include "..\..\script_component.hpp"
   ```
   (Or `#include "script_component.hpp"` if the file lives in `ai/`, `faction/`, `presence/`, or `data/` where a local shim exists.)

2. **Pick the right tier** per the cheat sheet:
   - Error path → `ERROR` / `ERROR_n`
   - Degraded fallback → `WARNING` / `WARNING_n`
   - Lifecycle milestone → `INFO` / `INFO_n`
   - Per-event detail → `LOG` / `LOG_n`
   - Variable inspection → `TRACE_n`

3. **Hoist any inline array literals** in the format args (see trap above).

4. **Stay under 8 format args** — for longer messages, hoist the `format [...]` itself.

5. **For player-facing `systemChat`** — leave unconditional. **For dev-probe `systemChat`** — wrap in `#ifdef DEBUG_MODE_FULL` (or `DEBUG_MODE_NORMAL` if it's a playtester signal like mission outcome).

6. **For map markers** — gameplay markers stay unconditional. Debug visualization markers (zone state ellipses, location dots) wrap in `#ifdef DEBUG_MODE_FULL`, including any later sites that update marker color/text/alpha.

7. **Run `hemtt check`** before considering the change done. It catches macro-arg-count errors and SQF syntax issues that the editor won't.

## Where the macros live

- `addons/main/script_mod.hpp` — selects `DEBUG_MODE_*`
- `addons/main/script_macros.hpp` — pulls in CBA's `script_macros_common.hpp`
- CBA's `script_macros_common.hpp` (in `include/x/cba/addons/main/`) — defines `LOG`, `INFO`, `WARNING`, `ERROR`, `TRACE_n`, `LOG_SYS`, `FORMAT_n`, etc.

CBA's tiering rules (for reference):
- `ERROR` / `ERROR_WITH_TITLE` are always defined.
- `INFO` is always defined (the documentation says otherwise but the code defines it unconditionally).
- `WARNING_*` is defined when `DEBUG_MODE_NORMAL` is set.
- `LOG_*` and `TRACE_n` are defined when `DEBUG_MODE_FULL` is set.
- Each higher tier implicitly defines all lower tiers.

## Historical context

DSC used raw `diag_log format ["DSC: ..."]` everywhere until mid-2026. The conversion to CBA macros was driven by the need for a true "release vs. playtest vs. debug" split — `diag_log` always logs, which meant Workshop builds shipped with the same RPT-spam volume as developer builds. The macros let the preprocessor strip the dev-only calls entirely.

The conversion also unified marker / systemChat debug-gating under the same `#ifdef DEBUG_MODE_FULL` umbrella, so a single switch in `script_mod.hpp` produces a quiet release build, a verbose playtest build, or a fully instrumented dev build.

All ~120 `diag_log` sites in `addons/core/functions/` were converted in a single sweep. Any new `diag_log` showing up in a PR should be flagged and replaced with the appropriate macro — there is no longer a reason to use `diag_log` directly in DSC code.
