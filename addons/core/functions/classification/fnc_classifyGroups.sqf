#include "script_component.hpp"

/*
 * Classify all groups from a faction extraction.
 * 
 * Takes the output of fnc_extractGroups and classifies each group,
 * returning an array of enriched group data with doctrine tags.
 * 
 * Arguments:
 *   0: Array of group data hashmaps from fnc_extractGroups <ARRAY>
 * 
 * Returns:
 *   Array of enriched group hashmaps with doctrine tags
 * 
 * Example:
 *   private _groups = ["rhs_faction_msv"] call DSC_core_fnc_extractGroups;
 *   private _classified = [_groups] call DSC_core_fnc_classifyGroups;
 */

params ["_groups"];

private _result = [];

{
    private _classifiedGroup = [_x] call DSC_core_fnc_classifyGroup;
    _result pushBack _classifiedGroup;
} forEach _groups;

// Log summary
private _tagCounts = createHashMap;
{
    private _tags = _x get "doctrineTags";
    {
        private _count = _tagCounts getOrDefault [_x, 0];
        _tagCounts set [_x, _count + 1];
    } forEach _tags;
} forEach _result;

TRACE_1("Classified groups: ",count _result);
TRACE_1("Tag distribution: ",_tagCounts);

_result
