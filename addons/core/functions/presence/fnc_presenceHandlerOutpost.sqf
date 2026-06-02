/*
 * Function: DSC_core_fnc_presenceHandlerOutpost
 * Description:
 *     Populate handler for "outpost" zones. Mid-tier military preset:
 *     static defenders, 1-2 patrols, one parked vehicle, no mortars.
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
    ["maxStatics",        3],
    ["staticChance",      0.6],
    ["maxGuardsPerTower", 1],
    ["useFootPatrols",    true],
    ["patrolCountRange",  [1, 2]],
    ["patrolMinRadius",   150],
    ["patrolMaxRadius",   300],
    ["patrolMaxAddon",    150],
    ["useMortars",        false],
    ["mortarCount",       0],
    ["vehDensity",        "light"],
    ["maxVehicles",       1],
    ["vehArmedChance",    0.4],
    ["spawnVehicles",     true]
];

[_zone, _preset] call DSC_core_fnc_presenceActivateMilitary
