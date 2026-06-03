/*
 * Function: DSC_core_fnc_presenceHandlerPopulatedArea
 * Description:
 *     Populate handler for "populatedArea" zones. Always spawns civilians
 *     (density scaled by influence/control), optionally overlays a small
 *     military patrol when influence is meaningful, and adds an opposing
 *     bluFor patrol on contested zones (skirmish).
 *
 *     Behavior is identical to the pre-refactor populatedArea branch.
 *
 * Arguments:
 *     0: _zone <HASHMAP>
 *
 * Return Value:
 *     <BOOL>
 */

params [["_zone", createHashMap, [createHashMap]]];

private _t0 = diag_tickTime;
private _timings = createHashMap;
private _stamp = {
    params ["_label"];
    _timings set [_label, (diag_tickTime - _t0) * 1000];
};

private _id           = _zone get "id";
private _controlledBy = _zone get "controlledBy";
private _influence    = _zone getOrDefault ["influence", 0];
private _pos          = _zone get "position";
private _radius       = _zone getOrDefault ["radius", 200];
private _structures   = _zone getOrDefault ["structures", []];
private _zoneTags     = _zone getOrDefault ["tags", []];
private _primaryFn    = _zone getOrDefault ["primaryFunction", ""];

// ============================================================================
// Civilians — density scaled by control + influence, floor ensures life
// ============================================================================
private _density = switch (_controlledBy) do {
    case "opFor":     { (1 - (_influence * 0.7)) max 0.25 };
    case "contested": { 0.65 };
    case "bluFor":    { 1.0 };
    default            { 0.9 };
};

private _basePop = (count _structures) * 0.4;
_basePop = (_basePop min 12) max 3;
private _targetCount = floor (_basePop * _density);
if (_targetCount < 1) then { _targetCount = 1 };

private _civClassMix = [_zoneTags, _primaryFn] call DSC_core_fnc_resolveCivilianMix;

private _civConfig = createHashMapFromArray [
    ["count",      _targetCount],
    ["radius",     _radius max 200],
    ["structures", _structures],
    ["classMix",   _civClassMix]
];
private _civResult = [_pos, _civConfig] call DSC_core_fnc_setupCivilians;
["civilians"] call _stamp;

(_zone get "units")  append (_civResult getOrDefault ["units", []]);
(_zone get "groups") append (_civResult getOrDefault ["groups", []]);

if ((count _civClassMix) > 1) then {
    diag_log format ["DSC: activatePresenceZone [%1] - civilian mix: %2 (primaryFn=%3, tags=%4)",
        _id, _civClassMix, _primaryFn, _zoneTags];
};

// ============================================================================
// Indoor garrison layer (Sprint D part 3) — light military only
// ============================================================================
// Civilian indoor garrisons were trialed and disabled — they cost budget
// for little gameplay payoff (wandering civilians already carry the
// "alive" feel). Light military indoor garrisons stay: they create the
// "is that building occupied?" tension in hostile/contested territory.
//
// Irregulars (armed civilian populace) get a separate, independent roll
// that runs on *any* populated area regardless of control/influence —
// they're not aligned with the controlling faction, they're locals who
// happen to be armed. Roll is intentionally low (~25-35%) so encounters
// stay surprising rather than constant.
private _mainStructs = _zone getOrDefault ["mainStructures", []];
private _sideStructs = _zone getOrDefault ["sideStructures", []];
private _totalStructs = (count _mainStructs) + (count _sideStructs);

private _milAllowed = (_controlledBy in ["opFor", "bluFor", "contested"])
    && { _influence >= 0.3 };

