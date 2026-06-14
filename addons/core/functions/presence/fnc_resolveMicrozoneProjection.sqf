/*
 * Function: DSC_core_fnc_resolveMicrozoneProjection
 * Description:
 *     Resolves "how much military presence does the nearest controlling
 *     installation project onto this microzone?" Sprint D.5.
 *
 *     A controlling faction with a base/outpost/camp nearby projects guards
 *     + patrols outward into surrounding compounds. Strength falls off with
 *     distance and is multiplied by a per-zone-type weight (high for
 *     infrastructure, low for farmland).
 *
 *     Reads precomputed nearest-controller data off the zone hashmap
 *     (populated by fnc_initPresenceManager during microzone registration)
 *     so this helper is O(1) at tick time.
 *
 *     Formula:
 *       strength      = controller.influence * (1 - dist / projectionRange)
 *       guardChance   = baseGuard  * strength * typeMultiplier
 *       patrolChance  = basePatrol * strength * typeMultiplier
 *
 *     baseGuard  = 0.55
 *     basePatrol = 0.45
 *
 *     When no controller is within projectionRange, strength is 0 and the
 *     handler falls back to its own civilian/irregular logic.
 *
 * Zone hashmap fields read:
 *     controllerDist        <NUMBER>  precomputed distance to nearest installation
 *     controllerSide        <SIDE>    side of controlling faction (east/west)
 *     controllerFaction     <STRING>  cfg faction id
 *     controllerInfluence   <NUMBER>  0..1 influence of the controller
 *     controllerType        <STRING>  "base"|"outpost"|"camp"
 *     controllerControl     <STRING>  "opFor"|"bluFor"|"contested"
 *     controllerProjRange   <NUMBER>  projection range used at precompute
 *
 * Registry fields read (DSC_presenceHandlers[zone.type].military):
 *     typeMultiplier        <NUMBER>  default 1.0
 *     guard.size            <ARRAY>   [min,max]
 *     guard.radius          <NUMBER>  satellite spawn radius
 *     guard.skill           <STRING>
 *     guard.irregularFallback <BOOL>  use irregulars when no controller in range
 *     patrol.size           <ARRAY>
 *     patrol.radius         <NUMBER>  patrol waypoint radius
 *     patrol.skill          <STRING>
 *
 * Arguments:
 *     0: _zone <HASHMAP>
 *
 * Return Value:
 *     <HASHMAP>
 *       "controllerSide"     <SIDE>
 *       "controllerFaction"  <STRING>
 *       "controllerControl"  <STRING>
 *       "guardChance"        <NUMBER>
 *       "patrolChance"       <NUMBER>
 *       "guardSize"          <ARRAY>  [min,max] copied from handler
 *       "guardRadius"        <NUMBER>
 *       "guardSkill"         <STRING>
 *       "patrolSize"         <ARRAY>
 *       "patrolRadius"       <NUMBER>
 *       "patrolSkill"        <STRING>
 *       "strength"           <NUMBER>  raw projection strength, for debug
 *       "irregularFallback"  <BOOL>
 */

params [["_zone", createHashMap, [createHashMap]]];

private _zType = _zone get "type";
private _registry = missionNamespace getVariable ["DSC_presenceHandlers", createHashMap];
private _handler  = _registry getOrDefault [_zType, createHashMap];
private _military = _handler getOrDefault ["military", createHashMap];

private _typeMult = _military getOrDefault ["typeMultiplier", 1.0];

private _guardCfg  = _military getOrDefault ["guard",  createHashMap];
private _patrolCfg = _military getOrDefault ["patrol", createHashMap];

private _result = createHashMapFromArray [
    ["controllerSide",    sideUnknown],
    ["controllerFaction", ""],
    ["controllerControl", "neutral"],
    ["guardChance",       0],
    ["patrolChance",      0],
    ["guardSize",         _guardCfg  getOrDefault ["size",   [2, 3]]],
    ["guardRadius",       _guardCfg  getOrDefault ["radius", 30]],
    ["guardSkill",        _guardCfg  getOrDefault ["skill",  "garrison_light"]],
    ["patrolSize",        _patrolCfg getOrDefault ["size",   [2, 3]]],
    ["patrolRadius",      _patrolCfg getOrDefault ["radius", 250]],
    ["patrolSkill",       _patrolCfg getOrDefault ["skill",  "garrison_light"]],
    ["strength",          0],
    ["irregularFallback", _guardCfg  getOrDefault ["irregularFallback", false]]
];

private _hasController = (_zone getOrDefault ["controllerFaction", ""]) != ""
                      || (_zone getOrDefault ["controllerControl", "neutral"]) != "neutral";

if (!_hasController) exitWith { _result };

private _ctrlDist   = _zone getOrDefault ["controllerDist", 999999];
private _ctrlInf    = _zone getOrDefault ["controllerInfluence", 0];
private _projRange  = _zone getOrDefault ["controllerProjRange", 3000];

private _strength = 0;
if (_projRange > 0 && _ctrlDist < _projRange) then {
    _strength = _ctrlInf * (1 - (_ctrlDist / _projRange));
    if (_strength < 0) then { _strength = 0 };
    if (_strength > 1) then { _strength = 1 };
};

// Sprint D.5 tuning iteration (June 2026 stress test): with narrower
// 1.1km activate radius, fewer zones live at once — push chance higher
// so individual encounters are denser rather than thinly spread.
private _baseGuard  = 0.35;
private _basePatrol = 0.15;

private _guardChance  = (_baseGuard  * _strength * _typeMult) min 1;
private _patrolChance = (_basePatrol * _strength * _typeMult) min 1;

// Handlers with no guard config (e.g. agriculturalSite) effectively never
// roll a guard/patrol. Same for empty patrol cfg.
if (_guardCfg  isEqualTo createHashMap) then { _guardChance  = 0 };
if (_patrolCfg isEqualTo createHashMap) then { _patrolChance = 0 };

_result set ["controllerSide",    _zone getOrDefault ["controllerSide", sideUnknown]];
_result set ["controllerFaction", _zone getOrDefault ["controllerFaction", ""]];
_result set ["controllerControl", _zone getOrDefault ["controllerControl", "neutral"]];
_result set ["guardChance",       _guardChance];
_result set ["patrolChance",      _patrolChance];
_result set ["strength",          _strength];

_result
