diag_log "===================";
diag_log "Starting Run 4...";
diag_log "===================";

// Mission start time
private _missionStartTime = diag_tickTime;
diag_log format ["[MISSION] Start time: %1", _missionStartTime];

// Baseline Garrison Profile for daytime CQB, 3 units per structure is pretty balanced
// Maybe drop spotTime if enemies are not NVG-capable.  Keep at 0.5 if they are
// private _skillProfile = [
//     ["aimingAccuracy", 0.2],
//     ["aimingShake",    0.3],
//     ["aimingSpeed",    0.3],
//     ["spotDistance",   0.5],
//     ["spotTime",       0.5],
//     ["courage",        0.5],
//     ["commanding",     0.5]
// ];

// Skill profile to apply
private _skillProfile = [
    ["aimingAccuracy", 0.2],
    ["aimingShake",    0.3],
    ["aimingSpeed",    0.3],
    ["spotDistance",   0.5],
    ["spotTime",       0.5],
    ["courage",        0.5],
    ["commanding",     0.5]
];

// Spawn and skill units per building
private _numUnits = 3;
{
    private _building = _x;
    private _buildingPositions = (_building buildingPos -1);
    diag_log format ["[GARRISON] %1 has %2 positions", _building, count _buildingPositions];

    private _shuffled = _buildingPositions call BIS_fnc_arrayShuffle;
    private _spawnPositions = _shuffled select [0, _numUnits];

    {
        private _group = createGroup east;
        private _unit = _group createUnit ["O_G_Soldier_lite_F", _x, [], 0, "NONE"];
        {
            _unit setSkill [_x select 0, _x select 1];
        } forEach _skillProfile;
        diag_log format ["[SKILL] Applied to: %1", _unit];
    } forEach _spawnPositions;

} forEach [structure_1, structure_2, structure_3];

// Watch for last unit killed
[_missionStartTime] spawn {
    params ["_missionStartTime"];
    waitUntil {
        sleep 2;
        ({ alive _x && side _x == east } count allUnits) == 0
    };
    _elapsed = diag_tickTime - _missionStartTime;
    diag_log format ["[MISSION] Last OPFOR killed. Elapsed: %1s", _elapsed];
};