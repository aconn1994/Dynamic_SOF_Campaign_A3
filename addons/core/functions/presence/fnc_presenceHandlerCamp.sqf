/*
 * Function: DSC_core_fnc_presenceHandlerCamp
 * Description:
 *     Populate handler for "camp" zones. Minimal contention point: one
 *     foot patrol, no static defenses, no vehicles, no mortars.
 *
 * Arguments:
 *     0: _zone <HASHMAP>
 *
 * Return Value:
 *     <BOOL>
 */

params [["_zone", createHashMap, [createHashMap]]];

private _preset = createHashMapFromArray [
    ["useStaticDefenses", false],
    ["maxStatics",        0],
    ["staticChance",      0.0],
    ["maxGuardsPerTower", 1],
    ["useFootPatrols",    true],
    ["patrolCountRange",  [1, 1]],
    ["patrolMinRadius",   100],
    ["patrolMaxRadius",   200],
    ["patrolMaxAddon",    100],
    ["useMortars",        false],
    ["mortarCount",       0],
    ["vehDensity",        "light"],
    ["maxVehicles",       0],
    ["vehArmedChance",    0.0],
    ["spawnVehicles",     false]
];

[_zone, _preset] call DSC_core_fnc_presenceActivateMilitary
