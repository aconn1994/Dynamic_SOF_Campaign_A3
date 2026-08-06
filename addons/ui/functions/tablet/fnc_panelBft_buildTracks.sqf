#include "..\..\script_component.hpp"
/*
 * Function: DSC_ui_fnc_panelBft_buildTracks
 * Description:
 *     Returns the full list of selectable / drawable BFT entries by combining
 *     the server-broadcast snapshot (DSC_bftTracks) with the client-only
 *     entries — every squad member and the player — and the active mission
 *     objective. Used by both the Draw EH (to render icons) and the click
 *     handler (to hit-test selections) so the two stay in sync.
 *
 *     Each entry follows the snapshot schema; client-only entries fill in
 *     the same keys with synthetic ids ("me", "squad_<name>") and the
 *     appropriate iconType.
 *
 * Arguments: none
 *
 * Return Value:
 *     <ARRAY of HASHMAP> — track entries (server + squad + player + objective).
 *     Objective entry uses category="objective" and is selectable.
 */

private _result = [];

// ----------------------------------------------------------------------------
// Clutter filter — when MINE is active, drop ambient garrisons, roving,
// mission attachments, ISR. Keeps the player, the squad, the objective,
// and any commanded / formerly-commanded track. State lives on the tablet
// display (set by panelBft_toggleFilter).
// ----------------------------------------------------------------------------
private _display      = uiNamespace getVariable ["DSC_TabletDisplay", displayNull];
private _filterMine   = if (isNull _display) then { false } else { _display getVariable ["DSC_bftFilterMine", false] };
private _mineKeepCats = ["commanded", "player", "squad", "objective"];

// ----------------------------------------------------------------------------
// 1. Server-broadcast tracks
// ----------------------------------------------------------------------------
private _tracks = missionNamespace getVariable ["DSC_bftTracks", []];
{
    if (_filterMine && {!((_x getOrDefault ["category", ""]) in _mineKeepCats)}) then { continue };
    _result pushBack _x;
} forEach _tracks;

// ----------------------------------------------------------------------------
// 2. Local player squad (excluding the player)
// ----------------------------------------------------------------------------
{
    private _u = _x;
    if (!alive _u) then { continue };
    if (_u isEqualTo player) then { continue };

    _result pushBack (createHashMapFromArray [
        ["id",          format ["squad_%1", netId _u]],
        ["category",    "squad"],
        ["iconType",    "inf"],
        ["group",       group _u],
        ["vehicle",     objNull],
        ["position",    getPosATL _u],
        ["dir",         getDir _u],
        ["side",        side _u],
        ["faction",     ""],
        ["label",       name _u],
        ["strength",    1],
        ["commandable", false],
        ["unit",        _u]
    ]);
} forEach (units group player);

// ----------------------------------------------------------------------------
// 3. The player
// ----------------------------------------------------------------------------
if (alive player) then {
    _result pushBack (createHashMapFromArray [
        ["id",          "me"],
        ["category",    "player"],
        ["iconType",    "inf"],
        ["group",       group player],
        ["vehicle",     objNull],
        ["position",    getPosATL player],
        ["dir",         getDir player],
        ["side",        side player],
        ["faction",     ""],
        ["label",       "ME"],
        ["strength",    1],
        ["commandable", false],
        ["unit",        player]
    ]);
};

// ----------------------------------------------------------------------------
// 4. Active mission objective (selectable so the player can see distances etc)
// ----------------------------------------------------------------------------
private _mission = missionNamespace getVariable ["DSC_currentMission", createHashMap];
private _objPos  = _mission getOrDefault ["location", []];
if (_objPos isEqualType [] && {count _objPos >= 2}) then {
    _result pushBack (createHashMapFromArray [
        ["id",          "objective"],
        ["category",    "objective"],
        ["iconType",    "objective"],
        ["group",       grpNull],
        ["vehicle",     objNull],
        ["position",    _objPos],
        ["dir",         0],
        ["side",        sideUnknown],
        ["faction",     ""],
        ["label",       _mission getOrDefault ["locationName", "OBJECTIVE"]],
        ["strength",    0],
        ["commandable", false]
    ]);
};

// ----------------------------------------------------------------------------
// 5. Hostile contact fixes (C2 Sprint F.4)
// ----------------------------------------------------------------------------
// SIGINT (radio direction finding on a transmitting element) and VISUAL
// (own-force contact reports) fixes from DSC_c2Contacts. These are SNAPSHOTS,
// not tracking — the marker sits where the element was when detected and ages
// out. See fnc_c2ContactRegister for the realism rationale.
//
// Filtered out under MINE for the same reason ambient garrisons are: that view
// means "the player's own assets".
//
// Age is computed client-side from the recorded serverTime so the marker can
// fade and label its own staleness without the server rebroadcasting.
if (!_filterMine) then {
    private _contacts = missionNamespace getVariable ["DSC_c2Contacts", []];
    {
        private _c   = _x;
        private _grp = _c getOrDefault ["group", grpNull];
        private _pos = _c getOrDefault ["position", []];
        if (_pos isNotEqualTo []) then {
            private _src = _c getOrDefault ["source", "SIGINT"];
            private _age = serverTime - (_c getOrDefault ["time", 0]);

            // Client-side expiry mirrors the server TTLs so a fix disappears
            // on time even between snapshot writes.
            private _ttl = [240, 90] select (_src isEqualTo "VISUAL");
            if (_age <= _ttl) then {
                private _lbl = _c getOrDefault ["label", ""];
                if (_lbl isEqualTo "") then { _lbl = "UNKNOWN" };

                _result pushBack (createHashMapFromArray [
                    ["id",            format ["contact_%1", _grp]],
                    ["category",      "hostile"],
                    ["iconType",      "hostile"],
                    ["group",         _grp],
                    ["vehicle",       _c getOrDefault ["vehicle", objNull]],
                    ["position",      _pos],
                    ["dir",           0],
                    ["side",          _c getOrDefault ["side", east]],
                    ["faction",       ""],
                    ["label",         _lbl],
                    ["strength",      _c getOrDefault ["strength", 0]],
                    ["commandable",   false],
                    ["contactSource", _src],
                    ["contactAge",    _age]
                ]);
            };
        };
    } forEach _contacts;
};

_result
