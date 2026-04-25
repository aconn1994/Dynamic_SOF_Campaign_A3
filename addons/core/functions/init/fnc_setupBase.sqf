/*
 * Function: DSC_core_fnc_setupBase
 * Description:
 *     Initializes a single military base — scans structures, sets up guards,
 *     places vehicles on helipad anchors, enables dynamic simulation.
 *     Handles player bases (marker-defined zones) and influence bases alike.
 *
 * Arguments:
 *     0: _baseConfig <HASHMAP>
 *        Required keys:
 *          "id"       <STRING>  - Base identifier (e.g. "player_base_1" or location ID)
 *          "type"     <STRING>  - "playerBase" | "bluFor" | "opFor"
 *          "position" <ARRAY>   - Center position [x, y, z]
 *          "side"     <SIDE>    - west, east, independent
 *          "faction"  <STRING>  - Faction classname (e.g. "BLU_F")
 *        Optional keys:
 *          "name"       <STRING>   - Display name (default: id)
 *          "radius"     <NUMBER>   - Search radius for non-marker bases (default: 500)
 *          "structures" <ARRAY>    - Pre-scanned structures (skips scan)
 *          "assets"     <HASHMAP>  - Pre-extracted faction assets (skips extraction)
 *          "factionData" <HASHMAP> - Full faction data for group selection
 *
 * Return Value:
 *     <HASHMAP> - Base registry entry (see base-initialization.md for schema)
 *
 * Example:
 *     [_config] call DSC_core_fnc_setupBase;
 */

params [
    ["_baseConfig", createHashMap, [createHashMap]]
];

private _id = _baseConfig getOrDefault ["id", ""];
private _type = _baseConfig getOrDefault ["type", ""];
private _position = _baseConfig getOrDefault ["position", []];
private _side = _baseConfig getOrDefault ["side", east];
private _faction = _baseConfig getOrDefault ["faction", ""];
private _name = _baseConfig getOrDefault ["name", _id];
private _radius = _baseConfig getOrDefault ["radius", 500];

private _result = createHashMapFromArray [
    ["id", _id],
    ["type", _type],
    ["side", _side],
    ["faction", _faction],
    ["position", _position],
    ["name", _name],
    ["radius", _radius],
    ["units", []],
    ["vehicles", []],
    ["groups", []],
    ["structures", []],
    ["zones", createHashMap],
    ["influenceId", _baseConfig getOrDefault ["influenceId", ""]]
];

if (_id == "" || _position isEqualTo []) exitWith {
    diag_log "DSC: fnc_setupBase - Missing required config (id or position)";
    _result
};

diag_log format ["DSC: fnc_setupBase - Initializing '%1' (%2) at %3", _name, _type, _position];

// ============================================================================
// Faction Assets
// ============================================================================
private _assets = _baseConfig getOrDefault ["assets", createHashMap];
if (_assets isEqualTo createHashMap) then {
    _assets = [_faction] call DSC_core_fnc_extractAssets;
};

// ============================================================================
// Structure Scan
// ============================================================================
private _structures = _baseConfig getOrDefault ["structures", []];

if (_type == "playerBase") then {
    // Player base: scan inside main marker area
    private _mainMarker = _id;
    private _markerExists = (getMarkerPos _mainMarker) isNotEqualTo [0,0,0];
    if (_markerExists) then {
        private _markerPos = getMarkerPos _mainMarker;
        private _markerSize = getMarkerSize _mainMarker;
        private _scanRadius = (_markerSize select 0) max (_markerSize select 1);

        if (_structures isEqualTo []) then {
            _structures = [_markerPos, ["House", "Building", "Strategic"], _scanRadius + 50] call DSC_core_fnc_getMapStructures;
            // Filter to only structures inside the marker area
            _structures = _structures select { getPos _x inArea _mainMarker };
        };

        diag_log format ["DSC: fnc_setupBase - Scanned %1 structures inside '%2'", count _structures, _mainMarker];
    } else {
        diag_log format ["DSC: fnc_setupBase - WARNING: Main marker '%1' not found", _mainMarker];
        if (_structures isEqualTo []) then {
            _structures = [_position, ["House", "Building", "Strategic"], _radius] call DSC_core_fnc_getMapStructures;
        };
    };
} else {
    // Influence base: use provided structures or scan by radius
    if (_structures isEqualTo []) then {
        _structures = [_position, ["House", "Building", "Strategic"], _radius] call DSC_core_fnc_getMapStructures;
    };
};

