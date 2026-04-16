// Test fnc_extractAssets
diag_log "========== DSC fnc_extractAssets TEST ==========";

private _testFactions = ["OPF_F", "IND_F", "BLU_F", "rhs_faction_usarmy_wd", "rhs_faction_usmc_d", "rhs_faction_msv"];

{
    private _faction = _x;
    diag_log format ["--- Testing: %1 ---", _faction];
    private _assets = [_faction] call DSC_core_fnc_extractAssets;
    
    private _statics = _assets get "staticWeapons";
    diag_log format ["  Static HMG: %1", _statics get "HMG"];
    diag_log format ["  Static AT: %1", _statics get "AT"];
    diag_log format ["  Static AA: %1", _statics get "AA"];
    
    private _cars = _assets get "cars";
    diag_log format ["  MRAPs: %1", _cars get "mrap"];
    
    diag_log format ["  Trucks: %1", count (_assets get "trucks")];
    diag_log format ["  APCs: %1", count (_assets get "apcs")];
    diag_log format ["  Tanks: %1", count (_assets get "tanks")];
    
    private _helis = _assets get "helicopters";
    diag_log format ["  Heli attack: %1", _helis get "attack"];
    diag_log format ["  Heli transport: %1", _helis get "transport"];
    
} forEach _testFactions;

diag_log "========== END TEST ==========";
