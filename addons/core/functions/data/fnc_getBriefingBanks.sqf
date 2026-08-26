#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_getBriefingBanks
 * Description:
 *     Returns the sectioned briefing sentence-bank registry consumed by
 *     fnc_composeBriefing (Campaign Overhaul Session 4,
 *     .crush/campaign-overhaul.md §6.1/§6.2). Wraps the existing
 *     fnc_getBriefingFragments registry (titlePrefix/objective/roe/taskIcon)
 *     into the five-section shape (SITUATION/MISSION/EXECUTION/INTEL/
 *     SUPPORT), further keyed by unit voice. The fragments file remains the
 *     single source of truth for mission-type-specific copy; this function
 *     only adds structure on top of it.
 *
 *     "missionType" here is the existing briefingArchetype identifier (e.g.
 *     "raid_kill_capture") — every key already present in
 *     fnc_getBriefingFragments gets a bank entry, so new archetypes pick up
 *     the section shape automatically with zero edits to this file.
 *
 *     PARITY NOTE (Session 4): exactly one voice ("GENERIC") is seeded.
 *     Each section pool holds a single phrasing, so selectRandom is a
 *     no-op today — the composed body must match fnc_createMissionBriefing's
 *     pre-refactor output byte-for-byte for the four live mission types
 *     (KILL_CAPTURE -> raid_kill_capture, SUPPLY_DESTROY ->
 *     raid_supply_destroy, INTEL_GATHER -> raid_intel_gather,
 *     HOSTAGE_RESCUE -> raid_hostage_rescue). Future sessions add
 *     phrasings/voices without touching fnc_composeBriefing. Do NOT add
 *     intel-conditioned inserts here — that is Session 7.
 *
 *     Shape:
 *         <missionType STRING> -> HASHMAP {
 *             "titlePrefix" <STRING>  - task title prefix (not a section;
 *                                       consumed directly by the caller for
 *                                       BIS_fnc_taskCreate).
 *             "taskIcon"    <STRING>  - Arma task icon classname.
 *             "voices"      <HASHMAP> - <unitVoice STRING> -> HASHMAP {
 *                 "situation" <ARRAY of STRING> - phrasing pool. Slots:
 *                                                 %locationName
 *                                                 %relativeDesc %areaDesc
 *                                                 %strengthEstimate
 *                 "mission"   <ARRAY of STRING> - phrasing pool (the
 *                                                 objective statement, no
 *                                                 runtime slots today)
 *                 "execution" <ARRAY of STRING> - phrasing pool (rules of
 *                                                 engagement, no runtime
 *                                                 slots today)
 *                 "intel"     <ARRAY of STRING> - phrasing pool. Slots:
 *                                                 %targetBlock
 *                                                 %garrisonEstimate
 *                                                 %patrolEstimate
 *                                                 %threatText
 *                 "support"   <ARRAY of STRING> - phrasing pool (empty
 *                                                 string today — no
 *                                                 deployment.supportAssets
 *                                                 model exists yet)
 *             }
 *         }
 *
 * Arguments: None
 *
 * Return Value:
 *     <HASHMAP> - missionType (briefingArchetype) -> bank entry (see shape
 *                 above).
 */

private _fragments = call DSC_core_fnc_getBriefingFragments;

// Shared across every mission type/voice today — the runtime-computed
// location/threat data was never mission-type-specific before this
// refactor, so parity requires identical phrasing here regardless of
// missionType.
private _situationTemplate = "<t font='PuristaBold'>LOCATION:</t> %locationName, %relativeDesc.<br/><br/><t font='PuristaBold'>AREA:</t> Operating from a %areaDesc, %strengthEstimate.<br/><br/>";
private _intelTemplate = "%targetBlock<t font='PuristaBold'>INTEL:</t><br/>- %garrisonEstimate<br/>- %patrolEstimate<br/><br/><t font='PuristaBold'>THREATS:</t><br/>%threatText<br/><br/>";
private _supportTemplate = "";

private _banks = createHashMap;

{
    private _archetypeKey = _x;
    private _fragment = _fragments get _archetypeKey;

    private _titlePrefix = _fragment getOrDefault ["titlePrefix", "Mission"];
    private _objective = _fragment getOrDefault ["objective", "Proceed to the area of operations and assess."];
    private _roe = _fragment getOrDefault ["roe", "Exercise caution and report findings."];
    private _taskIcon = _fragment getOrDefault ["taskIcon", "run"];

    private _missionTemplate = format ["<t font='PuristaBold'>OBJECTIVE:</t> %1<br/><br/>", _objective];
    private _executionTemplate = format ["<t font='PuristaBold'>RULES OF ENGAGEMENT:</t> %1", _roe];

    private _genericVoice = createHashMapFromArray [
        ["situation", [_situationTemplate]],
        ["mission", [_missionTemplate]],
        ["execution", [_executionTemplate]],
        ["intel", [_intelTemplate]],
        ["support", [_supportTemplate]]
    ];

    private _entry = createHashMapFromArray [
        ["titlePrefix", _titlePrefix],
        ["taskIcon", _taskIcon],
        ["voices", createHashMapFromArray [
            ["GENERIC", _genericVoice]
        ]]
    ];

    _banks set [_archetypeKey, _entry];
} forEach (keys _fragments);

_banks
