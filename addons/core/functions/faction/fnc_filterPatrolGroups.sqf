/*
 * Function: DSC_core_fnc_filterPatrolGroups
 * Description:
 *     Filters a list of classified foot group templates down to small recce /
 *     fireteam sized elements suitable for routine patrol presence. Used to
 *     prevent presence/mission population from pulling 7-9 man INFANTRY_SQUAD
 *     groups when a 3-4 man patrol is what the role needs.
 *
 *     Selection order:
 *       1. Groups tagged SCOUT_RECON (purpose-built recce teams)
 *       2. Groups tagged FIRETEAM (2-5 unit infantry teams)
 *       3. Fallback: the N smallest groups by member count
 *
 *     Excludes anti-armor / anti-air / special weapons teams from the
 *     primary pool — those should be passed in via the "specialGroups"
 *     config slot of fnc_setupPatrols instead.
 *
 * Arguments:
 *     0: _groupTemplates <ARRAY>   Foot group hashmaps from fnc_extractGroups
 *     1: _config         <HASHMAP> (optional)
 *        "minSize"       <NUMBER>  smallest acceptable member count (default 2)
 *        "maxSize"       <NUMBER>  largest acceptable member count (default 5)
 *        "fallbackCount" <NUMBER>  if no tag matches, return N smallest (default 5)
 *
 * Return Value:
 *     <ARRAY> - filtered group templates
 *
 * Example:
 *     private _recce = [_footGroups] call DSC_core_fnc_filterPatrolGroups;
 */

params [
    ["_groupTemplates", [], [[]]],
    ["_config", createHashMap, [createHashMap]]
];

if (_groupTemplates isEqualTo []) exitWith { [] };

private _minSize       = _config getOrDefault ["minSize", 2];
private _maxSize       = _config getOrDefault ["maxSize", 5];
private _fallbackCount = _config getOrDefault ["fallbackCount", 5];

// Reject groups that are weapons-team focused — these belong in specialGroups
private _excludeTags = ["AT_TEAM", "AA_TEAM", "MORTAR_SECTION", "WEAPONS_SQUAD",
                        "SNIPER_TEAM", "VEHICLE_CREW", "AIR_CREW"];

private _candidateTagged = _groupTemplates select {
    private _tags = _x getOrDefault ["doctrineTags", []];
    private _excluded = _excludeTags findIf {_x in _tags} != -1;
    !_excluded && {
        ("SCOUT_RECON" in _tags) || ("FIRETEAM" in _tags)
    }
};

if (_candidateTagged isNotEqualTo []) exitWith {
    // Further prefer the ones whose size falls in [_minSize, _maxSize]
    private _sized = _candidateTagged select {
        private _u = _x getOrDefault ["unitCount", -1];
        if (_u < 0) then {
            _u = count (_x getOrDefault ["units", []]);
        };
        _u <= 0 || {(_u >= _minSize) && (_u <= _maxSize)}
    };
    [_candidateTagged, _sized] select (_sized isNotEqualTo [])
};

// Fallback: pick the N smallest groups overall
private _withSize = _groupTemplates apply {
    private _u = _x getOrDefault ["unitCount", -1];
    if (_u < 0) then {
        _u = count (_x getOrDefault ["units", []]);
    };
    [_u, _x]
};
_withSize sort true;

private _picked = (_withSize select [0, _fallbackCount]) apply { _x select 1 };
_picked
