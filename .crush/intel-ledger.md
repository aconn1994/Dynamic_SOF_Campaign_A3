# Intel Ledger (Campaign Overhaul Session 2)

*Status: LIVE (August 2026). Keystone data store for the campaign overhaul —
see `.crush/campaign-overhaul.md` §4 for the full design rationale. This doc
is the implementation reference; the design doc is authoritative for intent.*

## What it is

`DSC_intelLedger` — a HASHMAP keyed `id -> token`, persistent for the lifetime
of one deployment (created/wiped once at session start, no cross-deployment
carryover per §11 decision 2). It is the single store every future pillar
(series gating, briefing composition, mission difficulty) reads through.

## Token schema (§4.1)

```
intelToken = createHashMapFromArray [
    ["id",           "<uid>"],
    ["type",         "HVT_LOCATION"],   // §4.2 catalog; NOT a closed enum
    ["subjectKind",  "ENTITY|LOCATION|FACTION|THREAD|AREA"],
    ["subjectRef",   "<id of the thing this is about>"],
    ["confidence",   0.65],             // clamped to [0,1] on add
    ["source",       "SSE|BODY_SEARCH|RECON|HQ|CIV_TIP|SIGINT|ISR"],
    ["scope",        "AREA|LOCATION|SERIES|DEPLOYMENT"],
    ["discoveredAt", serverTime],
    ["expiresAt",    serverTime + <per-type TTL>],
    ["payload",      createHashMap]     // type-specific (grid, pattern, classname)
]
```

Default TTLs are keyed by `type` in `fnc_intelAdd` with a 3600s fallback for
any unrecognized type — the catalog stays open-ended by design.

## The API (§4.5 — exactly these five calls, no more)

| Function | Signature | Purity |
|---|---|---|
| `fnc_intelInit` | `[] -> ledger` | Creates/wipes `DSC_intelLedger`. Idempotent. |
| `fnc_intelAdd` | `[partialToken] -> id` | Composition (default-filling + confidence clamp) is pure; the only side effect is one write to `DSC_intelLedger`. |
| `fnc_intelQuery` | `[ledger, criteria, now?] -> [token, ...]` | Fully pure — takes the ledger as data, touches no globals. `criteria` keys: `subjectRef`/`type`/`scope`/`source`, all optional (wildcard). Returns only LIVE (`expiresAt > now`) tokens. |
| `fnc_intelBest` | `[ledger, subjectRef, type, now?] -> token` | Pure; built on `fnc_intelQuery`. Empty `createHashMap` sentinel if nothing matches. |
| `fnc_intelDecay` | `[ledger, now?] -> droppedCount` | Pure over the passed ledger; mutates it in place via `deleteAt` (HashMap is a reference type — no re-`setVariable` needed for correctness). |

`now` is optional on query/best/decay (default `serverTime`) purely so Tier-1
tests can pin a deterministic clock instead of racing real elapsed time.

Real callers own the read/write of the global:

```sqf
private _ledger = missionNamespace getVariable ["DSC_intelLedger", createHashMap];
private _best = [_ledger, "hvt_bombmaker", "HVT_LOCATION"] call DSC_core_fnc_intelBest;
```

## Retrofit bridge

`fnc_buildMissionOutcome` stays a pure builder — it produces `intelGathered`
(an array of token hashmaps, or the legacy `{"type":"generic"}` sentinel) but
never touches the ledger itself. Two call sites feed it in, both doing the
same one-liner immediately after the outcome is built:

- `fnc_initServer.sqf` — the mission loop's outcome-handling site (`if
  (!_aborted)` block).
- `fnc_initTestScenario.sqf` — the harness single-shot debrief path.

```sqf
{
    [_x] call DSC_core_fnc_intelAdd;
} forEach (_outcome getOrDefault ["intelGathered", []]);
```

Since `fnc_intelAdd` fills every missing schema field, this also normalizes
the legacy sentinel token into a schema-valid one for free — no separate
normalization step was needed.

## Gotchas

- **Intel decay ≠ C2 alert decay.** Separate clock, separate store (`DSC_intelLedger`
  vs `DSC_c2Nodes`). Do not overload C2 node state as intel confidence.
- **Per-deployment lifetime.** `fnc_intelInit` wipes; there is no cross-deployment
  carryover in MVP.
- **`fnc_intelAdd` stores past-`expiresAt` tokens as-is** — it does not reject
  already-dead intel. `fnc_intelQuery`/`fnc_intelBest` are what exclude dead
  tokens, not `fnc_intelAdd`. Tested explicitly (see `intel_ledger` Tier-1 suite).
- **Do not add a sixth call.** The whole design intent (§4.5) is that every
  future pillar reads through exactly these four plus init. Resist adding
  speculative helpers even when a caller "just needs one more filter."

## Tier-1 tests

`intel_ledger` suite in `fnc_initServerDebug.sqf`, run via `fnc_runTests`.
Covers: add fills defaults + clamps confidence + returns id; query filters by
type/subjectRef/scope; best returns the highest-confidence live token and
ignores a higher-confidence expired one; decay drops expired tokens and keeps
live ones.
