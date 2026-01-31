#include "script_component.hpp"
/*
 * Filters classified groups by doctrine tags.
 * 
 * Takes a list of classified groups and filters them based on provided tags.
 * Groups must match ALL include tags and NONE of the exclude tags.
 * 
 * Arguments:
 *   0: Array of classified group hashmaps <ARRAY>
 *   1: Array of doctrine tags to include (ALL must match) <ARRAY>
 *   2: Array of doctrine tags to exclude (NONE must match) <ARRAY> (default: [])
 * 
 * Returns:
 *   Array of group hashmaps that match the tag criteria
 * 
 * Examples:
 *   // Get all groups with FOOT tag
 *   private _footGroups = [_classifiedGroups, ["FOOT"]] call DSC_core_fnc_getGroupsByTag;
 * 
 *   // Get groups that are BOTH elite AND recon
 *   private _eliteRecon = [_classifiedGroups, ["ELITE", "SCOUT_RECON"]] call DSC_core_fnc_getGroupsByTag;
 * 
 *   // Get foot infantry but exclude AA and AT teams
 *   private _basicInf = [_classifiedGroups, ["FOOT", "PATROL"], ["AA_TEAM", "AT_TEAM"]] call DSC_core_fnc_getGroupsByTag;
 */

params ["_groups", "_includeTags", ["_excludeTags", []]];

// Validate inputs
if (count _groups == 0) exitWith { [] };
if (count _includeTags == 0 && count _excludeTags == 0) exitWith { _groups };

// Filter groups
private _filteredGroups = _groups select {
    private _groupTags = _x get "doctrineTags";
    
    if (isNil "_groupTags") then { _groupTags = [] };
    
    private _match = true;
    
    // Check include tags - ALL must be present
    {
        if !(_x in _groupTags) exitWith { _match = false };
    } forEach _includeTags;
    
    // Check exclude tags - NONE must be present
    if (_match) then {
        {
            if (_x in _groupTags) exitWith { _match = false };
        } forEach _excludeTags;
    };
    
    _match
};

_filteredGroups