_result set ["structures", _structures];

// ============================================================================
// Zone Scanning (Player Base Only)
// ============================================================================
// Helipad classnames for detection
private _visibleHelipadTypes = [
    "Land_HelipadSquare_F", "Land_HelipadCircle_F", "Land_HelipadRescue_F",
    "Land_HelipadCivil_F", "Land_HelipadEmpty_F", "HeliH",
    "Land_JumpTarget_F"
];

if (_type == "playerBase") then {
    // Collect all sub-markers: player_base_1_zoneName_N
    private _prefix = _id + "_";
    private _subMarkers = allMapMarkers select { _x find _prefix == 0 };

    // Group markers by zone name
    // e.g. "player_base_1_heliport_0" → zone = "heliport"
    private _zoneMarkers = createHashMap; // zoneName → [marker1, marker2, ...]

    {
        private _markerName = _x;
        private _suffix = _markerName select [count _prefix]; // everything after prefix
        // Strip trailing _N index: find last underscore
        private _parts = _suffix splitString "_";
        if (count _parts >= 2) then {
            // Last part is the index, everything before is zone name
            private _zoneParts = _parts select [0, count _parts - 1];
            private _zoneName = _zoneParts joinString "_";
            private _existing = _zoneMarkers getOrDefault [_zoneName, []];
            _existing pushBack _markerName;
            _zoneMarkers set [_zoneName, _existing];
        } else {
            // Single part — treat whole suffix as zone name (no index)
            private _existing = _zoneMarkers getOrDefault [_suffix, []];
            _existing pushBack _markerName;
            _zoneMarkers set [_suffix, _existing];
        };
    } forEach _subMarkers;

    diag_log format ["DSC: fnc_setupBase - Found zones: %1", keys _zoneMarkers];

    // Scan each zone for helipad objects
    {
        private _zoneName = _x;
        private _markers = _y;
        private _zonePads = [];

        {
            private _marker = _x;
            private _mPos = getMarkerPos _marker;
            private _mSize = getMarkerSize _marker;
            private _scanDist = ((_mSize select 0) max (_mSize select 1)) + 20;

            // Find all helipad-like objects in this marker area
            private _nearPads = nearestObjects [_mPos, _visibleHelipadTypes, _scanDist];
            _nearPads = _nearPads select { getPos _x inArea _marker };
            _zonePads append _nearPads;
        } forEach _markers;

        // Deduplicate
        _zonePads = _zonePads arrayIntersect _zonePads;

        private _zoneData = createHashMapFromArray [
            ["markers", _markers],
            ["pads", _zonePads],
            ["vehicles", []]
        ];
        (_result get "zones") set [_zoneName, _zoneData];

        diag_log format ["DSC: fnc_setupBase - Zone '%1': %2 markers, %3 pads", _zoneName, count _markers, count _zonePads];
    } forEach _zoneMarkers;
};

// ============================================================================
// Guards Setup
// ============================================================================
private _guardConfig = createHashMap;
_guardConfig set ["structures", _structures];
_guardConfig set ["assets", _assets];
_guardConfig set ["maxGuardsPerStructure", 3];

// Use guardFaction override if provided (e.g., conventional infantry instead of SOF)
private _guardFaction = _baseConfig getOrDefault ["guardFaction", ""];
if (_guardFaction != "") then {
    _guardConfig set ["guardFaction", _guardFaction];
};

switch (_type) do {
    case "playerBase": {
        _guardConfig set ["maxStatics", 20];
        _guardConfig set ["staticChance", 0.5];
    };
    case "bluFor": {
        _guardConfig set ["maxStatics", 10];
        _guardConfig set ["staticChance", 0.5];
    };
    case "opFor": {
        _guardConfig set ["maxStatics", 10];
        _guardConfig set ["staticChance", 0.5];
    };
};

