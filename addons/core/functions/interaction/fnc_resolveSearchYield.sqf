#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_resolveSearchYield
 * Description:
 *     PURE. Resolves the intel scope/confidence yielded by searching a
 *     dead group, for the universal "Search" hook (§4.3 #2 / §13.4 of the
 *     session 5 spec). A random patrol yields a low-confidence AREA token;
 *     a group matching the currently active narrative thread's subject
 *     faction role yields a higher-confidence SERIES token.
 *
 *     No globals read — the caller resolves both faction role strings
 *     before calling this.
 *
 * Arguments:
 *     0: _victimFactionRole <STRING> - The dead group's resolved faction
 *        role (e.g. "opFor", "irregulars"). "" if unresolved.
 *     1: _activeSeriesFactionRole <STRING> - The active narrative thread's
 *        subject faction role. "" if no active series/thread.
 *
 * Return Value:
 *     <HASHMAP>:
 *        "scope"      <STRING> - "SERIES" | "AREA"
 *        "confidence" <NUMBER> - 0..1
 *
 * Example:
 *     private _yield = ["opFor", "opFor"] call DSC_core_fnc_resolveSearchYield;
 *     // -> scope: "SERIES", confidence: 0.65
 */

params [
    ["_victimFactionRole", "", [""]],
    ["_activeSeriesFactionRole", "", [""]]
];

private _match = (_victimFactionRole != "")
    && {_activeSeriesFactionRole != ""}
    && {_victimFactionRole == _activeSeriesFactionRole};

private _areaYield = createHashMapFromArray [
    ["scope", "AREA"],
    ["confidence", 0.25]
];
private _seriesYield = createHashMapFromArray [
    ["scope", "SERIES"],
    ["confidence", 0.65]
];

[_areaYield, _seriesYield] select _match
