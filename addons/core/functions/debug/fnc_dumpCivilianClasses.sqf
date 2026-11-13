#include "script_component.hpp"
/*
 * Function: DSC_core_fnc_dumpCivilianClasses
 * Description:
 *     AUTHORING TOOL — Ambient World Overhaul Session 04.
 *
 *     Dumps every person class the current mod load actually provides, so the
 *     hardcoded civilian class tables can be authored from ground truth
 *     instead of from memory. A guessed classname in a keyword list was free
 *     (it simply never matched); a guessed classname in a hardcoded allowlist
 *     is a silently missing archetype. This function is how that risk is
 *     removed.
 *
 *     Run it once per mod preset. Paste the output back into the session doc
 *     and the tables get authored with zero guesses. It is NOT part of any
 *     runtime path — nothing calls it, and it is safe to leave PREP'd.
 *
 *     Columns dumped, and why each one is worth having:
 *
 *       CLASS         The thing being mapped.
 *       DISPLAY       Human-readable name. Usually the single best signal for
 *                     an archetype ("Fisherman", "Priest", "Doctor").
 *       SIDE          Config side number (3 = civilian). Anything non-3 in a
 *                     civilian faction is exactly the VR/hologram/placeholder
 *                     class the strict allowlist exists to exclude.
 *       GENERICNAMES  e.g. "GreekMen" / "AfricanMen" / "TanoanMen". THE field
 *                     for regional casting — it is how BI itself tags the
 *                     ethnic variants, and it is far more reliable than
 *                     reading "_afro"/"_asia" out of a classname.
 *       IDENTITY      identityTypes[], e.g. "Head_Greek","LanguageGRE_F".
 *                     Second regional signal; also carries the spoken
 *                     language, which matters for the Session 09 host-nation
 *                     work.
 *       EDITORSUBCAT  Mod-dependent quality (RHS good, others poor) but free
 *                     to read and occasionally does the archetype grouping
 *                     for us.
 *       VEHCLASS      vehicleClass, the Eden/3den grouping.
 *
 *     Output goes to raw `diag_log` with a `DSCDUMP` prefix rather than the
 *     CBA macros, deliberately and for the same reason `fnc_diagSideDump`
 *     does it: this must appear regardless of the configured debug tier, and
 *     `DSCDUMP` greps cleanly out of a very noisy RPT. This is an authoring
 *     tool, not instrumentation.
 *
 *     It also copies the full dump to the clipboard by default, which is the
 *     actually-useful path — the RPT copy is the backup when the dump is
 *     large enough that the clipboard truncates.
 *
 * Arguments:
 *     0: _factions  <ARRAY>  - Faction classnames to dump. [] (default) means
 *                              "auto-detect": every faction that has at least
 *                              one civilian-side (side == 3) person class.
 *                              Pass explicit factions to dump a non-civilian
 *                              faction (e.g. a contractor faction authored on
 *                              independent).
 *     1: _includeAll <BOOL>  - false (default): only person classes whose
 *                              config side is civilian are auto-detected.
 *                              true: dump every person class of every faction
 *                              regardless of side. Large. Use when hunting a
 *                              faction whose civilians are miscast.
 *     2: _toClipboard <BOOL> - Copy the dump to the clipboard. Default true.
 *
 * Return Value:
 *     <HASHMAP> - faction <STRING> -> ARRAY of [class, display, side,
 *                 genericNames, identityTypes, editorSubcategory,
 *                 vehicleClass]. Returned so it can be post-processed in the
 *                 debug console without re-running the config walk.
 *
 * Example:
 *     // Everything civilian the current preset provides:
 *     [] call DSC_core_fnc_dumpCivilianClasses;
 *
 *     // One specific faction, including non-civilian-side members:
 *     [["IDAP"], true] call DSC_core_fnc_dumpCivilianClasses;
 */

params [
    ["_factions", [], [[]]],
    ["_includeAll", false, [false]],
    ["_toClipboard", true, [false]]
];

