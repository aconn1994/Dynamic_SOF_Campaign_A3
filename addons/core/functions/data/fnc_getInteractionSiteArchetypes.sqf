#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_getInteractionSiteArchetypes
 * Description:
 *     Returns the interaction-site archetype registry (session 5,
 *     `docs/campaign_overhaul/session_05_interaction_site.md` §5). Same
 *     shape family as `fnc_getObjectArchetypes` — the raid generator
 *     resolves a spec's "archetype" name here to fill in the site's
 *     action text, duration, tangibility, and the token-context template
 *     consumed by `fnc_interactionSiteOnCompleteIntel` via
 *     `fnc_buildIntelTokenFromSite`.
 *
 *     Field reference:
 *       "action"       <STRING>   Default action menu text.
 *       "duration"     <ARRAY>    Default [min,max] hold seconds.
 *       "tangibility"  <STRING>   Default tangibility tier ("abstract" |
 *                                 "focalProp" | "composition").
 *       "tokenContext" <HASHMAP>  Partial intel token template consumed by
 *                                 fnc_buildIntelTokenFromSite (type/source/
 *                                 confidence/scope defaults).
 *
 * Arguments: None
 *
 * Return Value:
 *     <HASHMAP> - Archetype name -> archetype hashmap.
 *
 * Example:
 *     private _archetypes = call DSC_core_fnc_getInteractionSiteArchetypes;
 *     private _sse = _archetypes get "SSE_INTEL";
 */

createHashMapFromArray [

    ["SSE_INTEL", createHashMapFromArray [
        ["action", "Conduct SSE"],
        ["duration", [20, 60]],
        ["tangibility", "abstract"],
        ["tokenContext", createHashMapFromArray [
            ["type", "HVT_LOCATION"],
            ["source", "SSE"],
            ["confidence", 0.6],
            ["scope", "LOCATION"]
        ]]
    ]],

    ["SUPPLY_DESTROY_SITE", createHashMapFromArray [
        ["action", "Verify Destruction"],
        ["duration", [15, 30]],
        ["tangibility", "abstract"],
        ["tokenContext", createHashMapFromArray [
            ["type", "ENEMY_STRENGTH"],
            ["source", "SSE"],
            ["confidence", 0.5],
            ["scope", "LOCATION"]
        ]]
    ]],

    ["CACHE_VERIFY", createHashMapFromArray [
        ["action", "Search Cache"],
        ["duration", [20, 40]],
        ["tangibility", "abstract"],
        ["tokenContext", createHashMapFromArray [
            ["type", "CACHE_LOCATION"],
            ["source", "SSE"],
            ["confidence", 0.55],
            ["scope", "AREA"]
        ]]
    ]],

    ["SABOTAGE_SITE", createHashMapFromArray [
        ["action", "Sabotage Equipment"],
        ["duration", [20, 45]],
        ["tangibility", "abstract"],
        ["tokenContext", createHashMapFromArray [
            ["type", "TACTICAL_ADVANTAGE"],
            ["source", "SSE"],
            ["confidence", 0.5],
            ["scope", "LOCATION"]
        ]]
    ]]
]
