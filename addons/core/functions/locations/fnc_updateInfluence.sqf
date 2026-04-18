#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_updateInfluence
 * Description:
 *     Updates influence after a mission result. Shifts control toward the
 *     winning faction at the mission location and propagates to nearby areas.
 *
 *     Designed to be called once per mission completion.
 *     The map evolves based on player actions, not continuous checks.
 *
 * Arguments:
 *     0: _influenceData <HASHMAP> - Current influence data from initInfluence
 *     1: _locationId <STRING> - ID of the mission location
 *     2: _result <STRING> - "success" or "failure"
 *     3: _missionType <STRING> - e.g. "KILL_CAPTURE" (for future type-specific effects)
 *
 * Return Value:
 *     <HASHMAP> - Updated influence data (same structure, modified values)
 *
 * Example:
 *     _influenceData = [_influenceData, "loc_42", "success", "KILL_CAPTURE"] call DSC_core_fnc_updateInfluence;
 */

params [
    ["_influenceData", createHashMap, [createHashMap]],
    ["_locationId", "", [""]],
    ["_result", "success", [""]],
    ["_missionType", "KILL_CAPTURE", [""]]
];

if (_influenceData isEqualTo createHashMap || _locationId == "") exitWith {
    diag_log "DSC: fnc_updateInfluence - Invalid parameters";
    _influenceData
};

private _influenceMap = _influenceData get "influenceMap";
private _locInfluence = _influenceMap getOrDefault [_locationId, createHashMap];

if (_locInfluence isEqualTo createHashMap) exitWith {
    diag_log format ["DSC: fnc_updateInfluence - Location %1 not in influence map", _locationId];
    _influenceData
};

private _currentOwner = _locInfluence get "controlledBy";
private _currentInfluence = _locInfluence get "influence";
private _locType = _locInfluence get "type";

// ============================================================================
// Calculate influence shift
// ============================================================================
// Success = player's faction gains influence (opFor loses)
// Failure = opFor strengthens (player faction loses)
// Control points shift more than mission sites

private _shiftAmount = switch (_locType) do {
    case "controlPoint":  { 0.25 }; // Big strategic impact
    case "populatedArea": { 0.15 }; // Moderate civic impact
    case "missionSite":   { 0.10 }; // Small tactical impact
    default               { 0.10 };
};

if (_result == "success") then {
    // Player success: shift toward bluFor
    switch (_currentOwner) do {
        case "opFor": {
            private _newInfluence = _currentInfluence - _shiftAmount;
            if (_newInfluence <= 0.3) then {
                _locInfluence set ["controlledBy", "contested"];
                _locInfluence set ["influence", 0.4];
            } else {
                _locInfluence set ["influence", _newInfluence];
            };
        };
        case "contested": {
            _locInfluence set ["controlledBy", "bluFor"];
            _locInfluence set ["influence", 0.5 + random 0.2];
        };
        case "bluFor": {
            _locInfluence set ["influence", (_currentInfluence + _shiftAmount * 0.5) min 1.0];
        };
        case "neutral": {
            _locInfluence set ["controlledBy", "bluFor"];
            _locInfluence set ["influence", 0.5];
        };
    };
    diag_log format ["DSC: updateInfluence - SUCCESS at %1: %2 -> %3 (influence: %4)",
        _locationId, _currentOwner, _locInfluence get "controlledBy", (_locInfluence get "influence") toFixed 2];
} else {
    // Player failure: opFor strengthens
    switch (_currentOwner) do {
        case "opFor": {
            _locInfluence set ["influence", (_currentInfluence + _shiftAmount * 0.5) min 1.0];
        };
        case "contested": {
            _locInfluence set ["controlledBy", "opFor"];
            _locInfluence set ["influence", 0.5 + random 0.2];
        };
        case "bluFor": {
            private _newInfluence = _currentInfluence - _shiftAmount;
            if (_newInfluence <= 0.3) then {
                _locInfluence set ["controlledBy", "contested"];
                _locInfluence set ["influence", 0.4];
            } else {
                _locInfluence set ["influence", _newInfluence];
            };
        };
        case "neutral": {
            _locInfluence set ["controlledBy", "opFor"];
            _locInfluence set ["influence", 0.5];
        };
    };
    diag_log format ["DSC: updateInfluence - FAILURE at %1: %2 -> %3 (influence: %4)",
        _locationId, _currentOwner, _locInfluence get "controlledBy", (_locInfluence get "influence") toFixed 2];
};

// Update the map entry
_influenceMap set [_locationId, _locInfluence];

// ============================================================================
// Propagate ripple to nearby locations (smaller effect)
// ============================================================================
private _rippleRadius = 2000;
private _rippleAmount = _shiftAmount * 0.3; // 30% of direct effect

private _allLocations = _influenceData getOrDefault ["locations", []];
private _missionLoc = _allLocations select { (_x get "id") == _locationId };

if (_missionLoc isNotEqualTo []) then {
    private _missionPos = (_missionLoc select 0) get "position";
    
    {
        private _nearbyId = _x get "id";
        if (_nearbyId == _locationId) then { continue };
        
        private _nearbyPos = _x get "position";
        private _dist = _missionPos distance2D _nearbyPos;
        
        if (_dist < _rippleRadius) then {
            private _nearbyInf = _influenceMap getOrDefault [_nearbyId, createHashMap];
            if (_nearbyInf isNotEqualTo createHashMap) then {
                private _nearbyOwner = _nearbyInf get "controlledBy";
                private _nearbyStr = _nearbyInf get "influence";
                private _scaledRipple = _rippleAmount * (1 - _dist / _rippleRadius);
                
                if (_result == "success" && _nearbyOwner == "opFor") then {
                    _nearbyInf set ["influence", (_nearbyStr - _scaledRipple) max 0.1];
                };
                if (_result != "success" && _nearbyOwner == "bluFor") then {
                    _nearbyInf set ["influence", (_nearbyStr - _scaledRipple) max 0.1];
                };
                
                _influenceMap set [_nearbyId, _nearbyInf];
            };
        };
    } forEach _allLocations;
};

_influenceData set ["influenceMap", _influenceMap];

_influenceData
