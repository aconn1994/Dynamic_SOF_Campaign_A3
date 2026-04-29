#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_getEntityArchetypes
 * Description:
 *     Returns the entity archetype registry. Entity archetypes describe
 *     human-shaped mission targets/objects (HVTs, hostages, informants) as
 *     pure data: how to resolve their classname, where to place them, how
 *     they behave, and what the briefing should say about them.
 *
 *     The raid generator consumes archetypes by name. Adding a new HVT
 *     variant is a content task — append a hashmap entry here.
 *
 *     Archetype Fields:
 *       "unitClassResolver" <STRING>  Resolver key consumed by
 *                                     fnc_resolveEntityClass. Either a
 *                                     well-known key ("officer", "civilian",
 *                                     "civilian_suit", "civilian_labcoat")
 *                                     or a literal classname.
 *       "placement"         <STRING>  Placement strategy key (currently
 *                                     "DEEP_BUILDING"; future: "GROUND_SIT",
 *                                     "GROUND_KNEEL", ...).
 *       "hasBodyguards"     <BOOL>    Hint to placement strategy.
 *       "fleeable"          <BOOL>    May trigger scripted escape behavior.
 *       "surrenderable"     <BOOL>    May surrender if cornered.
 *       "behavior"          <STRING>  "default" | "captive" | ...
 *                                     "captive" applies setCaptive + disableAI.
 *       "attachment"        <STRING>  Optional special attachment hook
 *                                     (e.g. "suicide_vest", "blindfold").
 *                                     Resolved by future attachment system.
 *       "animation"         <STRING>  Optional looping anim classname.
 *       "briefingTitle"     <STRING>  Short title for briefing fragment.
 *       "briefingDesc"      <STRING>  Description for briefing fragment.
 *
 * Arguments: None
 *
 * Return Value:
 *     <HASHMAP> - Archetype name -> archetype hashmap.
 *
 * Example:
 *     private _archetypes = call DSC_core_fnc_getEntityArchetypes;
 *     private _bombmaker = _archetypes get "BOMBMAKER";
 */

createHashMapFromArray [

    // === HVT Variants ===
    ["OFFICER", createHashMapFromArray [
        ["unitClassResolver", "officer"],
        ["placement", "DEEP_BUILDING"],
        ["hasBodyguards", true],
        ["fleeable", true],
        ["surrenderable", true],
        ["behavior", "default"],
        ["briefingTitle", "Enemy Commander"],
        ["briefingDesc", "A senior officer coordinating local operations."]
    ]],

    ["BOMBMAKER", createHashMapFromArray [
        ["unitClassResolver", "civilian_suit"],
        ["placement", "DEEP_BUILDING"],
        ["hasBodyguards", true],
        ["fleeable", false],
        ["surrenderable", false],
        ["behavior", "default"],
        ["attachment", "suicide_vest"],
        ["briefingTitle", "IED Facilitator"],
        ["briefingDesc", "Builds devices for the cell. Approach with caution — possible suicide vest."]
    ]],

    // === Civilian Variants ===
    ["HOSTAGE", createHashMapFromArray [
        ["unitClassResolver", "civilian"],
        ["placement", "GROUND_SIT"],
        ["hasBodyguards", false],
        ["fleeable", false],
        ["surrenderable", false],
        ["behavior", "captive"],
        ["attachment", "blindfold"],
        ["animation", "Acts_AidlPercMstpSnonWnonDnon01"],
        ["briefingTitle", "Hostage"],
        ["briefingDesc", "Confirmed PID. Extract alive."]
    ]]
]