if (_totalStructs > 0 && _milAllowed) then {
    private _sizeTier = switch (true) do {
        case (_totalStructs < 5):  { "isolated" };
        case (_totalStructs < 15): { "settlement" };
        case (_totalStructs < 50): { "town" };
        default                    { "city" };
    };

    // Overall zone-gate roll — perf safety valve. Larger zones less likely.
    private _zoneChance = switch (_sizeTier) do {
        case "isolated":   { 1 };
        case "settlement": { 1 };
        case "town":       { 1 };
        case "city":       { 1 };  // === town for first rollout
        default            { 1 };
    };

    if (random 1 <= _zoneChance) then {
        // Total cluster count per tier (1-2 max)
        private _totalClusters = switch (_sizeTier) do {
            case "isolated":   { (selectRandom [1, 1]) };
            case "settlement": { (selectRandom [1, 2]) };
            case "town":       { (selectRandom [1, 2]) };
            case "city":       { (selectRandom [1, 3]) };
            default            { (selectRandom [1, 2]) };
        };

        // Per-cluster engagement roll — even in hostile territory, not every
        // building is a hardpoint. Skip rate by control: bluFor 70%, opFor
        // 60%, contested 50% (numbers mirror prior civ/mil split).
        private _milClusters = 0;
        for "_i" from 1 to _totalClusters do {
            private _roll = random 1;
            private _wantMil = switch (_controlledBy) do {
                case "bluFor":    { _roll < 0.70 };
                case "opFor":     { _roll < 0.70 };
                case "contested": { _roll < 0.70 };
                default            { false };
            };
            if (_wantMil) then { _milClusters = _milClusters + 1 };
        };

        if (_milClusters > 0) then {
            private _factionData = missionNamespace getVariable ["DSC_factionData", createHashMap];

            // Contested: re-roll side per call (chaos). Other controls fixed.
            private _garrRoles = switch (_controlledBy) do {
                case "opFor":     { ["opFor", "opForPartner", "irregulars"] };
                case "bluFor":    { ["bluForPartner", "bluFor"] };
                case "contested": {
                    selectRandom [
                        ["opForPartner", "irregulars", "opFor"],
                        ["bluForPartner", "bluFor"]
                    ]
                };
                default            { [] };
            };

            private _garrGroups = [];
            private _garrSide = east;
            private _garrRole = "";
            {
                private _role = _x;
                private _roleData = _factionData getOrDefault [_role, createHashMap];
                private _roleSide = _roleData getOrDefault ["side", east];
                private _roleGroupsHM = _roleData getOrDefault ["groups", createHashMap];

                private _collected = [];
                {
                    _collected append (_y select {
                        private _t = _x getOrDefault ["doctrineTags", []];
                        ("FOOT" in _t || "PATROL" in _t)
                            && { !("ARMOR" in _t) }
                            && { !("NAVAL" in _t) }
                    });
                } forEach _roleGroupsHM;

                if (_collected isNotEqualTo []) exitWith {
                    _garrGroups = _collected;
                    _garrSide = _roleSide;
                    _garrRole = _role;
                };
            } forEach _garrRoles;

            if (_garrGroups isNotEqualTo []) then {
                private _garrMilResult = [_pos, _garrGroups, _garrSide,
                    createHashMapFromArray [
                        ["mainStructures", _mainStructs],
                        ["sideStructures", _sideStructs],
                        ["sizeTier",       _sizeTier],
                        ["anchorCount",    _milClusters],
                        ["forceSpawn",     true]
                    ]
                ] call DSC_core_fnc_setupLightMilitaryGarrison;

                (_zone get "units")  append (_garrMilResult getOrDefault ["units", []]);
                (_zone get "groups") append (_garrMilResult getOrDefault ["groups", []]);

                diag_log format ["DSC: activatePresenceZone [%1] - mil garrison: %2 cluster(s) (role=%3 tier=%4 ctrl=%5)",
                    _id, _milClusters, _garrRole, _sizeTier, _controlledBy];
            };
        };
    };
};

