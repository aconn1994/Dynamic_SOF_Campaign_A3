# Session 03 — Map Profile

**Owner item:** 2 (prerequisite)
**Model:** Sonnet
**Ships:** `fnc_getMapProfile` — one per-world table carrying region identity,
civilian/police/host-nation faction casting, and a climate block consumed later
by Session 11.
**Depends on:** nothing. Can run in parallel with 01/02.
**Status:** ⬜ not started — **mini-spec drafted below, awaiting owner approval.**
Once approved, the paste-ready Sonnet prompt at the bottom is the whole session.

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

  **Proposed resolution (carried into the mini-spec below, owner to confirm at
  approval):** take the recommendation. Ship the minimum schema plus the two
  already-cheap flavor fields the work order's own target block names
  (`architecture`, `languageHint`), stub `climate`, and leave
  `policeFaction` / `hostNationFaction` as explicit `""`. Growth is made safe
  rather than pre-empted: the Tier-1 schema check is a **required-keys subset
  check**, not an exact-key match, so Session 06 can add `civilianVehicles`,
  Session 09 can fill the faction fields, and Session 11 can replace the
  climate block **without touching this session's tests**. Record as Decision
  **C31** in the README Decision Log on approval.

---

# Approved Mini-Spec (Session 03)

*Status: drafted for approval. Sonnet scope — this is transcription + wiring,
there is no design left in it once the tables below are signed off.*

---

## §A1 — Scope and non-goals

**In scope:** one new pure, cached data function and its authored table, plus a
Tier-1 suite and three doc updates.

**Explicitly NOT in scope** (each would make this session the riskiest in the
program instead of the cheapest):

| Non-goal | Why | Lands in |
|---|---|---|
| Wiring the profile into `fnc_initServer`'s faction profile selection | Role sides are normalized exactly once at `initServer`; touching that is the single riskiest change in the program | Session 09 |
| Inventing `policeFaction` / `hostNationFaction` values | A guessed classname later reads as an intentional decision | Session 09 |
| Filling the `climate` block with real envelopes | Needs the weather resolver designed alongside it | Session 11 |
| Carrying vehicle classes / name lists | Q6 resolution — unused fields rot | Session 06 (`civilianVehicles`) |
| Modded terrains | Decision B6 — vanilla-authoritative; unknown worlds get the generic fallback and that is the whole answer | future project |
| Changing `fnc_resolveCivilianMix`, `fnc_setupCivilians`, or any consumer | **Nothing reads this function when the session closes.** That is the definition of done, not a shortcut | Sessions 04–06 |

---

## §A2 — Function signature and contract

One new file: **`addons/core/functions/data/fnc_getMapProfile.sqf`**.

```sqf
/*
 * Function: DSC_core_fnc_getMapProfile
 *
 * Arguments:
 *     0: _worldName <STRING> - World to resolve. Default: worldName.
 *     1: _rebuild   <BOOL>   - Discard the cache and recompute. Default false.
 *
 * Return Value:
 *     <HASHMAP> - Never nil, never empty. See §A3 for the schema.
 */
params [
    ["_worldName", worldName, [""]],
    ["_rebuild", false, [false]]
];
```

Contract:

- **Pure given an explicit world name.** The only `missionNamespace` touches are
  the cache and the warn-dedup map; the only engine read is the `worldName`
  *default argument*. This is what makes it Tier-1 testable from `test.VR`
  against `"Altis"` without being on Altis.
- **Total.** Every input returns a well-formed profile. Unknown world → the
  generic fallback + one `WARNING`. Never `nil`, never `createHashMap`, never an
  error.
- **Idempotent + cached.** Repeat calls for the same world return the **same
  hashmap reference**. Callers must treat the result as read-only; document this
  in the header comment (same posture as `fnc_getStructureCatalog`).
- **`_rebuild == true` clears the whole cache** (both the profile cache and the
  unknown-world warn-dedup map) and recomputes, mirroring
  `[true] call DSC_core_fnc_getStructureCatalog`. Used by the Tier-1 suite for a
  deterministic baseline.
