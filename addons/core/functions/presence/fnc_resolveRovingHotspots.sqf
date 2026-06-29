#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_resolveRovingHotspots
 * Description:
 *     Builds the hotspot registry used by the roving manager for air density
 *     biasing and ground patrol seeding. Hotspots are points where rover
 *     spawns are more likely and that act as plausible "origin / destination"
 *     pairs for transit-style flight paths.
 *
 *     Three hotspot tiers:
 *       - "airbase"   weight 4   (player_base_<N> markers — they are airfields,
 *                                 sided to bluFor / west by default)
 *       - "base"      weight 3   (military bases from influence data)
 *       - "outpost"   weight 1.5 (military outposts from influence data)
 *
 *     Each hotspot carries `side` (east/west) derived from the controlling
 *     faction via factionData. Hotspots with `neutral` or `contested` control
 *     are skipped — Phase 1 air only spawns from clearly opFor or bluFor sources.
 *
 *     Hotspot schema:
 *       "id"        <STRING>  - source id (locId or marker name)
 *       "type"      <STRING>  - "airbase" | "base" | "outpost"
 *       "position"  <ARRAY>   - [x, y, z]
 *       "side"      <SIDE>    - east | west
 *       "weight"    <NUMBER>  - density multiplier
 *       "influence" <NUMBER>  - 0..1 (1.0 for airbase markers)
 *
 * Arguments:
 *     0: _influenceData <HASHMAP> - from fnc_initInfluence
 *     1: _factionData   <HASHMAP> - from fnc_initFactionData
 *
 * Return Value:
 *     <HASHMAP> with keys:
 *       "all"  <ARRAY> all hotspots
 *       "east" <ARRAY> hotspots aligned with east side
 *       "west" <ARRAY> hotspots aligned with west side
 *
 * Example:
 *     private _hs = [_influenceData, _factionData] call DSC_core_fnc_resolveRovingHotspots;
 */

params [
    ["_influenceData", createHashMap, [createHashMap]],
    ["_factionData",   createHashMap, [createHashMap]]
];

private _result = createHashMapFromArray [["all", []], ["east", []], ["west", []]];

if (_influenceData isEqualTo createHashMap) exitWith {
    ERROR("resolveRovingHotspots - No influence data");
    _result
};

// Build faction -> side lookup from factionData. We only care about opFor /
// bluFor; partners/irregulars are folded into the closest top-tier side for
// hotspot purposes (opForPartner -> east, bluForPartner -> nearest of east/west).
private _factionToSide = createHashMap;
{
    private _role = _x;
    private _roleData = _y;
    private _side = _roleData getOrDefault ["side", civilian];
    {
        _factionToSide set [_x, _side];
    } forEach (_roleData getOrDefault ["factions", []]);
} forEach _factionData;

// Top-level side resolver — used when a location's controlling faction isn't
// directly in the lookup (orphan locations, dropped mods).
private _opForSide = ((_factionData getOrDefault ["opFor", createHashMap]) getOrDefault ["side", east]);
private _bluForSide = ((_factionData getOrDefault ["bluFor", createHashMap]) getOrDefault ["side", west]);

private _addHotspot = {
    params ["_id", "_type", "_pos", "_side", "_weight", "_influence"];
    private _hs = createHashMapFromArray [
        ["id",        _id],
        ["type",      _type],
        ["position",  _pos],
        ["side",      _side],
        ["weight",    _weight],
        ["influence", _influence]
    ];
    (_result get "all") pushBack _hs;
    if (_side isEqualTo east) then { (_result get "east") pushBack _hs };
    if (_side isEqualTo west) then { (_result get "west") pushBack _hs };
};

// ============================================================================
// Tier 1: airbases (player_base_<N> markers)
// ============================================================================
// These are 3den-placed by the mission designer. They are airfields and the
// player's main FOB sits on one. Sided to bluFor (west) by default — players
// fly from here, and we want ambient west air traffic biased toward them.
{
    private _markerName = _x;
    if ((toLower _markerName) find "player_base_" == 0 && {markerShape _markerName != ""}) then {
        private _pos = getMarkerPos _markerName;
        [_markerName, "airbase", _pos, _bluForSide, 4.0, 1.0] call _addHotspot;
    };
} forEach allMapMarkers;

// ============================================================================
// Tier 2 + 3: bases + outposts from influence data
// ============================================================================
private _influenceMap = _influenceData getOrDefault ["influenceMap", createHashMap];
private _bases    = _influenceData getOrDefault ["bases", []];
private _outposts = _influenceData getOrDefault ["outposts", []];

private _registerInstallation = {
    params ["_loc", "_type", "_weight"];
    private _locId = _loc get "id";
    private _locPos = _loc get "position";
    private _inf = _influenceMap getOrDefault [_locId, createHashMap];
    private _controlledBy = _inf getOrDefault ["controlledBy", "neutral"];
    private _faction = _inf getOrDefault ["faction", ""];
    private _influence = _inf getOrDefault ["influence", 0];

    // Phase 1: only clearly opFor / bluFor installations spawn air.
    // Contested / neutral skipped — ambiguous side ownership produces
    // wrong-side spawns and player confusion.
    if !(_controlledBy in ["opFor", "bluFor"]) exitWith {};

    private _side = _factionToSide getOrDefault [_faction, [_bluForSide, _opForSide] select (_controlledBy == "opFor")];
    [_locId, _type, _locPos, _side, _weight, _influence] call _addHotspot;
};

{ [_x, "base",    3.0] call _registerInstallation } forEach _bases;
{ [_x, "outpost", 1.5] call _registerInstallation } forEach _outposts;

INFO_3("rovingHotspots - %1 total (east=%2 west=%3)",count (_result get "all"),count (_result get "east"),count (_result get "west"));

_result
