# Dynamic SOF Campaign — Mission Catalog & On-the-Spot Generation Guide

This document separates two things you want kept independent:

1. **Mechanics** — what actually gets built in the mission (objectives, triggers, enemy composition, terrain requirements). These are 100% faction-agnostic and work with vanilla, RHS, CUP, 3CB, or any mod faction.
2. **Flavor** — the briefing/intel/tasking text that makes a mechanically generic "Direct Action" mission *feel* like a DEVGRU HVT raid one deployment and a Green Beret-advised partner-force raid the next.

The idea: your generator picks a **mission type** (weighted by which "unit type" the player selected for that deployment), then picks a **mechanical template**, then wraps it in **flavor text** pulled from a pool matching the unit type. Same underlying trigger logic, completely different player experience.

---

## PART 1 — MISSION TYPE CATALOG

Each entry: real-world SOF analog(s) for flavor tagging → core player objective → key mechanical building blocks → randomizable variables.

### A. Direct Action (DA)
**Analogs:** Rangers, DEVGRU, Delta, Raiders, SF (as supporting task)
**Objective:** Assault and clear a defined objective (compound, building cluster, camp) to kill/capture a target or destroy something inside it.
**Mechanics:**
- Objective = a marker-defined building cluster or compound (tag POIs on your terrain in advance, or use `nearestObjects`/`buildingPos` to auto-select a compound of sufficient size at runtime).
- Enemy group spawned via faction-agnostic array of unit classnames (see Part 2) sized to a difficulty variable.
- Win condition: trigger checking all AI in objective-area group are dead/captured, OR a specific "HVT" unit (tagged via variable name) is dead/captured.
**Randomize:** time of day, enemy alert state (patrolling vs. static vs. reinforced), presence of a "target" unit vs. generic clear, infil method (heli, vehicle, foot).

### B. Special Reconnaissance (SR)
**Analogs:** AFSOC SR, Marine Scout Snipers, SF, Raiders
**Objective:** Observe an objective for a set duration, report specific info (count, activity, vehicle presence), avoid detection. No direct engagement required — bonus/failure state tied to being spotted.
**Mechanics:**
- Place player in a designated "recon zone" trigger overlooking an objective marker.
- Use a countdown timer once player is in zone AND has line of sight (`lineIntersects` checks or simple radius+height check) to the objective.
- Detection = any enemy unit's `knowsAbout` player exceeds a threshold → mission complication (compromise state) rather than instant fail.
- Task complete = timer elapsed while still "green" (undetected) or player manually calls in the report via radio/action.
**Randomize:** distance to objective, terrain cover (add fog/vegetation modifiers), whether a wandering enemy patrol threatens the hide site, whether the mission converts into a "call for fire" finish (see M).

### C. Unconventional Warfare (UW)
**Analogs:** Green Berets (signature mission)
**Objective:** Multi-mission arc — contact a friendly guerrilla/resistance group, train them (escort/protect a training exercise), then jointly execute an operation with them as AI allies.
**Mechanics:**
- Stage 1: player moves to a marker, a friendly AI group (already-placed, `switchable`/allied side) is revealed/joins player's group or becomes a supporting AI faction.
- Stage 2 ("train-up"): a defend or escort mission using the resistance group as friendly AI that must survive above a casualty threshold.
- Stage 3: joint DA or ambush mission where the resistance group fights alongside the player (set via `addToWaypoint`/synchronized AI leadership or simple "follow" waypoints).
**Randomize:** resistance group's starting strength/equipment quality (ties to a persistent "campaign variable" you can grow over the deployment), whether stage 2 is interrupted by an enemy patrol.

