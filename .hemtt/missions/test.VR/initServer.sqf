// =================================================================
// =================  Setup Group Classifications  =================
// =================================================================
_opForGroups = ["OPF_F"] call DSC_core_fnc_extractGroups;
_classifiedGroups = [_opForGroups] call DSC_core_fnc_classifyGroups;

private _basicInfantrySquadGroups = [_classifiedGroups, ["FOOT", "INFANTRY_SQUAD", "PATROL"], ["ELITE", "SCOUT_RECON", "AMPHIBIOUS"]] call DSC_core_fnc_getGroupsByTag;
private _basicInfantryFireteamGroups = [_classifiedGroups, ["FOOT", "FIRETEAM", "PATROL"], ["ELITE", "SCOUT_RECON", "AMPHIBIOUS"]] call DSC_core_fnc_getGroupsByTag;
private _eliteInfantrySquadGroups = [_classifiedGroups, ["FOOT", "INFANTRY_SQUAD", "PATROL", "ELITE"], ["SCOUT_RECON", "AMPHIBIOUS"]] call DSC_core_fnc_getGroupsByTag;
private _eliteInfantryFireteamGroups = [_classifiedGroups, ["FOOT", "FIRETEAM", "PATROL", "ELITE"], ["SCOUT_RECON", "AMPHIBIOUS"]] call DSC_core_fnc_getGroupsByTag;

// =================================================================
// =======================  Get Structures  ========================
// =================================================================
private _structureCategories = ["BUILDING", "HOUSE", "BUNKER", "FORTRESS", "HOSPITAL", "VIEW-TOWER", "MILITARY", "VILLAGE", "CITY"];
private _locationStructures = nearestObjects [(getPos testUnit), _structureCategories, 500];

private _mainStructures = [];
private _sideStructures = [];
private _militaryTowers = []; // Cargo towers, patrol structures - fill top-down

// Military tower/lookout structure types
private _towerTypes = ["Cargo_HQ_base_F", "Cargo_Patrol_base_F", "Cargo_Tower_base_F"];

{
    private _struct = _x;
    private _noOfPositions = count (_x buildingPos -1);

    if (_noOfPositions == 0) then { continue };

    // Check if this is a military tower structure
    private _isTower = false;
    {
        if (_struct isKindOf _x) exitWith { _isTower = true };
    } forEach _towerTypes;

    if (_isTower) then {
        _militaryTowers pushBack _struct;
        _mainStructures pushBack _struct;
    } else {
        if (_noOfPositions >= 5) then {
            _mainStructures pushBack _struct;
        };
        if (_noOfPositions < 5) then {
            _sideStructures pushBack _struct;
        };
    };
} forEach _locationStructures;

diag_log format ["Main Structures found: %1", count _mainStructures];
diag_log format ["Side Structures found: %1", count _sideStructures];
diag_log format ["Military Towers found: %1", count _militaryTowers];

private _allGroups = _basicInfantrySquadGroups + _basicInfantryFireteamGroups + _eliteInfantrySquadGroups + _eliteInfantryFireteamGroups;


sleep 5;
// =================================================================
// ================  Determine Group/Unit Spawns  ==================
// =================================================================
// "Anchor + Satellites" Model (Option 5 from spike)
// 1. Roll density profile for the area
// 2. Pick anchor buildings (main structures)
// 3. Assign groups to anchors with satellite overflow

// Step 1: Roll density profile
private _densityProfile = selectRandomWeighted [
    "light", 0.30,
    "medium", 0.45,
    "heavy", 0.25
];

