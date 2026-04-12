params ["_unit"];
_backpack = backpack _unit;

_unit allowDamage false; 
_unit disableAI "ANIM";

_originalBackpackClass = "";
_originalBackpackItems = [];

if (count _backpack > 0) then
{
    _originalBackpackClass = _backpack call BIS_fnc_basicBackpack;	
    _originalBackpackItems = backpackItems _unit;

    removeBackpack _unit;
};

_unit addBackpack "B_Parachute";

if (count _originalBackpackClass > 0) then
{
    waitUntil {isNull (objectParent _unit)};

    _backpackDummy = _originalBackpackClass createVehicle position _unit;
	_backpackHolder = objectParent _backpackDummy;
	_backpackHolder attachTo [_unit, [-0.1, 0, -0.7], "Pelvis"];
	_backpackHolder setVectorDirAndUp [[0, -1, 0],[0, 0, -1]];
	
	waitUntil {!isNull (objectParent _unit)};
	
	deleteVehicle _backpackDummy;
	deleteVehicle _backpackHolder;
		
	_backpackDummy = _originalBackpackClass createVehicle position _unit;
	_backpackHolder = objectParent _backpackDummy;
	_backpackHolder attachTo [vehicle _unit, [-0.1, 0.7, 0]];
	_backpackHolder setVectorDirAndUp [[0, 0, -1],[0, 1, 0]];
	
	_unit allowDamage true; 	
	_unit enableAI "ANIM";
	
	waitUntil {(isNull (objectParent _unit))};
	
	deleteVehicle _backpackDummy;
	deleteVehicle _backpackHolder;
	
	removeBackpack _unit;
	_unit addBackpackGlobal _originalBackpackClass;	
	{_unit addItemToBackpack _x} forEach _originalBackpackItems;
};