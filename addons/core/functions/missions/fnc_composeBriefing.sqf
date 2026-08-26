#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_composeBriefing
 * Description:
 *     Composes the briefing body (SITUATION/MISSION/EXECUTION/INTEL/SUPPORT,
 *     .crush/campaign-overhaul.md §6.1) from a context hashmap, pulling
 *     phrasing from fnc_getBriefingBanks and interpolating named %slot
 *     placeholders. This is the single seam so a future optional LLM/DLL
 *     path can replace the sentence-bank composer without touching any
 *     caller (§6.4) — pure `context -> string`, no global reads, no
 *     spawning, fully Tier-1 testable with a mock context.
 *
 *     PARITY (Campaign Overhaul Session 4): with today's single-phrasing
 *     banks this reproduces fnc_createMissionBriefing's pre-refactor output
 *     byte-for-byte. The join order below (MISSION, SITUATION, INTEL,
 *     EXECUTION, SUPPORT) intentionally does not match the canonical
 *     SITUATION-first reading order from §6.1 — it mirrors today's onscreen
 *     layout (OBJECTIVE, then LOCATION/AREA, then TARGETS/INTEL/THREATS,
 *     then ROE) so the visible briefing text is unchanged. Section CONTENT
 *     is still bank-driven per section; only the concatenation order is
 *     legacy-shaped. Future sessions may reorder once new copy replaces the
 *     legacy layout. Intel-conditioned inserts are Session 7 — the
 *     "ledger" context key is carried through but deliberately not read
 *     here.
 *
 * Arguments:
 *     0: _context <HASHMAP> - Composition context:
 *        "missionType" <STRING>  - bank key (briefingArchetype), e.g.
 *                                  "raid_kill_capture". See
 *                                  fnc_getBriefingBanks.
 *        "unitVoice"   <STRING>  - bank sub-key (default "GENERIC").
 *        "ledger"      <HASHMAP> - intel ledger / active series handle,
 *                                  carried for future use (Session 7+), not
 *                                  read yet.
 *        "slots"       <HASHMAP> - named values used for %slot
 *                                  interpolation. Recognized keys:
 *              "locationName", "relativeDesc", "areaDesc",
 *              "strengthEstimate", "targetBlock", "garrisonEstimate",
 *              "patrolEstimate", "threatText"
 *
 * Return Value:
 *     <STRING> - HTML-formatted briefing body (same tags as before:
 *                <t font='PuristaBold'>, <br/>).
 *
 * Example:
 *     private _body = [createHashMapFromArray [
 *         ["missionType", "raid_kill_capture"],
 *         ["unitVoice", "GENERIC"],
 *         ["slots", createHashMapFromArray [["locationName", "Kavala"]]]
 *     ]] call DSC_core_fnc_composeBriefing;
 */

params [
    ["_context", createHashMap, [createHashMap]]
];

private _missionType = _context getOrDefault ["missionType", "raid_kill_capture"];
private _unitVoice = _context getOrDefault ["unitVoice", "GENERIC"];
private _slots = _context getOrDefault ["slots", createHashMap];

private _banks = call DSC_core_fnc_getBriefingBanks;
private _bankEntry = _banks getOrDefault [_missionType, createHashMap];
private _voices = _bankEntry getOrDefault ["voices", createHashMap];
private _sections = _voices getOrDefault [_unitVoice, createHashMap];

private _fnFill = {
    params ["_template", "_slotMap"];
    private _out = _template;
    {
        _out = [_out, ("%" + _x), (_slotMap get _x)] call CBA_fnc_replace;
    } forEach (keys _slotMap);
    _out
};

private _missionPool = _sections getOrDefault ["mission", [""]];
private _situationPool = _sections getOrDefault ["situation", [""]];
private _executionPool = _sections getOrDefault ["execution", [""]];
private _intelPool = _sections getOrDefault ["intel", [""]];
private _supportPool = _sections getOrDefault ["support", [""]];

private _missionText = [(selectRandom _missionPool), _slots] call _fnFill;
private _situationText = [(selectRandom _situationPool), _slots] call _fnFill;
private _intelText = [(selectRandom _intelPool), _slots] call _fnFill;
private _executionText = [(selectRandom _executionPool), _slots] call _fnFill;
private _supportText = [(selectRandom _supportPool), _slots] call _fnFill;

private _header = "<t size='1.2'>MISSION BRIEFING</t><br/><br/>";

_header + _missionText + _situationText + _intelText + _executionText + _supportText
