#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_bftSnapshot
 * Description:
 *     Server-side aggregator for the Blue Force Tracker. Walks the world-
 *     simulation data sources (presence zones, roving manager records, ISR
 *     drone, current mission), filters to friendly groups (side matches
 *     bluFor / bluForPartner from the active factionProfileConfig), classifies
 *     each track's marker subtype from its actual vehicle (inf / motor_inf /
 *     mech_inf / armor / air / plane / naval / uav), and broadcasts a
 *     normalized track list as DSC_bftTracks.
 *
 *     Player's own squad is NOT included here — the client always has it
 *     locally and overlays it client-side in panelBft_draw.
 *
 *     Runs forever in a spawned scope; cadence ~2.5s, phase-offset from
 *     presence/roving ticks so we don't stack server-side work.
 *
 *     Published globals:
 *       DSC_bftTracks         <ARRAY of HASHMAP>  friendly tracks snapshot
 *       DSC_bftFriendlySides  <ARRAY of SIDE>     resolved friendly sides
 *
 *     Track schema (per entry):
 *       id          STRING   stable key
 *       category    STRING   source bucket (garrison / ground / air / foot / boat / uav / mission)
 *       iconType    STRING   BI marker subtype (inf / motor_inf / mech_inf /
 *                            armor / air / plane / naval / uav)
 *       group       GROUP    group ref
 *       vehicle     OBJECT   vehicle ref (objNull when foot)
 *       position    ARRAY    world pos
 *       dir         NUMBER   leader/vehicle facing (informational; map icons
 *                            are drawn north-up in the client for readability)
 *       side        SIDE
 *       faction     STRING
 *       label       STRING
 *       strength    NUMBER   alive unit count
 *       commandable BOOL     reserved for BFT-3
 *
 * Arguments: none
 *
 * Example:
 *     [] spawn DSC_core_fnc_bftSnapshot;
 */

if (!isServer) exitWith {};

// ----------------------------------------------------------------------------
// Register the CBA event the tablet uses to issue commands. Server-only.
// ----------------------------------------------------------------------------
["DSC_bft_command", { _this call DSC_core_fnc_bftExecuteCommand }] call CBA_fnc_addEventHandler;

// Seed the commanded-group list so first-access doesn't trip up isNil guards
if (isNil { missionNamespace getVariable "DSC_bftCommandedGroups" }) then {
    missionNamespace setVariable ["DSC_bftCommandedGroups", [], true];
};

// ----------------------------------------------------------------------------
// Resolve friendly sides from the active faction profile
// ----------------------------------------------------------------------------
private _cfg = missionNamespace getVariable ["factionProfileConfig", createHashMap];
private _friendlySides = [];
{
    private _role = _cfg getOrDefault [_x, createHashMap];
    private _s = _role getOrDefault ["side", sideUnknown];
    if (_s isEqualType west && {_s != sideUnknown}) then {
        _friendlySides pushBackUnique _s;
    };
} forEach ["bluFor", "bluForPartner"];
if (_friendlySides isEqualTo []) then { _friendlySides = [west] };

missionNamespace setVariable ["DSC_bftFriendlySides", _friendlySides, true];

diag_log format ["DSC: bftSnapshot - friendly sides: %1", _friendlySides];

// ----------------------------------------------------------------------------
// Vehicle → BI marker subtype classifier
//
// Maps a (vehicle, leader) pair to one of BI's CfgMarkers icon keys so the
// client can pick "b_inf" vs "b_motor_inf" vs "b_armor" etc. Mounted Tank-
// hierarchy entries are split into MBT (transportSoldier == 0 → "armor")
// and IFV/APC (transportSoldier > 0 → "mech_inf"). Wheeled transports map
// to "motor_inf"; foot leaders map to "inf".
// ----------------------------------------------------------------------------
private _resolveIconType = {
    params ["_veh", "_ldr"];
    if (isNull _veh || {_veh isEqualTo _ldr}) exitWith { "inf" };

    private _type = typeOf _veh;
    private _cfg  = configFile >> "CfgVehicles" >> _type;
    private _transport = getNumber (_cfg >> "transportSoldier");

    switch (true) do {
        case (_veh isKindOf "UAV"):           { "uav" };
        case (_veh isKindOf "Plane"):         { "plane" };
        case (_veh isKindOf "Helicopter"):    { "air" };
        case (_veh isKindOf "Ship"):          { "naval" };
        case (_veh isKindOf "Tank"):          { ["armor", "mech_inf"] select (_transport > 0) };
        case (_veh isKindOf "Wheeled_APC_F"): { "motor_inf" };
        case (_veh isKindOf "Car"):           { "motor_inf" };
        default                                { "inf" };
    };
};

