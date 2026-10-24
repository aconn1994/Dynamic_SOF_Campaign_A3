# Session 01 Ambiguities — Structure Taxonomy

Transcribed from `docs/overhauls/ambient_world/session_01_structure_taxonomy.md`
§A6 ("Approved Mini-Spec"). These are the rows the agent flagged with
`// REVIEW` in `fnc_getStructureCatalog.sqf`'s Table 2 — low-confidence
transcription guesses that need a human decision, not something to silently
guess on. Each also carries its `// REVIEW` comment at the matching row in
code.

This session does **not** re-litigate or resolve any of these — it transcribes
them, per the hard constraint in the build prompt. Resolution is hand-editing
work for whoever picks up the "long pole" step in the session's human
playtest checklist.

| # | Class(es) | Scaffold guess | The question |
|---|---|---|---|
| 1 | `Land_PowerPoleWooden_F` | `power_distribution`, non-occupiable | Currently commented out. There are *thousands* of instances on Altis — including it may swamp `infrastructure` counts at every location and shift tag thresholds. In or out? |
| 2 | `Land_Bridge_*_PathLod_F`, `Land_Canal_Wall_Stairs_F`, `Land_Track_01_bridge_F` | `bridge`, occupiable + satellite | These are in `_sideCivilian` today, so legacy says occupiable — but garrisoning a bridge pathing LOD is probably an existing bug. Keep occupiable (safe, no behavior change) or mark non-occupiable (correct, but changes `side`)? |
| 3 | `Land_Stadium_p4/p5/p9_F` | `commercial` / `stadium` | Is a stadium commercial, or does it want a `civic` / `recreation` category? Category vocabulary is fixed at 11, so `commercial` unless you want to reopen B15. |
| 4 | `Land_Research_HQ_F`, `Land_Research_house_V1_F` | `military` / `command_post` | Military research, or a civilian `research_facility` subtype under `industrial`? They sit on CSAT installations in vanilla. |
| 5 | `Land_WoodenWall_04_s_d_5m_F`, `Land_BrickWall_03_l_gate_F` | `residential` / `house_annex` | These are **walls**, not buildings. They are in `_sideCivilian` today. Keep them (no behavior change) or drop them from the garrison arrays entirely (correct, but changes `side`)? |
| 6 | `Land_HaulTruck_01_abandoned_F`, `Land_MiningShovel_01_abandoned_F` | `industrial` / `mine_site` | Abandoned vehicle props, not structures. Own `derelict_vehicle` subtype, or fine as mine dressing? |
| 7 | `Land_Caravan_01_rust_F` | `residential` / `shed_domestic` | A caravan **is** a dwelling, unlike a shed — so folding it into `shed_domestic` denies it `civilian_home`. Restore the `caravan` subtype, or accept? |
| 8 | `Land_i_Stone_Shed_V2_dam_F`, `Land_i_Stone_Shed_V3_dam_F` | `residential` / `shed_domestic` | Today these are in `_func_residential` alongside *houses*. The scaffold reads them as damaged sheds. Confirm. |
| 9 | `Land_Temple_Native_01_F` | `religious` / `temple` | Tanoa native temple — religious, or a `landmark`-only cultural site? |
| 10 | `Land_SM_01_shed_F`, `Land_SM_01_shed_unfinished_F` | `industrial` / `warehouse_small` | What is "SM"? Guessed from current `_func_industrial` membership. |
| 11 | `Land_SCF_01_heap_bagasse_F` | `industrial` / `processing_plant`, occupiable | It is a *heap*. In `_mainCivilian` today so legacy says occupiable; almost certainly shouldn't be. |
| 12 | `Land_Radar_01_kitchen_F` | `infrastructure` / `radar_site` | It is a kitchen building that happens to sit on a radar site. `radar_site` (site-coherent) or `military`/`cargo_structure` (building-coherent)? |
| 13 | The 11 **NEW** classnames (see below) | as listed in §A5 | **Must be verified to exist in vanilla A3 with those exact names before shipping.** `Land_PowerWave_pole*` in particular is a guess at the family name. Any that don't resolve get dropped from Table 2 and listed here. |
| 14 | `Land_Sawmill_01_illuminati_tower_F` | `agricultural` / `sawmill` | Easter-egg object. Keep as sawmill dressing or drop? |
| 15 | `Land_Dome_Small_WIP_F`, `Land_Dome_Small_WIP2_F` | `military` / `dome` | "WIP" suggests construction, not a radome. `military`/`dome` or `industrial`/`construction_site`? They are in `_sideMilitary` today. |

## The 11 NEW classnames (item #13)

Added per the README's "Classes to add in Session 01" / "The military residue"
sections, transcribed verbatim from §A5. None have been verified in-game by
this session (the agent cannot launch Arma — see
`docs/campaign_overhaul/WORKFLOW_RULES.md`). Verify against the loaded mods
before trusting the coverage report's class counts:

1. `Land_PowerGenerator_F` → `power_station`
2. `Land_spp_Transformer_F` → `power_substation`
3. `Land_PowerPoleWooden_F` → `power_distribution` (also item #1 above — currently commented out in the pre-Session-01 file)
4. `Land_PowerWave_pole_F` → `power_distribution`
5. `Land_PowerWave_pole_L_F` → `power_distribution`
6. `Land_PowerWave_pole_R_F` → `power_distribution`
7. `Land_spp_Panel_F` → `solar_array`
8. `Land_TTowerSmall_1_F` → `comms_relay`
9. `Land_TTowerSmall_2_F` → `comms_relay`
10. `Land_Communication_anchor_F` → `comms_relay`
11. `Land_WaterTower_01_F` → `water_facility`
12. `Land_WaterTank_F` → `water_facility`
13. `Land_Radar_Small_F` → `radar_site`
14. `Land_Pipes_large_F` → `pipeline`

(Doc says "11"; the actual transcribed list in §A5 has 14 — all are included
verbatim in `fnc_getStructureCatalog.sqf`, each marked `// NEW` and
`// REVIEW` at its row. If any classname does not resolve in a given mod
load, treat it as item #13: omit the row rather than ship a phantom class —
see the gotcha in `AGENTS.md` and §A8 of the session doc.)

## Verification rule

If a NEW classname cannot be confirmed to exist, **omit the row** rather than
shipping a phantom. A phantom class is harmless to the legacy keys (it never
matches at runtime, so `isKindOf`/`typeOf` lookups simply miss) but it
inflates the coverage report and Table 2's row-count assertion, and it is
exactly the kind of silent-no-op the `unitClassResolver` gotcha in `AGENTS.md`
warns about.