- **Readable on every machine.** It is a `PREP_SUB(data,...)` function with a
  per-machine `missionNamespace` cache — no `publicVariable`, no server
  dependency. Briefings render client-side and must be able to call it.

### Authored table lives inside the function

Inlined, same call as Decision **B28** for the structure catalog: the authored
data and its resolution live in one file. The table literal is constructed
**inside the function body on a cache miss**, so the nested `climate` hashmap is
a fresh instance per resolution and the `+_hashmap` shallow-copy caveat in
`AGENTS.md` can never bite.

---

## §A3 — Profile schema

| Key | Type | Required | Notes |
|---|---|---|---|
| `world` | STRING | ✅ | The `worldName` key. On a fallback, **the requested name**, not `"__GENERIC__"`. |
| `displayName` | STRING | ✅ | Human name. `Enoch` → `"Livonia"`. Never `""`. |
| `realWorldAnalogue` | STRING | ✅ | `""` is legal (VR, fallback). |
| `region` | STRING | ✅ | From the fixed vocabulary below. |
| `hemisphere` | STRING | ✅ | `"north"` \| `"south"`. Must agree with `latitude`'s sign. |
| `latitude` | NUMBER | ✅ | Real-world degrees, **positive = north**. See the §A7 sign gotcha. |
| `civilianFactions` | ARRAY of STRING | ✅ | Non-empty, no empty strings. Session 04's pool builder reads this. |
| `policeFaction` | STRING | ✅ | `""` everywhere this session. `// TBD Session 09`. |
| `hostNationFaction` | STRING | ✅ | `""` everywhere this session. `// TBD Session 09`. |
| `architecture` | STRING | ✅ | From the fixed vocabulary below. Drives Session 04 archetype flavor. |
| `languageHint` | STRING | ✅ | `""` is legal. Future voice/name generation. |
| `isFallback` | BOOL | ✅ | `true` **only** on the generic profile. |
| `isSynthetic` | BOOL | ✅ | `true` only for `VR`. Lets a consumer skip ambient population on the test world without string-matching `"VR"`. |
| `climate` | HASHMAP | ✅ | `["band", <STRING non-empty>]`, `["stub", true]`. Session 11 replaces the contents wholesale. |

**Region vocabulary (fixed this session):** `mediterranean`, `tropical`,
`temperate_continental`, `temperate`, `arid`, `synthetic`.
**Architecture vocabulary (fixed this session):** `mediterranean`,
`tropical_colonial`, `eastern_european`, `generic`, `none`.

Both vocabularies are asserted in Tier-1. `arid` is authored with no current
member on purpose — it exists so a future map does not force a vocabulary
change plus a test change in the same commit.