// Classify structures for guard placement (main vs side)
private _structureTypes = [] call DSC_core_fnc_getStructureTypes;
private _mainTypes = _structureTypes getOrDefault ["main", []];
private _sideTypes = _structureTypes getOrDefault ["side", []];
private _militaryTypes = _structureTypes getOrDefault ["military", []];

private _mainStructures = [];
private _sideStructures = [];
{
    private _struct = _x;
    private _isMain = false;
    private _isSide = false;
    { if (_struct isKindOf _x) exitWith { _isMain = true } } forEach _mainTypes;
    if (!_isMain) then {
        { if (_struct isKindOf _x) exitWith { _isSide = true } } forEach _sideTypes;
    };
    if (!_isMain && !_isSide) then {
        { if (_struct isKindOf _x) exitWith { _isSide = true } } forEach _militaryTypes;
    };
    if (_isMain) then { _mainStructures pushBack _struct };
    if (_isSide) then { _sideStructures pushBack _struct };
} forEach _structures;

_guardConfig set ["mainStructures", _mainStructures];
_guardConfig set ["sideStructures", _sideStructures];

diag_log format ["DSC: fnc_setupBase - Guard scan: %1 main, %2 side structures", count _mainStructures, count _sideStructures];

// --- Static Defenses (towers, bunkers, static weapons) ---
private _staticConfig = createHashMapFromArray [
    ["assets", _assets],
    ["structures", _structures],
    ["maxStatics", _guardConfig getOrDefault ["maxStatics", 3]],
    ["staticChance", _guardConfig getOrDefault ["staticChance", 0.5]],
    ["maxGuardsPerStructure", _guardConfig getOrDefault ["maxGuardsPerStructure", 3]]
];
if (_guardFaction != "") then { _staticConfig set ["guardFaction", _guardFaction] };

private _staticResult = [_position, _faction, _side, _staticConfig] call DSC_core_fnc_setupStaticDefenses;

(_result get "units") append (_staticResult get "units");
(_result get "vehicles") append (_staticResult get "vehicles");
(_result get "groups") append (_staticResult get "groups");

// --- Entry Guards (ground-floor positions at buildings) ---
private _factionData = _baseConfig getOrDefault ["factionData", createHashMap];
private _roleData = _factionData getOrDefault ["opFor", _factionData getOrDefault ["bluFor", createHashMap]];
private _roleGroups = _roleData getOrDefault ["groups", createHashMap];
private _footGroups = [];
{
    _footGroups append _y;
} forEach _roleGroups;
_footGroups = _footGroups select {
    private _tags = _x getOrDefault ["doctrineTags", []];
    ("FOOT" in _tags || "PATROL" in _tags) && { !("ARMOR" in _tags) } && { !("NAVAL" in _tags) }
};

if (_footGroups isNotEqualTo []) then {
    private _entryGuardConfig = createHashMapFromArray [
        ["mainStructures", _mainStructures],
        ["sideStructures", _sideStructures],
        ["buildingCoverage", 0.3]
    ];

    private _guardResult = [_position, _footGroups, _side, _entryGuardConfig] call DSC_core_fnc_setupGuards;

    (_result get "units") append (_guardResult get "units");
    (_result get "groups") append (_guardResult get "groups");
} else {
    diag_log "DSC: fnc_setupBase - No foot groups available for entry guards";
};

