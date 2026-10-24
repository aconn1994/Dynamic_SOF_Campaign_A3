As we went through the `docs\campaign_overhaul\` development cycle, I realized that some of the different mission types I was planning would be a challenge, such as "SWEEP/OBSERVE", because it depends on the enemy AI which are unreliable.  SWEEP would work as a "Clear Area" or "Find and Eliminate Enemy in Area", but Observe is too tough because it purely relies on the AI doing what you need them to do at a specific moment.  I think a better avenue is to build up the world with a ton of variety, and put a smaller amount of responsibility on the AI.  I think simply using the "spotting" attribute on AI and manipulating that would work.

For example, I was previously trying to create explicit mission types for mission series to differentiate between AFO and DA style missions.  The DA style is fine, "a person is here, go kill/capture/rescue them." The AFO was too much responsibility on the AI, with SWEEP/OBSERVE its "get close enough without getting spotted".  When either I would walk right up next to them without being seen or I was spotted from 800 meters.  There is not alot that can be done about that given Armas engine constraints with AI.

My thought now is using the spotting attribute along with scaling the size of the missions.  An AFO mission might be to meet with an informant in a town.  The flow for the player is get to the informant without getting into a gunfight, speak with them, then leave without getting into a gunfight.  I can add to the briefing, use low visibility attire/weapons/vehicles/transportation, and maybe we can expermient with the spotting attribute on enemy units based on the faction type of CfgVehicles, but the mission doesn't depend on the AI doing the right thing in the right moment.  They are just an element to add variety, maybe they see you, maybe not. In real life lo-vis is not fool proof.  And then DA remains with a higher spotting attribute, because more than likely there will be military vehicles involved, larger assault force etc.

With this dynamic shift, I think the variety still lies with the ambient world.  Let me know what you think.

# Dynamic SOF Campaign (DSC)
## Mission Design Philosophy and Dynamic World Generation

**Status:** Design Direction  
**Project:** Dynamic SOF Campaign for Arma 3

---

## 1. Design Philosophy

DSC should prioritize a dynamic, believable operational environment over complex mission scripts that attempt to choreograph specific enemy AI behaviors.

Arma 3's AI is capable of providing engaging tactical encounters, but its behavior is not sufficiently predictable to reliably support mission objectives that depend on precise detection, patrol timing, or other specific reactions.

For example, a mission that requires the player to approach an enemy position without being detected can be undermined by inconsistent AI spotting behavior. An enemy might fail to notice a player at close range or detect them from an unreasonable distance. Attempting to compensate for these limitations with increasingly complex scripts introduces fragility and unnecessary development overhead.

DSC should instead create the conditions for interesting tactical experiences and allow the player and AI to determine how those situations unfold.

### Core Principles

- **The mission generator controls the situation.** Objectives, locations, enemy presence, faction composition, equipment, visibility, and environmental conditions establish the operational context.
- **The AI contributes uncertainty.** Patrols, detection, reactions, and opportunities create variation without being mandatory for mission completion.
- **The player creates the tactical experience.** Approach, observation, movement, engagement decisions, and withdrawal are driven primarily by player decisions.
- **Mission success depends on achievable objectives.** Essential mission progression must not rely on unreliable enemy behavior.
- **Replayability comes from combinations.** A relatively small collection of objective templates can produce varied experiences through differences in the surrounding world.

The objective is to build a robust, configuration-driven campaign where the environment creates the experience rather than a collection of bespoke scripts attempting to simulate every possible tactical situation.

---

## 2. AFO and DA as Operational Philosophies

DSC should retain the distinction between Advanced Force Operations (AFO) and Direct Action (DA), but these should represent different operational approaches rather than fundamentally different sets of AI behaviors.

### 2.1 AFO — Advanced Force Operations

AFO missions emphasize low visibility, access, reconnaissance, intelligence gathering, and discretion.

Typical characteristics:

- Limited personnel and equipment.
- Low-visibility weapons, clothing, and transportation where appropriate.
- Objectives involving people, locations, or information rather than immediate destruction.
- Greater emphasis on avoiding unnecessary escalation.
- Enemy presence that creates uncertainty without requiring a specific AI reaction.

Example objectives:

- Meet an informant in a town.
- Identify a suspected weapons shipment.
- Photograph a communications installation.
- Verify the presence of a target before a subsequent operation.
- Investigate a suspected safehouse.
- Conduct reconnaissance of a military installation.

An AFO mission does not require stealth to function as a mission type. Detection may occur, and the player may need to adapt. The mission remains valid even when the AI does not behave as expected.

### 2.2 DA — Direct Action

DA missions emphasize decisive action against a designated target or asset.

Typical characteristics:

- Greater potential for conspicuous force and equipment.
- Objectives involving capture, elimination, rescue, destruction, or recovery.
- More heavily defended objectives where appropriate.
- Higher likelihood of direct engagement.
- Mission success based on achieving a tangible operational effect.

Example objectives:

- Capture a hostile commander.
- Rescue a hostage.
- Destroy an ammunition depot.
- Raid an insurgent safehouse.
- Eliminate a weapons team.
- Seize a sensitive asset.

DA missions do not require a scripted firefight. A target might be lightly defended, caught off guard, or encountered under unexpected circumstances.

### 2.3 The Fundamental Distinction

**AFO and DA describe operational intent, not guaranteed tactical outcomes.**

An AFO mission can develop into a firefight. A DA mission can be completed with minimal resistance.

The mission generator establishes the context and constraints. The player determines the approach, while AI behavior contributes uncertainty.

---

## 3. Configurable Enemy Spotting and Alertness

DSC should use Arma 3's existing AI skill system to influence the likelihood and effectiveness of enemy detection rather than implementing an entirely separate stealth simulation.

Relevant skill subskills include:

- `spotDistance` — influences the AI's ability to spot targets at distance.
- `spotTime` — influences how quickly the AI recognizes targets.

These settings provide useful control over detection behavior, although they do not guarantee specific outcomes. Detection is also affected by visibility, movement, equipment, line of sight, other AI settings, and engine behavior.

### 3.1 Spotting Profiles

Enemy generation should support configurable spotting and alertness profiles.

Potential profiles include:

| Profile | Intended context |
|---|---|
| Routine Security | Ordinary garrisons and routine patrols |
| Reduced Vigilance | Distracted or poorly trained personnel |
| Heightened Alert | Suspicious or security-conscious defenders |
| Combat Alert | Personnel expecting or responding to hostile activity |
| Elite Security | Highly trained forces with stronger detection capabilities |

These profiles should be configurable rather than hardcoded into individual mission templates.

### 3.2 Faction Baselines

Faction capability can provide a baseline for spotting proficiency.

For example, trained military personnel may have higher baseline detection skills than poorly trained irregular militia.

However, faction identity should not determine the entire outcome. Alertness and operational context should also influence the final profile.

### 3.3 Mission Signature

The player's operational signature should influence the selected mission configuration.

Examples include:

- Low-visibility equipment and discreet transportation.
- Standard combat equipment and limited support.
- A conspicuous assault force with military vehicles.
- An operation taking place near an alerted installation.

The initial implementation can use predefined mission profiles rather than attempting to calculate a physically accurate probability of detection.

### 3.4 Implementation Considerations

- Apply spotting settings after unit creation and other skill initialization.
- Avoid overwriting faction-specific skill configurations unnecessarily.
- Keep values configurable and separate from objective logic.
- Test profiles in repeatable in-game scenarios before settling on final values.
- Do not assume a spotting profile guarantees that a unit will or will not detect the player.

The purpose is to influence the tactical atmosphere, not to make AI detection perfectly predictable.

---

## 4. Mission Compromise and Escalation Assessment

Mission success and mission compromise should be treated as separate concepts.

A player can achieve the primary objective while compromising the operation. Conversely, a player can encounter some enemy resistance without necessarily suffering a major operational failure.

**Compromise should measure the severity of the encounter, not simply whether the player was spotted or a shot was fired.**

For example, an enemy firing a few shots from a distance before the player breaks contact is very different from a sustained firefight that leaves multiple enemy and friendly personnel dead.

### 4.1 Primary Objective Completion

Primary objectives should be evaluated independently of enemy detection.

For an informant meeting, the essential conditions might be:

1. The player reaches the contact.
2. The player interacts with the contact and obtains the required intelligence.
3. The player completes the required withdrawal or extraction.

The mission should not fail merely because an enemy patrol detects the player.

### 4.2 Operational Outcome

DSC can record relevant events during the mission and use them to determine an operational outcome during debriefing.

Potential outcomes include:

- **Clean Completion:** The objective was achieved with minimal escalation.
- **Compromised Completion:** The objective was achieved, but the operation generated meaningful enemy awareness or escalation.
- **Contested Completion:** The objective was achieved despite a substantial engagement, casualties, or other significant complications.
- **Objective Failure:** The player failed to achieve the essential objective or an explicitly required condition.

These labels are illustrative. The final implementation should use a consistent outcome model that works across different mission templates.

### 4.3 Track Events Rather Than Scripted AI Intentions

Useful events and metrics may include:

- Whether friendly personnel fired weapons.
- Whether enemy personnel fired weapons.
- The number of friendly casualties.
- The number of enemy casualties.
- Civilian casualties.
- Whether an alarm or other escalation event was triggered.
- Whether the player completed the objective and withdrew.
- Whether the player abandoned the operation or lost a required asset.

These events are more reliable to evaluate than assumptions about whether an enemy AI unit successfully identified the player or followed a particular patrol route.

### 4.4 A Graduated Compromise Model

The system should distinguish between different levels of escalation.

| Level | Example | Interpretation |
|---|---|---|
| 0 — Undisturbed | Objective completed without a significant hostile response | Clean operation |
| 1 — Minor Contact | Brief enemy fire at a distance; player breaks contact without casualties | Limited compromise |
| 2 — Active Engagement | Sustained exchange of fire, an alarm, or meaningful enemy response | Compromised operation |
| 3 — Severe Engagement | Multiple friendly or enemy casualties, prolonged combat, or significant civilian harm | Heavily compromised operation |

These are starting categories, not final thresholds. The exact conditions should be tested and tuned against actual gameplay.

A single enemy casualty should not automatically have the same meaning as multiple friendly casualties and a prolonged engagement. Similarly, an isolated shot should not automatically invalidate a low-visibility operation.

### 4.5 Avoid Overly Simplistic Scoring

The system should not rely exclusively on the total number of shots fired or casualties taken.

For example:

- Friendly shots fired without enemy awareness may represent a different outcome from a sustained exchange of fire.
- Enemy shots fired from a distance may indicate contact without meaningful escalation.
- An alarm may be operationally significant even when nobody is injured.
- Civilian casualties should carry particular weight.
- A failed objective should remain a failure regardless of how quietly the player withdrew.

The outcome should be derived from a combination of recorded events and the mission's operational context.

The initial implementation can be a deterministic rule-based assessment rather than a complicated scoring algorithm.

### 4.6 Objective Success Versus Operational Quality

The debriefing system should distinguish between:

- **Mission Result:** Was the primary objective completed?
- **Operational Outcome:** How much escalation or compromise occurred?
- **Casualty Report:** What were the friendly, enemy, and civilian losses?
- **Additional Assessment:** Were optional conditions or secondary objectives completed?

This allows the campaign to recognize successful but messy operations without treating every unexpected AI reaction as mission failure.

---

## 5. Ambient World Generation as the Primary Source of Replayability

DSC's greatest source of replayability should be the variety of its operational environment.

Rather than creating a large number of narrowly defined mission types, DSC should develop a smaller library of reusable objective templates supported by independent world-generation systems.

### 5.1 World-Generation Dimensions

#### Objective

What must the player accomplish?

Examples: meet, observe, identify, capture, rescue, destroy, recover, or eliminate.

#### Location and Surroundings

Where does the operation take place?

Examples: towns, industrial sites, military installations, farms, coastal villages, road networks, and isolated compounds.

#### Population and Activity

What is happening in the surrounding area?

Examples: civilians, workers, parked vehicles, local militia, military patrols, checkpoints, or an unusually quiet settlement.

#### Enemy Posture

What is the enemy's current state?

Examples: routine security, distracted, suspicious, reinforced, on alert, or actively searching.

#### Player Signature

How conspicuous is the player's force?

Examples: low-visibility equipment, discreet transportation, standard combat kit, or a conspicuous assault force.

#### Environmental Conditions

What conditions affect the approach and operation?

Examples: time of day, weather, visibility, terrain, observation positions, and available insertion or extraction routes.

### 5.2 Independent Systems, Meaningful Combinations

Each dimension should be configured independently where practical, with constraints to prevent nonsensical combinations.

For example, a town-based intelligence mission could feature different combinations of civilian activity, patrol density, enemy posture, and transportation options without requiring a completely new mission script for each variation.

Similarly, a target-capture mission could use the same objective logic across different locations, garrison compositions, security configurations, and extraction options.

The goal is to increase the number of interesting situations without proportionally increasing the amount of mission-specific code.

---

## 6. Mission Success Should Depend on Player Actions

Every objective template should define explicit, achievable success conditions.

Essential progression should depend on events that DSC can reliably detect, such as:

- Reaching a designated location.
- Interacting with a target or informant.
- Obtaining intelligence.
- Recovering an asset.
- Rescuing a person.
- Eliminating or capturing a designated target.
- Destroying a specified object.
- Reaching a required extraction or debrief location.

Enemy spotting, patrol behavior, and reactions should influence the experience without becoming mandatory conditions unless a specific objective explicitly requires them.

### Example: AFO Informant Meeting

**Phase 1 — Approach**

The player reaches the town and locates the informant.

**Phase 2 — Contact**

The player interacts with the informant and obtains the intelligence.

**Phase 3 — Withdrawal**

The player returns to a designated extraction point or leaves the operational area, as required by the mission.

**Phase 4 — Debrief**

DSC evaluates objective completion, escalation, casualties, and any additional conditions.

The player can complete the primary objective even if an enemy notices them. The circumstances of that encounter influence the operational outcome rather than invalidating the objective.

This structure is reliable, easy to test, and reusable across many variations.

---

## 7. A Small Objective Library Supported by Rich World Systems

DSC should favor a small collection of reusable objective templates.

| Objective Template | Primary Player Action | Sources of Variation |
|---|---|---|
| Human Intelligence | Meet a contact and obtain information | Contact location, civilian activity, security posture |
| Surveillance | Identify or photograph a target | Site type, target visibility, guard composition |
| Reconnaissance | Survey an area | Terrain, patrol density, observation positions |
| Capture / Eliminate | Locate and act on a target | Target protection, reinforcements, escape routes |
| Recovery | Retrieve an item or person | Location, access restrictions, surrounding threats |
| Destruction | Destroy a designated asset | Asset type, security, approach and withdrawal options |

These templates should reuse existing DSC systems wherever possible, including:

- Objective handling.
- Location selection and classification.
- Faction profiles.
- Group spawning and doctrine classification.
- Enemy posture and spotting profiles.
- Debriefing and operational assessment.

The objective template defines **what the player must accomplish**.

The world configuration defines **what the experience looks and feels like**.

This separation should be maintained as the campaign expands.

---

## 8. Environmental Storytelling and Faction Relationships

The surrounding world should communicate the operational situation without requiring every spawned entity to participate in the objective.

For example, two missions to capture the same weapons dealer might differ substantially.

In one mission, the dealer occupies a quiet rural compound with a few armed guards and a civilian truck nearby.

In another, the dealer operates in a busy industrial area with parked vehicles, local militia, civilian workers, and a military patrol moving along the road.

The objective is identical, but the tactical situation is different.

Potential sources of environmental variation include:

- Civilian and military vehicle placement.
- Nearby group composition and density.
- Checkpoints and nearby installations.
- Building types and approach routes.
- Civilian activity and local hostility.
- Relationships between the target and surrounding factions.
- Available infiltration and extraction routes.

DSC's faction-role system can help make these combinations coherent.

Partner forces, civilians, irregulars, organized OpFor, and hidden sponsors can contribute to the atmosphere and context without every group needing to be directly involved in the mission objective.

The world should feel connected to the operation, even when much of it is ambient.

---

## 9. Recommended Development Sequence

The shift toward ambient world variation should be implemented incrementally.

### Phase 1 — Establish Spotting Profiles

Create configurable enemy spotting and alertness profiles.

Apply these profiles after unit creation and skill initialization. Test them in repeatable scenarios to determine whether they create useful differences without making enemy AI unrealistically ineffective or omniscient.

### Phase 2 — Complete One AFO Mission

Use the informant meeting as the initial test case.

Implement:

- Approach.
- Contact interaction.
- Intelligence acquisition.
- Withdrawal.
- Debriefing.
- Operational outcome assessment.

Enemy detection should be optional and must not be a mandatory failure condition.

### Phase 3 — Implement Operational Compromise Tracking

Record relevant events during the mission, including weapon firing, casualties, alarms, and objective completion.

Build a deterministic rule-based assessment that distinguishes minor contact from sustained combat and severe operational consequences.

Keep the assessment separate from primary objective completion.

### Phase 4 — Reuse the Systems for DA

Create a DA mission using the same underlying world-generation and assessment systems.

Use a more conspicuous player profile where appropriate, a defined target, and a suitable enemy posture.

The mission should remain functional regardless of whether the AI produces the anticipated level of resistance.

### Phase 5 — Expand Ambient World Variation

Before adding many new objective templates, vary:

- Locations.
- Nearby groups.
- Civilian activity.
- Vehicle placement.
- Enemy posture.
- Faction composition.
- Environmental conditions.
- Insertion and extraction options.

Evaluate how much replayability these combinations provide using the existing AFO and DA templates.

### Phase 6 — Validate the Combinations

Ensure that:

- Objectives remain achievable.
- Relevant groups spawn correctly.
- Faction roles and group classifications remain consistent.
- The player has a viable way to complete or abandon the operation.
- Unexpected AI behavior does not invalidate mission progression.
- Operational assessment reflects the severity of the encounter rather than a single arbitrary event.

---

## 10. Architectural Principles

The following principles should guide future DSC development.

1. **Configuration over hardcoding.** Faction capabilities, spotting profiles, enemy posture, and world-generation parameters should be configurable.

2. **Composition over mission proliferation.** Prefer reusable systems that create varied situations over many nearly identical mission scripts.

3. **Objectives independent of AI choreography.** Essential progression should not require precise patrol timing, detection behavior, or other unreliable AI outcomes.

4. **Operational quality independent of objective completion.** A successful objective can still result in a compromised operation.

5. **Event-driven assessment.** Use observable events and measurable outcomes to evaluate compromise rather than trying to infer the AI's intentions.

6. **Modular development.** Objective handling, world generation, spotting configuration, and debrief assessment should be separable systems.

7. **Test before expanding.** Establish that the core systems work reliably before introducing additional complexity.

8. **Player agency first.** DSC should create interesting situations and meaningful decisions rather than attempt to dictate every tactical outcome.

---

## Conclusion

DSC should be a dynamic SOF campaign in which a configurable operational environment produces replayable tactical experiences.

AFO and DA remain distinct operational philosophies, but neither depends on brittle AI choreography. Spotting profiles influence the likelihood of detection, the environment creates uncertainty, and mission success depends on clear player-driven objectives.

A separate operational assessment system records the consequences of the player's actions and the encounter itself. This allows DSC to distinguish a clean operation from a brief contact, a sustained firefight, or a severe engagement involving significant casualties.

The long-term goal is not to simulate every aspect of a real-world special operations mission. It is to build a robust framework in which a relatively small set of reusable systems can produce a large variety of believable, challenging, and replayable missions.

**Build the situation. Define the objective. Let the encounter unfold. Evaluate the outcome.**
