/*
 * Function: DSC_core_fnc_setupCivilians
 * Description:
 *     Spawns wandering civilians in a populated area. Each civilian is its
 *     own group (civilian side) with CARELESS behavior and a random MOVE
 *     waypoint cycle inside the area radius. Used by the presence manager
 *     to give towns + villages a baseline "alive" feel.
 *
 *     Civilians are placed at random building positions when available,
 *     falling back to random offsets around the location center.
 *
 * Arguments:
 *     0: _locationPos <ARRAY>   - [x,y,z] zone center
 *     1: _config      <HASHMAP> -
 *        "count"      <NUMBER>  Target civilian count (default 6)
 *        "radius"     <NUMBER>  Wander radius (default 200)
 *        "structures" <ARRAY>   Buildings to seed spawn positions (default [])
 *        "classPool"  <ARRAY>   Civilian classnames to pick from. Default:
 *                               resolved via fnc_resolveEntityClass "civilian".
 *        "classMix"   <ARRAY>   Optional [[resolverKey, weight], ...] mix.
 *                               When non-empty, each civilian picks a resolver
 *                               by weight (via fnc_resolveEntityClass) and
 *                               overrides classPool for that civilian. Used by
 *                               the presence manager to flavor towns by
 *                               functional tags (workers at industrial,
 *                               suits at commercial, etc.).
 *
 * Return Value:
 *     <HASHMAP> - "units", "groups"
 *
 * Example:
 *     [_pos, createHashMapFromArray [["count", 8], ["radius", 250]]] call DSC_core_fnc_setupCivilians;
 */

params [
    ["_locationPos", [], [[]]],
    ["_config", createHashMap, [createHashMap]]
];

private _result = createHashMapFromArray [
    ["units", []],
    ["groups", []]
];

if (_locationPos isEqualTo []) exitWith {
    diag_log "DSC: setupCivilians - no location position";
    _result
};

private _count      = _config getOrDefault ["count", 6];
private _radius     = _config getOrDefault ["radius", 200];
private _structures = _config getOrDefault ["structures", []];
private _classPool  = _config getOrDefault ["classPool", []];
private _classMix   = _config getOrDefault ["classMix", []];

if (_count <= 0) exitWith {
    diag_log "DSC: setupCivilians - count <= 0, skipping";
    _result
};

// ============================================================================
// Resolve classname pool (use pre-cached manPool from fnc_initFactionData)
// ============================================================================
// classMix bypasses classPool — each civilian rolls a resolver key by weight,
// then resolves to a concrete class via fnc_resolveEntityClass. Pool only
// matters as the fallback when classMix is empty.
if (_classPool isEqualTo [] && { _classMix isEqualTo [] }) then {
    private _factionData = missionNamespace getVariable ["DSC_factionData", createHashMap];
    private _civRole = _factionData getOrDefault ["civilians", createHashMap];
    _classPool = _civRole getOrDefault ["manPool", []];

    // Fallback to vanilla civilian if nothing cached (mod missing CIV_F)
    if (_classPool isEqualTo [] && {isClass (configFile >> "CfgVehicles" >> "C_man_1")}) then {
        _classPool = ["C_man_1"];
    };
};

if (_classPool isEqualTo [] && { _classMix isEqualTo [] }) exitWith {
    diag_log "DSC: setupCivilians - no civilian classes resolved, skipping";
    _result
};

// Pre-compute weighted lookup if classMix is provided
private _mixTotalWeight = 0;
{ _mixTotalWeight = _mixTotalWeight + (_x param [1, 0]) } forEach _classMix;
private _useMix = (_classMix isNotEqualTo []) && (_mixTotalWeight > 0);

// ============================================================================
// Collect spawn anchors — building positions first, random fallback after
// ============================================================================
private _anchors = [];
{
    private _bp = _x buildingPos -1;
    if (_bp isNotEqualTo []) then { _anchors append _bp };
} forEach _structures;

_anchors = _anchors call BIS_fnc_arrayShuffle;

// ============================================================================
// Spawn loop
// ============================================================================
private _spawned = 0;
for "_i" from 0 to (_count - 1) do {
    private _spawnPos = if (_i < count _anchors) then {
        _anchors select _i
    } else {
        private _ang = random 360;
        private _dist = random _radius;
        [
            (_locationPos select 0) + _dist * sin _ang,
            (_locationPos select 1) + _dist * cos _ang,
            0
        ]
    };

    private _class = if (_useMix) then {
        // Weighted resolver-key roll
        private _roll = random _mixTotalWeight;
        private _acc = 0;
        private _picked = "";
        {
            _acc = _acc + (_x param [1, 0]);
            if (_roll <= _acc) exitWith { _picked = _x param [0, "civilian"] };
        } forEach _classMix;
        if (_picked == "") then { _picked = "civilian" };
        private _resolved = [_picked, createHashMapFromArray [["fallback", ""]]] call DSC_core_fnc_resolveEntityClass;
        if (_resolved == "" && { _classPool isNotEqualTo [] }) then { _resolved = selectRandom _classPool };
        if (_resolved == "") then { _resolved = "C_man_1" };
        _resolved
    } else {
        selectRandom _classPool
    };
    private _group = createGroup [civilian, true];
    private _unit = _group createUnit [_class, _spawnPos, [], 0, "NONE"];
    if (isNull _unit) then { deleteGroup _group; continue };

    _unit setPosATL _spawnPos;
    _unit setDir random 360;
    _unit allowFleeing 0;
    _unit setBehaviour "CARELESS";
    _unit setCombatMode "BLUE";
    _unit setSpeedMode "LIMITED";
    _unit setSkill 0.3;

    // Patrol cycle within radius
    _group setBehaviour "CARELESS";
    _group setCombatMode "BLUE";
    _group setSpeedMode "LIMITED";

    for "_j" from 0 to 3 do {
        private _ang = random 360;
        private _dist = (_radius * 0.3) + random (_radius * 0.7);
        private _wpPos = [
            (_locationPos select 0) + _dist * sin _ang,
            (_locationPos select 1) + _dist * cos _ang,
            0
        ];
        private _wp = _group addWaypoint [_wpPos, 0];
        _wp setWaypointType "MOVE";
        _wp setWaypointBehaviour "CARELESS";
        _wp setWaypointSpeed "LIMITED";
        _wp setWaypointCompletionRadius 8;
        _wp setWaypointTimeout [4, 10, 18];
    };
    private _cycleWp = _group addWaypoint [_locationPos, 0];
    _cycleWp setWaypointType "CYCLE";

    // Dyn-sim: engine freezes idle civilians outside the Group activation
    // distance (1500m globally). Combat activation is unaffected.
    _group enableDynamicSimulation true;

    (_result get "units")  pushBack _unit;
    (_result get "groups") pushBack _group;
    _spawned = _spawned + 1;

    uiSleep 0.15;
};

diag_log format ["DSC: setupCivilians - spawned %1 civilians at %2 (radius %3)",
    _spawned, _locationPos, _radius];

_result