private _explicit = _factions isNotEqualTo [];

// ============================================================================
// One config walk. Every person class in the loaded preset, scope >= 2.
// ============================================================================
private _cfgVehicles = configFile >> "CfgVehicles";
private _filter = "getNumber (_x >> 'scope') >= 2 && getNumber (_x >> 'isMan') == 1";
private _allMen = _filter configClasses _cfgVehicles;

private _byFaction = createHashMap;
private _skippedBySide = 0;
private _skippedByFaction = 0;

{
    private _cfg = _x;
    private _class = configName _cfg;
    private _faction = getText (_cfg >> "faction");
    private _side = getNumber (_cfg >> "side");

    private _wanted = if (_explicit) then {
        _faction in _factions
    } else {
        _includeAll || { _side isEqualTo 3 }
    };

    if (!_wanted) then {
        if (_explicit) then { _skippedByFaction = _skippedByFaction + 1 }
        else { _skippedBySide = _skippedBySide + 1 };
        continue
    };

    private _identity = getArray (_cfg >> "identityTypes");

    private _entry = [
        _class,
        getText (_cfg >> "displayName"),
        _side,
        getText (_cfg >> "genericNames"),
        _identity joinString ",",
        getText (_cfg >> "editorSubcategory"),
        getText (_cfg >> "vehicleClass")
    ];

    private _list = _byFaction getOrDefault [_faction, []];
    _list pushBack _entry;
    _byFaction set [_faction, _list];

} forEach _allMen;

// ============================================================================
// Emit. Sorted by faction, then classname, so two dumps of the same preset
// diff cleanly and a re-run after adding a mod shows only the new rows.
// ============================================================================
private _lines = [];
_lines pushBack "DSCDUMP ============================================================";
_lines pushBack format [
    "DSCDUMP civilian class dump | world=%1 | mode=%2",
    worldName,
    (["auto-civilian", "explicit-factions"] select _explicit)
];
_lines pushBack "DSCDUMP CLASS | DISPLAY | SIDE | GENERICNAMES | IDENTITY | EDITORSUBCAT | VEHCLASS";
_lines pushBack "DSCDUMP ============================================================";

private _factionKeys = (keys _byFaction) call BIS_fnc_sortAlphabetically;
if (_factionKeys isEqualTo []) then { _factionKeys = keys _byFaction };

private _totalClasses = 0;

{
    private _faction = _x;
    private _entries = _byFaction get _faction;
    _entries sort true; // by classname, the first element
    _totalClasses = _totalClasses + (count _entries);

    private _factionName = getText (configFile >> "CfgFactionClasses" >> _faction >> "displayName");
    private _entryCount = count _entries;

    _lines pushBack "DSCDUMP";
    _lines pushBack format [
        "DSCDUMP --- FACTION: %1 (%2) | %3 classes ---",
        _faction,
        (["<not in CfgFactionClasses>", _factionName] select (_factionName isNotEqualTo "")),
        _entryCount
    ];

    {
        _x params ["_class", "_display", "_side", "_generic", "_ident", "_subcat", "_vehClass"];
        _lines pushBack format [
            "DSCDUMP %1 | %2 | %3 | %4 | %5 | %6 | %7",
            _class, _display, _side, _generic, _ident, _subcat, _vehClass
        ];
    } forEach _entries;

} forEach _factionKeys;

private _factionCount = count _factionKeys;

_lines pushBack "DSCDUMP";
_lines pushBack "DSCDUMP ============================================================";
_lines pushBack format [
    "DSCDUMP TOTAL: %1 classes across %2 factions (skipped: %3 non-civilian-side, %4 other-faction)",
    _totalClasses, _factionCount, _skippedBySide, _skippedByFaction
];
_lines pushBack "DSCDUMP ============================================================";

{ diag_log _x } forEach _lines;

if (_toClipboard) then {
    copyToClipboard (_lines joinString endl);
    diag_log "DSCDUMP (dump copied to clipboard)";
};

_byFaction