// Density determines: number of anchors, group sizes, satellite count
private _densityConfig = switch (_densityProfile) do {
    case "light": {
        createHashMapFromArray [
            ["anchorCount", [1, 3]],      // min, max anchors
            ["groupsPerAnchor", [1, 1]],  // min, max groups per anchor
            ["satelliteCount", [0, 1]],   // min, max satellites per anchor
            ["positionFill", 0.5]         // % of positions to fill
        ]
    };
    case "medium": {
        createHashMapFromArray [
            ["anchorCount", [2, 4]],
            ["groupsPerAnchor", [1, 2]],
            ["satelliteCount", [1, 2]],
            ["positionFill", 0.7]
        ]
    };
    case "heavy": {
        createHashMapFromArray [
            ["anchorCount", [3, 5]],
            ["groupsPerAnchor", [1, 2]],
            ["satelliteCount", [2, 3]],
            ["positionFill", 0.9]
        ]
    };
};

diag_log format ["DSC: Density profile: %1", _densityProfile];

// Step 2: Select anchor buildings from main structures
private _anchorRange = _densityConfig get "anchorCount";
private _numAnchors = (_anchorRange select 0) + floor random ((_anchorRange select 1) - (_anchorRange select 0) + 1);
_numAnchors = _numAnchors min (count _mainStructures); // Can't have more anchors than main structures

private _availableMain = +_mainStructures;
private _availableSide = +_sideStructures;
private _anchors = [];

// Pick anchors spread apart (not all clustered together)
for "_i" from 1 to _numAnchors do {
    if (count _availableMain == 0) exitWith {};
    
    private _anchor = if (count _anchors == 0) then {
        // First anchor is random
        selectRandom _availableMain
    } else {
        // Subsequent anchors prefer distance from existing anchors
        private _sorted = [_availableMain, [], {
            private _struct = _x;
            private _minDist = 999999;
            { _minDist = _minDist min (_struct distance2D _x) } forEach _anchors;
            -_minDist // Negative for descending (furthest first)
        }, "ASCEND"] call BIS_fnc_sortBy;
        _sorted select 0
    };
    
    _anchors pushBack _anchor;
    _availableMain = _availableMain - [_anchor];
};

diag_log format ["DSC: Selected %1 anchor buildings", count _anchors];

// Track all spawned groups
private _spawnedGroups = [];

// Step 3a: Populate military towers with 1-2 lookouts at top positions
private _towerUnitsSpawned = 0;
private _towerLookoutPositions = []; // Collect top positions from all towers

{
    private _tower = _x;
    private _towerPositions = _tower buildingPos -1;
    
    // Sort positions by height descending (highest first)
    _towerPositions = [_towerPositions, [], { -(_x select 2) }, "ASCEND"] call BIS_fnc_sortBy;
    
    if (count _towerPositions == 0) then { continue };
    
    // Take only 1-2 highest positions for lookouts
    private _numLookouts = 1 + floor random 2; // 1 or 2
    private _lookoutPositions = _towerPositions select [0, _numLookouts min count _towerPositions];
    
    _towerLookoutPositions append _lookoutPositions;
    
    diag_log format ["DSC: Tower %1 contributing %2 lookout positions", _tower, count _lookoutPositions];
} forEach _militaryTowers;

// Spawn individual units for tower lookouts (not full groups)
if (count _towerLookoutPositions > 0) then {
    private _lookoutGroup = createGroup [east, true];
    
    {
        private _unit = _lookoutGroup createUnit ["O_Soldier_F", _x, [], 0, "NONE"];
        _unit allowDamage false;
        _unit setPos _x;
        _unit disableAI "PATH";
        _towerUnitsSpawned = _towerUnitsSpawned + 1;
    } forEach _towerLookoutPositions;
    
    _spawnedGroups pushBack _lookoutGroup;
    diag_log format ["DSC: Placed %1 tower lookouts", count _towerLookoutPositions];
};

diag_log format ["DSC: Total tower units spawned: %1", _towerUnitsSpawned];

// Step 3b: For each anchor, assign groups and satellites
private _satelliteRange = _densityConfig get "satelliteCount";
private _groupsPerAnchorRange = _densityConfig get "groupsPerAnchor";
private _positionFill = _densityConfig get "positionFill";

