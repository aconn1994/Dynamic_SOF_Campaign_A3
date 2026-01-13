// DSC - Dynamic SOF Campaign - Altis
// Using Aegis and RHS for now, eventually vanilla will be default and code will check for Aegis/RHS mods

// ============================================================================
// STEP 1: Get all available factions from CfgFactionClasses
// ============================================================================
private _factions = [];
private _bluforFactions = [];
private _opforFactions = [];
private _greenforFactions = [];
{
    private _factionClass = configName _x;
    private _displayName = getText (_x >> "displayName");
    private _side = getNumber (_x >> "side");
    
    // Side mapping: 0=OPFOR, 1=BLUFOR, 2=INDFOR, 3=CIV
    private _sideName = ["OPFOR", "BLUFOR", "INDFOR", "CIVILIAN"] select (_side min 3);

    if (_sideName == "BLUFOR") then { _bluforFactions pushBack [_factionClass, _displayName, _side, _sideName] };
    if (_sideName == "OPFOR") then { _opforFactions pushBack [_factionClass, _displayName, _side, _sideName] };
    if (_sideName == "INDFOR") then { _greenforFactions pushBack [_factionClass, _displayName, _side, _sideName] };
    
    _factions pushBack [_factionClass, _displayName, _side, _sideName];
    
    // diag_log format ["DSC: Faction found - %1 (%2) [%3]", _displayName, _factionClass, _sideName];
} forEach ("true" configClasses (configFile >> "CfgFactionClasses"));


diag_log "=============== Groups for BluFor Factions =================";
{
    private _factionClass = _x select 0;
    [_factionClass] call DSC_core_fnc_factionGroupMapper;
} forEach _bluforFactions;

diag_log "=============== Groups for OpFor Factions =================";
{
    private _factionClass = _x select 0;
    [_factionClass] call DSC_core_fnc_factionGroupMapper;
} forEach _opforFactions;

diag_log "=============== Groups for IndFor Factions =================";
{
    private _factionClass = _x select 0;
    [_factionClass] call DSC_core_fnc_factionGroupMapper;
} forEach _greenforFactions;