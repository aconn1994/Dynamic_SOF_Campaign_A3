
// =================================================================
// =================  Get Faction Assets  ==========================
// =================================================================
private _staticWeapons = ["OPF_F", "staticWeapons"] call DSC_core_fnc_getFactionAssets;

diag_log format ["DSC: Static weapons for OPF_F - HMG: %1, AT: %2, AA: %3", 
    _staticWeapons get "HMG", 
    _staticWeapons get "AT", 
    _staticWeapons get "AA"
];

// =================================================================
// =================  Discover Structure Variants  =================
// =================================================================
private _towerBaseClasses = ["Cargo_Tower_base_F", "Cargo_Patrol_base_F", "Cargo_HQ_base_F"];
private _structureVariants = [_towerBaseClasses] call DSC_core_fnc_getStructureVariants;

// =================================================================
// ===================  Add to Zeus for Debug  =====================
// =================================================================
// Add units/vehicles to zeus
_curator = ((allCurators) select 0); // The curator object

// Add all existing units to be editable by this curator
{
    _curator addCuratorEditableObjects [[_x], true];
} forEach allUnits;