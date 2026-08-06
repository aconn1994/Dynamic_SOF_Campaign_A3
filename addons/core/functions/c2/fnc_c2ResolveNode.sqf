#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_c2ResolveNode
 * Description:
 *     Sprint F.1 — "who owns this ground?" lookup.
 *
 *     Returns the id of the C2 node that would plausibly claim a group at
 *     a given position. Used for entities that aren't tied to a zone by
 *     construction — roving patrols, mission AO population, anything
 *     spawned in open terrain.
 *
 *     Matching is REACH-AWARE, not merely nearest. A node only claims
 *     ground it can actually project a response into, so a patrol caught
 *     10 km from the nearest outpost resolves to "" and is genuinely on
 *     its own. That absence is the intended behavior, not a failure — it
 *     is what makes operating far from installations meaningfully safer.
 *
 *     Among nodes that CAN reach the position, the winner is scored rather
 *     than picked purely by distance, so a strong nearby base outranks a
 *     weak village that happens to be marginally closer:
 *
 *         score = (1 - dist/reach) * (0.35 + influence * 0.65)
 *
 * Arguments:
 *     0: _pos      <ARRAY>  - position to resolve
 *     1: _side     <SIDE>   - required side (sideUnknown = any)
 *     2: _maxDist  <NUMBER> - hard distance cap, 0 = use node reach only
 *
 * Return Value:
 *     <STRING> - node id, or "" if nothing in range can claim it
 *
 * Example:
 *     private _nodeId = [getPos _grp, east] call DSC_core_fnc_c2ResolveNode;
 */

params [
    ["_pos",     [], [[]]],
    ["_side",    sideUnknown, [sideUnknown]],
    ["_maxDist", 0, [0]]
];

if (_pos isEqualTo []) exitWith { "" };

private _nodes = missionNamespace getVariable ["DSC_c2Nodes", createHashMap];
if (_nodes isEqualTo createHashMap) exitWith { "" };

private _bestId = "";
private _bestScore = -1;

{
    private _nodeId = _x;
    private _node = _nodes get _nodeId;

    private _sideOk = (_side isEqualTo sideUnknown) || {(_node get "side") isEqualTo _side};
    if (_sideOk) then {
        private _dist = (_node get "position") distance2D _pos;
        private _reach = _node get "reach";

        private _capOk = (_maxDist <= 0) || {_dist <= _maxDist};
        if (_capOk && {_dist <= _reach}) then {
            private _influence = _node getOrDefault ["influence", 0];
            private _proximity = 1 - (_dist / _reach);
            private _score = _proximity * (0.35 + (_influence * 0.65));
            if (_score > _bestScore) then {
                _bestScore = _score;
                _bestId = _nodeId;
            };
        };
    };
} forEach (keys _nodes);

_bestId
