[] call DSC_core_fnc_initServer;

// ============================================================================
// TEST: Full Classification Pipeline
// ============================================================================

// private _testFactions = ["BLU_F", "OPF_F", "IND_F"];

// {
//     private _faction = _x;
    
//     diag_log "==============================================================";
//     diag_log format ["DSC: Faction '%1'", _faction];
//     diag_log "==============================================================";
    
//     // Layer 1: Extract groups
//     private _groups = [_faction] call DSC_core_fnc_extractGroups;
    
//     // Layer 2: Classify groups
//     private _classified = [_groups] call DSC_core_fnc_classifyGroups;
    
//     // Log each group
//     {
//         private _groupName = _x get "groupName";
//         private _category = _x get "category";
//         private _tags = _x get "doctrineTags";
//         private _analysis = _x get "unitAnalysis";
//         private _confidence = _x get "confidence";
        
//         diag_log format ["  %1 (%2)", _groupName, _category];
//         diag_log format ["    Tags: %1", _tags];
//         diag_log format ["    Units: %1 inf, %2 veh | AT=%3 AA=%4 MG=%5 | Conf: %6", 
//             _analysis get "infantryCount",
//             _analysis get "vehicleCount",
//             _analysis get "atCount",
//             _analysis get "aaCount",
//             _analysis get "mgCount",
//             _confidence
//         ];
//     } forEach _classified;
    
//     diag_log "";
// } forEach _testFactions;

// diag_log "==============================================================";
// diag_log "DSC: Classification complete";
// diag_log "==============================================================";
