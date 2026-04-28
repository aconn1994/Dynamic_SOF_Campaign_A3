#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_getMissionProfiles
 * Description:
 *     Returns mission profile definitions. Profiles are preset configurations
 *     that shape how missions are selected and generated. They set defaults
 *     for location filtering, density, QRF behavior, target faction pools,
 *     and AO population parameters.
 *
 *     Profiles are applied by fnc_resolveMissionConfig when a template includes
 *     a "missionProfile" field. Template-level overrides always take priority
 *     over profile defaults.
 *
 *     Priority order:
 *       1. Explicit template values (highest)
 *       2. Profile defaults
 *       3. Resolver auto-generated values (lowest)
 *
 * Arguments: None
 *
 * Return Value:
 *     <HASHMAP> - Profile name → profile definition hashmap
 *
 * Profile Fields:
 *     --- Selection ---
 *     "requiredTags"       - Location must have at least one (OR logic)
 *     "excludeTags"        - Location must have none
 *     "targetRoles"        - Which faction roles to draw targets from
 *     "description"        - Human-readable profile description
 *     --- Generation ---
 *     "density"            - AO population density baseline
 *     "qrfEnabled"         - Whether QRF can respond
 *     "qrfDelay"           - [min, max] seconds for QRF response
 *     "areaPresenceChance" - Base chance for area faction per patrol/garrison slot
 *     --- AO Population (override density-derived defaults in populateAO) ---
 *     "garrisonAnchors"    - [min, max] garrison anchor buildings
 *     "garrisonSatellites" - [min, max] satellite buildings per anchor
 *     "guardCoverage"      - 0.0-1.0 fraction of cluster buildings that get guards
 *     "guardsPerBuilding"  - [min, max] guards at each guarded building
 *     "patrolCount"        - [min, max] target faction patrol groups
 *     "maxVehicles"        - Hard cap on parked vehicles
 *     "vehicleArmedChance" - 0.0-1.0 chance each vehicle is armed
 *
 * Example:
 *     private _profiles = call DSC_core_fnc_getMissionProfiles;
 *     private _afo = _profiles get "AFO";
 */

private _profiles = createHashMapFromArray [

    // AFO (Advanced Force Operations)
    // Small team, isolated target, low-profile approach
    // Cell-level targets: bombmakers, couriers, facilitators
    // Soft locations: farms, compounds, warehouses, small clusters
    // Even in a larger location, AFO creates a small footprint:
    //   1 garrison anchor with 0-1 satellites = a single compound to clear
    //   Minimal guards, rare patrols, unarmed vehicles
    ["AFO", createHashMapFromArray [
        ["requiredTags", ["isolated", "low_density", "settlement"]],
        ["excludeTags", ["military", "urban", "high_density", "base", "outpost"]],
        ["density", "light"],
        ["qrfEnabled", false],
        ["areaPresenceChance", 0.3],
        ["targetRoles", ["opForPartner", "irregulars"]],
        ["garrisonAnchors", [1, 1]],
        ["garrisonSatellites", [0, 1]],
        ["guardCoverage", 0.4],
        ["guardsPerBuilding", [1, 1]],
        ["patrolCount", [0, 1]],
        ["maxVehicles", 2],
        ["vehicleArmedChance", 0.1],
        ["description", "Low-profile operation against a soft target"]
    ]],

    // DA (Direct Action)
    // Full assault force, fortified target, heavy resistance
    // High-value targets: commanders, facilities, strongholds
    // Hard locations: towns, military outposts, large compounds
    // Even in a smaller location, DA creates a heavy presence:
    //   Multiple garrison anchors with satellites = compound + surrounding area
    //   High guard coverage, multiple patrols, armed vehicles
    ["DA", createHashMapFromArray [
        ["requiredTags", ["medium_density", "high_density", "town", "military"]],
        ["excludeTags", ["base"]],
        ["density", "heavy"],
        ["qrfEnabled", true],
        ["qrfDelay", [60, 120]],
        ["areaPresenceChance", 0.9],
        ["targetRoles", ["opFor"]],
        ["garrisonAnchors", [2, 3]],
        ["garrisonSatellites", [1, 3]],
        ["guardCoverage", 0.8],
        ["guardsPerBuilding", [1, 2]],
        ["patrolCount", [2, 3]],
        ["maxVehicles", 4],
        ["vehicleArmedChance", 0.5],
        ["description", "Direct action against a fortified target"]
    ]],

    ["AFO_populated_zone", createHashMapFromArray [
        ["requiredTags", ["high_density", "city"]],
        ["excludeTags", ["base", "military"]],
        ["density", "heavy"],
        ["qrfEnabled", false],
        ["areaPresenceChance", 0.8],
        ["targetRoles", ["opForPartner", "irregulars"]],
        ["garrisonAnchors", [1, 1]],
        ["garrisonSatellites", [0, 2]],
        ["guardCoverage", 0.4],
        ["guardsPerBuilding", [0, 2]],
        ["patrolCount", [0, 1]],
        ["maxVehicles", 2],
        ["vehicleArmedChance", 0.1],
        ["description", "Low-profile operation against a soft target"]
    ]],

    ["DA_isolated_zone", createHashMapFromArray [
        ["requiredTags", ["isolated", "low_density", "settlement"]],
        ["excludeTags", ["military", "urban", "high_density", "base", "outpost"]],
        ["density", "heavy"],
        ["qrfEnabled", true],
        ["qrfDelay", [60, 120]],
        ["areaPresenceChance", 0.9],
        ["targetRoles", ["opFor"]],
        ["garrisonAnchors", [2, 3]],
        ["garrisonSatellites", [1, 3]],
        ["guardCoverage", 0.8],
        ["guardsPerBuilding", [1, 2]],
        ["patrolCount", [2, 3]],
        ["maxVehicles", 4],
        ["vehicleArmedChance", 0.5],
        ["description", "Direct action against a fortified target"]
    ]]
];

_profiles
