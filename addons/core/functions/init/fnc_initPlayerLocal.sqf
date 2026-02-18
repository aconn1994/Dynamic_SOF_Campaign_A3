// Wait until Global Server variables are initialized
waitUntil { missionNamespace getVariable ["initGlobalsComplete", false]; };

jointOperationCenter addAction [
    'Debrief Mission',
    {
        private _mission = missionNamespace getVariable ["DSC_currentMission", createHashMap];
        if (_mission isEqualTo createHashMap) exitWith { hint "No active mission." };
        
        private _missionGroups = _mission getOrDefault ["groups", []];
        if (_missionGroups isEqualTo []) exitWith { hint "No mission groups found." };

        private _groupAlives = false;
        {
            if ([_x] call DSC_core_fnc_groupActive) then { _groupAlives = true };
        } forEach _missionGroups;

        if (!_groupAlives) then { 
            missionNamespace setVariable ["missionComplete", true, true]; 
        };
        missionNamespace setVariable ["missionInProgress", false, true];
    },
    [],
    6,
    false,
    true,
    "",
    "missionNamespace getVariable ['missionInProgress', false] && _target distance _this < 5"
];

