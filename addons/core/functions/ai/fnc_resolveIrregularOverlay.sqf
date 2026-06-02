/*
 * Function: DSC_core_fnc_resolveIrregularOverlay
 * Description:
 *     Spawns a single small "armed civilian" patrol in a neutral-influence
 *     zone. Sources groups from the `irregulars` faction role first, falling
 *     back to `opForPartner` if irregulars are empty. Used by populated-area
 *     and camp handlers to make neutral zones feel inhabited and add random
 *     combat encounters across the map.
 *
 *     The patrol is spawned on `east` side regardless of the source role's
 *     natural side. This is deliberate:
 *       - irregulars' natural side is `independent`. The presence manager
 *         locks east<->independent friendly so opFor partners don't kill
 *         each other on sight. That same lock prevents independent units
 *         from engaging the player reliably (default west<->independent
 *         varies by map and mission config).
 *       - Forcing east side gives clean hostility-to-player (west<->east is
 *         hostile by default Arma diplomacy) while keeping the units aligned
 *         with the rest of the east bloc (no opFor-vs-irregular friendly
 *         fire).
 *       - This matches the trick used by fnc_setupContestedSkirmish, which
 *         force-spawns west-side patrols regardless of the underlying
 *         faction's natural side.
 *
 *     Cosmetic tradeoff: HUD/curator will display these units as OPFOR.
 *     They still look like whatever faction the source groups came from
 *     (looters, militia, criminal gangs).
 *
 * Arguments:
 *     0: _zonePos    <ARRAY>   - [x,y,z] zone center
 *     1: _zoneRadius <NUMBER>  - zone radius (drives spawn + patrol distances)
 *     2: _config     <HASHMAP>
 *        "factionData" <HASHMAP> overrides DSC_factionData
 *        "spawnAngle"  <NUMBER>  degrees from zone center (default random)
 *        "patrolCount" <ARRAY>   [min,max] patrol groups (default [1,1])
 *
 * Return Value:
 *     <HASHMAP> "units", "groups"
 */

params [
    ["_zonePos", [], [[]]],
    ["_zoneRadius", 200, [0]],
    ["_config", createHashMap, [createHashMap]]
];

private _result = createHashMapFromArray [
    ["units", []],
    ["groups", []]
];

if (_zonePos isEqualTo []) exitWith { _result };

private _factionData = _config getOrDefault ["factionData",
    missionNamespace getVariable ["DSC_factionData", createHashMap]];

private _spawnAngle  = _config getOrDefault ["spawnAngle", random 360];
private _patrolCount = _config getOrDefault ["patrolCount", [1, 1]];

// Candidate roles in priority order: armed civilians first, militia-style
// auxiliaries as the fallback.
private _candidateRoles = ["irregulars", "opForPartner"];

private _pickedGroups = [];
private _pickedRole = "";

{
    private _role = _x;
    private _roleData = _factionData getOrDefault [_role, createHashMap];
    private _groupsHM = _roleData getOrDefault ["groups", createHashMap];

    private _flat = [];
    {
        _flat append (_y select {
            private _tags = _x getOrDefault ["doctrineTags", []];
            ("FOOT" in _tags || "PATROL" in _tags)
                && {!("ARMOR" in _tags)}
                && {!("NAVAL" in _tags)}
        });
    } forEach _groupsHM;

    if (_flat isNotEqualTo []) exitWith {
        _pickedGroups = _flat;
        _pickedRole = _role;
    };
} forEach _candidateRoles;

if (_pickedGroups isEqualTo []) exitWith {
    diag_log "DSC: resolveIrregularOverlay - no irregulars/opForPartner groups available";
    _result
};

// Recce/fireteam-sized only — these are "armed civilians", not real squads.
private _patrolPool = [_pickedGroups] call DSC_core_fnc_filterPatrolGroups;
if (_patrolPool isEqualTo []) then { _patrolPool = _pickedGroups };

private _patrolConfig = createHashMapFromArray [
    ["patrolCount",  _patrolCount],
    ["spawnRadius",  [(_zoneRadius max 100), (_zoneRadius max 200) + 100]],
    ["patrolRadius", [(_zoneRadius max 150), (_zoneRadius max 250) + 100]],
    ["spawnAngle",   _spawnAngle]
];

// Force east side for player-hostility. See header comment for rationale.
private _patrolResult = [_zonePos, _patrolPool, east, _patrolConfig] call DSC_core_fnc_setupPatrols;

(_result get "units")  append (_patrolResult getOrDefault ["units", []]);
(_result get "groups") append (_patrolResult getOrDefault ["groups", []]);

diag_log format ["DSC: resolveIrregularOverlay - %1 patrol units (role '%2', forced east side)",
    count (_result get "units"), _pickedRole];

_result
