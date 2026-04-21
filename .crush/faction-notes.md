Skip to content
Chat history


This is a copy of a conversation between ChatGPT & Anonymous.

Report conversation
You said:
Ok I’m back to working on my DJC Arma 3 mission with a fresh start. I’m changing the name to DSC (Dynamic SOF (Special Operations Forces) Campaign) since I would like to give the player the ability to choose the type of special operations faction they would like to play as. But otherwise a lot of the same concepts remain.

I’ve started in a fresh code repo and one of the things I am planning on doing is tying the factions used to the map. So Altis would be occupied by their host nation forces, and then there would be occupiers/invaders/rogue factions/armed civilians etc. What I want to do is consider the types of factions that would operate in a warzone/hostile area. Please use the Altis map from Arma 3 to draw up some possibilities
ChatGPT said:
Nice, that rename actually fits the concept really well. DSC immediately communicates player choice + SOF flavor, and tying factions to terrain/map context is exactly the right direction for replayability.

Below is a map-aware faction ecology for Altis, written in a way that should translate cleanly into data-driven mission generation later (faction roles, relationships, escalation states, etc.).

I’ll assume vanilla Arma 3 assets first, with notes where mods (CUP, RHS, etc.) could slot in cleanly.

1. Baseline: Altis as a Sovereign Host Nation
Altis Armed Forces (AAF) – Host Nation Military
Role: Legitimate national military
Alignment: BLUFOR-aligned but politically fragile
Presence: Island-wide, concentrated around cities, airbases, ports

Operational Behavior

Checkpoints on MSRs

Static bases near population centers

Patrols scale with instability level

Reluctant to operate deep in insurgent areas without SOF support

Gameplay Use

Friendly or semi-friendly AI

Can:

Provide intel

Request support

Become compromised later in the campaign

Can flip loyalty under certain conditions (coups, infiltration, pressure)

Escalation Hooks

Corruption → leaks intel to enemies

Fractures into loyalist vs nationalist splinter groups

2. Occupying / Intervening Forces
NATO Intervention Force
Role: External stabilizing / occupation force
Alignment: Friendly to player SOF (depending on chosen faction)
Presence: Airfields, ports, FOBs, coastal areas

Operational Behavior

Heavily equipped but politically constrained

Focus on:

HVT raids

Air interdiction

Base security

Avoids civilian-heavy zones unless escalated

Gameplay Use

Air support provider

Logistics backbone

Can trigger escalation if collateral damage rises

Dynamic Twist

NATO ROE tightens or loosens over time

Can pull out, creating power vacuums

3. Peer / Near-Peer Adversaries
CSAT Expeditionary Force
Role: Strategic rival power
Alignment: Hostile
Presence: Seized bases, covert FOBs, black sites

Operational Behavior

Uses drones, EW, advanced optics

Focus on:

Strategic infrastructure

Intel denial

Counter-SOF operations

Gameplay Use

High-threat zones

Late-campaign escalation faction

Actively hunts player if detected

Dynamic Hooks

Can:

Arm insurgents

Sponsor proxy militias

Conduct deniable ops

4. Insurgent & Irregular Forces
Altis Liberation Front (Insurgents)
Role: Nationalist / separatist insurgency
Alignment: Hostile, but morally gray
Presence: Rural villages, mountains, forests

Operational Behavior

IEDs, ambushes, hit-and-run

Blends with civilian population

Avoids direct confrontation

Gameplay Use

Core “clear and hold” enemy

SSE-heavy gameplay:

Cache raids

Document recovery

HVT capture

Dynamic Hooks

Public support varies

Can turn hostile to occupiers and host nation

Armed Civilian Militias
Role: Self-defense or criminalized locals
Alignment: Neutral / unpredictable
Presence: Small towns, farms, outskirts

Operational Behavior

Poor coordination

Defensive posture unless provoked

React to nearby fighting

Gameplay Use

ROE pressure on player

Mistakes have consequences

Can become informants or enemies

Dynamic Hooks

Arm themselves as instability rises

Can be absorbed into insurgent groups

5. Criminal & Rogue Actors
Organized Crime Syndicates
Role: War profiteers
Alignment: Opportunistic
Presence: Ports, cities, smuggling routes

Operational Behavior

Smuggling weapons, people, intel

Avoids militaries unless cornered

