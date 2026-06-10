DSC_dynRespawnArmed = false;
[] spawn {
    waitUntil { sleep 0.5; alive player && {(getPosATL player) distance2D [0, 0] > 100} };
    DSC_dynRespawnArmed = true;
    diag_log "DSC: Dynamic respawn armed";
};

addMissionEventHandler ["EntityKilled", {
    params ["_killed"];
    if (_killed isEqualTo player && {DSC_dynRespawnArmed}) then {
        [_killed] call DSC_core_fnc_placeDynamicRespawn;
    };
}];