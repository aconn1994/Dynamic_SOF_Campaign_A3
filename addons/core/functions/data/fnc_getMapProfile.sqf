#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_getMapProfile
 * Description:
 *     Returns the per-world map profile — Ambient World Overhaul Session 03,
 *     docs/overhauls/ambient_world/session_03_map_profile.md "Approved
 *     Mini-Spec" §A2-§A5. One table carrying region identity, civilian/
 *     police/host-nation faction casting, and a climate stub, so Sessions
 *     04/09/11 all read from the same source instead of three drifting
 *     tables keyed on worldName.
 *
 *     Pure given an explicit world name — the only missionNamespace touches
 *     are the profile cache and the unknown-world warn-dedup map, and the
 *     only engine read is the _worldName default argument. Total: every
 *     input returns a well-formed profile, an unrecognized world degrades to
 *     the generic fallback plus one WARNING, never nil, never an error.
 *
 *     NO CONSUMERS as of this session. Session 04 is the first reader;
 *     Session 09 owns the faction-casting wiring.
 *
 * Arguments:
 *     0: _worldName <STRING> - World to resolve. Default: worldName.
 *     1: _rebuild   <BOOL>   - Discard the cache and recompute. Default false.
 *
 * Return Value:
 *     <HASHMAP> - Never nil, never empty. Schema (§A3):
 *       "world"              <STRING>  The worldName key (requested name on fallback).
 *       "displayName"        <STRING>  Human name, never "".
 *       "realWorldAnalogue"  <STRING>  "" is legal.
 *       "region"             <STRING>  Fixed vocabulary (see below).
 *       "hemisphere"         <STRING>  "north" | "south".
 *       "latitude"           <NUMBER>  Real-world degrees, positive = north.
 *       "civilianFactions"   <ARRAY>   Non-empty array of STRING.
 *       "policeFaction"      <STRING>  "" this session. // TBD Session 09
 *       "hostNationFaction"  <STRING>  "" this session. // TBD Session 09
 *       "architecture"       <STRING>  Fixed vocabulary (see below).
 *       "languageHint"       <STRING>  "" is legal.
 *       "isFallback"         <BOOL>    true only on the generic profile.
 *       "isSynthetic"        <BOOL>    true only for VR.
 *       "climate"            <HASHMAP> ["band", <STRING>], ["stub", true].
 *
 *     Region vocabulary: mediterranean, tropical, temperate_continental,
 *     temperate, arid, synthetic.
 *     Architecture vocabulary: mediterranean, tropical_colonial,
 *     eastern_european, generic, none.
 *
 *     The returned hashmap is the CACHED instance — read-only for callers.
 *     A consumer that mutates it poisons every later caller on that machine.
 *
 * Example:
 *     private _profile = [] call DSC_core_fnc_getMapProfile;
 *     private _region = _profile get "region";
 *
 *     private _livonia = ["Enoch"] call DSC_core_fnc_getMapProfile;
 *     // _livonia get "displayName" == "Livonia"
 */

params [
    ["_worldName", worldName, [""]],
    ["_rebuild", false, [false]]
];

if (_rebuild) then {
    missionNamespace setVariable ["DSC_mapProfileCache", createHashMap];
    missionNamespace setVariable ["DSC_mapProfileUnknownWarned", createHashMap];
};

if (isNil { missionNamespace getVariable "DSC_mapProfileCache" }) then {
    missionNamespace setVariable ["DSC_mapProfileCache", createHashMap];
};
if (isNil { missionNamespace getVariable "DSC_mapProfileUnknownWarned" }) then {
    missionNamespace setVariable ["DSC_mapProfileUnknownWarned", createHashMap];
};

private _cache = missionNamespace getVariable ["DSC_mapProfileCache", createHashMap];
private _key = toLower _worldName;

if (_key in _cache) exitWith { _cache get _key };

