commandPostFlagPole addAction ["Halo Jump",
{
    openMap true;
    player onMapSingleClick {
        _playersInTrigger = list commandPostflagPoleRadiusTrigger select { isPlayer _x };
        hint format ["Players in trigger: %1", _playersInTrigger];
        {
            {
                _startPosition = [(_pos select 0), (_pos select 1) + (_forEachIndex * 6), (_pos select 2) + 2000];
                _x setPos _startPosition;
                if (isPlayer _x) then {
                    [[_x], 'acorns_modules\insertions\simulateParachute.sqf'] remoteExec ['execVM', _x, false];
                } else {
                    [_x] execVM 'acorns_modules\insertions\simulateParachute.sqf';
                };
            } forEach units _x;
        } forEach _playersInTrigger;
        openMap false;
    };
}, [], 6, false, true, "", "_target distance _this < 5"];

commandPostFlagPole addAction ["Helo Transport",
{
    lightTransportHelo = friendlyFactionSerialized get "lightTransportHelo";
    mediumTransportHelo = friendlyFactionSerialized get "mediumTransportHelo";
    heavyTransportHelo = friendlyFactionSerialized get "heavyTransportHelo";

    createDialog "HelicopterTransportPopupMenu";

    ((findDisplay 12345) displayCtrl 201) ctrlSetText (lightTransportHelo select 0);
    ((findDisplay 12345) displayCtrl 202) ctrlSetText (mediumTransportHelo select 0);
    ((findDisplay 12345) displayCtrl 203) ctrlSetText (heavyTransportHelo select 0);
}, [], 6, false, true, "", "_target distance _this < 5"];