### D. Foreign Internal Defense / COIN
**Analogs:** Green Berets, MARSOC (advisor role)
**Objective:** Support a friendly local-force AI unit that is doing the actual fighting; player advises/enables (calls in support, provides overwatch, medevacs their casualties) rather than taking point.
**Mechanics:**
- Spawn a friendly AI squad with its own waypoints executing a patrol/clear task.
- Player's task = keep them alive / provide fire support from a support role, or take over only if they get pinned down (trigger on their casualty rate or being "suppressed" for X seconds).
**Randomize:** quality of partner force (accuracy/skill sliders), whether an ambush is sprung on them mid-patrol, civilian presence requiring restraint.

### E. Counter-Terrorism / Hostage Rescue (CT/HR)
**Analogs:** DEVGRU, Delta, SF CIF
**Objective:** Clear a building/compound containing both hostiles and non-combatant hostages; hostages must survive, precision required.
**Mechanics:**
- Place hostage unit(s) (civilian side or captive-flagged units, `setCaptive true`) inside the objective alongside hostile AI.
- Fail condition: hostage death (kill event handler on those specific units).
- Extra tension: use `enableAI "TARGET"` off for hostages, and consider a scripted "hostage takes damage if firefight drags on near them" mechanic for urgency.
**Randomize:** number/location of hostages within the structure, whether hostiles are alerted at mission start (dynamic vs. surprise breach), presence of an IED/booby trap object.