Gameplay Use

Non-traditional objectives:

Intercept shipments

Capture financiers

Can sell intel to any side

Dynamic Hooks

Can be secretly backed by foreign powers

Can destabilize regions faster than combat

Private Military Companies (PMC)
Role: Deniable force multiplier
Alignment: Conditional
Presence: Guarding infrastructure, VIPs

Operational Behavior

Highly trained

Aggressive ROE

Often escalate conflicts

Gameplay Use

Ambiguous enemies

Player may:

Fight them

Replace them

Unmask their sponsor

Dynamic Hooks

Can switch sides

Contract expires mid-campaign

6. Extremist / Radical Factions
Foreign Jihadist Cell
Role: Chaos actor
Alignment: Hostile to all
Presence: Hidden camps, urban safehouses

Operational Behavior

Suicide attacks

Spectacular violence

Poor long-term planning

Gameplay Use

Time-sensitive missions

Civilian-heavy consequences

Intelligence race mechanics

Dynamic Hooks

Exploit instability caused by others

Draw international intervention

7. Intelligence & Shadow Actors
Foreign Intelligence Operatives
Role: Manipulators
Alignment: Unknown
Presence: Embedded everywhere

Operational Behavior

No visible patrols

Operate through proxies

Steal intel, sabotage relations

Gameplay Use

Counterintelligence missions

False-flag events

Misdirection mechanics

Dynamic Hooks

Player may unknowingly aid them

Can trigger faction-on-faction conflict

8. Example Altis Faction Matrix (Useful for Code)
Faction	Controls Territory	Patrols	Civ Interaction	Escalation
AAF	Yes	Medium	Moderate	Medium
NATO	Yes (FOBs)	High	Low	High
CSAT	Limited	High	None	Very High
Insurgents	Yes (soft)	Low	High	Medium
Militias	Local	Very Low	Very High	Low
Crime	No	Very Low	Medium	Low
PMC	Contract	Medium	Low	Medium
9. SOF Player Faction Tie-In (Future-Proofing)
This structure supports:

US SOF

NATO SOF

AAF Special Forces

Independent PMC-style SOF

Even CSAT SOF campaigns

All without changing the map logic—just relationships and permissions.

10. Suggested Next Step (If You Want)
If you want, next we can:

Design a faction definition schema (JSON/SQF-friendly)

Build a territory control + instability model

Define intel economy (documents, phones, laptops → task generation)

Map faction presence to terrain types automatically (urban vs rural vs coast)

Just tell me where you want to go next with DSC.

You said:
Can apply the most popular faction mods for Arma 3 to this model? (RHS, CUP, CFP, Aegis, 3CB)
ChatGPT said:
Absolutely—this is where DSC really starts to shine. Below I’ve mapped the major, popular faction mods directly onto the Altis faction ecology we already defined, keeping things modular, swappable, and code-friendly.

I’ll structure this in layers:

Faction role (from the model)

Concrete mod factions you can spawn

How they behave in DSC

Escalation / campaign hooks

This lets you do things like:

“Altis insurgency backed by CFP, escalates into RHS peer conflict with Aegis late game.”

1. Host Nation Forces (Altis Sovereign)
Altis Armed Forces (AAF) – Modded Variants
Aegis
AAF (Aegis Expanded)

Altis National Guard / Reserve

Why Aegis

Modernized vanilla assets

Fits Altis lore perfectly

Best “baseline realism” without overpowering

DSC Use

Default host nation

First point of contact for SOF

Can fracture into:

Loyalist AAF

Nationalist hardliners

CUP
CUP AAF

Generic European Armed Forces

DSC Use

Substitute Aegis when CUP is loaded

Slightly lower tech, broader asset pool

2. External Intervention / Occupiers
NATO / Western Coalition
RHS
US Army / USMC

US SOCOM (MARSOC, Rangers, SF)

UK Armed Forces (if paired with 3CB)

DSC Role

Major BLUFOR presence

Air superiority

High ISR capability

Escalation

Early: Advisors & SOF

Mid: Mechanized patrols

Late: Full brigade footprint

3CB
British Armed Forces

UKSF (SAS / SBS)

DSC Use

Ideal for:

Player faction

Allied SOF

Works excellently on Altis as a NATO member

CUP
US Army

USMC

German/Dutch style factions