**Schema checks are subset checks.** A profile carrying *extra* keys passes.
This is the Q6 escape hatch and must be pinned by its own assertion (§A6 #6),
or a later session adding one key turns this suite red for no reason.

---

## §A4 — The authored table (transcribe verbatim)

Seven rows: five shipped maps, the test world, and the fallback template.

| Key | `world` | `displayName` | `realWorldAnalogue` | `region` | `hemisphere` | `latitude` | `architecture` | `languageHint` | `climate.band` |
|---|---|---|---|---|---|---|---|---|---|
| `Altis` | `Altis` | Altis | Lemnos, Greece | `mediterranean` | north | `39.9` | `mediterranean` | `greek` | `mediterranean` |
| `Stratis` | `Stratis` | Stratis | Agios Efstratios, Greece | `mediterranean` | north | `39.5` | `mediterranean` | `greek` | `mediterranean` |
| `Malden` | `Malden` | Malden | Fictional Mediterranean island (Malden 2035) | `mediterranean` | north | `42.0` *(REVIEW — §A9)* | `mediterranean` | `french` | `mediterranean` |
| `Tanoa` | `Tanoa` | Tanoa | Horizon Islands, South Pacific (Fiji/Vanuatu analogue) | `tropical` | south | `-17.6` | `tropical_colonial` | `french` | `tropical` |
| `Enoch` | `Enoch` | **Livonia** | Eastern Poland / Belarus border | `temperate_continental` | north | `52.1` | `eastern_european` | `polish` | `continental` |
| `VR` | `VR` | Virtual Reality | `""` | `synthetic` | north | `0` | `none` | `""` | `none` |
| `__GENERIC__` | *(requested name)* | *(requested name)* | `""` | `temperate` | north | `45.0` | `generic` | `""` | `temperate` |

Every row: `civilianFactions = ["CIV_F"]`, `policeFaction = ""`,
`hostNationFaction = ""`, `climate = createHashMapFromArray [["band", <above>], ["stub", true]]`.
`isFallback = false` except `__GENERIC__`. `isSynthetic = true` only on `VR`.

`civilianFactions` is `["CIV_F"]` on **every** row because that is the only
civilian faction classname verified in this repo (`fnc_initServer.sqf:59`,
`fnc_initTestScenario.sqf:163`). Per-map civilian *flavor* is Session 04's
archetype problem, not a faction-casting problem. See §A9 before adding any
second entry.

---

## §A5 — Resolution, caching, and the fallback path

```
getMapProfile [_worldName, _rebuild]
  ├─ if _rebuild: delete DSC_mapProfileCache + DSC_mapProfileUnknownWarned
  ├─ _key = toLower _worldName
  ├─ cache hit on _key  -> return the cached instance (same ref)
  ├─ build the authored table (fresh literals)
  ├─ exact-ish lookup: match a table row whose key toLower == _key
  │     hit  -> INFO_2 once ("map profile: %1 (%2)"), cache under _key, return
  │     miss -> fallback path
  └─ fallback path:
        _profile = +(table get "__GENERIC__")      // shallow copy is enough,
                                                   // climate literal is fresh
        _profile set ["world", _worldName];        // requested name, verbatim
        _profile set ["displayName", _worldName];
        warn-once per distinct _key via DSC_mapProfileUnknownWarned
        cache under _key, return
```

- **Lookup is case-insensitive** on the key, but the stored `world` value is the
  string the caller passed (or the authored casing on a hit — authored casing
  wins, so `["altis"]` returns `world == "Altis"`).
- **Warn once per distinct unknown world, never once per call.** Dedup hashmap
  `DSC_mapProfileUnknownWarned`, directly mirroring the `DSC_structureUnknownWarned`
  precedent in `AGENTS.md`. A consumer calling this per location would otherwise
  flood the RPT on a modded terrain.
- **Cache key is `missionNamespace` `DSC_mapProfileCache`** (HASHMAP
  `lowercased world -> profile`). Never `uiNamespace` — it survives a mission
  restart and would serve a stale table while the table is being hand-edited
  (the `AGENTS.md` structure-taxonomy cache gotcha, same failure mode).
- **No alias table.** `["Livonia"]` must fall back, loudly. The whole point of
  keying on `worldName` is that `worldName` is the only string the engine
  guarantees; silently aliasing a display name would mask a real caller bug
  (some future consumer passing `displayName` through by accident) and the
  fallback warning is exactly the signal that wants to be seen. Pinned by
  assertion §A6 #18.

---

## §A6 — Tier-1 assertion list (`suite: map_profile`, 19 assertions)

Registered as an inline `_testSuites set ["map_profile", { ... }]` block in
`fnc_initServerDebug.sqf` — the established pattern (no per-suite file, no
`XEH_PREP` entry for the suite). Force a rebuild once at the top of the suite
for a deterministic baseline, exactly as `structure_catalog` does.

| # | Assertion | Why |
|---|---|---|
| 1 | Each of `Altis`/`Stratis`/`Malden`/`Tanoa`/`Enoch` resolves with `isFallback == false` | the shipped maps |
| 2 | `VR` resolves with `isFallback == false` **and** `isSynthetic == true` | the harness runs there |
| 3 | An unknown world (`"NotAWorld_DSC"`) returns a profile with `isFallback == true` and does not throw | must degrade, not error |
| 4 | The fallback profile's `world` **and** `displayName` are the *requested* name, not `"__GENERIC__"` | a caller logging `world` must see what it asked for |
| 5 | Every profile (all 6 known + a fallback) carries every required key from §A3, with the right type | stops a half-filled profile shipping |
| 6 | A profile with an **extra** key still passes the schema check (subset semantics) | Q6 growth path — Sessions 06/09/11 must not turn this suite red |
| 7 | `civilianFactions` is a non-empty ARRAY of non-empty STRINGs on every profile | Session 04 depends on it |
| 8 | `policeFaction` and `hostNationFaction` are STRING and `""` on every profile | pins "don't invent a classname" until Session 09 |
| 9 | `climate` is a HASHMAP with `stub == true` and a non-empty `band` on every profile | Session 11's seam exists and is recognisably a stub |
| 10 | `region` is in the fixed region vocabulary on every profile | typo guard |
| 11 | `architecture` is in the fixed architecture vocabulary on every profile | typo guard |
| 12 | `latitude` is a NUMBER in `[-90, 90]` on every profile | Session 11 does sun math off it |
| 13 | `hemisphere` agrees with `latitude`'s sign on every profile (`lat >= 0` ⇒ `north`) | the one internally-checkable consistency rule in the table |
| 14 | `Tanoa` specifically is `south` with a negative latitude | the only southern row — pins the sign convention against a copy-paste error |
| 15 | Lookup is case-insensitive: `"altis"`, `"ALTIS"`, `"Altis"` all resolve non-fallback, and `world` reads `"Altis"` | |
| 16 | Calling with **no argument** returns the profile for `worldName` | works on any terrain including `VR` |
| 17 | Cached — a sentinel key set on the first returned handle is visible on a second call; `[_w, true]` rebuild clears it | same probe pattern as `structure_catalog` #12; **remove the sentinel afterwards** |
| 18 | `Enoch`'s `displayName` is `"Livonia"`, **and** `["Livonia"]` resolves as a **fallback** | the `worldName` gotcha and the no-alias rule, both pinned |
| 19 | Three calls for the same unknown world leave exactly **one** entry in `DSC_mapProfileUnknownWarned` | warn-once, not warn-per-call |

*#1, #5 and #7–#13 each loop over the whole map set internally and report as a
single labelled assertion — do not split them per-world, the suite output stays
readable and a failure label names the offending world in its message.*

---

## §A7 — Gotchas and hard constraints

- **🔴 Do NOT read `configFile >> "CfgWorlds" >> worldName >> "latitude"`.**
  The engine's terrain latitude uses the **opposite sign convention** (BIKI:
  negative values are north of the equator) and is a map-author-supplied value
  tuned for the in-game sun, not a real-world coordinate — Altis ships roughly
  `-35` while Lemnos is `39.9 N`. The profile's `latitude` is **authored
  real-world truth, positive = north**. If Session 11 ever needs the engine
  value, it converts explicitly at that call site. Fold this into `AGENTS.md`.
