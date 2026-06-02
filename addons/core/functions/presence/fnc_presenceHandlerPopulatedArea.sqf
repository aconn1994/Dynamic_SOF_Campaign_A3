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

private _civConfig = createHashMapFromArray [
    ["count",      _targetCount],
    ["radius",     _radius max 200],
    ["structures", _structures]
];
private _civResult = [_pos, _civConfig] call DSC_core_fnc_setupCivilians;
["civilians"] call _stamp;

(_zone get "units")  append (_civResult getOrDefault ["units", []]);
(_zone get "groups") append (_civResult getOrDefault ["groups", []]);

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
            ["patrolCount", [1, 1]]
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
