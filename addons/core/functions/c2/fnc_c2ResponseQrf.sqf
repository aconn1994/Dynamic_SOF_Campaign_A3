#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_c2ResponseQrf
 * Description:
 *     Sprint F.3 — dispatches a Quick Reaction Force from an installation
 *     toward a last known position.
 *
 *     REAL SPAWN, REAL TRAVEL. The QRF is created at the node's own position
 *     and drives or walks the actual distance. This is a deliberate design
 *     decision: Arma firefights are long, and a 5-8 minute transit is
 *     tension rather than dead time. It also means the player can *see* them
 *     coming, break contact, reposition, or set an ambush on the road —
 *     which is the entire tactical payoff of the C2 layer being legible.
 *
 *     Consequence budget: QRF spawns intentionally IGNORE the presence
 *     manager's unit cap. A response the player earned must never be
 *     silently cancelled because the ambient world happened to be busy.
 *     Frame cost is still respected via fnc_spawnGroupYielding.
 *
 *     Mounted where possible, on foot otherwise. A node with motorized
 *     groups in its faction pool sends vehicles; one without sends runners.
 *     That falls out of the faction data rather than being configured, so a
 *     militia outpost with no trucks naturally responds slower and weaker
 *     than a CSAT airbase.
 *
 * Arguments:
 *     0: _nodeId <STRING>  - dispatching node
 *     1: _cfg    <HASHMAP> - ladder entry for current alert level
 *
 * Return Value:
 *     <NUMBER> - QRF elements dispatched
 */

params [
    ["_nodeId", "", [""]],
    ["_cfg",    createHashMap, [createHashMap]]
];

if (!isServer) exitWith { 0 };
if (_nodeId isEqualTo "") exitWith { 0 };

private _nodes = missionNamespace getVariable ["DSC_c2Nodes", createHashMap];
private _node = _nodes getOrDefault [_nodeId, createHashMap];
if (_node isEqualTo createHashMap) exitWith { 0 };

private _cs      = _node get "callsign";
private _nodePos = _node get "position";
private _side    = _node get "side";
private _faction = _node get "faction";
private _reach   = _node getOrDefault ["reach", 1500];

private _lkp = _node getOrDefault ["lkp", createHashMap];
private _lkpPos = _lkp getOrDefault ["position", []];
if (_lkpPos isEqualTo []) exitWith { 0 };

private _confidence = _lkp getOrDefault ["confidence", 0.5];

// ============================================================================
// Reach gate — beyond it, nothing arrives
// ============================================================================
// Not a delayed response, not a smaller one. Nothing. This is what makes
// operating far from installations meaningfully safer and requires no
// special-casing anywhere else in the system.
private _dist = _nodePos distance2D _lkpPos;
if (_dist > _reach) exitWith {
    LOG_3("c2Qrf [%1] - LKP %2m beyond reach %3m, no response",_cs,round _dist,_reach);
    0
};

// ============================================================================
// Resolve a group to send
// ============================================================================
private _factionData = missionNamespace getVariable ["DSC_factionData", createHashMap];
private _factionProfileConfig = missionNamespace getVariable ["factionProfileConfig", createHashMap];

private _roleName = "";
{
    private _facs = (_y getOrDefault ["factions", []]);
    if (_faction in _facs) exitWith { _roleName = _x };
} forEach _factionProfileConfig;

private _roleData   = _factionData getOrDefault [_roleName, createHashMap];
private _roleGroups = _roleData getOrDefault ["groups", createHashMap];
private _facGroups  = _roleGroups getOrDefault [_faction, []];

if (_facGroups isEqualTo []) exitWith {
    LOG_2("c2Qrf [%1] - no groups available for faction %2",_cs,_faction);
    0
};

// Prefer mounted. A motorized element arrives fast and telegraphs itself
// (engine noise, headlights at night), which is good for legibility.
private _mounted = _facGroups select {
    private _tags = _x getOrDefault ["doctrineTags", []];
    ("MOTORIZED" in _tags || {"MECHANIZED" in _tags}) &&
    {!("ARMOR" in _tags)} && {!("NAVAL" in _tags)} && {!("AIR_CREW" in _tags)}
};