- **Livonia's `worldName` is `Enoch`.** Verified in-repo: the map folder is
  `addons/maps/DSC_Livonia.enoch/` and `fnc_getStructureCatalog.sqf`'s per-map
  exclusion table is already keyed `"Enoch"`.
- **Cache in `missionNamespace`, never `uiNamespace`** — `uiNamespace` survives
  a mission restart and would serve a stale profile across dev iterations while
  the table is being edited ("my edit did nothing").
- **The returned hashmap is the cached instance.** Document read-only in the
  header. A consumer that mutates it poisons every later caller on that machine.
- **Nothing may read this function when the session closes.** If `hemtt check`
  is clean and the RPT is byte-identical to a pre-session run except for one new
  `INFO` line, the session is correct. Resist "while I'm here" wiring.
- **CBA log macros only, never `diag_log`**, and **hoist every inline array
  literal out of a log macro argument** — `count (_profile get "civilianFactions")`
  and `getOrDefault ["k", v]` inside a `LOG_n`/`INFO_n`/`WARNING_n` arg break
  HEMTT's preprocessor comma count. Assign to a `private` first.
- **`#include "..\..\script_component.hpp"`** at the top of the new file (the
  `data/` folder has its own `script_component.hpp` — match the sibling files).
- **`select` over `if/then/else` for constant assignment**, and parenthesise any
  unary command inside a comparison — HEMTT lints both.