{
    private _anchor = _x;
    private _anchorPos = getPos _anchor;
    
    // Determine satellites for this anchor (nearby side structures)
    private _numSatellites = (_satelliteRange select 0) + floor random ((_satelliteRange select 1) - (_satelliteRange select 0) + 1);
    
    // Get closest side structures to this anchor
    private _nearbySide = [_availableSide, [], { _x distance2D _anchorPos }, "ASCEND"] call BIS_fnc_sortBy;
    private _satellites = [];
    
    for "_j" from 0 to (_numSatellites - 1) do {
        if (_j >= count _nearbySide) exitWith {};
        private _sat = _nearbySide select _j;
        // Only use satellites within 50m of anchor
        if (_sat distance2D _anchorPos < 50) then {
            _satellites pushBack _sat;
            _availableSide = _availableSide - [_sat];
        };
    };
    
    diag_log format ["DSC: Anchor %1 has %2 satellites", _anchor, count _satellites];
    
    // Collect all positions for this cluster (anchor + satellites)
    private _clusterBuildings = [_anchor] + _satellites;
    private _allPositions = [];
    
    {
        private _positions = _x buildingPos -1;
        _allPositions append _positions;
    } forEach _clusterBuildings;
    
    // Determine how many groups for this anchor
    private _numGroups = (_groupsPerAnchorRange select 0) + floor random ((_groupsPerAnchorRange select 1) - (_groupsPerAnchorRange select 0) + 1);
    
    // Calculate target unit count based on position fill
    private _targetUnits = floor ((count _allPositions) * _positionFill);
    private _unitsSpawned = 0;
    
    diag_log format ["DSC: Cluster has %1 positions, targeting %2 units", count _allPositions, _targetUnits];
    
    // Spawn groups until we hit target or run out of groups
    for "_g" from 1 to _numGroups do {
        if (_unitsSpawned >= _targetUnits) exitWith {};
        if (count _allGroups == 0) exitWith {};
        
        // Select a random group template
        private _selectedGroup = selectRandom _allGroups;
        private _groupPath = _selectedGroup get "path";
        private _groupName = _selectedGroup get "groupName";
        private _unitAnalysis = _selectedGroup get "unitAnalysis";
        private _groupSize = _unitAnalysis get "infantryCount";
        
        // Skip if group is too large for remaining positions
        if (_groupSize > (count _allPositions - _unitsSpawned)) then { continue };
        
        diag_log format ["DSC: Spawning group %1 (%2 units) at anchor", _groupName, _groupSize];
        
        // Parse the group path and spawn
        private _pathParts = _groupPath splitString "/";
        private _groupConfig = configFile >> "CfgGroups";
        { _groupConfig = _groupConfig >> _x } forEach _pathParts;
        
        private _spawnedGroup = [_anchorPos, east, _groupConfig] call BIS_fnc_spawnGroup;
        _spawnedGroups pushBack _spawnedGroup;
        
        // Place units in building positions
        {
            if (_unitsSpawned >= count _allPositions) exitWith {};
            
            _x allowDamage false;
            _x setPos (_allPositions select _unitsSpawned);
            _x disableAI "PATH";
            
            _unitsSpawned = _unitsSpawned + 1;
        } forEach units _spawnedGroup;
    };
    
    diag_log format ["DSC: Spawned %1 units in cluster", _unitsSpawned];
    
} forEach _anchors;

// Re-enable damage after positioning
sleep 2;
{
    { _x allowDamage true } forEach units _x;
} forEach _spawnedGroups;

diag_log format ["DSC: Total groups spawned: %1", count _spawnedGroups];




// =================================================================
// ===================  Add to Zeus for Debug  =====================
// =================================================================
// Add units/vehicles to zeus
_curator = ((allCurators) select 0); // The curator object

// Add all existing units to be editable by this curator
{
    _curator addCuratorEditableObjects [[_x], true];
} forEach allUnits;