private _foot = _facGroups select {
    private _tags = _x getOrDefault ["doctrineTags", []];
    ("FOOT" in _tags || {"PATROL" in _tags}) &&
    {!("STATIC" in _tags)} && {!("NAVAL" in _tags)} && {!("AIR_CREW" in _tags)}
};

private _pool = _mounted;
private _isMounted = true;
if (_pool isEqualTo []) then {
    _pool = _foot;
    _isMounted = false;
};
if (_pool isEqualTo []) exitWith {
    LOG_1("c2Qrf [%1] - no suitable QRF groups (no mounted or foot)",_cs);
    0
};

private _pick = selectRandom _pool;
// Group hashmaps from fnc_extractGroups carry "path" ("Side/Faction/Cat/Name"),
// not a config object. fnc_spawnGroupYielding accepts the path string form
// directly and walks it itself.
private _groupPath = _pick getOrDefault ["path", ""];
private _groupName = _pick getOrDefault ["groupName", "unknown"];
if (_groupPath isEqualTo "") exitWith {
    LOG_1("c2Qrf [%1] - selected group has no config path",_cs);
    0
};

// ============================================================================
// Spawn at the installation
// ============================================================================
// Offset onto a nearby road when mounted so the vehicle isn't birthed inside
// a building; foot elements can start at the node itself.
private _spawnPos = _nodePos;
if (_isMounted) then {
    private _roads = _nodePos nearRoads 300;
    if (_roads isNotEqualTo []) then {
        _spawnPos = getPosATL (selectRandom _roads);
    };
};

// Spawner choice is forced by capability, not preference:
//
//   fnc_spawnGroupYielding creates units one at a time via createUnit, which
//   is the mod's standing anti-stutter convention — but it CANNOT create
//   vehicles. A MOTORIZED CfgGroups entry lists its transport as a unit slot,
//   and createUnit on a vehicle class does not produce a crewed vehicle.
//
//   So mounted elements must go through BIS_fnc_spawnGroup, which handles
//   vehicle creation and crew seating. That is a single-frame burst of ~5-8
//   entities. It is accepted here for the same reason fnc_setupVehiclePatrol
//   accepts it: a QRF is a rare, player-triggered event, not a per-tick cost,
//   and correctness of the vehicle beats smoothing one frame.
private _grp = grpNull;
private _vehicle = objNull;

if (_isMounted) then {
    private _pathParts = _groupPath splitString "/";
    private _groupCfg = configFile >> "CfgGroups";
    { _groupCfg = _groupCfg >> _x } forEach _pathParts;

    _grp = [_spawnPos, _side, _groupCfg] call BIS_fnc_spawnGroup;

    if (!isNull _grp) then {
        {
            if (!isNull (objectParent _x)) exitWith { _vehicle = vehicle _x };
        } forEach units _grp;

        // A "motorized" group whose vehicle failed to spawn is just infantry
        // standing at a base — acceptable, but relabel so the log is honest.
        if (isNull _vehicle) then { _isMounted = false };
    };
} else {
    _grp = [_spawnPos, _side, _groupPath] call DSC_core_fnc_spawnGroupYielding;
};

if (isNull _grp) exitWith {
    LOG_2("c2Qrf [%1] - spawn failed for %2",_cs,_groupName);
    0
};

// ============================================================================
// Posture — these are hunting, not ambient
// ============================================================================
{
    if (alive _x) then {
        _x enableAI "AUTOCOMBAT";
        _x enableAI "TARGET";
        _x enableAI "AUTOTARGET";
        _x enableDynamicSimulation true;
    };
} forEach units _grp;

_grp setBehaviour "AWARE";
_grp setCombatMode "YELLOW";
_grp setSpeedMode "FULL";
_grp enableDynamicSimulation true;
if (!isNull _vehicle) then { _vehicle enableDynamicSimulation true };

// Mounted elements need the driver leading, or waypoints route through a
// passenger's foot pathing and the vehicle sits still.
if (!isNull _vehicle) then {
    private _driver = driver _vehicle;
    if (!isNull _driver) then { _grp selectLeader _driver };
};