- **No `distance`/`distance2D` in this session**, so the precedence gotcha does
  not apply; do not introduce a position-aware field to make it apply.

---

## §A8 — Deliverables and definition of done

1. `addons/core/functions/data/fnc_getMapProfile.sqf` — §A2 signature, §A3
   schema, §A4 table inlined, §A5 resolution.
2. `PREP_SUB(data,getMapProfile);` added to `addons/core/XEH_PREP.hpp`, in
   alphabetical position (between `getInteractionSiteArchetypes` and
   `getMissionProfiles`).
3. `map_profile` Tier-1 suite registered inline in
   `addons/core/functions/init/fnc_initServerDebug.sqf`, all 19 assertions.
4. `hemtt check` clean.
5. **No consumer wired. No behavior change.**
6. Docs:
   - `AGENTS.md` — key-systems table row for `fnc_getMapProfile`; the
     `CfgWorlds` latitude sign gotcha and the no-alias rule folded into the
     gotcha list.
   - `docs/overhauls/ambient_world/README.md` — status tracker row 03; Decision
     **C31** (Q6 resolution) added to the Decision Log; Q6 struck from Open
     Questions.
   - This file — results log appended (see the template in
     `docs/campaign_overhaul/session_02_intel_ledger.md`).
7. **No new `DSC_testConfig` file.** Session 03 is Tier-1 only; the existing
   `docs/test_harness/01_tier1_headless.sqf` run covers it. Do not author a
   Tier-2 harness for a function nothing calls.

---

## §A9 — Unverified data (the agent cannot launch Arma)

Flag these in-file with `// REVIEW` so the owner can settle them with a config
browser; **none of them block the session**, and every one of them is a
one-value edit afterwards.

1. **`Malden` latitude `42.0`** — Malden 2035 is a fictional Mediterranean
   island with no canonical real-world coordinate. The value is an authored
   approximation chosen to sit in the same climate band as Altis/Stratis. Only
   Session 11's sun math will ever care.
2. **`Tanoa` latitude `-17.6` / `hemisphere "south"`** — from the Horizon
   Islands' canonical South Pacific placement, not from a config read.
3. **`civilianFactions` beyond `CIV_F`** — Apex and Contact civilian classes may
   or may not sit under additional `CfgFactionClasses` entries (the Laws of War
   IDAP faction is the obvious candidate). **Do not guess a classname.** Session
   04's `fnc_buildCivilianPool` logs the pool and every rejected class per
   faction; grow this array from that evidence, not from memory. Adding a second
   entry later is a one-line table edit and assertion #7 already covers it.
4. **`languageHint` values** are flavor strings with no consumer yet; they are
   unconstrained by any vocabulary assertion on purpose.
5. **The `CfgWorlds` latitude sign convention** (§A7) is from BIKI, not from an
   in-engine read. It is stated as a *reason not to read the config at all*, so
   being wrong about it costs nothing this session — but verify before Session
   11 if that session ever wants the engine value.

---

## Paste-ready prompt (Sonnet, to build the approved spec)

