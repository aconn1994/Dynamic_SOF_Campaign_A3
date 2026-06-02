/*
 * Function: DSC_core_fnc_presenceHandlerBase
 * Description:
 *     Populate handler for "base" zones. Heaviest military preset:
 *     marksman towers, static weapons, foot patrols, mortars, parked
 *     vehicles. Delegates to fnc_presenceActivateMilitary with the base
 *     preset.
 *
 * Arguments:
 *     0: _zone <HASHMAP>
 *
 * Return Value:
 *     <BOOL>
 */

params [["_zone", createHashMap, [createHashMap]]];

private _preset = createHashMapFromArray [
    ["useStaticDefenses", true],
    ["maxStatics",        6],
    ["staticChance",      0.7],
    ["maxGuardsPerTower", 2],
    ["useFootPatrols",    true],
    ["patrolCountRange",  [2, 3]],
    ["patrolMinRadius",   200],
    ["patrolMaxRadius",   400],
    ["patrolMaxAddon",    200],
    ["useMortars",        true],
    ["mortarCount",       -1],          // -1 = random 1-2
    ["vehDensity",        "medium"],
    ["maxVehicles",       2],
    ["vehArmedChance",    0.6],
    ["spawnVehicles",     true]
];

[_zone, _preset] call DSC_core_fnc_presenceActivateMilitary