// ============================================================================
// Authored table (§A4) — transcribed verbatim. Seven rows: five shipped maps,
// the test world, and the fallback template. Every row shares
// civilianFactions = ["CIV_F"] (§A9 item 3 - the only verified civilian
// faction classname in this repo), policeFaction/hostNationFaction = ""
// (// TBD Session 09), and a fresh climate stub hashmap.
// ============================================================================
private _table = createHashMapFromArray [

    ["altis", createHashMapFromArray [
        ["world", "Altis"],
        ["displayName", "Altis"],
        ["realWorldAnalogue", "Lemnos, Greece"],
        ["region", "mediterranean"],
        ["hemisphere", "north"],
        ["latitude", 39.9],
        ["civilianFactions", ["CIV_F"]],
        ["policeFaction", ""], // TBD Session 09
        ["hostNationFaction", ""], // TBD Session 09
        ["architecture", "mediterranean"],
        ["languageHint", "greek"],
        ["isFallback", false],
        ["isSynthetic", false],
        ["climate", createHashMapFromArray [["band", "mediterranean"], ["stub", true]]]
    ]],

    ["stratis", createHashMapFromArray [
        ["world", "Stratis"],
        ["displayName", "Stratis"],
        ["realWorldAnalogue", "Agios Efstratios, Greece"],
        ["region", "mediterranean"],
        ["hemisphere", "north"],
        ["latitude", 39.5],
        ["civilianFactions", ["CIV_F"]],
        ["policeFaction", ""], // TBD Session 09
        ["hostNationFaction", ""], // TBD Session 09
        ["architecture", "mediterranean"],
        ["languageHint", "greek"],
        ["isFallback", false],
        ["isSynthetic", false],
        ["climate", createHashMapFromArray [["band", "mediterranean"], ["stub", true]]]
    ]],

    ["malden", createHashMapFromArray [
        ["world", "Malden"],
        ["displayName", "Malden"],
        ["realWorldAnalogue", "Fictional Mediterranean island (Malden 2035)"],
        ["region", "mediterranean"],
        ["hemisphere", "north"],
        ["latitude", 42.0], // REVIEW (§A9 #1) - no canonical real-world coordinate, authored approximation
        ["civilianFactions", ["CIV_F"]],
        ["policeFaction", ""], // TBD Session 09
        ["hostNationFaction", ""], // TBD Session 09
        ["architecture", "mediterranean"],
        ["languageHint", "french"],
        ["isFallback", false],
        ["isSynthetic", false],
        ["climate", createHashMapFromArray [["band", "mediterranean"], ["stub", true]]]
    ]],

    ["tanoa", createHashMapFromArray [
        ["world", "Tanoa"],
        ["displayName", "Tanoa"],
        ["realWorldAnalogue", "Horizon Islands, South Pacific (Fiji/Vanuatu analogue)"],
        ["region", "tropical"],
        ["hemisphere", "south"],
        ["latitude", -17.6], // REVIEW (§A9 #2) - canonical Horizon Islands placement, not a config read
        ["civilianFactions", ["CIV_F"]],
        ["policeFaction", ""], // TBD Session 09
        ["hostNationFaction", ""], // TBD Session 09
        ["architecture", "tropical_colonial"],
        ["languageHint", "french"],
        ["isFallback", false],
        ["isSynthetic", false],
        ["climate", createHashMapFromArray [["band", "tropical"], ["stub", true]]]
    ]],

    ["enoch", createHashMapFromArray [
        ["world", "Enoch"],
        ["displayName", "Livonia"],
        ["realWorldAnalogue", "Eastern Poland / Belarus border"],
        ["region", "temperate_continental"],
        ["hemisphere", "north"],
        ["latitude", 52.1],
        ["civilianFactions", ["CIV_F"]],
        ["policeFaction", ""], // TBD Session 09
        ["hostNationFaction", ""], // TBD Session 09
        ["architecture", "eastern_european"],
        ["languageHint", "polish"],
        ["isFallback", false],
        ["isSynthetic", false],
        ["climate", createHashMapFromArray [["band", "continental"], ["stub", true]]]
    ]],

    ["vr", createHashMapFromArray [
        ["world", "VR"],
        ["displayName", "Virtual Reality"],
        ["realWorldAnalogue", ""],
        ["region", "synthetic"],
        ["hemisphere", "north"],
        ["latitude", 0],
        ["civilianFactions", ["CIV_F"]],
        ["policeFaction", ""], // TBD Session 09
        ["hostNationFaction", ""], // TBD Session 09
        ["architecture", "none"],
        ["languageHint", ""],
        ["isFallback", false],
        ["isSynthetic", true],
        ["climate", createHashMapFromArray [["band", "none"], ["stub", true]]]
    ]],

    ["__generic__", createHashMapFromArray [
        ["world", "__GENERIC__"],
        ["displayName", "__GENERIC__"],
        ["realWorldAnalogue", ""],
        ["region", "temperate"],
        ["hemisphere", "north"],
        ["latitude", 45.0],
        ["civilianFactions", ["CIV_F"]],
        ["policeFaction", ""], // TBD Session 09
        ["hostNationFaction", ""], // TBD Session 09
        ["architecture", "generic"],
        ["languageHint", ""],
        ["isFallback", true],
        ["isSynthetic", false],
        ["climate", createHashMapFromArray [["band", "temperate"], ["stub", true]]]
    ]]
];

// ============================================================================
// Resolution (§A5) - case-insensitive lookup; authored casing wins on a hit.
// Unknown world -> generic fallback with the requested name, warn once.
// ============================================================================
if (_key in _table) exitWith {
    private _profile = _table get _key;
    private _profileWorld = _profile get "world";
    private _profileDisplay = _profile get "displayName";
    INFO_2("getMapProfile - map profile: %1 (%2)",_profileWorld,_profileDisplay);

    _cache set [_key, _profile];
    missionNamespace setVariable ["DSC_mapProfileCache", _cache];
    _profile
};

private _warned = missionNamespace getVariable ["DSC_mapProfileUnknownWarned", createHashMap];

if !(_key in _warned) then {
    WARNING_1("getMapProfile - unknown world '%1', returning generic fallback profile",_worldName);
    _warned set [_key, true];
    missionNamespace setVariable ["DSC_mapProfileUnknownWarned", _warned];
};

private _fallback = +(_table get "__generic__");
_fallback set ["world", _worldName];
_fallback set ["displayName", _worldName];

_cache set [_key, _fallback];
missionNamespace setVariable ["DSC_mapProfileCache", _cache];

_fallback
