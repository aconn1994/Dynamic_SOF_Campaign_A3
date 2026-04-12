#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_requestExtraction
 * Description:
 *     Full extraction lifecycle: player picks pickup LZ on map,
 *     chinook spawns from direction of base and lands, player picks
 *     destination LZ, chinook flies with fast travel simulation,
 *     lands at destination, despawns after passengers disembark.
 *
 * Arguments:
 *     0: _caller <OBJECT> - Player who requested extraction
 *
 * Return Value:
 *     None (spawned - runs asynchronously)
 *
 * Example:
 *     [player] spawn DSC_core_fnc_requestExtraction;
 */

params [
    ["_caller", objNull, [objNull]]
];

if (isNull _caller) exitWith {};

// Prevent double-calling
if (_caller getVariable ["DSC_extractionInProgress", false]) exitWith {
    hint "Extraction already in progress.";
};
_caller setVariable ["DSC_extractionInProgress", true, true];

// ============================================================================
// PHASE 1: Select Pickup LZ
// ============================================================================
hint "Select pickup LZ on map.";
openMap true;

private _pickupPos = [];

// Use a variable to communicate between onMapSingleClick and this scope
_caller setVariable ["DSC_extractionPickupPos", nil];

onMapSingleClick {
    player setVariable ["DSC_extractionPickupPos", _pos];
    onMapSingleClick "";
};

waitUntil { sleep 0.1; !isNil { _caller getVariable "DSC_extractionPickupPos" } || !visibleMap };

_pickupPos = _caller getVariable ["DSC_extractionPickupPos", []];
_caller setVariable ["DSC_extractionPickupPos", nil];

if (_pickupPos isEqualTo []) exitWith {
    hint "Extraction cancelled.";
    _caller setVariable ["DSC_extractionInProgress", false, true];
    openMap false;
};

openMap false;

// ============================================================================
// PHASE 2: Spawn and fly chinook to pickup LZ
// ============================================================================
// Create invisible helipad for clean landing
private _pickupPad = "Land_HelipadEmpty_F" createVehicle _pickupPos;

// Determine spawn direction from base
private _basePos = getPos jointOperationCenter;
private _spawnDir = _basePos getDir _pickupPos;
private _spawnDist = 2000;
private _spawnPos = _pickupPos getPos [_spawnDist, _spawnDir + 180];
_spawnPos set [2, 0];

private _heloData = [_spawnPos] call DSC_core_fnc_spawnTransportHelo;
private _vehicle = _heloData get "vehicle";
private _heloGroup = _heloData get "group";
private _crew = _heloData get "crew";

// Create pickup marker
private _pickupMarker = createMarker ["dsc_extraction_pickup", _pickupPos];
_pickupMarker setMarkerTypeLocal "mil_pickup";
_pickupMarker setMarkerColorLocal "ColorGreen";
_pickupMarker setMarkerText "Extraction LZ";

systemChat "Extraction inbound to pickup LZ.";
hint "Extraction helicopter inbound.";

// Fly to pickup
private _wpPickup = _heloGroup addWaypoint [_pickupPos, 0];
_wpPickup setWaypointType "TR UNLOAD";
_wpPickup setWaypointBehaviour "CARELESS";
_wpPickup setWaypointCombatMode "BLUE";
_wpPickup setWaypointSpeed "NORMAL";

// Wait for landing (close to pad and low speed)
waitUntil {
    sleep 1;
    (_vehicle distance2D _pickupPos < 30) && ((getPos _vehicle select 2) < 5) && (speed _vehicle < 5)
};

sleep 2;
systemChat "Extraction helicopter on station. Board and select destination.";
hint "Board the helicopter.\nThen use 'Select Destination' in scroll menu.";

// ============================================================================
// PHASE 3: Wait for destination selection
// ============================================================================
private _destinationPos = [];
_caller setVariable ["DSC_extractionDestPos", nil];

// Add action on the helicopter for destination selection
private _destActionId = _vehicle addAction [
    "Select Destination",
    {
        params ["_target", "_callerUnit", "_actionId"];
        
        openMap true;
        onMapSingleClick {
            player setVariable ["DSC_extractionDestPos", _pos];
            onMapSingleClick "";
        };
    },
    nil,
    6,
    false,
    true,
    "",
    "vehicle _this == _target"
];

