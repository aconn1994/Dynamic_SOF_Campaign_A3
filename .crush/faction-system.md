# Faction System — DSC

## Design Goal

Discover and use factions from any loaded mods (RHS, CUP, CFP, Aegis, 3CB, vanilla) without hardcoding. Factions are mapped to campaign roles, then their groups and assets are extracted and classified automatically.

## Pipeline Overview

```
Faction Profile Config (roles → faction classnames)
        │
        ▼
fnc_initFactionData          ← orchestrator
    ├── validates each faction exists in CfgFactionClasses
    ├── skips missing factions with warning (mod not loaded)
    │
    ├── fnc_extractGroups    ← per faction, from CfgGroups
    │       └── raw group data: side, category, units, vehicles, path
    │
    ├── fnc_classifyGroups   ← per faction
    │       └── fnc_classifyGroup  ← per group
    │               └── fnc_classifyUnit  ← per unit in group
    │
    └── fnc_extractAssets    ← per faction, from CfgVehicles
            └── categorized vehicles, statics, aircraft, boats, drones
```

## Faction Profiles

Defined in `fnc_initServer`. A profile maps **roles** to **faction classnames + side**:

```sqf
createHashMapFromArray [
    ["bluFor", createHashMapFromArray [
        ["side", west],
        ["factions", ["BLU_F"]]
    ]],
    ["opFor", createHashMapFromArray [
        ["side", east],
        ["factions", ["OPF_F", "OPF_R_F"]]
    ]],
    // ... etc
]
```

### Roles

| Role | Combat? | Description |
|------|---------|-------------|
| `bluFor` | Yes | Player faction — group/asset extraction |
| `bluForPartner` | Yes | Friendly AI forces |
| `opFor` | Yes | Primary enemy |
| `opForPartner` | Yes | Enemy auxiliaries, militia |
| `irregulars` | Yes | Insurgents, armed civilians |
| `civilians` | No | Neutral population (no extraction) |
| `environmentalActors` | No | IDAP, UN (no extraction) |

Only combat roles get group + asset extraction. Civilian roles are stored but not processed yet.

## Group Extraction (`fnc_extractGroups`)

Walks `CfgGroups >> Side >> Faction >> Category >> Group` and returns raw data per group:

| Field | Type | Example |
|-------|------|---------|
| `side` | Number | `0` (OPFOR) |
| `sideName` | String | `"East"` |
| `factionClass` | String | `"rhs_faction_msv"` |
| `category` | String | `"Infantry"`, `"SpecOps"`, `"Motorized"` |
| `groupName` | String | `"rhs_group_rus_msv_infantry_squad"` |
| `path` | String | `"East/rhs_faction_msv/Infantry/GroupName"` |
| `units` | Array | Config paths to each unit slot |
| `vehicles` | Array | Vehicle classnames from `vehicle` property |
| `unitCount` | Number | Count of unit slots |

### Known CfgGroups Desync Workarounds

Some factions have different classnames in `CfgFactionClasses` vs `CfgGroups`:

| CfgFactionClasses | CfgGroups Entry |
|-------------------|-----------------|
| `BLU_G_F` | `Guerilla` |
| `BLU_GEN_F` | `Gendarmerie` |
| `rhs_faction_socom` | `rhs_faction_socom_marsoc` |

These are handled with explicit remapping in `fnc_extractGroups`.

## Unit Classification (`fnc_classifyUnit`)

Inspects each unit classname via CfgVehicles and returns:

- **Identity**: `isMan`, `isVehicle`, `vehicleType`, `faction`, `rank`, `displayName`
- **Capabilities**: `hasAT`, `hasAA`, `hasMG`, `hasSniper`, `hasMortar`, `hasNVG`
- **Roles**: `isOfficer`, `isMedic`, `isEngineer`, `isPilot`, `isCrew`, `isDiver`, `isRecon`
- **Traits array**: Summary like `["AT", "NVG", "RECON"]`

Detection methods (in priority order):
1. **Magazine-based** — AT vs AA ammo types (handles multi-purpose launchers like Titan)
2. **Weapon classname** — Pattern matching (`rpg`, `lmg`, `svd`, etc.)
3. **Editor subcategory** — `medic`, `engineer`, `pilot`, `crew`, `recon`, `special`
4. **Display name / classname** — Fallback pattern matching

## Group Classification (`fnc_classifyGroup`)

Aggregates unit classifications into group-level **doctrine tags**:

### Tag Assignment Logic

| Tag | Condition |
|-----|-----------|
| `FIRETEAM` | 2-5 infantry, no vehicles |
| `INFANTRY_SQUAD` | 6-14 infantry, no vehicles |
| `PLATOON_ELEMENT` | 15+ infantry |
| `AT_TEAM` | 2+ AT specialists, or small group with AT |
| `AA_TEAM` | 2+ AA specialists, or small group with AA |
| `SNIPER_TEAM` | Sniper + ≤3 infantry |
| `MORTAR_SECTION` | Has mortar carrier |
| `SCOUT_RECON` | Recon units or category contains "recon"/"specop" |
| `ELITE` | Name/category matches SF patterns |
| `MILITIA` | Name/category matches militia patterns |
| `FOOT` | No vehicles |
| `MOTORIZED` / `MECHANIZED` / `ARMORED` | Vehicle type in group |
| `PATROL` | 2-8 foot infantry, not sniper team |

Each classified group also gets:
- `unitAnalysis` hashmap — counts of each role type
- `confidence` score — 0.0-1.0 based on how many signals matched

## Group Filtering (`fnc_getGroupsByTag`)

Downstream systems filter groups by doctrine tags:

```sqf
// All foot groups excluding amphibious
[_groups, ["FOOT"], ["AMPHIBIOUS", "NAVAL"]] call DSC_core_fnc_getGroupsByTag;

// Elite recon only
[_groups, ["ELITE", "SCOUT_RECON"]] call DSC_core_fnc_getGroupsByTag;
```

- Include tags: ALL must match
- Exclude tags: NONE may match

## Asset Extraction (`fnc_extractAssets`)

Scans `CfgVehicles` for all scope≥2 vehicles matching a faction. Categorizes into:

| Category | Subcategories |
|----------|--------------|
| `staticWeapons` | `HMG`, `GMG`, `AT`, `AA`, `mortar`, `cannon`, `other` |
| `cars` | `unarmed`, `armed`, `mrap` |
| `trucks` | (flat array) |
| `apcs` | (flat array) |
| `tanks` | (flat array) |
| `helicopters` | `attack`, `transport` |
| `planes` | `attack`, `transport` |
| `boats` | (flat array) |
| `drones` | (flat array) |

Classification uses `isKindOf` inheritance checks, `simulation` config value, `editorSubcategory`, turret weapons, and `transportSoldier` capacity (≥6 = transport).

## Output Structure

`fnc_initFactionData` returns:

```sqf
// Per role:
_factionData get "opFor"
    → "factions"  : ["OPF_F", "OPF_R_F"]          // validated
    → "side"      : east
    → "groups"    : { "OPF_F": [classified groups], "OPF_R_F": [...] }
    → "assets"    : { "OPF_F": { staticWeapons: {...}, cars: {...}, ... } }
```

This structure feeds directly into `fnc_populateAO` and `fnc_initInfluence`.