DSC Use

Lighter-weight NATO option

Good fallback if RHS not present

3. Peer / Near-Peer Adversaries
CSAT / Eastern Coalition
RHS
Russian Armed Forces

VDV / Spetsnaz

Russian Naval Infantry

DSC Role

Primary peer adversary

EW, armor, drones

Late-game threat

Escalation

Covert advisors → expeditionary force → open conflict

Aegis
CSAT (Expanded)

Iranian-style proxies

DSC Use

Keeps vanilla lore intact

Best when mixing with RHS for balance

CUP
Russian Federation

Eastern European Militaries

DSC Use

Less cutting-edge than RHS

Easier early-game peer conflict

4. Insurgents & Guerrillas
Nationalist / Separatist Insurgents
CFP (Community Factions Project)
Greek Insurgents

Eastern European Insurgents

Militia & Rebels (dozens of variants)

Why CFP is king here

Massive faction diversity

Perfect for dynamic spawning

Lightweight AI gear profiles

DSC Role

Core asymmetric threat

Terrain-aware (mountains, villages)

CUP
Takistani Insurgents

Middle Eastern Rebels

African Insurgents

DSC Use

Generic insurgent fallback

Easy to reskin narratively

RHS
ChDKZ

Insurgent Militia

DSC Use

More disciplined insurgents

Higher mid-game threat

5. Armed Civilians & Militias
Local Defense Groups
CFP
Armed Civilians

Village Militias

Criminal Gangs

DSC Role

ROE stressors

Informants

Wildcard actors

CUP
Paramilitary Police

Civil Defense Units

6. Criminal & Rogue Actors
Smugglers / Warlords / Crime Syndicates
CFP
Cartels

Organized Crime

Warlord Militias

DSC Use

Smuggling routes

Intel markets

Non-ideological enemies

CUP
PMC / Mercenaries

7. Private Military Companies
PMCs & Contractors
CFP
Western PMC

Eastern PMC

Generic Contractors

DSC Role

Deniable ops

Infrastructure security

Can flip sides

CUP
Private Contractors

8. Extremists / Terror Cells
Transnational Extremists
CFP
ISIS-style factions

Radical Islamist Cells

DSC Role

High-urgency missions

Suicide attacks

Media-driven escalation

CUP
Takistani Terror Groups

9. Intelligence / Shadow Actors
Covert & Proxy Forces
RHS
Spetsnaz (unmarked)

FSB-style units

CFP
Unmarked Paramilitaries

Black Ops Groups

DSC Use

False flags

Proxy warfare

Player misdirection

10. Player SOF Faction Options (By Mod)
Player SOF	Mod
US SOF	RHS
UKSF	3CB
NATO SOF	CUP
AAF SOF	Aegis
PMC SOF	CFP
Eastern SOF	RHS / Aegis
11. Example Altis Campaign Config (Conceptual)
DSC_Altis_Factions = [
  ["HOST_NATION", "AAF_AEGIS"],
  ["OCCUPIER", "RHS_US_ARMY"],
  ["INSURGENT", "CFP_GREEK_INSURGENTS"],
  ["PEER", "RHS_RUSSIAN_FORCES"],
  ["CRIMINAL", "CFP_ORGANIZED_CRIME"],
  ["PMC", "CFP_WESTERN_PMC"]
];
12. Why This Works for DSC
Mod-aware but not mod-dependent

Easy fallback hierarchy:

RHS → CUP → Aegis → Vanilla

Supports:

Low-intensity COIN

Hybrid warfare

Full conventional war

Perfect for:

Intel-driven task generation

Layer-based escalation (your original DJC concept)

Want to go Deeper Next?
We can:

Build a mod detection & auto-selection system

Define gear tiers per faction

Create SOF-specific task pools

Design dynamic alliances & betrayals

If you tell me what part you’re coding first (factions, tasks, intel, or territory), I’ll help you design it cleanly from the ground up.

You said:
Can you give some examples of going through CfgVehicles to find factions and unit roles? I’m thinking I want to have small configs with each map defining default factions that the player can override based on additional mods they have loaded. I also want a way to ensure you can’t use something like US Navy as an occupying force if that makes sense
ChatGPT said:
This is a very good instinct, and you’re thinking about it the “engine-native” way 👍
CfgVehicles + metadata filtering is exactly how you make DSC mod-agnostic, future-proof, and player-overrideable.