// Wait for destination to be selected
waitUntil {
    sleep 0.5;
    !isNil { _caller getVariable "DSC_extractionDestPos" }
};

_destinationPos = _caller getVariable ["DSC_extractionDestPos", []];
_caller setVariable ["DSC_extractionDestPos", nil];
_vehicle removeAction _destActionId;

if (_destinationPos isEqualTo []) exitWith {
    hint "Extraction cancelled - no destination.";
    _caller setVariable ["DSC_extractionInProgress", false, true];
    deleteMarker "dsc_extraction_pickup";
    { deleteVehicle _x } forEach _crew;
    deleteVehicle _vehicle;
    deleteVehicle _pickupPad;
};

openMap false;

// Create destination marker
private _destMarker = createMarker ["dsc_extraction_dest", _destinationPos];
_destMarker setMarkerTypeLocal "mil_end";
_destMarker setMarkerColorLocal "ColorGreen";
_destMarker setMarkerText "Destination LZ";

// Destination invisible helipad
private _destPad = "Land_HelipadEmpty_F" createVehicle _destinationPos;

systemChat "Destination set. En route.";

// ============================================================================
// PHASE 4: Fly toward destination with fast travel
// ============================================================================
// Clear old waypoints
while { (waypoints _heloGroup) isNotEqualTo [] } do {
    deleteWaypoint [_heloGroup, 0];
};

// Fly toward destination initially
private _wpDest = _heloGroup addWaypoint [_destinationPos, 0];
_wpDest setWaypointType "MOVE";
_wpDest setWaypointBehaviour "CARELESS";
_wpDest setWaypointSpeed "FULL";
_heloGroup setCurrentWaypoint _wpDest;
_vehicle flyInHeight 150;

// Wait until 1km+ from pickup (traveled enough to fast-travel)
waitUntil {
    sleep 1;
    _vehicle distance2D _pickupPos > 1000
};

// Fast travel for all passengers
[_vehicle, _destinationPos] call DSC_core_fnc_simulateFastTravel;

// Clear waypoints and set landing waypoint
while { (waypoints _heloGroup) isNotEqualTo [] } do {
    deleteWaypoint [_heloGroup, 0];
};

private _wpLand = _heloGroup addWaypoint [_destinationPos, 0];
_wpLand setWaypointType "TR UNLOAD";
_wpLand setWaypointBehaviour "CARELESS";
_wpLand setWaypointCombatMode "BLUE";
_wpLand setWaypointSpeed "NORMAL";
_heloGroup setCurrentWaypoint _wpLand;

// Wait for landing at destination
waitUntil {
    sleep 1;
    (_vehicle distance2D _destinationPos < 30) && ((getPos _vehicle select 2) < 5) && (speed _vehicle < 5)
};

sleep 2;
systemChat "Arrived at destination. Disembark.";
hint "Disembark at destination.";

// ============================================================================
// PHASE 5: Wait for disembark, then cleanup
// ============================================================================
// Wait until no non-crew passengers remain
waitUntil {
    sleep 2;
    private _passengers = (crew _vehicle) select { !(_x in _crew) };
    _passengers isEqualTo []
};

sleep 3;
systemChat "All passengers off. Helicopter departing.";

// Fly away
while { (waypoints _heloGroup) isNotEqualTo [] } do {
    deleteWaypoint [_heloGroup, 0];
};

private _departDir = _destinationPos getDir _basePos;
private _departPos = _destinationPos getPos [3000, _departDir];
_departPos set [2, 0];

private _wpDepart = _heloGroup addWaypoint [_departPos, 0];
_wpDepart setWaypointType "MOVE";
_wpDepart setWaypointBehaviour "CARELESS";
_wpDepart setWaypointSpeed "FULL";
_heloGroup setCurrentWaypoint _wpDepart;
_vehicle flyInHeight 200;

// Wait until far from destination, then despawn
waitUntil {
    sleep 2;
    _vehicle distance2D _destinationPos > 2000
};

// Cleanup
{ deleteVehicle _x } forEach _crew;
deleteVehicle _vehicle;
deleteGroup _heloGroup;
deleteVehicle _pickupPad;
deleteVehicle _destPad;
deleteMarker "dsc_extraction_pickup";
deleteMarker "dsc_extraction_dest";

_caller setVariable ["DSC_extractionInProgress", false, true];

diag_log "DSC: Extraction complete - helicopter despawned";