// ============================================================================
// Zone Vehicle Placement (Player Base)
// ============================================================================
if (_type == "playerBase") then {
    private _zones = _result get "zones";

    // --- Heliport: transport helicopters on visible pads ---
    private _heliportZone = _zones getOrDefault ["heliport", createHashMap];
    private _heliportPads = _heliportZone getOrDefault ["pads", []];
    private _transportHelos = (_assets getOrDefault ["helicopters", createHashMap]) getOrDefault ["transport", []];

    if (_heliportPads isNotEqualTo [] && _transportHelos isNotEqualTo []) then {
        {
            if (random 1 > 0.5) then { continue };
            private _pad = _x;
            private _padPos = getPos _pad;
            private _padDir = getDir _pad;
            private _heloClass = selectRandom _transportHelos;

            private _helo = createVehicle [_heloClass, _padPos, [], 0, "NONE"];
            _helo setPos _padPos;
            _helo setDir _padDir;
            _helo setFuel 1;
            _helo lock 0; // Unlocked

            (_result get "vehicles") pushBack _helo;
            (_heliportZone get "vehicles") pushBack _helo;

            diag_log format ["DSC: fnc_setupBase - Heliport: placed %1 on pad at %2", _heloClass, _padPos];
        } forEach _heliportPads;
    };

    // --- Airstrip: planes only on invisible pads ---
    private _airstripZone = _zones getOrDefault ["airstrip", createHashMap];
    private _airstripPads = _airstripZone getOrDefault ["pads", []];
    private _transportPlanes = (_assets getOrDefault ["planes", createHashMap]) getOrDefault ["transport", []];
    private _attackPlanes = (_assets getOrDefault ["planes", createHashMap]) getOrDefault ["attack", []];
    private _airstripPool = _transportPlanes + _attackPlanes;

    if (_airstripPads isNotEqualTo [] && _airstripPool isNotEqualTo []) then {
        {
            if (random 1 > 0.3) then { continue };
            private _pad = _x;
            private _padPos = getPos _pad;
            private _padDir = getDir _pad;
            private _acClass = selectRandom _airstripPool;

            private _ac = createVehicle [_acClass, _padPos, [], 0, "NONE"];
            _ac setPos _padPos;
            _ac setDir _padDir;
            _ac setFuel 1;
            _ac lock 0;

            (_result get "vehicles") pushBack _ac;
            (_airstripZone get "vehicles") pushBack _ac;

            diag_log format ["DSC: fnc_setupBase - Airstrip: placed %1 at %2", _acClass, _padPos];
        } forEach _airstripPads;
    };

    // --- Motor Pool: ground vehicles on invisible pads only ---
    private _motorpoolZone = _zones getOrDefault ["motorpool", createHashMap];
    private _motorpoolPads = _motorpoolZone getOrDefault ["pads", []];
    // Only use invisible helipads for ground vehicles
    private _motorpoolInvisible = _motorpoolPads select { typeOf _x == "Land_HelipadEmpty_F" };
    private _carsArmed = (_assets getOrDefault ["cars", createHashMap]) getOrDefault ["armed", []];
    private _carsMrap = (_assets getOrDefault ["cars", createHashMap]) getOrDefault ["mrap", []];
    private _groundTrucks = _assets getOrDefault ["trucks", []];
    private _groundApcs = _assets getOrDefault ["apcs", []];
    private _groundPool = _carsArmed + _carsMrap + _groundTrucks + _groundApcs;

    if (_motorpoolInvisible isNotEqualTo [] && _groundPool isNotEqualTo []) then {
        {
            if (random 1 > 0.3) then { continue };
            private _pad = _x;
            private _padPos = getPos _pad;
            private _padDir = getDir _pad;
            private _vehClass = selectRandom _groundPool;

            private _veh = createVehicle [_vehClass, _padPos, [], 0, "NONE"];
            _veh setPos _padPos;
            _veh setDir _padDir;
            _veh setFuel 1;
            _veh lock 0;

            (_result get "vehicles") pushBack _veh;
            (_motorpoolZone get "vehicles") pushBack _veh;

            diag_log format ["DSC: fnc_setupBase - Motor Pool: placed %1 at %2", _vehClass, _padPos];
        } forEach _motorpoolInvisible;
    };

    // --- TOC: utility vehicles on invisible pads, helicopters on visible pads ---
    private _tocZone = _zones getOrDefault ["toc", createHashMap];
    private _tocPads = _tocZone getOrDefault ["pads", []];
    private _utilityPool = (_assets getOrDefault ["cars", createHashMap]) getOrDefault ["unarmed", []];

    if (_tocPads isNotEqualTo []) then {
        {
            private _pad = _x;
            private _padPos = getPos _pad;
            private _padDir = getDir _pad;
            private _isInvisible = typeOf _pad == "Land_HelipadEmpty_F";

            if (_isInvisible) then {
                if (_utilityPool isEqualTo []) then { continue };
                private _vehClass = selectRandom _utilityPool;
                private _veh = createVehicle [_vehClass, _padPos, [], 0, "NONE"];
                _veh setPos _padPos;
                _veh setDir _padDir;
                _veh setFuel 1;
                _veh lock 0;

                (_result get "vehicles") pushBack _veh;
                (_tocZone get "vehicles") pushBack _veh;
                diag_log format ["DSC: fnc_setupBase - TOC: placed utility %1 at %2", _vehClass, _padPos];
            } else {
                if (_transportHelos isEqualTo []) then { continue };
                private _heloClass = selectRandom _transportHelos;
                private _helo = createVehicle [_heloClass, _padPos, [], 0, "NONE"];
                _helo setPos _padPos;
                _helo setDir _padDir;
                _helo setFuel 1;
                _helo lock 0;

                (_result get "vehicles") pushBack _helo;
                (_tocZone get "vehicles") pushBack _helo;
                diag_log format ["DSC: fnc_setupBase - TOC: placed helo %1 at %2", _heloClass, _padPos];
            };
        } forEach _tocPads;
    };
};

