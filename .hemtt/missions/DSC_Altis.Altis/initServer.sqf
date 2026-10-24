[] call DSC_core_fnc_initServer;
[] call DSC_core_fnc_initServerDebug;

// private _className = "Land_PowerLine_01_pole_transformer_F"; // change to your structure class

// // nearestObjects is faster; nearestTerrainObjects only works for terrain-baked objects
// private _structures = nearestObjects [
//     [worldSize / 2, worldSize / 2],
//     [_className],
//     worldSize * 0.75 // radius large enough to cover the whole map from center
// ];

// {
//     private _markerName = format ["structMarker_%1", _forEachIndex];
//     private _marker = createMarker [_markerName, getPosATL _x];
//     _marker setMarkerShape "ICON";
//     _marker setMarkerType "mil_dot";
//     _marker setMarkerSize [0.5, 0.5];
//     _marker setMarkerColor "ColorRed";
// } forEach _structures;