Skip to content
Chat history


You said:
For my Arma 3 mission, I'm trying to find a good algorithm for filling out a cluster of structures with soldiers properly in terms of size.  So lets say I have an area with 15 structures I want to fill out with units, the structures are of all shapes and sizes (some fit 2 people, some fit 20).  I have the structures split into main structures (5+ unit positions) and side structures (< 5 positions).  I want the script to vary between levels of population density, sometimes very populous to simulate a heavily fortified area, someones not very populous which would be closer to a dry whole.  Give me some options for deciding how to do it.  My main thought is if I have 15 structures and 4 groups of varying sizes, I don't want them spread over all of the structures, and I want a realistic setup of a group being in a house, or maybe having a larger group spread over a few structures close to each other.
ChatGPT said:
This is a great problem to think about up front 👍 — if you get this right, everything downstream (AI behavior, patrols, CQB feel) just feels more believable.

I’ll give you several algorithmic patterns, from simple → more “mil-sim plausible,” and call out when each one shines. None of these require perfect building position data — they work well with exactly what you described (structure count + capacity buckets).

First: frame the problem the way a human commander would
Before spawning a single unit, decide intent, not placement.

Realistically, a force occupying an area thinks in terms of:

How important is this location?

What’s the mission? (hold, observe, rest, deny access)

What level of force do we commit?

So your algorithm should make one high-level decision, then cascade down.

I recommend always doing this in three passes:

Decide density & posture

Decide grouping / clustering

Assign buildings & positions

Everything below fits into that flow.

Option 1: Density → Occupancy Budget (simple, flexible)
Step 1: Roll a population density profile
Instead of “random units per building,” roll a density state for the whole cluster:

_density = selectRandomWeighted [
    ["abandoned", 0.15],
    ["light",     0.30],
    ["medium",    0.35],
    ["heavy",     0.20]
];
Each density defines:

% of structures used

% of available positions filled

Preferred building types

Example table:

Density	Structures Used	Position Fill	Behavior
abandoned	10–25%	20–40%	sentries only
light	30–45%	40–60%	small teams
medium	50–70%	60–80%	squads
heavy	70–90%	80–100%	fortified
Step 2: Convert density into a unit budget
Instead of “15 buildings,” think:

“This area supports ~32 soldiers.”

Then your job becomes allocation, not guessing.

This alone prevents:

Over-spreading

Unrealistic 1–2 men in every shack

Option 2: Building Clusters (prevents over-spreading)
This directly addresses your concern 👍

Core idea
Don’t assign units to buildings individually.
Group buildings first, then assign groups to clusters.

Step 1: Cluster buildings by proximity
Use distance thresholds (e.g. 20–30m)

Prefer clusters with at least 1 main structure

You’ll get things like:

Cluster A: 1 main + 2 side

Cluster B: 1 main

Cluster C: 2 side

Cluster D: 1 main + 4 side

Step 2: Assign groups to clusters, not buildings
Now roll:

How many clusters are occupied?

How many groups per cluster?

Examples:

Light density → 1–2 clusters occupied

Medium → 2–3 clusters

Heavy → most clusters, with overlap

This gives you:

One squad holding a compound

Another squad down the street

Empty space in between

Very realistic.

Option 3: Group-Centric Placement (most realistic feel)
This one mirrors how units actually operate.

Step 1: Decide how many groups exist
Based on density + faction type:

_groups = [
    1 + floor random 2, // light
    2 + floor random 2, // medium
    3 + floor random 2  // heavy
];
Each group has:

Size (fireteam / squad / reinforced squad)

Posture (static, security, resting)

Step 2: Each group chooses a “home building”
Rules:

Groups prefer main structures

Only 1 group per main structure (unless heavy)

Side structures are auxiliary

Step 3: Spillover logic
If group size > building capacity:

Occupy nearby side structures within X meters

Keep command element in main building

Put 2–3 men in adjacent buildings

This directly produces:

“A squad holding 1 house + 2 sheds”
instead of
“2 men in every building”

Option 4: Role-Based Building Usage (very believable)
Instead of raw numbers, assign roles.

Building roles
Strongpoint (main buildings, high capacity)

Security (side buildings near roads)

Auxiliary (sleeping, ammo, reserve)

Empty / abandoned

Density controls role distribution.

Example (medium density):

2 strongpoints

2–3 security buildings

1 auxiliary

rest empty

Each role defines:

Max group size

Allowed unit types

Stance / alertness

This works beautifully with CQB missions.

Option 5: Hybrid “Anchor + Satellites” model (highly recommended)
This is probably the sweet spot for you.

Algorithm
Pick 1–3 anchor buildings (main structures)

Assign full groups to anchors

For each anchor:

Roll number of satellite buildings (0–3)

Only within a radius

Assign overflow or security teams to satellites

Density controls:
Number of anchors

Size of groups

Satellite count

Result:

Natural compounds

Clear centers of resistance

Empty or lightly occupied outskirts

Anti-patterns to avoid (you already sensed these)
You’re absolutely right to avoid:
❌ “One group touches every building”
❌ “Every building has something in it”
❌ “Uniform distribution regardless of building size”

These kill realism fast.

Practical implementation tips (Arma-specific)
Cache building position counts early (you already do this well)

Track claimed buildings so groups don’t fight for space

Use soft caps, not hard rules (let 10–20% break the rules)

Log decisions — debugging population logic is painful otherwise

If you want, next steps
If you want, I can:

Sketch pseudo-SQF for the Anchor + Satellites model

Help you define density profiles as config data

Tie this into alert state escalation (dry hole → QRF)

Integrate this with your existing fn_extractComposition logic

Just tell me which direction you want to go 👀




No file chosenNo file chosen
ChatGPT can make mistakes. Check important info.
