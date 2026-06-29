#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_getSkillProfile
 * Description:
 *     Returns an AI skill profile hashmap for a given difficulty level.
 *     Apply to units with fnc_applySkillProfile.
 *
 *     Profiles are designed around player experience:
 *     - "moderate": Forgiving, good for casual coop. AI misses often, reacts slowly.
 *     - "hard": Challenging. AI is accurate and reacts quickly but not instant.
 *     - "realism": Lethal. Fast spotting, accurate fire, aggressive behavior.
 *
 * Arguments:
 *     0: _profileName <STRING> - "moderate", "hard", or "realism"
 *
 * Return Value:
 *     <HASHMAP> - Skill values keyed by sub-skill name
 *
 * Example:
 *     private _profile = ["hard"] call DSC_core_fnc_getSkillProfile;
 */

params [
    ["_profileName", "moderate", [""]]
];

private _profile = switch (toLower _profileName) do {
    case "cqb_baseline": {
        createHashMapFromArray [
            ["aimingAccuracy", 0.2],
            ["aimingShake",    0.3],
            ["aimingSpeed",    0.3],
            ["spotDistance",   0.5],
            ["spotTime",       0.5], // Drop at night if not nightvision-capable
            ["courage",        0.5],
            ["commanding",     0.5]
        ]
    };

    case "garrison_light": {
        // Softer than cqb_baseline. "Guy looks up from a chair when shot at"
        // rather than "instant headshot." Used by indoor light-military
        // garrisons in towns/compounds — ambient encounters, not hardpoints.
        createHashMapFromArray [
            ["aimingAccuracy", 0.12],   // Wide spray, lots of misses
            ["aimingShake",    0.25],   // Visible sway
            ["aimingSpeed",    0.2],    // Slow target tracking
            ["spotDistance",   0.35],   // Won't notice you from far
            ["spotTime",       0.25],   // Slow reaction after combat activation
            ["courage",        0.45],   // Will retreat under sustained pressure
            ["commanding",     0.4]
        ]
    };

    case "moderate": {
        createHashMapFromArray [
            // --- Aiming ---
            ["aimingAccuracy", 0.15],   // How tight shots group. 0.15 = lots of misses, suppressive feel
            ["aimingShake", 0.3],       // Weapon sway. Lower = more shake = less precise
            ["aimingSpeed", 0.25],      // How fast AI tracks moving targets. Low = slow to adjust

            // --- Detection ---
            ["spotDistance", 0.4],      // Range at which AI detects enemies. 0.4 = won't spot you from far
            ["spotTime", 0.3],          // Reaction speed after detection. Low = slow to engage

            // --- Behavior ---
            ["courage", 0.4],           // Morale. Low = more likely to flee/suppress. 0.4 = will retreat under pressure
            ["commanding", 0.4],        // How fast squad leaders share targets. Low = uncoordinated squads
            ["general", 0.4],           // Overall tactical intelligence. Affects positioning, cover usage

            // --- Combat ---
            ["endurance", 0.4],         // Suppression effectiveness and formation discipline
            ["reloadSpeed", 0.5]        // Reload/weapon switch speed. 0.5 = average
        ]
    };

    case "hard": {
        createHashMapFromArray [
            // --- Aiming ---
            ["aimingAccuracy", 0.35],   // Noticeably more accurate. Will land hits at medium range
            ["aimingShake", 0.5],       // Steadier aim, less random spray
            ["aimingSpeed", 0.5],       // Tracks moving targets at reasonable speed

            // --- Detection ---
            ["spotDistance", 0.6],      // Detects at longer range. Harder to sneak up on
            ["spotTime", 0.5],          // Reacts within a couple seconds of spotting

            // --- Behavior ---
            ["courage", 0.6],           // Holds position under fire longer. Won't break easily
            ["commanding", 0.6],        // Squads coordinate faster, share targets quicker
            ["general", 0.6],           // Better use of cover, flanking, tactical movement

            // --- Combat ---
            ["endurance", 0.6],         // Better suppression, maintains formation
            ["reloadSpeed", 0.6]        // Faster reloads, less downtime
        ]
    };

    case "realism": {
        createHashMapFromArray [
            // --- Aiming ---
            ["aimingAccuracy", 0.55],   // Accurate at range. First shots are dangerous
            ["aimingShake", 0.7],       // Steady. Aimed shots will connect
            ["aimingSpeed", 0.7],       // Quickly tracks targets. Peeking is risky

            // --- Detection ---
            ["spotDistance", 0.8],      // Long detection range. Must use terrain to approach
            ["spotTime", 0.7],          // Fast reaction. Little time between spotted and shot at

            // --- Behavior ---
            ["courage", 0.75],          // Will fight to the death in most cases
            ["commanding", 0.75],       // Squads coordinate well, flanking maneuvers
            ["general", 0.75],          // Strong tactical AI. Uses cover, suppresses, bounds

            // --- Combat ---
            ["endurance", 0.7],         // Effective suppression, disciplined movement
            ["reloadSpeed", 0.7]        // Quick weapon handling
        ]
    };

    default {
        WARNING_1("Unknown skill profile '%1', defaulting to moderate",_profileName);
        ["moderate"] call DSC_core_fnc_getSkillProfile
    };
};

_profile