```
Read docs/campaign_overhaul/WORKFLOW_RULES.md (still law),
docs/overhauls/ambient_world/README.md, and
docs/overhauls/ambient_world/session_03_map_profile.md.

Implement the APPROVED MINI-SPEC at the bottom of the session doc
("# Approved Mini-Spec (Session 03)"). It is fully decided — the function
signature (§A2), the profile schema and the two fixed vocabularies (§A3), the
complete 7-row authored table (§A4), the resolution/caching/fallback rules
(§A5), and the 19 Tier-1 assertions (§A6) are all signed off. Do NOT
re-litigate any of it and do NOT add fields that are not in §A3.

Your job is transcription + wiring, in this order:

1. Write addons/core/functions/data/fnc_getMapProfile.sqf — §A2 signature and
   header contract, the §A4 table inlined in the function body, the §A5
   resolution/cache/fallback path. Put // REVIEW on the rows and values listed
   in §A9. Match the file style of its siblings in that folder
   (fnc_getSweepArchetypes.sqf is a good exemplar for the header block;
   fnc_getStructureCatalog.sqf is the exemplar for the missionNamespace cache
   and the warn-once dedup map).
2. Add PREP_SUB(data,getMapProfile); to addons/core/XEH_PREP.hpp in
   alphabetical position (between getInteractionSiteArchetypes and
   getMissionProfiles).
3. Add the map_profile Tier-1 suite to
   addons/core/functions/init/fnc_initServerDebug.sqf as an inline
   _testSuites set ["map_profile", { ... }] block — that is the established
   pattern (no per-suite file, no XEH_PREP entry for the suite). All 19
   assertions from §A6, same [label, passed] result shape and same
   force-rebuild-once-at-the-top structure as the existing structure_catalog
   suite. Follow its cache-sentinel probe pattern for assertion 17, including
   removing the sentinel afterwards.
4. hemtt check clean.
5. Docs: AGENTS.md key-systems row + the two new gotchas from §A7 (the
   CfgWorlds latitude sign convention, and the deliberate no-alias rule);
   README.md status tracker row for Session 03, Decision C31 recording the Q6
   resolution, and Q6 struck from the Open Questions list; a Results log
   section appended to session_03_map_profile.md.

Hard constraints:
- NO CONSUMERS. Nothing may call fnc_getMapProfile when you are done. Do not
  touch fnc_initServer, fnc_initFactionData, fnc_resolveCivilianMix,
  fnc_setupCivilians, or any faction profile. Session 04 is the first reader
  and Session 09 owns the faction wiring — that is the riskiest change in the
  program and it is not this session.
- policeFaction and hostNationFaction stay "" with a // TBD Session 09 comment.
  Do not invent a faction classname.
- climate stays stubbed: ["band", <string>], ["stub", true]. Nothing else.
- civilianFactions is ["CIV_F"] on every row. Do not add a second faction from
  memory — see §A9 item 3.
- Never read configFile >> "CfgWorlds" >> ... >> "latitude". The profile's
  latitude is authored real-world truth, positive = north; the engine value
  uses the opposite sign convention. §A7.
- Cache in missionNamespace (DSC_mapProfileCache), never uiNamespace. Warn
  once per distinct unknown world via DSC_mapProfileUnknownWarned, never once
  per call — mirror the DSC_structureUnknownWarned precedent.
- Unknown world must WARN and return the generic fallback. Never nil, never
  an empty hashmap, never an ERROR/throw.
- Respect the CBA log-macro comma-counting trap: hoist every inline array
  literal (count (_p get "civilianFactions"), getOrDefault ["k", v], etc.) to
  a local before passing it to LOG_n / INFO_n / WARNING_n / ERROR_n / TRACE_n.
- CBA log macros only, never diag_log. #include the data/ folder's
  script_component.hpp like its siblings do.

Sonnet scope — build the approved spec, do not redesign it.
```

---

## Human playtest checklist

This session is behaviorally invisible. The playtest is a **non-regression
check plus one five-second eyeball**:

- [ ] `hemtt check` clean.
- [ ] `test.VR` → `fnc_runTests` prints `PASS: map_profile` for all 19
      assertions. Note that assertions 1 and 5 exercise Altis/Tanoa/Enoch etc.
      **from the VR world** — that is the point of the explicit `_worldName`
      argument, not a bug.
- [ ] Launch `hemtt launch developer_factions` on Altis. The RPT must be
      unchanged from a pre-session run **except** that nothing new appears at
      all (the function is never called). If you see a map-profile `INFO` line
      during a normal boot, something got wired that shouldn't have been.
