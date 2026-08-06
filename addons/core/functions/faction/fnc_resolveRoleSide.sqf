#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_resolveRoleSide
 * Description:
 *     Single authority for "what engine side does this faction role actually
 *     spawn on?"
 *
 *     THE PROBLEM THIS SOLVES
 *
 *     Arma has three usable sides but DSC has five combatant roles, so roles
 *     have to share sides. The faction profile's natural mapping was:
 *
 *         bluFor        -> west
 *         bluForPartner -> independent      <-- player's allies
 *         opFor         -> east
 *         opForPartner  -> east
 *         irregulars    -> independent      <-- player's enemies
 *
 *     That double-books INDEPENDENT for both the player's partner forces and
 *     a hostile role. Arma diplomacy is SIDE-level — there is no per-faction
 *     relation — so it is literally impossible for AAF to be friendly to the
 *     player while Looters on the same side are hostile.
 *
 *     The old code papered over this with a blanket
 *     `east setFriend [independent, 1]` so opFor and irregulars would
 *     cooperate. But that also made the player's own AAF/Gendarmerie friendly
 *     to CSAT, and nothing ever set west<->independent explicitly, so the
 *     actual player relationship fell through to whatever the mission.sqm
 *     default happened to be. A playtest produced exactly the asymmetry that
 *     implies: enemy independents shooting at the player while the player's
 *     squad refused to return fire, because west considered them friendly.
 *
 *     THE RULE
 *
 *     INDEPENDENT is reserved for the player's side of the war. Any hostile
 *     role whose natural side is independent is FORCED TO EAST at spawn.
 *     `fnc_resolveIrregularOverlay` already did this locally; this makes it
 *     the global convention so mission generation, presence, and roving all
 *     agree.
 *
 *     Result — a clean three-way split that side-level diplomacy can express:
 *
 *         west        = player + bluFor
 *         independent = bluForPartner (allies, friendly to player)
 *         east        = opFor + opForPartner + irregulars (all hostile)
 *
 *     Cooperation between opFor and irregulars is then automatic: they are
 *     literally the same side, so no setFriend is needed at all.
 *
 * Arguments:
 *     0: _role     <STRING> - faction role key
 *     1: _natural  <SIDE>   - side from factionProfileConfig (fallback)
 *
 * Return Value:
 *     <SIDE> - the side this role must actually spawn on
 *
 * Example:
 *     private _side = ["irregulars", independent] call DSC_core_fnc_resolveRoleSide;  // east
 */

params [
    ["_role",    "", [""]],
    ["_natural", east, [east]]
];

switch (_role) do {
    case "bluFor":        { west };
    case "bluForPartner": { independent };

    // Hostile roles collapse onto east regardless of their faction's
    // natural side. This is the load-bearing line.
    case "opFor";
    case "opForPartner";
    case "irregulars":    { east };

    case "civilians";
    case "environmentalActors": { civilian };

    default { _natural };
};
