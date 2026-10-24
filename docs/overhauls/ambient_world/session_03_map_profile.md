# Session 03 — Map Profile

**Owner item:** 2 (prerequisite)
**Model:** Sonnet
**Ships:** `fnc_getMapProfile` — one per-world table carrying region identity,
civilian/police/host-nation faction casting, and a climate block consumed later
by Session 11.
**Depends on:** nothing. Can run in parallel with 01/02.

---

## Why

The owner's note: *"Civilian factions/types are map based"* and
*"Altis = Lemnos, Greece"*. Three separate downstream needs want the same table:

1. **Session 04 (civilians)** — which civilian faction(s) populate this world,
   and what the local flavor is.
2. **Session 09 (factions)** — who the host nation and police force are, which
   is how the owner's *"Altis police run airport security and are on the
   payroll"* briefing becomes expressible.
3. **Session 11 (weather/time)** — climate band, seasonal temperature/rain/fog
   envelopes, sunrise/sunset behavior.

Building three tables keyed on `worldName` would be three places to drift. Build
one now with the climate block stubbed.

---

## Target

```sqf
// fnc_getMapProfile  —  pure, cached
// [_worldName] -> HASHMAP   (defaults to current worldName)
createHashMapFromArray [
    ["world",          "Altis"],
    ["displayName",    "Altis"],
    ["realWorldAnalogue", "Lemnos, Greece"],
    ["region",         "mediterranean"],
    ["hemisphere",     "north"],
    ["latitude",       39.9],

    // --- population / faction casting (Sessions 04, 09) ---
    ["civilianFactions", ["CIV_F"]],
    ["policeFaction",    "..."],          // TBD Session 09
    ["hostNationFaction","..."],          // TBD Session 09
    ["architecture",     "mediterranean"],// drives civilian archetype flavor
    ["languageHint",     "greek"],        // future voice/name generation

    // --- climate (Session 11 fills this; stubbed now) ---
    ["climate", createHashMapFromArray [
        ["stub", true]
    ]]
]
```

Shipped worlds: `Altis`, `Stratis`, `Malden`, `Tanoa`, `Enoch` (Livonia), plus
`VR` (the test world — must resolve, used by Tier-1/Tier-2 harness).

Unknown world → a **generic temperate profile** with `isFallback: true` and one
`WARNING`. Never `nil`, never an error.

---

## Deliverables

1. **`fnc_getMapProfile`** (`addons/core/functions/data/`) — pure, cached, takes
   an optional `_worldName` (defaults to `worldName`) so it is Tier-1 testable
   without being on that map.
2. Profiles for the 5 shipped maps + `VR` + generic fallback.
3. **No consumers wired yet.** This session ships the table only. Session 04 is
   its first reader. Resist wiring it into `fnc_initServer`'s faction profile
   selection now — that is Session 09 and it is the riskiest change in the
   program.

---

## Tier-1 test plan (`suite: map_profile`)

| Assertion | Why |
|---|---|
| Every shipped world resolves to a profile with `isFallback == false` | |
| An unknown world returns the generic profile with `isFallback == true` | must degrade, not throw |
| `VR` resolves | the harness runs there |
| Every profile has every required key (schema check against a key list) | stops a half-filled profile shipping |
| `civilianFactions` is a non-empty array of strings for every profile | Session 04 depends on it |
| Calling with no argument uses `worldName` | |
| Result is cached (second call returns same ref) | |
| Latitude is in `[-90, 90]`; hemisphere agrees with its sign | Session 11 will do sun math off these |

---

## Gotchas

- **Livonia's `worldName` is `Enoch`**, not `Livonia`. Key on `worldName`, list
  the display name separately.
- **Don't guess faction classnames.** `policeFaction` / `hostNationFaction` are
  genuinely Session 09 decisions (and the owner flagged police disposition as
  architecturally new). Leave them as explicit `""` + a `// TBD Session 09`
  comment rather than inventing a value that later reads as intentional.
- **Cache in `missionNamespace`, not `uiNamespace`**, unless a client needs it
  pre-mission.
- The profile must be **readable on clients** (briefings render client-side).

---

## Definition of done

- `fnc_getMapProfile` registered in `XEH_PREP.hpp`.
- `hemtt check` clean.
- Tier-1 suite `map_profile` registered and passing.
- No behavior change anywhere (nothing reads it yet).
- `AGENTS.md` key-systems table updated.

---

## Open question for the owner

- **Q6 — How much flavor do you want in the profile now?** Minimum viable is
  region + civilian factions + climate stub. But it is cheap to also carry
  things like typical vehicle classes, name lists, and architecture hints while
  the table is being authored. Worth doing now, or add per-session as each
  consumer appears? *Recommendation: add per-session* — unused fields rot.