- [ ] Optional sanity poke from the debug console:
      `str ([] call DSC_core_fnc_getMapProfile)` on Altis → `region`
      `mediterranean`, `displayName` `Altis`, `isFallback` `false`.
      `str (["Enoch"] call DSC_core_fnc_getMapProfile)` → `displayName`
      `Livonia`. `str (["Nowhere"] call DSC_core_fnc_getMapProfile)` →
      `isFallback` `true` plus exactly one WARNING in the RPT, no matter how
      many times you run it.
- [ ] Confirm §A9's `// REVIEW` markers are present on the Malden/Tanoa
      latitudes and the `civilianFactions` rows, so the hand-edit pass has
      something to find.

---

## Results log

- Build: `hemtt check` clean, `hemtt build` clean (193 sqf files compiled,
  0 errors/warnings, 4 PBOs built).
- Shipped: `addons/core/functions/data/fnc_getMapProfile.sqf` — §A2 signature
  (`[_worldName, _rebuild]`, both optional), the §A4 seven-row table
  (`Altis`/`Stratis`/`Malden`/`Tanoa`/`Enoch`/`VR`/`__GENERIC__`) inlined in
  the function body, the §A5 case-insensitive lookup + per-key
  `missionNamespace` cache (`DSC_mapProfileCache`) + warn-once dedup
  (`DSC_mapProfileUnknownWarned`) + no-alias fallback path. `// REVIEW`
  markers present on the Malden latitude (`42.0`), the Tanoa latitude
  (`-17.6`), and a comment pointing at §A9 item 3 above the shared
  `civilianFactions = ["CIV_F"]` row convention.
  `PREP_SUB(data,getMapProfile);` registered in `XEH_PREP.hpp` in
  alphabetical position between `getInteractionSiteArchetypes` and
  `getMissionProfiles`.
- Tier-1: `map_profile` suite registered in `fnc_initServerDebug.sqf`
  (inline `_testSuites set [...]` block, same pattern as `structure_catalog`
  and `location_poi` — no per-suite file, no `XEH_PREP` entry). All 19
  assertions from §A6 present: shipped-map/VR/unknown resolution, fallback
  naming, the §A3 schema subset check (plus the "extra key still passes"
  case), `civilianFactions`/`policeFaction`/`hostNationFaction`/`climate`
  field checks, region/architecture vocabulary checks, the
  latitude/hemisphere consistency check and the Tanoa south pin,
  case-insensitive lookup, the no-argument default, the cache + `[_w, true]`
  rebuild probe (sentinel removed afterwards, mirroring the
  `structure_catalog` #12 pattern), the Enoch/Livonia no-alias pin, and the
  warn-once-per-distinct-world check (the suite forces its own rebuild
  immediately before this last assertion so earlier assertions' unknown-world
  calls can't inflate the count). Not yet run in-engine (requires
  `hemtt launch` + `test.VR` with `fnc_runTests` enabled — human playtest
  step, see the checklist above).
- No consumers wired: confirmed by `grep`/code search — nothing outside
  `fnc_getMapProfile.sqf` itself, `XEH_PREP.hpp`, and the Tier-1 suite
  references `DSC_core_fnc_getMapProfile`. `fnc_initServer`,
  `fnc_initFactionData`, `fnc_resolveCivilianMix`, `fnc_setupCivilians`, and
  every faction profile are untouched.
- Follow-ups / new gotchas: two folded into `AGENTS.md` — the `CfgWorlds`
  latitude sign-convention trap (never read the engine value as real-world
  truth) and the deliberate no-alias rule (`["Livonia"]` must fall back
  loudly, not silently resolve to `Enoch`). Decision **C31** (Q6 resolution)
  recorded in this program's README Decision Log; Q6 struck from the Open
  Questions list.
- Playtest: _pending_ — human to run `fnc_runTests` in `test.VR` and confirm
  `map_profile/*` all PASS, then launch on Altis and confirm the RPT is
  byte-identical to a pre-session run (no new `INFO`/`WARNING` lines), per
  the checklist above.