// ============================================================================
// Irregular indoor garrison — runs on any populated area, low chance
// ============================================================================
// Armed civilian populace. Independent of `controlledBy` / `_influence` so
// the player can stumble into a hostile compound anywhere. Sourced from the
// `irregulars` role (falls back to `opForPartner` to match the wandering
// irregular overlay's role priority). Force-east side for player hostility
// — same trick the irregular overlay + contested skirmish use.
if (_totalStructs > 0) then {
    private _sizeTier = switch (true) do {
        case (_totalStructs < 5):  { "isolated" };
        case (_totalStructs < 15): { "settlement" };
        case (_totalStructs < 50): { "town" };
        default                    { "city" };
    };

    // Higher chance in neutral/contested (where the populace is the only
    // armed presence), lower in opFor-/bluFor-controlled (controlling
    // garrison already provides combat encounters).
    private _irrChance = switch (_controlledBy) do {
        case "neutral":   { 0.40 };
        case "contested": { 0.40 };
        case "opFor":     { 0.20 };
        case "bluFor":    { 0.25 };
        default            { 0.30 };
    };

    if (random 1 < _irrChance) then {
        private _factionData = missionNamespace getVariable ["DSC_factionData", createHashMap];

        private _irrGroups = [];
        private _irrRole = "";
        {
            private _role = _x;
            private _roleData = _factionData getOrDefault [_role, createHashMap];
            private _roleGroupsHM = _roleData getOrDefault ["groups", createHashMap];

            private _collected = [];
            {
                _collected append (_y select {
                    private _t = _x getOrDefault ["doctrineTags", []];
                    ("FOOT" in _t || "PATROL" in _t)
                        && { !("ARMOR" in _t) }
                        && { !("NAVAL" in _t) }
                });
            } forEach _roleGroupsHM;

            if (_collected isNotEqualTo []) exitWith {
                _irrGroups = _collected;
                _irrRole = _role;
            };
        } forEach ["irregulars", "opForPartner"];

        if (_irrGroups isNotEqualTo []) then {
            // 1 cluster only — armed-civilian holdout, not a hardpoint.
            private _irrResult = [_pos, _irrGroups, east,
                createHashMapFromArray [
                    ["mainStructures", _mainStructs],
                    ["sideStructures", _sideStructs],
                    ["sizeTier",       _sizeTier],
                    ["anchorCount",    1],
                    ["forceSpawn",     true]
                ]
            ] call DSC_core_fnc_setupLightMilitaryGarrison;

            (_zone get "units")  append (_irrResult getOrDefault ["units", []]);
            (_zone get "groups") append (_irrResult getOrDefault ["groups", []]);

            diag_log format ["DSC: activatePresenceZone [%1] - irregular garrison: 1 cluster (role=%2 tier=%3 ctrl=%4)",
                _id, _irrRole, _sizeTier, _controlledBy];
        };
    };
};
["garrison"] call _stamp;

// ============================================================================
// Military overlay — single small patrol from controlling side, at >=0.3 inf
// ============================================================================
if (_controlledBy in ["opFor", "bluFor", "contested"] && {_influence >= 0.3}) then {
    private _factionData = missionNamespace getVariable ["DSC_factionData", createHashMap];

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
        private _patrolPool = [_overlayGroups] call DSC_core_fnc_filterPatrolGroups;
        if (_patrolPool isEqualTo []) then { _patrolPool = _overlayGroups };

        private _primaryAngle = if (_controlledBy == "contested") then { random 360 } else { -1 };

        private _patrolConfig = createHashMapFromArray [
            ["patrolCount",  [0, 3]],
            ["spawnRadius",  [(_radius max 100), (_radius max 200) + 100]],
            ["patrolRadius", [(_radius max 150), (_radius max 250) + 100]],
            ["spawnAngle",   _primaryAngle]
        ];

        private _patrolResult = [_pos, _patrolPool, _overlaySide, _patrolConfig] call DSC_core_fnc_setupPatrols;
        (_zone get "units")  append (_patrolResult getOrDefault ["units", []]);
        (_zone get "groups") append (_patrolResult getOrDefault ["groups", []]);

        diag_log format ["DSC: activatePresenceZone [%1] - military overlay: %2 patrol units from role '%3' (%4)",
            _id, count (_patrolResult getOrDefault ["units", []]), _overlayRole, _controlledBy];

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

// ============================================================================
// Irregular overlay — neutral-influence zones get armed civilians
// ============================================================================
// Towns without a controlling faction still feel inhabited via the civilian
// pass above. We add a single small "armed civilian" patrol (force-east for
// player hostility) so neutral territory has random encounters instead of
// being completely empty of threats. See fnc_resolveIrregularOverlay.
if (_controlledBy == "neutral") then {
    private _irregularResult = [
        _pos,
        _radius,
        createHashMapFromArray [
            ["patrolCount", [0, 3]]
        ]
    ] call DSC_core_fnc_resolveIrregularOverlay;

    (_zone get "units")  append (_irregularResult getOrDefault ["units", []]);
    (_zone get "groups") append (_irregularResult getOrDefault ["groups", []]);

    if ((_irregularResult getOrDefault ["units", []]) isNotEqualTo []) then {
        diag_log format ["DSC: activatePresenceZone [%1] - irregular overlay: %2 patrol units (neutral town)",
            _id, count (_irregularResult getOrDefault ["units", []])];
    };
};
["irregularOverlay"] call _stamp;

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
