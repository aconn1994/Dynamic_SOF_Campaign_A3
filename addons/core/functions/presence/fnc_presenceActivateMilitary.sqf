/*
 * Function: DSC_core_fnc_presenceActivateMilitary
 * Description:
 *     Shared activation body for military presence zones (base / outpost /
 *     camp). Resolves faction role, picks foot groups (with allied-role
 *     borrow fallback), classifies structures, then applies the supplied
 *     preset to drive static defenses, foot patrols, mortars, and parked
 *     vehicles.
 *
 *     Behavior is identical to the pre-refactor monolithic switch — the
 *     only change is that per-type knobs come from _preset rather than an
 *     inline switch on zone type.
 *
 * Arguments:
 *     0: _zone   <HASHMAP> - Zone hashmap from DSC_presenceZones
 *     1: _preset <HASHMAP> - Per-type populate config (see handler files)
 *
 * Return Value:
 *     <BOOL> - true if anything was spawned, false if no-op / blocked
 */

params [
    ["_zone",   createHashMap, [createHashMap]],
    ["_preset", createHashMap, [createHashMap]]
];

private _t0 = diag_tickTime;
private _timings = createHashMap;
private _stamp = {
    params ["_label"];
    _timings set [_label, (diag_tickTime - _t0) * 1000];
};

private _id           = _zone get "id";
private _type         = _zone get "type";
private _controlledBy = _zone get "controlledBy";
private _faction      = _zone get "faction";
private _pos          = _zone get "position";
private _radius       = _zone getOrDefault ["radius", 200];
private _structures   = _zone getOrDefault ["structures", []];

// Gate checks — preserved from pre-refactor logic
if !(_controlledBy in ["opFor", "bluFor", "contested"]) exitWith {
    diag_log format ["DSC: activatePresenceZone [%1] - skip (controlledBy=%2 not opFor/bluFor/contested)", _id, _controlledBy];
    false
};
if (_faction == "" && {_type != "camp"}) exitWith {
    diag_log format ["DSC: activatePresenceZone [%1] - skip (no faction assigned)", _id];
    false
};
if (_structures isEqualTo [] && {_type != "camp"}) exitWith {
    diag_log format ["DSC: activatePresenceZone [%1] - skip (no structures)", _id];
    false
};

// ============================================================================
// Resolve role data: foot groups + assets for this faction
// ============================================================================
private _factionData = missionNamespace getVariable ["DSC_factionData", createHashMap];
private _factionProfileConfig = missionNamespace getVariable ["factionProfileConfig", createHashMap];

private _roleName = "";
private _side = east;
if (_faction != "") then {
    {
        private _facs = (_y getOrDefault ["factions", []]);
        if (_faction in _facs) exitWith {
            _roleName = _x;
            _side = _y getOrDefault ["side", east];
        };
    } forEach _factionProfileConfig;

    if (_roleName == "") then {
        diag_log format ["DSC: activatePresenceZone [%1] - faction %2 not in any role, will borrow", _id, _faction];
    };
};

if (_roleName == "") then {
    _side = switch (_controlledBy) do {
        case "bluFor":    { west };
        case "opFor":     { east };
        case "contested": { east };
        default            { east };
    };
};

private _roleData   = _factionData getOrDefault [_roleName, createHashMap];
private _roleGroups = _roleData getOrDefault ["groups", createHashMap];
private _facGroups  = _roleGroups getOrDefault [_faction, []];

private _footGroups = _facGroups select {
    private _tags = _x getOrDefault ["doctrineTags", []];
    ("FOOT" in _tags || "PATROL" in _tags) && { !("ARMOR" in _tags) } && { !("NAVAL" in _tags) }
};

if (_footGroups isEqualTo []) then {
    _footGroups = _facGroups select {
        private _tags = _x getOrDefault ["doctrineTags", []];
        ("MECHANIZED" in _tags || "MOTORIZED" in _tags) && { !("ARMOR" in _tags) } && { !("NAVAL" in _tags) }
    };
};