// Skill: responders are the sharp end, but still bounded by the mod's
// cqb_baseline philosophy so a QRF is a fight rather than a firing squad.
[units _grp, "cqb_baseline"] call DSC_core_fnc_applySkillProfile;

// C2 provenance — a QRF is itself an element that can be wiped before it
// reports, which means ambushing the QRF is a legitimate play with the same
// mechanics as ambushing anything else.
[_grp, _nodeId, "patrol"] call DSC_core_fnc_c2StampGroup;
_grp setVariable ["DSC_c2IsQrf", true, true];

// ============================================================================
// Route to the LKP
// ============================================================================
private _searchRadius = (_cfg getOrDefault ["searchSpread", 200]) * (1 + ((1 - _confidence) * 2));
private _hasLambs = isClass (configFile >> "CfgPatches" >> "lambs_wp");

// Mounted elements must TRAVEL first. LAMBS taskHunt starts a search pattern
// immediately, which makes a vehicle crawl and mill around near its spawn
// instead of covering the ground to the objective — so mounted QRF always
// gets a plain move-and-engage order and only foot QRF gets taskHunt.
//
// This also preserves the design intent that the player can see a mounted
// response coming down a road and react to it.
if (_hasLambs && {!_isMounted}) then {
    // Position is arg 4 in taskHunt's signature — see fnc_c2ResponseRecall.
    [_grp, _searchRadius, 15, [], _lkpPos, false] spawn (missionNamespace getVariable "lambs_wp_fnc_taskHunt");
} else {
    private _convCfg = createHashMapFromArray [
        ["radius",     _searchRadius],
        ["behaviour",  "AWARE"],
        ["combatMode", "YELLOW"],
        ["speed",      "FULL"]
    ];
    [[_grp], _lkpPos, _convCfg] call DSC_core_fnc_convergePatrols;
};

// ============================================================================
// Register + telegraph
// ============================================================================
private _dispatched = _node getOrDefault ["dispatched", []];
_dispatched pushBack createHashMapFromArray [
    ["group",     _grp],
    ["vehicle",   _vehicle],
    ["kind",      ["foot", "mounted"] select _isMounted],
    ["target",    _lkpPos],
    ["spawnTime", serverTime]
];
_node set ["dispatched", _dispatched];

private _stats = missionNamespace getVariable ["DSC_c2Stats", createHashMap];
_stats set ["responsesDispatched", (_stats getOrDefault ["responsesDispatched", 0]) + 1];

private _uc = count (units _grp);
private _kindLabel = ["foot", "mounted"] select _isMounted;
private _bearing = round (_lkpPos getDir _nodePos);
INFO_5("c2 QRF DISPATCHED [%1] - %2 %3 units toward LKP %4m out (bearing %5 from target)",_cs,_uc,_kindLabel,round _dist,_bearing);

private _grid = mapGridPosition _lkpPos;
[
    "COMMAND",
    _cs,
    "QRF",
    format ["Move to grid %1, %2 element, engage on contact", _grid, _kindLabel],
    _nodeId,
    "BASIC",
    _lkpPos
] call DSC_core_fnc_c2FeedAdd;

// ============================================================================
// F.4 — player-facing dispatch notification
// ============================================================================
// This is the payoff line of the whole system, and the reason ISR is worth
// carrying: bearing plus travel distance is exactly what a player needs to
// decide whether to break contact, reposition, or set an ambush. It is a
// decision aid, not target data — the player learns something is coming and
// roughly from where, never where individual units are.
//
// Gated at ENHANCED (drone on station) rather than BASIC, because a QRF is
// usually dispatched from a node several kilometres away that the player has no
// local awareness of. That gate is what makes losing the drone matter.
private _etaMin = round ((_dist / 1000) * 2.5) max 1;
[
    "ISR",
    "",
    "",
    format ["QRF dispatched from %1 - %2 element, bearing %3, approx %4 min out",
        _cs, _kindLabel, _bearing, _etaMin],
    _nodeId,
    "ENHANCED",
    _lkpPos
] call DSC_core_fnc_c2FeedAdd;

// Diegetic cue, no coverage required — headlights leaving the installation.
["DISPATCH", _nodePos] call DSC_core_fnc_c2Telegraph;

1
