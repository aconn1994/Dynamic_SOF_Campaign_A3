/*
 * Function: DSC_core_fnc_activatePresenceZone
 * Description:
 *     Spawns AI presence for a zone based on its type + controlling side.
 *     Sprint 2 implements opFor outposts only. All other zone types are no-ops
 *     and will be added in later sprints.
 *
 *     Spawned units, vehicles, and groups are stored on the zone hashmap so
 *     fnc_despawnPresenceZone can tear them down cleanly when the player
 *     leaves.
 *
 * Arguments:
 *     0: _zone <HASHMAP> - Zone hashmap from DSC_presenceZones
 *
 * Return Value:
 *     <BOOL> - true if anything was spawned, false if no-op / blocked
 */

params [["_zone", createHashMap, [createHashMap]]];

// Per-step timing — written into _zone."timings" and aggregated globally
// in DSC_presenceTimings so we can spot hot spawners without an external profiler.
private _t0 = diag_tickTime;
private _timings = createHashMap;
private _stamp = {
    params ["_label"];
    _timings set [_label, (diag_tickTime - _t0) * 1000]; // ms since start
};

private _id           = _zone get "id";
private _type         = _zone get "type";
private _controlledBy = _zone get "controlledBy";
private _faction      = _zone get "faction";
private _influence    = _zone getOrDefault ["influence", 0];
private _pos          = _zone get "position";
private _radius       = _zone getOrDefault ["radius", 200];
private _structures   = _zone getOrDefault ["structures", []];