if (_footGroups isEqualTo []) then {
    private _allowedSides = switch (_controlledBy) do {
        case "bluFor":    { ["bluForPartner", "bluFor"] };
        case "opFor":     { ["opFor", "opForPartner", "irregulars"] };
        case "contested": { ["opForPartner", "irregulars", "opFor"] };
        default            { [] };
    };
    {
        private _otherRole = _x;
        if (_otherRole == _roleName) then { continue };
        private _otherRoleData = _factionData getOrDefault [_otherRole, createHashMap];
        private _otherGroups = _otherRoleData getOrDefault ["groups", createHashMap];
        if (_roleName == "") then {
            _side = _otherRoleData getOrDefault ["side", _side];
            _roleName = _otherRole;
        };
        {
            private _candidate = _y select {
                private _tags = _x getOrDefault ["doctrineTags", []];
                ("FOOT" in _tags || "PATROL" in _tags) && { !("ARMOR" in _tags) } && { !("NAVAL" in _tags) }
            };
            _footGroups append _candidate;
        } forEach _otherGroups;
    } forEach _allowedSides;
    if (_footGroups isNotEqualTo []) then {
        diag_log format ["DSC: activatePresenceZone [%1] - borrowed %2 foot groups from allied roles (faction='%3' ctrl=%4)",
            _id, count _footGroups, _faction, _controlledBy];
    };
};

private _roleAssets = _roleData getOrDefault ["assets", createHashMap];
private _assets = _roleAssets getOrDefault [_faction, createHashMap];
if (_assets isEqualTo createHashMap) then {
    _assets = [_faction] call DSC_core_fnc_extractAssets;
};

// ============================================================================
// Classify structures (main / side) so setupGuards has something to bind to
// ============================================================================
private _structureTypes = [] call DSC_core_fnc_getStructureTypes;
private _mainTypes     = _structureTypes getOrDefault ["main", []];
private _sideTypes     = _structureTypes getOrDefault ["side", []];
private _militaryTypes = _structureTypes getOrDefault ["military", []];

private _mainStructures = [];
private _sideStructures = [];
{
    private _struct = _x;
    private _isMain = false;
    private _isSide = false;
    { if (_struct isKindOf _x) exitWith { _isMain = true } } forEach _mainTypes;
    if (!_isMain) then {
        { if (_struct isKindOf _x) exitWith { _isSide = true } } forEach _sideTypes;
    };
    if (!_isMain && !_isSide) then {
        { if (_struct isKindOf _x) exitWith { _isSide = true } } forEach _militaryTypes;
    };
    if (_isMain) then { _mainStructures pushBack _struct };
    if (_isSide) then { _sideStructures pushBack _struct };
} forEach _structures;

// ============================================================================
// Preset values
// ============================================================================
private _useStaticDefenses = _preset getOrDefault ["useStaticDefenses", false];
private _maxStatics        = _preset getOrDefault ["maxStatics", 0];
private _staticChance      = _preset getOrDefault ["staticChance", 0.0];
private _maxGuardsPerTower = _preset getOrDefault ["maxGuardsPerTower", 1];
private _useFootPatrols    = _preset getOrDefault ["useFootPatrols", false];
private _patrolCountRange  = _preset getOrDefault ["patrolCountRange", [0, 0]];
private _patrolMinRadius   = _preset getOrDefault ["patrolMinRadius", 200];
private _patrolMaxRadius   = _preset getOrDefault ["patrolMaxRadius", 400];
private _patrolMaxAddon    = _preset getOrDefault ["patrolMaxAddon", 200];
private _useMortars        = _preset getOrDefault ["useMortars", false];
private _mortarCount       = _preset getOrDefault ["mortarCount", 0];
if (_mortarCount < 0) then { _mortarCount = 1 + floor random 2 }; // -1 sentinel -> random 1-2
private _vehDensity        = _preset getOrDefault ["vehDensity", "light"];
private _maxVehicles       = _preset getOrDefault ["maxVehicles", 1];
private _vehArmedChance    = _preset getOrDefault ["vehArmedChance", 0.35];
private _spawnVehicles     = _preset getOrDefault ["spawnVehicles", true];

private _patrolRadiusRange = [(_radius max _patrolMinRadius), (_radius max _patrolMaxRadius) + _patrolMaxAddon];

// ============================================================================
// Static defenses — towers + bunkers manned with marksmen / static weapons
// ============================================================================
if (_useStaticDefenses) then {
    private _staticConfig = createHashMapFromArray [
        ["assets",                _assets],
        ["structures",            _structures],
        ["maxStatics",            _maxStatics],
        ["staticChance",          _staticChance],
        ["maxGuardsPerStructure", _maxGuardsPerTower],
        ["guardFaction",          _faction]
    ];
    private _staticResult = [_pos, _faction, _side, _staticConfig] call DSC_core_fnc_setupStaticDefenses;
    (_zone get "units")    append (_staticResult getOrDefault ["units", []]);
    (_zone get "vehicles") append (_staticResult getOrDefault ["vehicles", []]);
    (_zone get "groups")   append (_staticResult getOrDefault ["groups", []]);
};
["staticDefenses"] call _stamp;

