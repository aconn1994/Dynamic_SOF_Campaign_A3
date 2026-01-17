// Wait until Global Server variables are initialized
waitUntil { missionNamespace getVariable ["initGlobalsComplete", false]; };

jointOperationCenter addAction [
    'Debrief Mission',
    {
        private _enemyMissionGroups = missionNamespace getVariable ["enemyMissionGroups", grpNull];
        private _missionComplete = missionNamespace getVariable ["missionComplete", false];
        if ((count _enemyMissionGroups) == 0) exitWith { hint "Enemy Group non-existent. Check script." };

        private _groupAlives = false;

        {
            private _alive = [_x] call DSC_core_fnc_groupActive;

            if (_alive) then { _groupAlives = true };

        } forEach _enemyMissionGroups;

        if (!_groupAlives) then { missionNamespace setVariable ["missionComplete", true, true]; };
        missionNamespace setVariable ["missionInProgress", false, true];
    },
    [],
    6,
    false,
    true,
    "",
    "_target distance _this < 5"
];

