jointOperationCenter addAction [
    'Debrief Mission',
    {
        private _enemyMissionGroup = missionNamespace getVariable ["enemyMissionGroup", grpNull];
        private _missionComplete = missionNamespace getVariable ["missionComplete", false];
        if (isNull _enemyMissionGroup) exitWith { hint "Enemy Group non-existent. Check script." };

        private _groupAlive = false;
        {
            if ((alive _x) && !(captive _x)) then {
                _groupAlive = true;
            };
        } forEach units _enemyMissionGroup;

        if (!_groupAlive) then { missionNamespace setVariable ["missionComplete", true, true]; };
        missionNamespace setVariable ["missionInProgress", false, true];
    }, [], 6, false, true, "", "_target distance _this < 5"];