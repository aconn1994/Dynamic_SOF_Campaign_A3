#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_drawCompoundMarkers
 * Description:
 *     Draws SOF raid-style compound intel markers for any RAID-style mission:
 *       - One Contact_circle4 per cluster center (cluster A, B, C...)
 *       - Alpha-numeric dot markers on each building in/near the cluster
 *         (A1, A2... B1, B2...) for radio callout reference
 *
 *     Large locations (cities/towns/villages or buildingCount > 25) only mark
 *     buildings within a tight radius of each cluster anchor. Small/isolated
 *     locations mark every building in the cluster plus a clearance ring of
 *     nearby Houses for full compound detail.
 *
 *     Buildings already marked by an earlier cluster are not re-marked.
 *
 * Arguments:
 *     0: _clusters <ARRAY>   - Cluster hashmaps; each needs "center" and
 *                              "buildings". Typically _ao get "garrisonClusters".
 *     1: _location <HASHMAP> - Location object (used for large-location detect)
 *     2: _config <HASHMAP>   - Optional overrides:
 *        "circleType"        <STRING>  Marker type for cluster center (default "Contact_circle4")
 *        "circleColor"       <STRING>  (default "ColorRed")
 *        "dotColor"          <STRING>  (default "ColorBlack")
 *        "namePrefix"        <STRING>  Marker name prefix (default "dsc")
 *        "nearbyRadius"      <NUMBER>  Clearance ring around each cluster building (default 50)
 *        "largeLocationDots" <NUMBER>  Dot radius when location is large (default 75)
 *        "smallLocationDots" <NUMBER>  Dot radius when location is small (default 999)
 *        "isLarge"           <BOOL>    Override auto-detect
 *
 * Return Value:
 *     <ARRAY> - All marker names created (push onto mission "markers" array
 *               for cleanup).
 *
 * Example:
 *     private _markers = [
 *         _ao getOrDefault ["garrisonClusters", []],
 *         _location
 *     ] call DSC_core_fnc_drawCompoundMarkers;
 */

params [
    ["_clusters", [], [[]]],
    ["_location", createHashMap, [createHashMap]],
    ["_config", createHashMap, [createHashMap]]
];

private _circleType = _config getOrDefault ["circleType", "Contact_circle4"];
private _circleColor = _config getOrDefault ["circleColor", "ColorRed"];
private _dotColor = _config getOrDefault ["dotColor", "ColorBlack"];
private _namePrefix = _config getOrDefault ["namePrefix", "dsc"];
private _nearbyRadius = _config getOrDefault ["nearbyRadius", 50];
private _largeRadius = _config getOrDefault ["largeLocationDots", 75];
private _smallRadius = _config getOrDefault ["smallLocationDots", 999];

// Auto-detect large location unless caller overrode
private _locType = _location getOrDefault ["locType", ""];
private _buildingCount = _location getOrDefault ["buildingCount", 0];
private _isLargeAuto = _locType in ["NameCityCapital", "NameCity", "NameVillage"] || _buildingCount > 25;
private _isLarge = _config getOrDefault ["isLarge", _isLargeAuto];
private _dotRadius = [_smallRadius, _largeRadius] select _isLarge;

private _clusterLetters = ["A","B","C","D","E","F","G","H","I","J","K","L"];
private _markers = [];
private _markedBuildings = [];

{
    private _cluster = _x;
    private _clusterCenter = _cluster get "center";
    private _clusterBuildings = _cluster get "buildings";
    private _letter = _clusterLetters select (_forEachIndex min (count _clusterLetters - 1));

    // Contact circle on the cluster anchor
    private _circleName = format ["%1_cluster_%2", _namePrefix, _forEachIndex];
    private _circleMarker = createMarker [_circleName, _clusterCenter];
    _circleMarker setMarkerTypeLocal _circleType;
    _circleMarker setMarkerColor _circleColor;
    _markers pushBack _circleName;

    // Gather buildings within clearance radius, skip already-marked by prior clusters
    private _buildingsToMark = [];
    {
        private _bldg = _x;
        if (_bldg distance2D _clusterCenter < _dotRadius && { !(_bldg in _markedBuildings) }) then {
            _buildingsToMark pushBackUnique _bldg;
        };
        {
            if (_x distance2D _bldg <= _nearbyRadius && { !(_x in _markedBuildings) }) then {
                _buildingsToMark pushBackUnique _x;
            };
        } forEach (nearestObjects [getPos _bldg, ["House"], _nearbyRadius]);
    } forEach _clusterBuildings;

    _markedBuildings append _buildingsToMark;

    {
        private _bldgPos = getPos _x;
        private _label = format ["%1%2", _letter, _forEachIndex + 1];
        private _dotName = format ["%1_bldg_%2_%3", _namePrefix, _letter, _forEachIndex];
        private _dotMarker = createMarker [_dotName, _bldgPos];
        _dotMarker setMarkerTypeLocal "mil_dot";
        _dotMarker setMarkerColorLocal _dotColor;
        _dotMarker setMarkerTextLocal format [" %1", _label];
        _dotMarker setMarkerSize [0.5, 0.5];
        _markers pushBack _dotName;
    } forEach _buildingsToMark;

    diag_log format ["DSC: drawCompoundMarkers - Cluster %1: %2 buildings marked (%3 garrisoned + nearby clearance)", _letter, count _buildingsToMark, count _clusterBuildings];
} forEach _clusters;

_markers