Below I’ll walk through this in practical SQF patterns, not just theory.

1. Core Idea (High-Level)
You want:

Map config defines:

Allowed roles (Host Nation, Occupier, Insurgent, etc.)

Default faction candidates

Runtime scanning:

Detect what mods are loaded

Pull valid units from CfgVehicles

Role validation layer:

Prevent nonsensical assignments (e.g. US Navy = Occupier on Altis)

Player override:

Player can replace factions, but still must pass validation

This implies three classification layers:

Faction (faction class)

Side (BLUFOR / OPFOR / IND)

Role suitability (your custom logic)

2. Scanning CfgVehicles for Factions
Basic Pattern: Get All Unit Classes
private _allUnits = [];
{
    _allUnits pushBack configName _x;
} forEach ("true" configClasses (configFile >> "CfgVehicles"));
That’s too raw. We filter.

Filter: Only Man Units
private _manUnits = [];
{
    if (getNumber (_x >> "isMan") == 1) then {
        _manUnits pushBack _x;
    };
} forEach ("true" configClasses (configFile >> "CfgVehicles"));
Extract Faction + Side
private _factions = createHashMap;

{
    private _faction = getText (_x >> "faction");
    private _side    = getNumber (_x >> "side");

    if (_faction != "") then {
        if !(_factions in _faction) then {
            _factions set [_faction, _side];
        };
    };
} forEach _manUnits;
Now you have:

[
  "BLU_F",
  "OPF_F",
  "IND_F",
  "rhs_faction_usarmy",
  "UK3CB_BAF_Faction_Army"
]
3. Getting Unit Roles (Infantry, SOF, Crew, Militia)
Role Detection via editorSubcategory
private _roles = [];

{
    private _subcat = getText (_x >> "editorSubcategory");

    if (_subcat != "") then {
        _roles pushBackUnique _subcat;
    };
} forEach _manUnits;
Common values:

EdSubcat_Personnel

EdSubcat_Personnel_SpecialForces

EdSubcat_Personnel_Crew

EdSubcat_Personnel_Pilot

EdSubcat_Personnel_Paratroopers

This is gold for SOF vs conventional filtering.

4. Building a Faction Index (Recommended)
You want something like:

DSC_FactionIndex = [
  factionClass => [
    side,
    displayName,
    roles[],
    sourceAddon,
    tags[]
  ]
];
Example Builder
private _index = createHashMap;

{
    private _faction = getText (_x >> "faction");
    if (_faction == "") exitWith {};

    private _side = getNumber (_x >> "side");
    private _display = getText (configFile >> "CfgFactionClasses" >> _faction >> "displayName");
    private _addon = configSourceAddonList _x select 0;
    private _role = getText (_x >> "editorSubcategory");

    if !(_index in _faction) then {
        _index set [_faction, [
            _side,
            _display,
            [],
            _addon,
            []
        ]];
    };

    private _entry = _index get _faction;
    (_entry select 2) pushBackUnique _role;
} forEach _manUnits;

DSC_FactionIndex = _index;
5. Role Suitability Rules (Prevent “US Navy Occupier”)
This is where DSC adds intelligence above raw configs.

Define Role Requirements
DSC_RoleRequirements = [
  ["HOST_NATION", ["INFANTRY", "POLICE"]],
  ["OCCUPIER", ["INFANTRY", "MECH", "ARMOR"]],
  ["INSURGENT", ["MILITIA", "IRREGULAR"]],
  ["SOF", ["SPECIAL_FORCES"]],
  ["PMC", ["INFANTRY", "SPECIAL_FORCES"]]
];
Tag Factions Based on Their Units
We infer tags from roles:

{
    private _roles = _x select 2;
    private _tags = [];

    if ("EdSubcat_Personnel_SpecialForces" in _roles) then {
        _tags pushBack "SOF";
    };
    if ("EdSubcat_Personnel_Crew" in _roles) then {
        _tags pushBack "MECH";
    };
    if ("EdSubcat_Personnel_Personnel" in _roles) then {
        _tags pushBack "INFANTRY";
    };

    (_x select 4) append _tags;
} forEach (values DSC_FactionIndex);
Block Invalid Assignments
DSC_fnc_isFactionValidForRole = {
    params ["_factionClass", "_campaignRole"];

    private _data = DSC_FactionIndex get _factionClass;
    if (isNil "_data") exitWith {false};

    private _tags = _data select 4;

    private _required = DSC_RoleRequirements select {
        (_x select 0) == _campaignRole
    } select 0 select 1;

    (_required findIf {_x in _tags}) != -1
};
Now:

["rhs_faction_us_navy", "OCCUPIER"] call DSC_fnc_isFactionValidForRole;
// false
6. Map-Level Configs (Altis Example)
DSC_Altis.sqf
DSC_MapDefaults = [
  "HOST_NATION", ["AAF_AEGIS"],
  "OCCUPIER", ["RHS_US_ARMY", "UK3CB_BAF_ARMY"],
  "INSURGENT", ["CFP_GREEK_INSURGENTS"],
  "PEER", ["RHS_RUSSIAN_FORCES"]
];
At runtime:

Validate each faction

If missing or invalid → fallback

If player override → revalidate

7. Player Override Logic
if !( [_chosenFaction, _role] call DSC_fnc_isFactionValidForRole ) then {
    hint "Selected faction is not suitable for this role.";
    _chosenFaction = _defaultFaction;
};
8. Why This Scales Well
✔ Works with any mod
✔ No hardcoding of unit classnames
✔ Prevents immersion-breaking setups
✔ Lets players override without breaking logic
✔ Compatible with:

RHS

CUP

CFP

Aegis

3CB

Future mods you haven’t seen yet

Next Steps (Strongly Recommended)
If you want, next we can:

Build a faction scoring system instead of boolean valid/invalid

Create gear-tier detection (AKs vs NVGs vs drones)

Add terrain affinity (urban / rural / maritime)

Formalize this into a reusable DSC_fnc_buildFactionIndex

Just tell me which piece you want to tackle next.

You said:
Can you explain what terrain affinity is and what that would look like?
ChatGPT said:
Terrain affinity is one of those concepts that feels like flavor at first, but once you wire it into generation it becomes a force multiplier for believability, mission variety, and AI behavior. In DSC terms, it answers:

“Where does this faction naturally operate, and where do they struggle?”

Below I’ll break it down from concept → data → implementation → gameplay effects, all grounded in Arma 3’s engine and Altis specifically.

1. What Terrain Affinity Means (DSC Definition)
Terrain affinity = a faction’s operational comfort and effectiveness across terrain types.

It affects:

Where they spawn

What missions they generate

How dense / capable their presence is

What assets they use

It is not hard restriction—it’s weighted preference.

2. Core Terrain Types (Altis-Oriented)
For Altis, you get excellent mileage from a small, reusable set:

DSC_TerrainTypes = [
  "URBAN",        // Kavala, Pyrgos
  "RURAL",        // villages, farmland
  "MOUNTAIN",     // central highlands
  "FOREST",       // wooded hills
  "COASTAL",      // beaches, ports
  "MARITIME",     // open water
  "AIRFIELD",     // military airbases
  "INDUSTRIAL"    // factories, power plants
];
You can auto-detect most of these with:

nearestLocations

surfaceIsWater

map grid density

building counts

3. Affinity as a Weighted Profile (Not Yes/No)
Each faction gets a numeric weight per terrain.

Example: Insurgents
DSC_TerrainAffinity_Insurgent = [
  ["URBAN", 0.4],
  ["RURAL", 0.8],
  ["MOUNTAIN", 1.0],
  ["FOREST", 0.9],
  ["COASTAL", 0.3],
  ["AIRFIELD", 0.1],
  ["INDUSTRIAL", 0.2]
];
Interpretation:

Mountains = stronghold

Urban = present but cautious

Airfields = rare, risky

Example: NATO Conventional Forces
DSC_TerrainAffinity_NATO = [
  ["URBAN", 0.9],
  ["RURAL", 0.6],
  ["MOUNTAIN", 0.4],
  ["FOREST", 0.5],
  ["COASTAL", 0.8],
  ["AIRFIELD", 1.0],
  ["INDUSTRIAL", 0.9]
];
Example: SOF Units
DSC_TerrainAffinity_SOF = [
  ["URBAN", 0.8],
  ["RURAL", 0.8],
  ["MOUNTAIN", 0.9],
  ["FOREST", 0.9],
  ["COASTAL", 0.7],
  ["MARITIME", 0.6],
  ["AIRFIELD", 0.5]
];
SOF has wide competence, but rarely controls terrain.

