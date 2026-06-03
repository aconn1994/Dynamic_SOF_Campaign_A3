/*
 * Function: DSC_core_fnc_setupMortarEmplacement
 * Description:
 *     Places 1-2 mortars near a military location as area-denial indirect-fire
 *     assets. Mortars are positioned at the location edge, slightly offset
 *     from the center, with crew that respects combat activation.
 *
 *     This is intentionally minimal — mortars get a basic gunner from the
 *     faction's man pool, no fire mission scripting yet. Their value is
 *     presence + the threat of artillery if combat starts.
 *
 * Arguments:
 *     0: _locationPos <ARRAY>  - center of the location
 *     1: _faction     <STRING> - faction classname
 *     2: _side        <SIDE>
 *     3: _config      <HASHMAP>
 *        "assets"       <HASHMAP> Pre-extracted faction assets (required)
 *        "guardFaction" <STRING>  Faction id for crew (default: _faction)
 *        "count"        <NUMBER>  Mortars to spawn (default: 1)
 *        "offsetMin"    <NUMBER>  Min meters from center (default: 80)
 *        "offsetMax"    <NUMBER>  Max meters from center (default: 150)
 *
 * Return Value:
 *     <HASHMAP> - "units", "vehicles", "groups"
 */

params [
    ["_locationPos", [], [[]]],
    ["_faction", "", [""]],
    ["_side", east, [east]],
    ["_config", createHashMap, [createHashMap]]
];

private _result = createHashMapFromArray [
    ["units", []],
    ["vehicles", []],
    ["groups", []]
];

if (_locationPos isEqualTo []) exitWith { _result };

private _assets = _config getOrDefault ["assets", createHashMap];
if (_assets isEqualTo createHashMap) then {
    _assets = [_faction] call DSC_core_fnc_extractAssets;
};

private _statics = _assets getOrDefault ["staticWeapons", createHashMap];
private _mortars = _statics getOrDefault ["mortar", []];

if (_mortars isEqualTo []) exitWith {
    diag_log format ["DSC: setupMortarEmplacement - no mortars for faction %1", _faction];
    _result
};

private _count     = _config getOrDefault ["count", 1];
private _offsetMin = _config getOrDefault ["offsetMin", 80];
private _offsetMax = _config getOrDefault ["offsetMax", 150];
private _guardFaction = _config getOrDefault ["guardFaction", _faction];

// Crew class lookup
private _crewClass = "";
private _filterStr = format ["getNumber (_x >> 'scope') >= 2 && getText (_x >> 'faction') == '%1' && getNumber (_x >> 'isMan') == 1", _guardFaction];
private _factionMen = _filterStr configClasses (configFile >> "CfgVehicles");
if (_factionMen isNotEqualTo []) then {
    _crewClass = configName (selectRandom _factionMen);
} else {
    _crewClass = switch (_side) do {
        case east: { "O_Soldier_F" };
        case west: { "B_Soldier_F" };
        case independent: { "I_Soldier_F" };
        default { "O_Soldier_F" };
    };
};

private _group = createGroup [_side, true];

for "_i" from 0 to (_count - 1) do {
    private _ang = random 360;
    private _dist = _offsetMin + random (_offsetMax - _offsetMin);
    private _pos = _locationPos getPos [_dist, _ang];

    // Snap to flat ground
    _pos set [2, 0];
    if (surfaceIsWater _pos) then { continue };

    private _mortarClass = selectRandom _mortars;
    private _mortar = createVehicle [_mortarClass, _pos, [], 0, "NONE"];
    _mortar setPos _pos;
    _mortar setDir (random 360);

    private _gunner = _group createUnit [_crewClass, _pos, [], 0, "NONE"];
    _gunner allowDamage false;
    _gunner moveInGunner _mortar;
    [_gunner, "moderate", 0.05] call DSC_core_fnc_applySkillProfile;
    [{_this allowDamage true}, _gunner, 3] call CBA_fnc_waitAndExecute;

    (_result get "vehicles") pushBack _mortar;
    (_result get "units")    pushBack _gunner;

    diag_log format ["DSC: setupMortarEmplacement - %1 placed at %2", _mortarClass, _pos];
    uiSleep 0.2;
};

if ((units _group) isNotEqualTo []) then {
    (_result get "groups") pushBack _group;
    _group enableDynamicSimulation true;
    { _x enableDynamicSimulation true } forEach (_result get "vehicles");
    [_group] call DSC_core_fnc_addCombatActivation;
} else {
    deleteGroup _group;
};

_result
