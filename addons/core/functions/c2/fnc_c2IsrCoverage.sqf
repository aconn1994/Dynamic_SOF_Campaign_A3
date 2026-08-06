#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_c2IsrCoverage
 * Description:
 *     Sprint F.4 — "how well can the player see this piece of the enemy
 *     network right now?"
 *
 *     The C2 network has been fully functional since F.3 but almost entirely
 *     invisible: everything it did was legible only in the RPT. F.4 makes it
 *     perceivable, and this function is the gate that decides how much.
 *
 *     THE DESIGN CONSTRAINT
 *
 *     ISR must be a force multiplier on DECISION QUALITY, not a wallhack. The
 *     player should learn *that a response was launched, from where, and how
 *     long they have* — information that rewards breaking contact,
 *     repositioning, or setting an ambush. They should NOT get a free target
 *     list. So coverage grants access to the enemy's CONVERSATION, never to
 *     their unit positions.
 *
 *     FIDELITY TIERS
 *
 *       NONE     (0) - no access. The world behaves as it did before F.4:
 *                      the player sees consequences, never causes.
 *       BASIC    (1) - own eyes and ears. Traffic from nodes physically close
 *                      to the player, i.e. things they could plausibly notice.
 *       ENHANCED (2) - UAV on station. Intercepts across the drone's orbit,
 *                      plus dispatch notifications (the payoff tier).
 *       FULL     (3) - reserved for F.5 SIGINT (captured radios / hacked
 *                      infrastructure). Whole-network read access.
 *
 *     Tiers are a ceiling, not a switch: a line tagged `grade` is delivered
 *     only when the player's tier for that node's position is >= it.
 *
 *     DEGRADERS
 *
 *     Kept deliberately coarse. The point is that coverage is *conditional*
 *     and the player can feel it change, not that it is finely simulated:
 *       - the UAV must be ALIVE and have crew
 *       - the node must be inside the UAV's effective orbit radius
 *       - heavy fog or rain shrinks that radius
 *       - night has no penalty (SIGINT/radio intercept doesn't care about
 *         light, and punishing the player's preferred infil window would be
 *         backwards for a SOF mod)
 *
 * Arguments:
 *     0: _pos <ARRAY> - world position being observed (usually a node's)
 *
 * Return Value:
 *     <ARRAY> [_tier, _tierName, _reason]
 *       _tier     <NUMBER> 0..3
 *       _tierName <STRING> "NONE" | "BASIC" | "ENHANCED" | "FULL"
 *       _reason   <STRING> which source granted it, for the tablet header
 *
 * Example:
 *     ([_nodePos] call DSC_core_fnc_c2IsrCoverage) params ["_tier", "_name", "_why"];
 */

params [["_pos", [], [[]]]];

if (_pos isEqualTo []) exitWith { [0, "NONE", "no position"] };

private _tier   = 0;
private _reason = "no coverage";

// ============================================================================
// BASIC — the player's own presence
// ============================================================================
// Anything happening within earshot is something the player could reasonably
// be aware of. This is what makes the system legible with no assets at all:
// assault a compound and you hear its traffic, because you are standing in it.
private _player = call CBA_fnc_currentUnit;
if (!isNull _player) then {
    private _dPlayer = _pos distance2D (getPosASL _player);
    if (_dPlayer < 800) then {
        _tier   = 1;
        _reason = "local";
    };
};

// ============================================================================
// ENHANCED — persistent ISR drone on station
// ============================================================================
// The drone is the deliberate gate on the good information (dispatch alerts +
// ETAs). It has to be alive, crewed, and actually overhead — so losing it is a
// real loss, and the player has a reason to protect it.
private _uav = missionNamespace getVariable ["DSC_activeUAV", objNull];
if (!isNull _uav && {alive _uav} && {(crew _uav) isNotEqualTo []}) then {

    // Weather shrinks the effective orbit. Overcast alone is not enough —
    // fog and rain are what matter, and they are what the player can see out
    // the window, so the degrade is legible rather than mysterious.
    private _wx = (fog max rain) min 1;
    private _radius = 2500 * (1 - (_wx * 0.5));

    private _dUav = _pos distance2D (getPosASL _uav);
    if (_dUav < _radius) then {
        if (_tier < 2) then {
            _tier   = 2;
            _reason = "ISR drone";
        };
    };
};

// ============================================================================
// FULL — SIGINT (F.5 placeholder)
// ============================================================================
// Captured radios / hacked infrastructure will set this flag per faction or
// per region. Wired now so F.5 is purely additive and the tier plumbing is
// already exercised end to end.
if (missionNamespace getVariable ["DSC_c2SigintActive", false]) then {
    _tier   = 3;
    _reason = "SIGINT";
};

private _names = ["NONE", "BASIC", "ENHANCED", "FULL"];

[_tier, _names select _tier, _reason]