4. How Terrain Affinity Is Used (Mechanically)
A. Spawn Location Selection
When DSC needs a location:

private _score = _terrainWeight * _baseFactionStrength * _regionInstability;
Locations with higher scores are:

More likely to spawn enemies

Spawn stronger enemy groups

B. Mission Type Filtering
Terrain	Mission Bias
URBAN	CQB, raids, HVT capture
MOUNTAIN	Recon, cache hunts
COASTAL	Smuggling interdiction
AIRFIELD	Sabotage, seizure
FOREST	Ambushes, patrols
Example:

if (_terrain == "MOUNTAIN" && _affinity < 0.4) exitWith {};
C. Asset Selection
Terrain affinity directly influences what units spawn:

Low road density → fewer vehicles

Urban + high affinity → mechanized infantry

Forest + insurgents → foot patrols, technicals

Coastal + high maritime affinity → boats, divers

D. AI Behavior (Optional but Powerful)
You can subtly modify AI:

if (_affinity < 0.4) then {
  _group setBehaviour "AWARE";
  _group setSpeedMode "LIMITED";
};
Low affinity = cautious movement.

5. How You Derive Terrain Types in Arma 3
Urban Detection
count (nearestObjects [_pos, ["House"], 150]) > 20
Mountain Detection
(getTerrainHeightASL _pos) > 200
Coastal Detection
surfaceIsWater (_pos vectorAdd [0,50,0])
Forest Detection
count (nearestTerrainObjects [_pos, ["TREE"], 50]) > 15
6. Map-Level Terrain Profiles (Altis)
Altis naturally supports:

Mountain insurgency

Urban counterinsurgency

Coastal smuggling

Airfield-centric power projection

Your map config can bias regions:

DSC_Altis_TerrainBias = [
  ["MOUNTAIN", 1.2],
  ["COASTAL", 1.1],
  ["URBAN", 1.0]
];
7. Integrating Terrain Affinity with Faction Index
Add terrain affinity to faction metadata:

DSC_FactionIndex set [
  "CFP_GREEK_INSURGENTS",
  [
    _side,
    _display,
    _roles,
    _addon,
    _tags,
    DSC_TerrainAffinity_Insurgent
  ]
];
8. Preventing Immersion Breaks (Key Use Case)
This is how you prevent nonsense like:

❌ Mechanized battalion in a forested mountain valley
❌ Amphibious forces controlling inland villages
❌ Insurgents holding a modern airbase

Without hard bans.

9. Why This Is Perfect for DSC
Terrain affinity:

Scales difficulty naturally

Encourages recon and intel

Makes each map feel different

Works with any faction mod

Integrates seamlessly with your layer-based campaign

It’s also very cheap performance-wise.

Suggested Next Step
If you want, next we can:

Formalize a terrain classifier function

Tie terrain affinity into your intel economy

Build a region control heatmap

Add weather / time-of-day affinity

Just tell me which direction you want to go next with DSC.

You said:
Can you explain the use of “editorSubcategory” for identifying roles? Is that something built into Arma?
ChatGPT said:
Yes — editorSubcategory is 100% a built-in Arma 3 config property, not something invented by mods, and that’s exactly why it’s so useful for what you’re doing.

That said, it’s important to understand what it is, what it isn’t, and how reliable it is so you don’t over-trust it.

1. What editorSubcategory Actually Is
In Arma 3, every placeable object in Eden belongs to:

Category (editorCategory)

Subcategory (editorSubcategory)

These exist solely to organize objects in the Eden editor UI, but because they’re defined in config, scripts can read them at runtime.

Example (from a unit config)
class B_Soldier_F: B_Soldier_base_F {
    editorCategory = "EdCat_Soldiers";
    editorSubcategory = "EdSubcat_Personnel";
};
This is vanilla BI config.

2. Common Built-In editorSubcategory Values for Units
Bohemia provides a standardized set that most mods follow (especially RHS, CUP, 3CB).