// ----------------------------------------------------------------------------
// Snapshot loop
//
// Interval is read from `DSC_bftSnapshotInterval` each tick (default 2.5 s,
// clamped 0.5–10 s). Set via debug console — e.g. `DSC_bftSnapshotInterval = 5;`
// — without restarting the loop; effective on the very next iteration.
// ----------------------------------------------------------------------------

while {true} do {
    private _tracks = [];

    // ========================================================================
    // 1. Presence zones — friendly garrisons / patrols spawned by handlers
    // ========================================================================
    private _zones = missionNamespace getVariable ["DSC_presenceZones", createHashMap];
    {
        private _zone = _y;
        private _zname = _zone getOrDefault ["name", _zone getOrDefault ["id", ""]];
        private _zfac  = _zone getOrDefault ["faction", ""];
        private _zgrps = _zone getOrDefault ["groups", []];

        {
            private _grp = _x;
            if (isNull _grp) then { continue };
            if !((side _grp) in _friendlySides) then { continue };
            private _aliveUnits = (units _grp) select { alive _x };
            if (_aliveUnits isEqualTo []) then { continue };

            private _ldr = leader _grp;
            private _veh = vehicle _ldr;
            private _trackVeh = [objNull, _veh] select (_veh != _ldr);
            private _iconType = [_trackVeh, _ldr] call _resolveIconType;

            _tracks pushBack createHashMapFromArray [
                ["id",          format ["pz_%1", groupId _grp]],
                ["category",    "garrison"],
                ["iconType",    _iconType],
                ["group",       _grp],
                ["vehicle",     _trackVeh],
                ["position",    getPosATL _ldr],
                ["dir",         getDir _ldr],
                ["side",        side _grp],
                ["faction",     _zfac],
                ["label",       _zname],
                ["strength",    count _aliveUnits],
                ["commandable", true],
                ["role",        _grp getVariable ["DSC_bftRole", ""]]
            ];
        } forEach _zgrps;
    } forEach _zones;

    // ========================================================================
    // 2. Roving manager — air / ground / foot / boat patrols in friendly
    //    territory
    // ========================================================================
    private _labelByType = createHashMapFromArray [
        ["air",    "AIR PATROL"],
        ["ground", "GND PATROL"],
        ["foot",   "FOOT PATROL"],
        ["boat",   "BOAT PATROL"]
    ];

    private _roving = missionNamespace getVariable ["DSC_rovingActive", []];
    {
        private _rec  = _x;
        private _grp  = _rec getOrDefault ["group",   grpNull];
        private _side = _rec getOrDefault ["side",    sideUnknown];
        private _veh  = _rec getOrDefault ["vehicle", objNull];
        private _type = _rec getOrDefault ["type",    "ground"];

        if (isNull _grp) then { continue };
        if !(_side in _friendlySides) then { continue };

        private _aliveUnits = (units _grp) select { alive _x };
        if (_aliveUnits isEqualTo []) then { continue };

        private _ldr = leader _grp;
        private _pos = [getPosATL _ldr, getPosATL _veh] select (!isNull _veh && {alive _veh});
        private _dir = [getDir _ldr, getDir _veh] select (!isNull _veh && {alive _veh});

        // Roving type ("foot") may legitimately have no vehicle; classifier
        // returns "inf" in that case. Air / ground / boat use the vehicle.
        private _iconType = [_veh, _ldr] call _resolveIconType;

        _tracks pushBack createHashMapFromArray [
            ["id",          _rec getOrDefault ["id", format ["rov_%1", groupId _grp]]],
            ["category",    _type],
            ["iconType",    _iconType],
            ["group",       _grp],
            ["vehicle",     _veh],
            ["position",    _pos],
            ["dir",         _dir],
            ["side",        _side],
            ["faction",     ""],
            ["label",       _labelByType getOrDefault [_type, "PATROL"]],
            ["strength",    count _aliveUnits],
            ["commandable", true],
            ["role",        _grp getVariable ["DSC_bftRole", ""]]
        ];
    } forEach _roving;

    // ========================================================================
    // 3. Persistent ISR drone — always friendly, always interesting
    // ========================================================================
    private _uav = missionNamespace getVariable ["DSC_activeUAV", objNull];
    if (!isNull _uav && {alive _uav}) then {
        _tracks pushBack createHashMapFromArray [
            ["id",          "uav_isr"],
            ["category",    "uav"],
            ["iconType",    "uav"],
            ["group",       grpNull],
            ["vehicle",     _uav],
            ["position",    getPosATL _uav],
            ["dir",         getDir _uav],
            ["side",        west],
            ["faction",     ""],
            ["label",       "ISR DRONE"],
            ["strength",    1],
            ["commandable", false]
        ];
    };

    // ========================================================================
    // 4. Mission-attached friendly groups (rare today; future BFT-4)
    // ========================================================================
    private _mission   = missionNamespace getVariable ["DSC_currentMission", createHashMap];
    private _mGroups   = _mission getOrDefault ["groups", []];
    {
        private _grp = _x;
        if (isNull _grp) then { continue };
        if !((side _grp) in _friendlySides) then { continue };
        private _aliveUnits = (units _grp) select { alive _x };
        if (_aliveUnits isEqualTo []) then { continue };

        private _ldr = leader _grp;
        private _veh = vehicle _ldr;
        private _trackVeh = [objNull, _veh] select (_veh != _ldr);
        private _iconType = [_trackVeh, _ldr] call _resolveIconType;

        _tracks pushBack createHashMapFromArray [
            ["id",          format ["mz_%1", groupId _grp]],
            ["category",    "mission"],
            ["iconType",    _iconType],
            ["group",       _grp],
            ["vehicle",     _trackVeh],
            ["position",    getPosATL _ldr],
            ["dir",         getDir _ldr],
            ["side",        side _grp],
            ["faction",     ""],
            ["label",       "ATTACHED"],
            ["strength",    count _aliveUnits],
            ["commandable", true],
            ["role",        _grp getVariable ["DSC_bftRole", ""]]
        ];
    } forEach _mGroups;

    // ========================================================================
    // 5. Groups under (or formerly under) player command via BFT-3. Stored
    //    separately because they're detached from their parent presence /
    //    roving record once taken — this is the only place they show up
    //    afterward. Role tag drives the label suffix.
    // ========================================================================
    private _commanded = missionNamespace getVariable ["DSC_bftCommandedGroups", []];
    {
        private _grp = _x;
        if (isNull _grp) then { continue };
        if !((side _grp) in _friendlySides) then { continue };
        private _aliveUnits = (units _grp) select { alive _x };
        if (_aliveUnits isEqualTo []) then { continue };

        private _ldr = leader _grp;
        private _veh = vehicle _ldr;
        private _trackVeh = [objNull, _veh] select (_veh != _ldr);
        private _iconType = [_trackVeh, _ldr] call _resolveIconType;
        private _role = _grp getVariable ["DSC_bftRole", ""];
        private _qrfTriggered = _grp getVariable ["DSC_bftQrfTriggered", false];

        private _qrfLabel = ["QRF %1", "QRF→ %1"] select _qrfTriggered;
        private _label = switch (toLower _role) do {
            case "commanded":  { format ["CMD %1",   groupId _grp] };
            case "moving":     { format ["MOVE %1",  groupId _grp] };
            case "moving_obj": { format ["→OBJ %1",  groupId _grp] };
            case "qrf":        { format [_qrfLabel,  groupId _grp] };
            default            { format ["FREE %1",  groupId _grp] };
        };

        _tracks pushBack createHashMapFromArray [
            ["id",          format ["cmd_%1", groupId _grp]],
            ["category",    "commanded"],
            ["iconType",    _iconType],
            ["group",       _grp],
            ["vehicle",     _trackVeh],
            ["position",    getPosATL _ldr],
            ["dir",         getDir _ldr],
            ["side",        side _grp],
            ["faction",     ""],
            ["label",       _label],
            ["strength",    count _aliveUnits],
            ["commandable", true],
            ["role",        _role],
            ["triggered",   _qrfTriggered]
        ];
    } forEach _commanded;

    // ------------------------------------------------------------------------
    missionNamespace setVariable ["DSC_bftTracks", _tracks, true];

    private _interval = missionNamespace getVariable ["DSC_bftSnapshotInterval", 2.5];
    _interval = (_interval max 0.5) min 10;
    uiSleep _interval;
};
