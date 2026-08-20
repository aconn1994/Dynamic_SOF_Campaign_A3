# Test Harness — Example Configs

Two example `DSC_testConfig` blocks for the Tier-1/Tier-2 test harness
(`DSC_core_fnc_runTests` + `DSC_core_fnc_initTestScenario`). See
`.crush/agentic-workflow-and-testing.md` Part B and
`docs/campaign_overhaul/session_01_test_harness.md` for the full design.

## Files

- `01_tier1_headless.sqf` — Tier-1 headless suite run. No terrain needed,
  boots only `globals`, registers no mission generation. Paste into (or
  `execVM` from) `test.VR`'s `initServer.sqf` above the
  `DSC_core_fnc_runTests` call, or register additional suites the same way
  before calling it.
- `02_tier2_altis_forced_kill_capture.sqf` — Tier-2 feature harness. Boots
  `globals + locations + factions + influence`, forces a `KILL_CAPTURE`
  template with the `AFO_rural` profile at a fixed location, single-shot
  (immediate debrief cycle), player teleported ~150m from the objective.
  Intended for a dedicated test mission following the `DSC_Test.<Terrain>`
  naming pattern described in the design doc (e.g. `DSC_Test.Altis`) — swap
  in whatever real location id exists on the terrain you're testing against
  (dump `DSC_locations` once with `steps: ["globals","locations"]` and no
  forced location to find one), or delete the `"location"` key entirely to
  let `regionCenter`/`regionRadius` (or full auto-selection) pick one.

## Usage

1. Copy the relevant block's contents into the target mission's
   `initServer.sqf`, **before** the harness call:
   - Tier-1: before `[] call DSC_core_fnc_runTests;`
   - Tier-2: before `[] call DSC_core_fnc_initTestScenario;` (this call
     replaces `DSC_core_fnc_initServer` for that mission — do not call both).
2. `hemtt build`, then `hemtt launch` with the matching preset from
   `.hemtt/launch.toml`'s tier-switch comment block active.
3. Read the filtered `DSC:` lines in the RPT for `PASS`/`FAIL`/summary
   (Tier-1) or `initTestScenario - ...` step banners + the single generated
   mission (Tier-2).