### F. Personnel Recovery / CSAR
**Analogs:** PJs (signature), all units as generic
**Objective:** Locate and extract an isolated friendly unit (downed pilot, captured operator) who may be injured and needs to be carried/escorted to an extraction point, potentially through hostile territory.
**Mechanics:**
- Spawn an injured "survivor" unit (low health, or literal wounded state via ACE Medical if you're using it) at a semi-random location within a search radius.
- Task 1: find them (radio beacon simulated by a marker only revealed once player is within X meters, or a random-walk search area).
- Task 2: escort/carry to an exfil point while under time or enemy pressure.
**Randomize:** how injured the survivor is (whether they can walk vs. need to be carried/vehicle-evac'd), enemy search parties actively hunting them (adds urgency), distance to exfil.

### G. Maritime Operations (VBSS / Combat Diver Recon)
**Analogs:** SEALs, DEVGRU
**Objective (VBSS):** Insert via boat, board a ship/vessel object, clear it deck by deck, secure cargo or detainees.
**Objective (Recon):** Swim/insert covertly to a coastal objective, gather info or plant a sensor/charge, exfil without contact.
**Mechanics:**
- Uses Arma's boat assets or a static "ship" object placed on the map with enterable interior (many terrains/mods have these; otherwise treat a coastal structure as the "vessel").
- VBSS clear logic identical to Direct Action but confined to a vertical, compartmentalized space — good for testing close-quarters AI behavior.
- Recon uses same detection-timer logic as SR but with a swim insertion phase.
**Randomize:** sea state/visibility, whether the vessel is underway (patrol boats nearby) or static, cargo type (weapons cache vs. contraband vs. detainee).

### H. Sensitive Site Exploitation (SSE)
**Analogs:** Delta, SF, DEVGRU — usually tacked onto a DA mission
**Objective:** After clearing an objective, search it for intel items (documents, laptops, phones represented by placed objects with an addAction "search") within a time window before extract.
**Mechanics:**
- Place 1–3 "intel item" objects inside the objective structure.
- `addAction` to collect; on collection, set a global/mission variable (e.g., `missionNamespace setVariable ["campaign_intel_1", true]`).
- This is your **campaign-chaining hook**: intel collected here can literally determine the next mission's location/type (see Part 3).
**Randomize:** number of intel items, whether they're guarded by a "final holdout" enemy, time pressure (QRF inbound).

### I. Sabotage / Demolition
**Analogs:** SF, SEALs, Raiders
**Objective:** Destroy a specific structure or piece of equipment (bridge, radar, fuel tanks, parked aircraft) using satchels/explosives, then exfil before/after detonation.
**Mechanics:**
- Place a "target object" (existing map object or spawned prop) with a trigger checking `damage` or a specific `setDamage 1` action tied to a nearby placed explosive being detonated.
- Simple version: addAction "Plant Charge" near object → timer → explosion via `createVehicle "Bo_GBU12_LGB"`-style scripted detonation or literal placed explosive.
**Randomize:** number of targets (single vs. multiple requiring split timing), guard presence, whether it's timed demolition (sneak in/out) vs. remote-detonated after player is clear.

### J. Ambush / Interdiction
**Analogs:** Rangers, SF, Raiders, generic
**Objective:** Intercept a moving target — vehicle convoy or foot patrol — along a route, destroy/disable it before it reaches a destination.
**Mechanics:**
- Spawn a convoy/patrol group with waypoints along a road/path toward an "arrival" trigger (mission fails or escalates if they reach it).
- Player sets up along the route; ambush trigger area, or just open engagement.
**Randomize:** convoy composition (soft-skin vs. armored — scales difficulty), time-to-arrival window (forces player to move fast to get in position), whether convoy has escort/QRF that responds to contact.

### K. Airfield / Objective Seizure
**Analogs:** Rangers (signature)
**Objective:** Seize and hold a large area objective (airfield, compound complex, LZ) against initial defenders, then hold against a counterattack wave until reinforcement/extract.
**Mechanics:**
- Two-phase trigger: Phase 1 clear initial garrison (same as DA). Phase 2 spawns a delayed "counterattack" group with waypoints converging on the objective after a timer, player must hold X minutes or until an extraction asset arrives.
**Randomize:** garrison size, counterattack delay and strength, insertion method (static-line jump, heli, ground infil).

### L. Sniper / Overwatch
**Analogs:** Marine Scout Snipers, AFSOC SR
**Objective:** Provide long-range overwatch for another element (AI-controlled friendly squad executing a separate task), engaging only priority/threat targets, remaining undetected as long as possible.
**Mechanics:**
- Pairs naturally with FID or a friendly-AI DA mission: player is placed at a distant vantage marker while an AI squad executes the "real" mission below.
- Player's task tracks kills of designated threats (e.g., enemies with a specific unit variable flag "priority target") and/or the survival of the friendly squad.
**Randomize:** engagement range/terrain (open desert vs. broken urban rooftops), wind (if using ACE/advanced ballistics), whether player is spotted and must relocate ("shoot and scoot").

### M. Combat Control / JTAC
**Analogs:** AFSOC CCT, TACP
**Objective:** Either (1) secure and mark/control an austere landing zone for follow-on forces, or (2) act as terminal controller calling in simulated CAS/artillery on multiple designated targets.
**Mechanics:**
- LZ control: clear a small area, place smoke/marker objects, trigger checks area is clear when a scripted "inbound transport" spawns and lands.
- JTAC: designate target objects/groups, addAction "Call Strike" triggers a scripted airstrike effect (module `BIS_fnc_moduleCAS` or simple `createVehicle` bomb effect) after a delay — rewards patience and correct target ID over rushing in with a rifle.
**Randomize:** number of targets to service, enemy AA presence threatening the "aircraft," IFF/friendly-fire risk element (mixed friendly/enemy positions nearby).

### N. Detainee / HVT Capture (non-lethal objective)
**Analogs:** Delta, DEVGRU, SF CIF
**Objective:** Same shape as DA, but the named target must be captured alive — killing them fails or degrades the mission.
**Mechanics:**
- Tag the HVT unit with a variable name; give them a "surrender" behavior below a health/suppression threshold (`setCaptive true` + disable weapons on trigger) rather than dying.
- Player must then escort/extract the detainee (similar to CSAR carry logic).
**Randomize:** whether HVT tries to flee/hide among civilians, bodyguard strength, exfil pressure (QRF searching for the detainee).

### O. Quick Reaction Force (QRF) / Combat Intervention
**Analogs:** Delta/DEVGRU CIF, generic "reserve" element
**Objective:** Player is on standby; a random developing situation (another friendly element in trouble, a compromised operation) triggers mid-deployment and requires immediate reinforcement with limited planning time.
**Mechanics:**
- This is a great **mission-generator wildcard**: at a random point in the campaign, instead of a scheduled mission, trigger a "flash tasking" — spawn player near a QRF pad with a short/no-briefing window, then generate a quick DA/CSAR/ambush-defense at short notice using the same building blocks as above but with a compressed prep timer and no ability to choose loadout freely.
**Randomize:** which mission type is spun up (pull from A/E/F/J templates), response time window, whether it's a false alarm requiring restraint.

### P. Show of Force / Presence Patrol (low-intensity filler)
**Analogs:** any unit, "quiet deployment day"
**Objective:** Patrol a route/area, react to whatever's encountered (nothing, a minor contact, a civilian interaction) — useful as a pacing/breather mission between high-intensity ones, or to build campaign intel passively.
**Mechanics:**
- Simple waypoint patrol with a chance-based random-event trigger (spawn nothing / spawn a minor 2–3 man contact / spawn a civilian who gives a "tip" that seeds the next mission's location).
**Randomize:** event chance table, route length/terrain.

### Q. Weapons/Contraband Cache Interdiction
**Analogs:** SF, MARSOC, Rangers
**Objective:** Locate and destroy/secure a hidden weapons cache (crates placed in a structure or camouflaged outdoor location) before it can be moved/used.
**Mechanics:**
- Similar to SSE but object-destruction focused: place ammo-box props, task = destroy via satchel or `setDamage`.
- Optional twist: cache is being loaded onto a vehicle at mission start (timer pressure).
**Randomize:** number/spread of cache locations across a wider area (forces movement/recon rather than a single building clear), guard presence.

---

## PART 2 — MAKING IT FACTION-AGNOSTIC IN SQF

The key is to never hardcode a specific faction's classnames into your mission-type logic. Instead, build **arrays of arrays** the player (or you, pre-mission) selects once per campaign, and every mission template pulls from those arrays.

```sqf
// Example: faction config, set once at campaign start based on player's mod selection
missionNamespace setVariable ["campaign_playerFaction", ["B_Soldier_F","B_Soldier_AR_F","B_Soldier_LAT_F"]];
missionNamespace setVariable ["campaign_enemyFaction", ["O_Soldier_F","O_Soldier_AR_F","O_Soldier_GL_F"]];
missionNamespace setVariable ["campaign_friendlyAuxFaction", ["I_Soldier_F","I_Soldier_AR_F"]]; // resistance/partner force for UW/FID
```

If you want this to work with *any* installed mod without you manually curating classname lists, use `configProperties` to pull all valid infantry classnames from whatever factions are active in `CfgFactionClasses`/`CfgGroups` at mission start, filter by side, and randomly draw from that pool. This is more setup work but means new mod factions "just work" without editing your mission.

```sqf
// Rough sketch: gather all rifleman-type classnames for a given side from active CfgGroups
private _cfg = configFile >> "CfgGroups" >> "West"; // side-specific branch varies by mod
// walk the config tree, collect vehicle classes tagged as infantry, filter/reject as needed
```

For a first pass, I'd recommend hand-curating 3–4 faction sets (vanilla NATO/CSAT/AAF, plus your favorite mod set) into arrays like above — fully automatic config-walking is a nice v2 feature once the mission-type logic is solid.

---

## PART 3 — ON-THE-SPOT GENERATION ARCHITECTURE

Suggested flow for a single mission being generated mid-campaign:

1. **Pick unit type** (already chosen by player at campaign start, or rotates per deployment) → determines the *weighted mission pool* (e.g., Green Beret pool leans UW/FID/COIN/SSE; DEVGRU pool leans DA/CT/VBSS/QRF).
2. **Roll mission type** from that weighted pool (simple `selectRandomWeighted`).
3. **Roll a location** from a pre-tagged marker pool matching the mission's terrain needs (compound, coastline, airfield, road route, etc.) — tag your terrain in the editor ahead of time with markers named like `loc_compound_1`, `loc_coast_2`, `loc_route_1`, categorized by type so the generator only draws from the matching category.
4. **Spawn enemy/friendly elements** using the faction arrays from Part 2, scaled by a difficulty variable that can escalate over the course of the campaign (early deployment = smaller garrisons, later = reinforced).
5. **Generate the task** via `BIS_fnc_taskCreate`, with the description string built from a **template + variable substitution** (see Part 4) rather than static text.
6. **Wire win/lose conditions** per the mechanics described in Part 1 for that mission type — these can be reusable functions (`fnc_missionType_DA.sqf`, `fnc_missionType_SR.sqf`, etc.) called with parameters (location marker, difficulty, faction arrays) rather than rewritten per mission.
7. **On completion**, roll/store any campaign-persistent outcomes (SSE intel found, partner-force casualties from UW, HVT captured vs. killed) into `profileNamespace` or a saved variable so the next deployment's briefing can reference it.

This keeps every mission type as a **single reusable function** — you write "Direct Action" logic once, and it gets called dozens of times across a campaign with different markers, factions, and difficulty, always feeling fresh because of variable placement, enemy composition, and flavor text.

---

## PART 4 — BRIEFING/INTEL TEXT TEMPLATING

To make a mechanically identical DA mission feel different depending on unit type, keep a text-template bank per unit type with placeholders your script fills in:

```sqf
// Example template pool for "Direct Action" flavored as DEVGRU
private _briefTemplates = [
  "SIGINT indicates a high-value facilitator is operating out of a compound near %1. Task Unit is to conduct a direct-action raid, neutralize or capture the target, and be wheels-up before first light.",
  "A joint operations cell has developed actionable intelligence on a weapons transfer point at %1. You are tasked to interdict the site and exploit any material of intelligence value."
];

// Example template pool for "Direct Action" flavored as Green Beret CIF (same mechanical mission)
private _briefTemplatesSF = [
  "Partner-force reporting places an insurgent cell leader at a compound near %1. Given the sensitivity of the target, this is being run as a unilateral strike rather than a partnered operation.",
  "A resistance contact has passed word of a weapons cache being guarded near %1. Recommend a direct assault to deny the enemy this material before it's moved."
];

private _locationName = "the village of Rogovo"; // pulled from your marker/location metadata
private _brief = format [(selectRandom _briefTemplates), _locationName];
```

Build a handful of templates per mission type per unit-type "voice" (aim for 3–5 each so repeats aren't obvious over a long campaign), store them in a simple `.sqf` or `.hpp` data file, and have your generator function pick one at random and `format` in the location name, target name, and any campaign-state callbacks (e.g., referencing intel gathered in a previous mission).

**Chaining across a deployment:** since SSE (Part 1-H) and Show of Force events (Part 1-P) can set persistent variables, your briefing generator can check those and insert a line like:

```sqf
if (missionNamespace getVariable ["campaign_intel_1", false]) then {
  _brief = _brief + " Intel recovered from the previous operation has been folded into this tasking.";
};
```

This is what will sell the "campaign" feeling — the player will notice their prior mission's outcome being referenced, even though under the hood it's just a boolean flag feeding a string template.

---

## SUGGESTED NEXT STEPS

1. Pick 3–4 mission types to prototype first (I'd suggest **Direct Action, Special Reconnaissance, Personnel Recovery, and SSE** since they cover a good spread of playstyles and their logic is reusable across most other types).
2. Build each as a standalone, parameterized function (location marker, faction arrays, difficulty) so they can be called repeatedly.
3. Build your marker-tagging convention on whichever terrain(s) you're targeting.
4. Build the briefing-template data file and wire the `selectRandom` + `format` substitution.
5. Layer in the campaign-persistence hooks (SSE intel, UW resistance-force strength, HVT capture/kill outcome) last, once individual missions work in isolation.

Happy to help write the actual SQF for any specific mission type's win/lose logic, the weighted-random mission picker, or the briefing template system next — just let me know which piece you want to tackle first.
