params ["_milLocations"];

private _locationIndex = 0;
{
    private _location = _x;
    private _locationMarker = createMarker [format ["enemy_base_location_%1", _locationIndex], _x];
    _locationMarker setMarkerTypeLocal "hd_dot";
    _locationMarker setMarkerTextLocal "";

    // Structures on Location for Garrisoned Units
    private _locationStructs = [_location, 250] call DSC_core_fnc_getAreaStructures;

    private _structIndex = 0;
    {
        private _loc = _x;

        private _marker = createMarker [str _loc + str _locationIndex + str _structIndex, _loc];
        _marker setMarkerTypeLocal "hd_dot";
        _marker setMarkerSizeLocal [0.25, 0.25];
        _marker setMarkerColorLocal "ColorOrange";

        _structIndex = _structIndex + 1;
    } forEach _locationStructs;

    // Get positions for guard units
    private _guardPosts = [_location, _locationStructs] call DSC_core_fnc_getGuardPosts;
    {
        private _loc = _x;

        private _marker = createMarker [str _loc + str _locationIndex + str _structIndex, _loc];
        _marker setMarkerTypeLocal "hd_dot";
        _marker setMarkerSizeLocal [0.25, 0.25];
        _marker setMarkerColorLocal "ColorYellow";
    } forEach _guardPosts;

    _locationIndex = _locationIndex + 1;

} forEach _milLocations;
