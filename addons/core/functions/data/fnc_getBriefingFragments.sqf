#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_getBriefingFragments
 * Description:
 *     Returns the briefing fragment registry. Each fragment supplies the
 *     mission-type-specific portions of a briefing — title prefix,
 *     objective statement, rules of engagement, task icon — leaving the
 *     intel/area/threat blocks to be composed from runtime data
 *     (location, AO tags, entity/object archetypes).
 *
 *     fnc_createMissionBriefing reads the mission's "briefingArchetype"
 *     field and looks up the matching fragment here. New raid variants
 *     register a fragment instead of forking the briefing function.
 *
 *     Field reference:
 *       "titlePrefix"  <STRING>  Prefix used in task title before location.
 *       "objective"    <STRING>  Plain-language action statement (one line).
 *       "roe"          <STRING>  Rules of engagement / exit conditions.
 *       "taskIcon"     <STRING>  Arma task icon classname (kill, target,
 *                                destroy, getin, intel, run, etc.).
 *
 * Arguments: None
 *
 * Return Value:
 *     <HASHMAP> - Fragment name -> fragment hashmap.
 */

createHashMapFromArray [

    ["raid_kill_capture", createHashMapFromArray [
        ["titlePrefix", "Eliminate HVT"],
        ["objective", "Locate and eliminate or capture a high-value target."],
        ["roe", "Weapons free. Eliminate or capture the HVT and RTB for debrief."],
        ["taskIcon", "kill"]
    ]],

    ["raid_supply_destroy", createHashMapFromArray [
        ["titlePrefix", "Destroy Supplies"],
        ["objective", "Locate and destroy enemy supply caches."],
        ["roe", "Weapons free. Confirm all caches destroyed before exfiltrating."],
        ["taskIcon", "destroy"]
    ]],

    ["raid_intel_gather", createHashMapFromArray [
        ["titlePrefix", "Recover Intel"],
        ["objective", "Locate and recover sensitive intelligence materials."],
        ["roe", "Weapons free. Recover intel and RTB. Avoid destroying source materials."],
        ["taskIcon", "intel"]
    ]],

    ["raid_hostage_rescue", createHashMapFromArray [
        ["titlePrefix", "Hostage Rescue"],
        ["objective", "Locate and recover friendly hostages alive."],
        ["roe", "Weapons free. Hostages must be extracted alive — collateral damage will compromise the mission."],
        ["taskIcon", "getin"]
    ]],

    ["raid_sabotage", createHashMapFromArray [
        ["titlePrefix", "Sabotage"],
        ["objective", "Destroy designated equipment and recover any associated intel."],
        ["roe", "Weapons free. Confirm targets destroyed before exfiltrating."],
        ["taskIcon", "destroy"]
    ]],

    // Session 6 (SWEEP archetype) — information is the objective, not a body
    // count. ROE is deliberately "weapons tight" across all three; getting
    // spotted converts the mission rather than failing it (fnc_sweepConvert).
    ["sweep_observe", createHashMapFromArray [
        ["titlePrefix", "Recon - Observe"],
        ["objective", "Establish a standoff vantage and observe the objective without being detected."],
        ["roe", "Weapons tight. Avoid contact - compromise converts this into an exfil-under-pressure mission."],
        ["taskIcon", "intel"]
    ]],

    ["sweep_area", createHashMapFromArray [
        ["titlePrefix", "Recon - Area Sweep"],
        ["objective", "Sweep the designated search points and report on enemy disposition."],
        ["roe", "Weapons tight unless engaged. Avoid contact - compromise converts this into a direct-action mission."],
        ["taskIcon", "intel"]
    ]],

    ["sweep_pid", createHashMapFromArray [
        ["titlePrefix", "Recon - PID"],
        ["objective", "Positively identify the designated target without engaging."],
        ["roe", "Weapons tight. Avoid contact - compromise converts this into a direct-action mission."],
        ["taskIcon", "intel"]
    ]]
]
