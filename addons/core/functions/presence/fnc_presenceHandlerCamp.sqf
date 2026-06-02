/*
 * Function: DSC_core_fnc_presenceHandlerCamp
 * Description:
 *     Populate handler for "camp" zones. Minimal contention point: one
 *     foot patrol, no static defenses, no vehicles, no mortars.
 *
 *     Neutral-influence camps short-circuit to spawn a single "armed
 *     civilian" patrol via fnc_resolveIrregularOverlay instead of falling
 *     through to the military pipeline (which would skip them outright).
 *
 * Arguments:
 *     0: _zone <HASHMAP>
 *
 * Return Value:
 *     <BOOL>
 */

params [["_zone", createHashMap, [createHashMap]]];

private _controlledBy = _zone get "controlledBy";

// Neutral camp -> armed civilians only. Curator + timing logging is done
// inline here since we're skipping the military pipeline entirely.
if (_controlledBy == "neutral") exitWith {
    private _id     = _zone get "id";
    private _pos    = _zone get "position";
    private _radius = _zone getOrDefault ["radius", 200];

    private _t0 = diag_tickTime;
    private _irregularResult = [
        _pos,
        _radius,
        createHashMapFromArray [
            ["patrolCount", [1, 1]]
        ]
    ] call DSC_core_fnc_resolveIrregularOverlay;
    private _elapsedMs = (diag_tickTime - _t0) * 1000;

    (_zone get "units")  append (_irregularResult getOrDefault ["units", []]);
    (_zone get "groups") append (_irregularResult getOrDefault ["groups", []]);

    private _curator = if (allCurators isNotEqualTo []) then { allCurators select 0 } else { objNull };
    if (!isNull _curator && {(_zone get "units") isNotEqualTo []}) then {
        _curator addCuratorEditableObjects [(_zone get "units"), true];
    };

    private _timings = createHashMapFromArray [["irregularOverlay", _elapsedMs]];
    _zone set ["timings", _timings];
    ["camp", _id, _timings, count (_zone get "units"), 0] call DSC_core_fnc_presenceLogTimings;

    diag_log format ["DSC: activatePresenceZone [%1] - neutral camp: %2 irregular units",
        _id, count (_zone get "units")];

    (count (_zone get "units")) > 0
};

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