Infantry & Roles
Subcategory	Meaning
EdSubcat_Personnel	Standard infantry
EdSubcat_Personnel_SpecialForces	SOF
EdSubcat_Personnel_Snipers	Snipers
EdSubcat_Personnel_Paratroopers	Airborne
EdSubcat_Personnel_Crew	Vehicle crew
EdSubcat_Personnel_Pilots	Pilots
EdSubcat_Personnel_Divers	Combat divers
These are editor conventions, but they map extremely well to operational roles.

3. Why editorSubcategory Is Useful for DSC
It Solves a Hard Problem Cleanly
Without it, you’d have to:

Parse classnames (_SF_, _Recon_, etc.)

Maintain mod-specific lists

Break every time a mod updates

With it:

Mods self-identify roles

You stay mod-agnostic

You can dynamically adapt to loaded content

That’s huge.

4. How Reliable Is It?
Reliability by Mod
Mod	Reliability
Vanilla / Aegis	⭐⭐⭐⭐⭐
RHS	⭐⭐⭐⭐⭐
CUP	⭐⭐⭐⭐☆
3CB	⭐⭐⭐⭐⭐
CFP	⭐⭐⭐☆☆
CFP sometimes lumps things together, but still usable.

Important Reality Check
editorSubcategory tells you how the unit is presented, not necessarily how it’s equipped.

Example:

A “Special Forces” unit might have no NVGs

A “Militia” unit might still be under EdSubcat_Personnel

That’s why you should treat it as a primary signal, not the only one.

5. Best Practice: Use It as a Signal, Not Truth
Think of editorSubcategory as:

“The mod author’s intent”

You then layer your own logic on top.

6. Practical Role Inference Pattern
Step 1: Read Subcategory
private _subcat = getText (_unitCfg >> "editorSubcategory");
Step 2: Map Subcategory → DSC Role Tags
DSC_SubcatRoleMap = [
  ["EdSubcat_Personnel", ["INFANTRY"]],
  ["EdSubcat_Personnel_SpecialForces", ["SOF"]],
  ["EdSubcat_Personnel_Snipers", ["SNIPER"]],
  ["EdSubcat_Personnel_Crew", ["CREW", "MECH"]],
  ["EdSubcat_Personnel_Pilots", ["AIR"]],
  ["EdSubcat_Personnel_Divers", ["MARITIME", "SOF"]],
  ["EdSubcat_Personnel_Paratroopers", ["AIRBORNE"]]
];
Step 3: Assign Tags to Faction
{
    private _subcat = getText (_x >> "editorSubcategory");

    {
        if (_subcat == (_x select 0)) then {
            (_factionTags append (_x select 1));
        };
    } forEach DSC_SubcatRoleMap;

} forEach _units;
7. Handling Missing or Bad Data (Very Important)
Fallback 1: Class Inheritance
if (_subcat == "") then {
    if (_unitCfg isKindOf "B_Soldier_diver_F") then {
        _tags pushBack "MARITIME";
    };
};
Fallback 2: Equipment Inspection (Advanced)
if ("NVGoggles" in (getArray (_unitCfg >> "linkedItems"))) then {
    _tags pushBack "NIGHT_CAPABLE";
};
8. Why This Prevents Nonsense Like “US Navy Occupier”
The US Navy faction will:

Mostly expose:

EdSubcat_Personnel_Divers

EdSubcat_Personnel_Pilots

Very few (or no):

EdSubcat_Personnel

EdSubcat_Personnel_Crew

Your role validation sees:

No INFANTRY

No MECH
→ Fails OCCUPIER role

Without hardcoding “don’t allow Navy”.

9. Editor vs Runtime Clarification
Important to know:

✔ editorSubcategory is available at runtime
✔ It does not require Eden
✔ It works in dedicated servers
✔ It works with mods

It’s just config data.

10. Summary (Mental Model)
editorSubcategory = author-declared role intent

It is:

Built-in

Standardized

Mod-friendly

You should:

Use it first

Validate it

Augment it

For DSC, this is exactly the right abstraction level.

If You Want to Go Further
Next logical expansions:

Weapon-based role inference (AT, AA, MG)

Doctrine detection (light infantry vs mechanized)

Capability scoring (instead of boolean roles)

Mission generator hooks (SOF-only tasks)

If you want, tell me which one you want to tackle next and I’ll walk you through it step-by-step.




No file chosenNo file chosen
ChatGPT can make mistakes. Check important info.
