# Session 04 — Civilian Classification

**Owner item:** 2
**Model:** Opus spec → Sonnet build
**Ships:** A civilian archetype registry with behavior intent, a rewritten
resolver, and faction-pool hygiene.
**Depends on:** 01 (subtypes), 03 (map profile).

---

## Owner's stated problems

1. *"People in full suits walking around in the woods 10km from the nearest
   community."*
2. *"Hologram/VR civilians walking around everywhere."*
3. Only four archetypes exist (`civilian`, `civilian_worker`, `civilian_suit`,
   `civilian_labcoat`) and the owner wants depth **with behavior**.

### Root causes found in the planning pass

| Symptom | Cause | Fix lands in |
|---|---|---|
| VR / hologram civilians | `fnc_initFactionData`'s `_extractManPool` filters only `scope >= 2 && faction == '<X>' && isMan == 1`. **No classname denylist exists anywhere in the repo.** | **This session** |
| Every suit is the same man | `fnc_resolveEntityClass`'s `civilian_suit` and `civilian_labcoat` branches take the **first** keyword match, not a random one | **This session** |
| Wrong-archetype civilians anywhere | All three specialty branches fall back to `selectRandom _pool` (an unfiltered pool member) when no keyword matches | **This session** |
| Civilians in the woods / on water | `fnc_setupCivilians` fallback spawn is a raw polar offset, `z = 0`, no terrain/water/slope validation | **Session 05** |
| Hamlet draws the same mix as a city | `fnc_resolveCivilianMix` baseline is uniform | **Session 05** |

---

## Target

### Archetype registry — `fnc_getCivilianArchetypes`

~10–14 archetypes, each carrying **appearance keywords, behavior intent, and
placement affinity**:

```sqf
["FARMER", createHashMapFromArray [
    ["keywords",      ["farmer","worker","hunter"]],
    ["behavior",      "WORK_LOOP"],          // see behavior vocabulary
    ["anchorSubtypes",["barn_large","barn_small","cowshed","field"]],
    ["anchorFlags",   ["workplace"]],
    ["outdoorBias",   0.8],                  // likely outside vs indoors
    ["nightPresence", 0.2],                  // multiplier after dark
    ["vehicles",      ["tractor","civ_truck"]]
]],
```

Candidate archetype list (owner to approve/trim):
`RESIDENT`, `FARMER`, `WORKER` (industrial), `DOCKWORKER`, `SHOPKEEPER`,
`OFFICE_WORKER`, `MEDICAL_STAFF`, `CLERGY`, `TEACHER`, `FISHERMAN`,
`MECHANIC`, `VENDOR`, `LOITERER` (youth/idlers), `TRAVELLER` (transient, roads).

Behavior vocabulary (intent only; Session 05 implements):
`IDLE_ANCHORED` · `WORK_LOOP` · `WANDER_LOCAL` · `STAND_POST` ·
`TRANSIT` (road-to-road).

### Resolver v2 — `fnc_resolveCivilianClass`

Replaces the civilian branches of `fnc_resolveEntityClass` (which keeps its
`officer` / literal-classname duties).

- Keyword match → **`selectRandom` over ALL matches**, never first-hit.
- No match → fall back along an explicit **archetype fallback chain**
  (`MEDICAL_STAFF → OFFICE_WORKER → RESIDENT`), not a blind pool pick.
- Unknown archetype key → **ERROR + degrade to `RESIDENT`**, same posture as
  `fnc_resolveEntityClass`'s unknown-resolver branch (see `AGENTS.md` gotcha).

#### Mods must never be a requirement (Decision C21)

Every archetype terminates in a **generic civilian fallback that fits any
scenario**, so a vanilla-only install gets a complete, coherent population with
correct *behavior* even when several archetypes resolve to the same classname.
Mods improve fidelity; they are never load-bearing.

Concretely: the fallback chain must bottom out at a vanilla class that is
guaranteed to exist, and the resolver must **never** return `""` or `objNull`.
A Tier-1 assertion pins this.

### Pool hygiene — `fnc_buildCivilianPool`

Applied at `fnc_initFactionData` extraction time:

- **Denylist** by classname substring: `_VR_`, `VirtualReality`, `_F_Hologram`,
  `Hologram`, plus anything the playtest turns up.
- Reject units whose config side is not `civilian` when extracted for a civilian
  role.
- Log the pool size per faction, and log **every rejected class once** so the
  denylist can be grown from evidence rather than guessed.
- Map-profile-driven: pool is built from `fnc_getMapProfile`'s
  `civilianFactions`, not a hardcoded `["CIV_F"]`.

---

## Tier-1 test plan (`suite: civilian_class`)

Resolver and pool-builder must be **pure over a passed-in pool** so they test
with no world and no config access.

| Assertion | Why |
|---|---|
| Keyword match over a mock pool returns a *member of the match set*, and across N calls returns >1 distinct value when >1 match exists | pins the first-hit defect closed |
| Unknown archetype key ERRORs and returns the `RESIDENT` fallback | the `unitClassResolver` gotcha class |
| Fallback chain is followed in order when the primary has no match | |
| Empty pool returns a safe hardcoded default (`C_man_1`), never `""` | spawn code must never get an empty classname |
| **Every archetype resolves to a non-empty classname against a VANILLA-ONLY mock pool** | Decision C21 — mods are never a requirement; pinned |
| Denylist removes `_VR_` / `Hologram` classes from a mock pool | the owner's reported bug, pinned |
| Denylist is case-insensitive | |
| Pool builder with all-rejected input returns `[]` + ERROR, does not throw | |
| Every archetype in the registry has every required key | schema guard |
| Every `anchorSubtype` referenced by an archetype exists in the Session 01 catalog | **cross-table integrity — the highest-value assertion here** |
| `nightPresence` and `outdoorBias` are in `[0,1]` | Session 05 multiplies by these |

---

## Gotchas

- **`joinSilent` after every `createUnit`.** Not negotiable (`AGENTS.md`). Any
  new spawn path in this session inherits it.
- **Civilians must never be C2-stamped.** Existing gotcha; preserve the
  `side != civilian` filter at the presence dispatcher.
- **`setCaptive true` makes `side _unit` report CIVILIAN** — any side validation
  added here must exclude captives.
- **Don't widen `fnc_resolveEntityClass`'s contract.** It serves HVTs and
  hostages too. Add the civilian resolver beside it; don't overload it.
- **`fnc_resolveCivilianMix` output format must stay compatible** with
  `fnc_setupCivilians`'s `classMix` until Session 05 rewrites both together —
  or change both in that session, not this one.

---

## Definition of done

- `fnc_getCivilianArchetypes`, `fnc_resolveCivilianClass`,
  `fnc_buildCivilianPool` registered in `XEH_PREP.hpp`.
- `fnc_initFactionData` builds the civilian pool through the hygiene path.
- `hemtt check` clean; Tier-1 `civilian_class` passing.
- Playtest: RPT logs the civilian pool per faction with rejected classes listed;
  **zero VR/hologram units observed in a full Altis run**.
- `AGENTS.md`: new gotchas (pool hygiene, first-hit resolver) folded in.

---

## Open questions

- **Q7 — ANSWERED (Decision C20): keep the full archetype list.** Several
  archetypes will resolve to the same vanilla classname with different
  *behavior*; that is acceptable and intended. Behavior is what sells it, and
  modded civilian factions fill in appearance later.
- **Q8 — Should `environmentalActors` (IDAP, UN, contractors) route through the
  same archetype system** (`AID_WORKER`, `JOURNALIST`, `CONTRACTOR`), or stay
  separate? *Recommendation: same system, different registry entries.*
