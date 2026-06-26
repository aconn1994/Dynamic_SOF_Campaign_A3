#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_bftResolveIconType
 * Description:
 *     Returns the BI marker subtype key ("inf" / "motor_inf" / "mech_inf" /
 *     "armor" / "air" / "plane" / "uav" / "naval") for a friendly group.
 *     This is the same classification rule the BFT snapshot used inline;
 *     extracted so the server-side HC icon attachment can stay in sync
 *     with how the tablet draws each group.
 *
 *     Callers map the returned key to whatever they need:
 *       - Tablet draw EH: "\A3\ui_f\data\map\markers\nato\b_<key>.paa"
 *       - HC addGroupIcon: "b_<key>" as a CfgGroupIcons class name
 *
 *     Mapping:
 *       - Foot leader  → "inf"
 *       - Car / wheeled APC → "motor_inf"
 *       - Tank with transportSoldier > 0 → "mech_inf" (IFV / APC)
 *       - Tank with transportSoldier == 0 → "armor" (MBT)
 *       - Helicopter → "air"
 *       - Plane → "plane"
 *       - UAV → "uav"
 *       - Ship → "naval"
 *       - Anything else → "inf"
 *
 * Arguments:
 *     0: _grp <GROUP> - the group to classify
 *
 * Return Value:
 *     <STRING> - one of the iconType keys above
 */

params [["_grp", grpNull, [grpNull]]];

if (isNull _grp) exitWith { "inf" };

private _ldr = leader _grp;
if (isNull _ldr) exitWith { "inf" };

private _veh = vehicle _ldr;
if (_veh isEqualTo _ldr) exitWith { "inf" };

private _type = typeOf _veh;
private _cfg  = configFile >> "CfgVehicles" >> _type;
private _transport = getNumber (_cfg >> "transportSoldier");

switch (true) do {
    case (_veh isKindOf "UAV"):           { "uav" };
    case (_veh isKindOf "Plane"):         { "plane" };
    case (_veh isKindOf "Helicopter"):    { "air" };
    case (_veh isKindOf "Ship"):          { "naval" };
    case (_veh isKindOf "Tank"):          { ["armor", "mech_inf"] select (_transport > 0) };
    case (_veh isKindOf "Wheeled_APC_F"): { "motor_inf" };
    case (_veh isKindOf "Car"):           { "motor_inf" };
    default                                { "inf" };
};