// ============================================================================
// Sprint 3 branch: populated areas — civilians ALWAYS spawn, density varies
// ============================================================================
if (_type == "populatedArea") exitWith {
    // Density factor: every populated area gets civilians, opFor presence just
    // thins the crowd. Floor ensures at least a skeleton population so towns
    // never feel completely dead unless influence is at max.
    private _density = switch (_controlledBy) do {
        case "opFor":     { (1 - (_influence * 0.7)) max 0.25 };  // 1.0->0.25 floor
        case "contested": { 0.65 };
        case "bluFor":    { 1.0 };
        default            { 0.9 };                                  // neutral
    };

    // Base population scales with structure count, capped so towns don't drown
    private _basePop = (count _structures) * 0.4;
    _basePop = (_basePop min 12) max 3;
    private _targetCount = floor (_basePop * _density);
    if (_targetCount < 1) then { _targetCount = 1 };

    private _civConfig = createHashMapFromArray [
        ["count",      _targetCount],
        ["radius",     _radius max 200],
        ["structures", _structures]
    ];
    private _civResult = [_pos, _civConfig] call DSC_core_fnc_setupCivilians;
    ["civilians"] call _stamp;

    (_zone get "units")  append (_civResult getOrDefault ["units", []]);
    (_zone get "groups") append (_civResult getOrDefault ["groups", []]);

    // ------------------------------------------------------------------------
    // Sprint 5: Military overlay on populated zones
    // ------------------------------------------------------------------------
    // Towns with meaningful faction control get a single small patrol overlay.
    // opFor towns -> opFor / opForPartner / irregular patrol
    // bluFor towns -> bluForPartner patrol
    // contested -> patrol from the dominant side (true dual-side comes in Sprint 8)
    // neutral / low influence -> no overlay
    if (_controlledBy in ["opFor", "bluFor", "contested"] && {_influence >= 0.3}) then {
        // Pick the role/side for the overlay
        private _factionData = missionNamespace getVariable ["DSC_factionData", createHashMap];
        private _factionProfileConfig = missionNamespace getVariable ["factionProfileConfig", createHashMap];

        // Candidate roles in priority order — first non-empty wins
        private _candidateRoles = switch (_controlledBy) do {
            case "opFor":     { ["opFor", "opForPartner", "irregulars"] };
            case "bluFor":    { ["bluForPartner", "bluFor"] };
            case "contested": { ["opForPartner", "irregulars", "opFor"] };
            default            { [] };
        };

        private _overlayGroups = [];
        private _overlaySide = east;
        private _overlayRole = "";
        {
            private _role = _x;
            private _roleData = _factionData getOrDefault [_role, createHashMap];
            private _roleSide = _roleData getOrDefault ["side", east];
            private _roleGroupsHM = _roleData getOrDefault ["groups", createHashMap];

            private _collected = [];
            {
                _collected append (_y select {
                    private _tags = _x getOrDefault ["doctrineTags", []];
                    ("FOOT" in _tags || "PATROL" in _tags)
                        && { !("ARMOR" in _tags) }
                        && { !("NAVAL" in _tags) }
                });
            } forEach _roleGroupsHM;

            if (_collected isNotEqualTo []) exitWith {
                _overlayGroups = _collected;
                _overlaySide = _roleSide;
                _overlayRole = _role;
            };
        } forEach _candidateRoles;

        if (_overlayGroups isNotEqualTo []) then {
            // Recce-sized only — towns get foot patrols, not full squads
            private _patrolPool = [_overlayGroups] call DSC_core_fnc_filterPatrolGroups;
            if (_patrolPool isEqualTo []) then { _patrolPool = _overlayGroups };

            // For contested zones, pick a directional spawn so the opposing
            // bluFor patrol can spawn opposite. For non-contested zones, leave
            // the spawn angle random (existing behavior).
            private _primaryAngle = if (_controlledBy == "contested") then { random 360 } else { -1 };

            private _patrolConfig = createHashMapFromArray [
                ["patrolCount",  [1, 1]],
                ["spawnRadius",  [(_radius max 100), (_radius max 200) + 100]],
                ["patrolRadius", [(_radius max 150), (_radius max 250) + 100]],
                ["spawnAngle",   _primaryAngle]
            ];

            private _patrolResult = [_pos, _patrolPool, _overlaySide, _patrolConfig] call DSC_core_fnc_setupPatrols;
            (_zone get "units")  append (_patrolResult getOrDefault ["units", []]);
            (_zone get "groups") append (_patrolResult getOrDefault ["groups", []]);

            diag_log format ["DSC: activatePresenceZone [%1] - military overlay: %2 patrol units from role '%3' (%4)",
                _id, count (_patrolResult getOrDefault ["units", []]), _overlayRole, _controlledBy];

            // Contested towns: add an opposing bluFor-side patrol on the
            // far side of the zone. They'll engage on contact (west <-> east
            // is hostile by default).
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
    };
    ["militaryOverlay"] call _stamp;

    private _curator = if (allCurators isNotEqualTo []) then { allCurators select 0 } else { objNull };
    if (!isNull _curator) then {
        _curator addCuratorEditableObjects [(_zone get "units"), true];
    };
    ["curator"] call _stamp;

    _zone set ["timings", _timings];
    ["populatedArea", _id, _timings, count (_zone get "units"), 0] call DSC_core_fnc_presenceLogTimings;

    (format ["DSC presence: ACTIVATED %1 — %2 civilians (ctrl=%3 inf=%4)",
        _zone get "name", count (_zone get "units"), _controlledBy, _influence toFixed 2
    ]) remoteExec ["systemChat", 0];

    diag_log format ["DSC: activatePresenceZone [%1] - populatedArea: %2 civs (ctrl=%3 inf=%4 density=%5)",
        _id, count (_zone get "units"), _controlledBy, _influence toFixed 2, _density toFixed 2];

    true
};

// ============================================================================
// Military zone branch: bases / outposts / camps
//   Sprint 6: opFor + bluFor + contested + (neutral camps via partner overlay)
//   Skips only locations that have no controlling side at all.
// ============================================================================
if !(_type in ["outpost", "base", "camp"]) exitWith {
    diag_log format ["DSC: activatePresenceZone [%1] - skip (type=%2 unsupported)", _id, _type];
    false
};
if !(_controlledBy in ["opFor", "bluFor", "contested"]) exitWith {
    diag_log format ["DSC: activatePresenceZone [%1] - skip (controlledBy=%2 not opFor/bluFor/contested)", _id, _controlledBy];
    false
};
// Contested camps may carry no faction (rare) — let them fall through, the
// borrowed-foot-groups path below will pick something usable.
if (_faction == "" && {_type != "camp"}) exitWith {
    diag_log format ["DSC: activatePresenceZone [%1] - skip (no faction assigned)", _id];
    false
};
// Camps may legitimately have no structures (open clearing) — fall through
// to foot patrol. Non-camp types require structures.
if (_structures isEqualTo [] && {_type != "camp"}) exitWith {
    diag_log format ["DSC: activatePresenceZone [%1] - skip (no structures)", _id];
    false
};

// ============================================================================
// Resolve role data: foot groups + assets for this faction
// ============================================================================
private _factionData = missionNamespace getVariable ["DSC_factionData", createHashMap];
private _factionProfileConfig = missionNamespace getVariable ["factionProfileConfig", createHashMap];

// Find the role that owns this faction. For an unassigned-faction camp we
// just pick a sensible default later via the borrow path.
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

// Side defaults for empty-faction zones — we'll pick infantry from the
// dominant side's allied roles via the borrow path.
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

// Filter to foot infantry only — no vehicle/armor/static groups for patrol
// placement. We rely on doctrineTags from the classifier.
private _footGroups = _facGroups select {
    private _tags = _x getOrDefault ["doctrineTags", []];
    ("FOOT" in _tags || "PATROL" in _tags) && { !("ARMOR" in _tags) } && { !("NAVAL" in _tags) }
};

// Fallback 1: include MECHANIZED/MOTORIZED groups (still have infantry inside)
// for armor-heavy factions like rhs_faction_tv that have no pure foot groups.
if (_footGroups isEqualTo []) then {
    _footGroups = _facGroups select {
        private _tags = _x getOrDefault ["doctrineTags", []];
        ("MECHANIZED" in _tags || "MOTORIZED" in _tags) && { !("ARMOR" in _tags) } && { !("NAVAL" in _tags) }
    };
};

// Fallback 2: borrow foot groups from any other faction on the same control side.
// Tank divisions don't patrol their own perimeter — they call infantry support.
// For "contested" zones we pull from opFor-aligned irregulars/partners (the
// dominant insurgent side); presence overlays may add a bluFor counter-patrol
// later in a dedicated dual-side sprint.
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
        // Also adopt that role's side so units spawn on the correct engine side
        if (_roleName == "") then {
            _side = _otherRoleData getOrDefault ["side", _side];
            _roleName = _otherRole; // for downstream asset lookup
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

// Note: empty _footGroups is no longer fatal. Static defenses + mortars +
// vehicles can still run; only the patrol step needs foot groups. The
// useFootPatrols flag in the preset block is gated on this below.

// Faction assets (pull from role first, fall back to fresh extract)
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
// Per-type density presets
// ============================================================================
//
// Military installations (base/outpost) act as AREA DETERRENTS, not garrisons:
//   - Static defenders fill towers + bunkers (marksmen / static weapons / lookouts)
//   - Light roving foot patrols sweep nearby roads/perimeter
//   - Bases get artillery (mortars) for area denial
//   - No room-by-room building garrisons — keep unit count low (~10-20)
//
// Camps are minimal contention points: 1 patrol, optional building guards if structures exist.
//
private _useStaticDefenses = false;   // towers + statics + lookouts
private _maxStatics        = 0;
private _staticChance      = 0.0;
private _maxGuardsPerTower = 1;
private _useFootPatrols    = false;
private _patrolCountRange  = [0, 0];
private _patrolRadiusRange = [200, 500];
private _useMortars        = false;
private _mortarCount       = 0;
private _vehDensity        = "light";
private _maxVehicles       = 1;
private _vehArmedChance    = 0.35;
private _spawnVehicles     = true;

switch (_type) do {
    case "base": {
        _useStaticDefenses = true;
        _maxStatics        = 6;
        _staticChance      = 0.7;
        _maxGuardsPerTower = 2;
        _useFootPatrols    = true;
        _patrolCountRange  = [2, 3];
        _patrolRadiusRange = [(_radius max 200), (_radius max 400) + 200];
        _useMortars        = true;
        _mortarCount       = 1 + floor random 2; // 1-2 mortars
        _vehDensity        = "medium";
        _maxVehicles       = 2;
        _vehArmedChance    = 0.6;
    };
    case "outpost": {
        _useStaticDefenses = true;
        _maxStatics        = 3;
        _staticChance      = 0.6;
        _maxGuardsPerTower = 1;
        _useFootPatrols    = true;
        _patrolCountRange  = [1, 2];
        _patrolRadiusRange = [(_radius max 150), (_radius max 300) + 150];
        _useMortars        = false;
        _vehDensity        = "light";
        _maxVehicles       = 1;
        _vehArmedChance    = 0.4;
    };
    case "camp": {
        // Camps stay minimal — single patrol, no static defenses or mortars
        _useStaticDefenses = false;
        _useFootPatrols    = true;
        _patrolCountRange  = [1, 1];
        _patrolRadiusRange = [(_radius max 100), (_radius max 200) + 100];
        _useMortars        = false;
        _spawnVehicles     = false;
    };
    default {};
};

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
    // Restrict to recce / fireteam sized groups so a "patrol" stays small.
    // Larger squads are reserved for QRF / mission objectives.
    private _patrolGroups = [_footGroups] call DSC_core_fnc_filterPatrolGroups;
    if (_patrolGroups isEqualTo []) then { _patrolGroups = _footGroups };

    // For contested military zones, pin the primary patrol's spawn angle so
    // we can place the opposing patrol opposite.
    private _primaryAngle = if (_controlledBy == "contested") then { random 360 } else { -1 };

    private _patrolConfig = createHashMapFromArray [
        ["patrolCount",  _patrolCountRange],
        ["patrolRadius", _patrolRadiusRange],
        ["spawnAngle",   _primaryAngle]
    ];
    private _patrolResult = [_pos, _patrolGroups, _side, _patrolConfig] call DSC_core_fnc_setupPatrols;
    (_zone get "units")  append (_patrolResult getOrDefault ["units", []]);
    (_zone get "groups") append (_patrolResult getOrDefault ["groups", []]);

    // Contested military zone: spawn a bluFor-side opposing patrol on the
    // far side. west vs east is hostile by default, so they'll engage on
    // contact as patrol paths overlap inside the zone radius.
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
// Mortars / indirect fire (bases only)
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

// Zeus integration — add everything to the first curator for debugging
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