// ============================================================================
// Vehicle Placement (BluFor / OpFor Bases)
// ============================================================================
if (_type in ["bluFor", "opFor"]) then {
    // Scan for any helipads in the base area
    private _basePads = nearestObjects [_position, _visibleHelipadTypes, _radius];

    if (_basePads isNotEqualTo []) then {
        private _heloPool = if (_type == "opFor") then {
            private _attack = (_assets getOrDefault ["helicopters", createHashMap]) getOrDefault ["attack", []];
            private _transport = (_assets getOrDefault ["helicopters", createHashMap]) getOrDefault ["transport", []];
            _attack + _transport
        } else {
            (_assets getOrDefault ["helicopters", createHashMap]) getOrDefault ["transport", []]
        };

        if (_heloPool isNotEqualTo []) then {
            private _maxHelos = 2 min count _basePads;
            for "_i" from 0 to (_maxHelos - 1) do {
                private _pad = _basePads select _i;
                private _padPos = getPos _pad;
                private _padDir = getDir _pad;
                private _heloClass = selectRandom _heloPool;

                private _helo = createVehicle [_heloClass, _padPos, [], 0, "NONE"];
                _helo setPos _padPos;
                _helo setDir _padDir;
                _helo setFuel 1;
                _helo lock 2; // Locked for AI bases

                (_result get "vehicles") pushBack _helo;

                diag_log format ["DSC: fnc_setupBase - %1 base helo: %2 at %3", _type, _heloClass, _padPos];
            };
        };
    };

    // Ground vehicles via parking position finder
    private _gpArmed = (_assets getOrDefault ["cars", createHashMap]) getOrDefault ["armed", []];
    private _gpMrap = (_assets getOrDefault ["cars", createHashMap]) getOrDefault ["mrap", []];
    private _gpTrucks = _assets getOrDefault ["trucks", []];
    private _groundPool = _gpArmed + _gpMrap + _gpTrucks;

    if (_groundPool isNotEqualTo []) then {
        private _maxGround = [2, 3] select (_type == "opFor");
        private _parkSpots = [_position, _radius * 0.7, _maxGround] call DSC_core_fnc_findParkingPosition;
        {
            _x params ["_spotPos", "_spotDir"];
            private _vehClass = selectRandom _groundPool;
            private _veh = createVehicle [_vehClass, _spotPos, [], 0, "NONE"];
            _veh setPos _spotPos;
            _veh setDir _spotDir;
            _veh setFuel 1;
            _veh lock 2;

            (_result get "vehicles") pushBack _veh;
            diag_log format ["DSC: fnc_setupBase - %1 ground vehicle: %2 at %3", _type, _vehClass, _spotPos];
        } forEach _parkSpots;
    };
};

// ============================================================================
// Dynamic Simulation
// ============================================================================
private _allUnits = _result get "units";
private _allVehicles = _result get "vehicles";

{ _x triggerDynamicSimulation true } forEach _allUnits;
{ _x triggerDynamicSimulation true } forEach _allVehicles;

diag_log format ["DSC: fnc_setupBase - '%1' complete: %2 units, %3 vehicles, %4 groups (dynSim enabled)",
    _name, count _allUnits, count _allVehicles, count (_result get "groups")];

_result
