#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_c2ContactRegister
 * Description:
 *     Sprint F.4 — records or refreshes a fix on a HOSTILE element so it can be
 *     drawn on the Blue Force Tracker.
 *
 *     IS THIS REALISTIC? YES — BUT ONLY THESE TWO SOURCES
 *
 *     The design constraint from the start of F.4 is that ISR must improve
 *     DECISION QUALITY, not hand over a target list. An enemy marker is a big
 *     step toward a wallhack, so each source has to correspond to a real
 *     military capability:
 *
 *     1. "SIGINT" — RADIO DIRECTION FINDING.
 *        You cannot see an enemy patrol, but when it TRANSMITS you can get a
 *        bearing on the transmitter, and with two receivers a fix. This is
 *        genuine, routine SIGINT and it is exactly what the C2 network already
 *        simulates: every contact report is a radio emission from a known
 *        position. So a group that opens its mouth gets marked, and a group
 *        that stays silent does not.
 *
 *        This is the mechanically interesting one, because it makes the report
 *        timer legible *spatially*: kill a patrol before it transmits and it
 *        never appears on your map at all. Let it report and you learn roughly
 *        where it was — but so does the enemy learn where you are. Both sides
 *        pay for talking.
 *
 *     2. "VISUAL" — OWN-FORCE CONTACT REPORTS.
 *        Something on the player's side has actually seen the element. This is
 *        the most ordinary BFT function there is: subordinate units report
 *        contacts and they appear on the common operational picture. Gated on
 *        the engine's own `knowsAbout`, so it cannot reveal anything the
 *        player's side has not genuinely observed.
 *
 *     WHAT MAKES IT NOT A WALLHACK
 *
 *       - Fixes are SNAPSHOTS, not tracking. The marker sits where the element
 *         was when it was detected. Enemies move; the marker does not.
 *       - Fixes AGE OUT (default 240s SIGINT / 90s VISUAL). A stale radio fix
 *         is worse than useless if you treat it as live.
 *       - Visual fixes refresh while the contact remains observed, so they are
 *         accurate exactly as long as somebody is looking.
 *       - Silent, unobserved enemies are completely invisible. Most of the
 *         world stays dark.
 *
 *     Position is stored as-recorded, deliberately without jitter. The
 *     inaccuracy is temporal (the marker is old) rather than spatial, which
 *     reads as honest rather than buggy — a player who sees a 3-minute-old fix
 *     understands why the enemy is not there any more.
 *
 * Arguments:
 *     0: _group  <GROUP>  - the hostile group being fixed
 *     1: _pos    <ARRAY>  - position of the fix
 *     2: _source <STRING> - "SIGINT" | "VISUAL"
 *     3: _label  <STRING> - callsign if known, "" otherwise
 *
 * Return Value:
 *     <BOOL> - true if recorded
 */

params [
    ["_group",  grpNull, [grpNull]],
    ["_pos",    [], [[]]],
    ["_source", "SIGINT", [""]],
    ["_label",  "", [""]]
];

if (!isServer) exitWith { false };
if (isNull _group || {_pos isEqualTo []}) exitWith { false };

// A wiped group is not a contact. Recording one would leave a permanent
// marker on a crater.
private _live = (units _group) select { alive _x };
if (_live isEqualTo []) exitWith { false };

private _contacts = missionNamespace getVariable ["DSC_c2Contacts", []];

// Prune expired fixes on every write, so the array cannot grow without bound
// and the reader never has to think about staleness.
private _ttlFor = {
    params ["_src"];
    // A radio fix stays useful longer than an eyeball because it is a
    // recorded emission rather than a live observation — but both decay.
    switch (_src) do {
        case "VISUAL": { 90 };
        default        { 240 };
    }
};

private _kept = [];
{
    private _c = _x;
    private _age = serverTime - (_c getOrDefault ["time", 0]);
    private _ttl = [_c getOrDefault ["source", "SIGINT"]] call _ttlFor;
    if (_age <= _ttl) then { _kept pushBack _c };
} forEach _contacts;
_contacts = _kept;

// ============================================================================
// Refresh an existing fix on the same group, or append
// ============================================================================
// Keyed on the group so a patrol that transmits three times produces one
// marker that updates, not three stacked ghosts. A VISUAL fix supersedes a
// SIGINT one for the same group — actually seeing something beats inferring
// it from a radio burst.
private _existing = -1;
{
    if ((_x getOrDefault ["group", grpNull]) isEqualTo _group) exitWith { _existing = _forEachIndex };
} forEach _contacts;

private _leader = leader _group;
private _veh = objNull;
if (!isNull _leader) then {
    private _lv = vehicle _leader;
    if (_lv isNotEqualTo _leader) then { _veh = _lv };
};

private _entry = createHashMapFromArray [
    ["group",    _group],
    ["position", _pos],
    ["time",     serverTime],
    ["source",   _source],
    ["label",    _label],
    ["side",     side _group],
    ["strength", count _live],
    ["vehicle",  _veh]
];

if (_existing >= 0) then {
    private _prev    = _contacts select _existing;
    private _prevSrc = _prev getOrDefault ["source", "SIGINT"];
    private _prevAge = serverTime - (_prev getOrDefault ["time", 0]);

    // Don't let a radio burst overwrite a FRESH visual contact — actually
    // seeing something beats inferring it from an emission. An explicit flag
    // rather than `exitWith`, which inside a `then` block has ambiguous
    // scope (same reasoning as fnc_c2ContactReport's `_running`).
    private _supersede = true;
    if (_prevSrc isEqualTo "VISUAL" && {_source isNotEqualTo "VISUAL"} && {_prevAge < 30}) then {
        _supersede = false;
    };

    if (_supersede) then {
        // Preserve the better label if the new one is blank.
        if (_label isEqualTo "") then {
            _entry set ["label", _prev getOrDefault ["label", ""]];
        };
        _contacts set [_existing, _entry];
    };
} else {
    _contacts pushBack _entry;
};

missionNamespace setVariable ["DSC_c2Contacts", _contacts, true];

LOG_3("c2Contact %1 fix on %2 (%3 live)",_source,groupId _group,count _live);

true