// ============================================================================
// Foot patrols — roving infantry around the location
// ============================================================================
if (_useFootPatrols && {_footGroups isNotEqualTo []}) then {
    private _patrolGroups = [_footGroups] call DSC_core_fnc_filterPatrolGroups;
    if (_patrolGroups isEqualTo []) then { _patrolGroups = _footGroups };

    private _primaryAngle = if (_controlledBy == "contested") then { random 360 } else { -1 };

    private _patrolConfig = createHashMapFromArray [
        ["patrolCount",  _patrolCountRange],
        ["patrolRadius", _patrolRadiusRange],
        ["spawnAngle",   _primaryAngle]
    ];
    private _patrolResult = [_pos, _patrolGroups, _side, _patrolConfig] call DSC_core_fnc_setupPatrols;
    (_zone get "units")  append (_patrolResult getOrDefault ["units", []]);
    (_zone get "groups") append (_patrolResult getOrDefault ["groups", []]);

    if (_controlledBy == "contested") then {
        private _skirmishConfig = createHashMapFromArray [
            ["factionData", _factionData],
            ["spawnAngle",  _primaryAngle + 180]
        ];
        private _skirmishResult = [_pos, _radius, _skirmishConfig] call DSC_core_fnc_setupContestedSkirmish;
        (_zone get "units")  append (_skirmishResult getOrDefault ["units", []]);
        (_zone get "groups") append (_skirmishResult getOrDefault ["groups", []]);
    };
};
["patrols"] call _stamp;

// ============================================================================
// Mortars / indirect fire
// ============================================================================
if (_useMortars && _mortarCount > 0) then {
    private _mortarConfig = createHashMapFromArray [
        ["assets",       _assets],
        ["guardFaction", _faction],
        ["count",        _mortarCount]
    ];
    private _mortarResult = [_pos, _faction, _side, _mortarConfig] call DSC_core_fnc_setupMortarEmplacement;
    (_zone get "units")    append (_mortarResult getOrDefault ["units", []]);
    (_zone get "vehicles") append (_mortarResult getOrDefault ["vehicles", []]);
    (_zone get "groups")   append (_mortarResult getOrDefault ["groups", []]);
};
["mortars"] call _stamp;

// ============================================================================
// Parked vehicles
// ============================================================================
if (_spawnVehicles) then {
    private _vehConfig = createHashMapFromArray [
        ["assets",      _assets],
        ["structures",  _structures],
        ["density",     _vehDensity],
        ["maxVehicles", _maxVehicles],
        ["armedChance", _vehArmedChance]
    ];

    private _vehResult = [_pos, _faction, _side, _vehConfig] call DSC_core_fnc_setupVehicles;
    (_zone get "units")    append (_vehResult getOrDefault ["units", []]);
    (_zone get "vehicles") append (_vehResult getOrDefault ["vehicles", []]);
    (_zone get "groups")   append (_vehResult getOrDefault ["groups", []]);
};
["vehicles"] call _stamp;

diag_log format ["DSC: activatePresenceZone [%1] - %2 units, %3 vehicles, %4 groups (faction=%5)",
    _id,
    count (_zone get "units"),
    count (_zone get "vehicles"),
    count (_zone get "groups"),
    _faction
];

// Zeus integration
private _curator = if (allCurators isNotEqualTo []) then { allCurators select 0 } else { objNull };
if (!isNull _curator) then {
    private _all = (_zone get "units") + (_zone get "vehicles");
    if (_all isNotEqualTo []) then {
        _curator addCuratorEditableObjects [_all, true];
        diag_log format ["DSC: activatePresenceZone [%1] - added %2 entities to Zeus", _id, count _all];
    };
};
["curator"] call _stamp;

_zone set ["timings", _timings];
[_type, _id, _timings, count (_zone get "units"), count (_zone get "vehicles")] call DSC_core_fnc_presenceLogTimings;

(format ["DSC presence: ACTIVATED %1 — %2u %3v",
    _zone get "name",
    count (_zone get "units"),
    count (_zone get "vehicles")
]) remoteExec ["systemChat", 0];

true
