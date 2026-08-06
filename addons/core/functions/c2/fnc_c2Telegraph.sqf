#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_c2Telegraph
 * Description:
 *     Sprint F.4 — always-visible cause-and-effect cues, independent of ISR
 *     coverage.
 *
 *     THE PROBLEM THIS SOLVES
 *
 *     Before F.4 the entire C2 network was invisible. A QRF would arrive and,
 *     from the player's chair, four vehicles simply materialised out of the
 *     terrain for no discernible reason. A simulation the player cannot
 *     perceive is indistinguishable from random spawning — worse, it reads as
 *     unfair, because the player had no opportunity to notice or prevent it.
 *
 *     ISR-gated chatter is the *detailed* answer, but it must not be the only
 *     one. If the player needs a drone on station to understand why they are
 *     being flanked, then without a drone the system may as well not exist.
 *     So a minimal set of cues is ALWAYS available:
 *
 *       - a flare over a compound that just went to RED
 *       - vehicle lights leaving an installation at night
 *
 *     These are diegetic. They are things a person standing on that hillside
 *     would actually see, which is why they need no coverage gate and no UI.
 *     A player with no assets can still learn "the compound lit a flare, they
 *     know I'm here" and act on it.
 *
 *     WHY DISTANCE-GATED
 *
 *     Fired unconditionally these would light up the whole terrain — the
 *     network raises alerts constantly across dozens of nodes, and flares
 *     visible from 8 km away are noise, not signal. Only events within
 *     plausible visual range of a player produce an effect.
 *
 * Arguments:
 *     0: _type <STRING> - "ALERT_RED" | "DISPATCH"
 *     1: _pos  <ARRAY>  - world position of the originating node
 *
 * Return Value:
 *     <BOOL> - true if a cue was produced
 */

params [
    ["_type", "", [""]],
    ["_pos",  [], [[]]]
];

if (!isServer) exitWith { false };
if (_type isEqualTo "" || {_pos isEqualTo []}) exitWith { false };

// ============================================================================
// Visual-range gate
// ============================================================================
// 3 km is generous for a flare at night and roughly the limit at which vehicle
// lights read as a moving light source rather than a dot. Beyond that the cue
// is noise.
private _anyNear = false;
{
    if (alive _x && {(getPosASL _x) distance2D _pos < 3000}) exitWith { _anyNear = true };
} forEach allPlayers;

if (!_anyNear) exitWith { false };

switch (_type) do {

    // ------------------------------------------------------------------------
    // ALERT_RED — a node has confirmed contact
    // ------------------------------------------------------------------------
    // An illumination flare is the perfect telegraph: unmistakable, diegetic,
    // directional, and it genuinely changes the tactical situation by lighting
    // the area. The player reads "they know" without a single line of UI.
    case "ALERT_RED": {
        // Only meaningful in darkness. In daylight a flare is invisible and
        // the cue would be wasted — daytime players rely on chatter and on
        // seeing the response itself.
        if (sunOrMoon > 0.35) exitWith { false };

        private _flarePos = [_pos select 0, _pos select 1, 220];
        private _flare = createVehicle ["F_20mm_White", _flarePos, [], 0, "CAN_COLLIDE"];
        if (isNull _flare) exitWith { false };

        // Slight outward drift so it arcs rather than dropping dead vertical.
        private _dir = random 360;
        _flare setVelocity [(sin _dir) * 6, (cos _dir) * 6, -2];

        LOG_1("c2Telegraph - ALERT_RED flare at %1",_pos);
        true
    };

    // ------------------------------------------------------------------------
    // DISPATCH — something has been sent
    // ------------------------------------------------------------------------
    // Headlights leaving a base at night is the single most useful telegraph in
    // the design: it gives bearing and timing, which is exactly the information
    // that lets a player break contact or set an ambush. Deliberately NOT
    // ISR-gated for that reason.
    case "DISPATCH": {
        if (sunOrMoon > 0.35) exitWith { false };

        // Force lights on any vehicle leaving the area. The AI often decides
        // to run dark, which silently removes the cue.
        private _lit = 0;
        {
            private _veh = _x;
            if (alive _veh && {(getPosASL _veh) distance2D _pos < 400} && {!isNull (driver _veh)}) then {
                _veh setPilotLight true;
                _lit = _lit + 1;
            };
        } forEach vehicles;

        LOG_2("c2Telegraph - DISPATCH lights on %1 vehicle(s) near %2",_lit,_pos);
        _lit > 0
    };

    default {
        WARNING_1("c2Telegraph - unknown cue type '%1'",_type);
        false
    };
};
