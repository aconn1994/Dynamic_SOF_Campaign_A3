# Arma 3 Mission Generator Overhaul — Agent Context

## Overview

This document captures all design decisions, tuning data, and code changes made during a ground-up rewrite of an Arma 3 mission generator. The goal is difficulty without being overwhelming — the player should have seconds to react but be punished for bad decisions or carelessness. The mission supports solo player or low-number coop with optional AI squadmates.

The overhaul is being built in stages:
1. ✅ Garrison units — vanilla AI, solo player
2. 🔲 Guard units
3. 🔲 Patrol units
4. 🔲 Friendly AI squadmates
5. 🔲 LAMBS_Danger.fsm integration

---

## Stage 1: Garrison Units — COMPLETED

### Design Principles

- Garrison units are a **distraction and positional threat**, not the primary combat AI
- They create pressure through **cover advantage and sight lines**, not tactics
- **Do not fill every building** — 40-60% occupancy creates uncertainty that does more work than unit count
- Each unit should be their own **separate group** so they react independently and don't break CQB by trying to consolidate into formation with a leader in another building

### Tuned Skill Profile

This profile was used for controlled tests.  Three structures. 2 to 3 units per structure. Daytime. See test results below.

```sqf
private _skillProfile = [
    ["aimingAccuracy", 0.2],
    ["aimingShake",    0.3],
    ["aimingSpeed",    0.3],
    ["spotDistance",   0.5],
    ["spotTime",       0.5], // Drop at night if not nightvision-capable
    ["courage",        0.5],
    ["commanding",     0.5]
];
```

**Rationale:**
- Low accuracy and shake means first shot isn't guaranteed to hit — creates a reaction window
- Moderate aimingSpeed means they find the player quickly but don't drill instantly
- spotTime at 0.5 gives the player time to break LOS before position is fully locked
- Do not lower aimingSpeed to compensate for accuracy — high aimingSpeed with moderate accuracy is what creates the panic/reaction window feel

### Unit Count Per Building

| Location Type | Units Per Building |
|---|---|
| Main structures (large) | 3 |
| Smaller side structures | 2 |
| Maximum (bug threshold) | 4-5 (treat as overcrowded, avoid) Maybe tweak based on structure? Office buildings, military barracks, unfinished parking structures can have more. |

Structure 3 in testing had only 4 `buildingPos` slots. At 3 units that is 75% occupancy — noticeably tighter than buildings with 9-10 positions. Account for available positions when setting unit count.

### Known Issue: Opposing Unit Problem
*Ignore for now.  In time this may be solved with grenades/other means.*

When two units spawn at opposing ends of an open upper floor, the player cannot engage one without taking fire from the other. This is a **design problem, not a difficulty lever**. It creates frustration rather than tension.

**Recommended fix:** Weight spawn position selection so units in the same room are not placed at directly opposing angles. Or document it as intentional and expect players to carry grenades.

### Spawn and Group Logic

Units must be spawned into **individual groups per unit**. Using a shared group causes the engine's formation logic to pull units out of buildings toward the group leader on contact, breaking CQB behavior entirely.

```sqf
{
    private _building = _x;
    private _positions = (_building buildingPos -1) call BIS_fnc_arrayShuffle;
    private _spawnPositions = _positions select [0, _numUnits];

    {
        private _group = createGroup east;
        private _unit = _group createUnit [<soldier_class>, _x, [], 0, "NONE"];
        {
            _unit setSkill [_x select 0, _x select 1];
        } forEach _skillProfile;
    } forEach _spawnPositions;

} forEach [structure_1, structure_2, structure_3];
```

`buildingPos -1` returns all defined interior positions for a structure. Shuffle and slice to `_numUnits` for randomized placement each run.

### Testing Data — 2 Units Per Building (6 Total)

Fixed building layout, randomized unit positions.

| Run | Time | Result | Notes |
|-----|------|--------|-------|
| 1 | 91s | Survived | Baseline |
| 2 | DNF | Killed | Buttonhook, enemy at unexpected angle |
| 3 | DNF | Killed | Caught in open between structures |
| 4 | DNF | Killed | Second unit in same room after engaging first |
| 5 | 126s | Survived | Slow deliberate approach |

**Conclusion:** Skill profile is correctly tuned. Deaths were tactical mistakes not AI lethality. Profile does not need adjustment.

### Testing Data — 3 Units Per Building (9 Total)

| Run | Time | Result | Notes |
|-----|------|--------|-------|
| 1 | DNF | Killed | Two units at opposing ends of open floor |
| 2 | 169s | Survived | Cross fire, lost time on open floor |
| 3 | 150s | Survived | Adapting — checking windows before crossing |
| 4 | 167s | Survived | Forced to reroute, balcony engagement |
| 5 | 149s | Survived | Took damage from carelessness |

**Conclusion:** 3 units per building is the right density for main structures. Times clustered 150-170s, survival rate 4/5. Cross-structure sight lines are creating natural overlapping fields of fire without being engineered. Player learned to check windows before crossing between structures.

### Full initServer Snippet (Current State)

```sqf
// Mission start time
private _missionStartTime = diag_tickTime;
diag_log format ["[MISSION] Start time: %1", _missionStartTime];

// Skill profile
private _skillProfile = [
    ["aimingAccuracy", 0.2],
    ["aimingShake",    0.3],
    ["aimingSpeed",    0.3],
    ["spotDistance",   0.5],
    ["spotTime",       0.5],
    ["courage",        0.5],
    ["commanding",     0.5]
];

// Spawn and skill units per building in isolated groups
private _numUnits = 3;
{
    private _building = _x;
    private _buildingPositions = (_building buildingPos -1);
    diag_log format ["[GARRISON] %1 has %2 positions", _building, count _buildingPositions];

    private _shuffled = _buildingPositions call BIS_fnc_arrayShuffle;
    private _spawnPositions = _shuffled select [0, _numUnits];

    private _group = createGroup east;

    {
        private _unit = _group createUnit ["O_G_Soldier_lite_F", _x, [], 0, "NONE"];
        {
            _unit setSkill [_x select 0, _x select 1];
        } forEach _skillProfile;
        diag_log format ["[SKILL] Applied to: %1", _unit];
    } forEach _spawnPositions;

} forEach [structure_1, structure_2, structure_3];

// Watch for last unit killed
[_missionStartTime] spawn {
    params ["_missionStartTime"];
    waitUntil {
        sleep 2;
        ({ alive _x && side _x == east } count allUnits) == 0
    };
    _elapsed = diag_tickTime - _missionStartTime;
    diag_log format ["[MISSION] Last OPFOR killed. Elapsed: %1s", _elapsed];
};
```

---

## Stage 2: Guard Units — TO BE WRITTEN

### Design Principles

- Guards are a **visible deterrent first, combatant second**
- Player must be able to **spot guards before engaging** — no hidden bush snipers
- Guards are anchored to **logical visible positions**: doors, entry points, corners with long sight lines
- Guards watch obvious approach routes — the threat is that they're watching, not that they're hidden
- Alert state: let the **engine handle propagation** via share knowledge system — no custom scripting needed for alert behavior

### Guard Count

- 1 or 2 guards per location
- If 1: place at main entry point
- If 2: main entry + next most tactically significant point (corner with long sight line or secondary entrance)
- Guards per location form a **single group** so they cover each other

### Placement Logic (To Be Implemented)

Anchor to entry points, not perimeter radius. Filter `buildingPos` results for ground floor (Z < 1.5) to identify door-adjacent positions. Place guards at or just outside those positions **facing outward** toward the most likely approach route. Facing direction is critical — a guard facing a wall is useless.

```sqf
// Candidate approach — get ground floor entry-adjacent positions
private _entryPoints = [];
for "_i" from 0 to 20 do {
    private _pos = _mainStructure buildingPos _i;
    if (_pos isEqualTo [0,0,0]) exitWith {};
    if ((_pos select 2) < 1.5) then {
        _entryPoints pushBack _pos;
    };
};
```

### Function Structure (To Be Rewritten)

The existing guard function has three parts that need to be separated:

1. **Static defenses** (patrol towers, static weapons, snipers) — pull into its own standalone function entirely. Tower units need logic for whether they are manning a weapon or occupying the tower position.

2. **Military perimeter guards** — anchor to gates, vehicle entrances, open ground approaches

3. **Civilian structure guards** — anchor to main doors and corners commanding approach sight lines

Parts 2 and 3 share the same core placement logic, just different reference points. They should call a shared placement function with different anchor inputs rather than being written separately.

---

## Stage 3: Patrol Units — PENDING

### Design Principles (Agreed, Not Yet Implemented)

- One unpredictable patrol is more stressful than three predictable ones
- Vary timing with randomized wait times at waypoints
- Mix foot and vehicle patrols so timing cannot be gamed
- Some patrols should double back rather than loop
- Patrols roam the **further perimeter** beyond guard positions
- Patrols punish **static camping** — guards punish rushing, garrison punishes carelessness

---

## Stage 4: Friendly AI Squadmates — PENDING

### Design Considerations (Agreed, Not Yet Implemented)

- AI squadmates spot enemies through foliage, call contacts early, and may fire before player has positioned
- Scale enemy behavior and composition to squad size, not just player count
- Adding players: add **problems requiring coordination** not just more enemy bodies
- Suppression behavior pins friendly AI too — use this, don't fight it
- Design around AI squadmate as a **liability** — patrol behavior that reacts to sound will be triggered by friendly AI regularly, creating emergent tension

---

## Stage 5: LAMBS_Danger.fsm Integration — PENDING

### Key Levers Identified (Not Yet Implemented)

- **Suppression** set aggressive — primary tension tool, creates reaction window naturally
- **LAMBS_Sup** — suppression effect on AI units causes friendly AI to go evasive rather than standing and dying
- **Danger.fsm** infantry module — suppress-then-advance behavior
- Reduce garrison radius so units don't share position data through buildings
- Waypoint randomization for patrols — small random delays make timing impossible to game
- Flanking behavior on sustained contact — positional punishment for stalling is more interesting than accuracy punishment

### Skill Profile Adjustments for LAMBS

When LAMBS is added, revisit:
- `aimingSpeed` can go higher (0.6-0.7) because suppression creates the reaction window instead of accuracy gap
- `courage` high — units should push and not just hide, keeps pressure on player
- Last known position handling changes significantly under LAMBS — vanilla behavior of firing at last known position will be replaced

---

## General Design Rules Established

- **Change one variable per test run** — unit count, one skill value, or placement only
- **Slow deliberate play succeeds, rushing dies** — this is the intended feel and current tuning supports it
- **Positioning is free difficulty** — placement changes create more tension than skill slider changes
- **Quality over quantity** — 4 intelligent units are harder than 8 units milling around
- **Don't let enemy count creep** just because player has squadmates
- The "last 20%" problem: consider a small QRF (2-4 units) arriving 90-120 seconds after sustained contact to pressure extraction without overwhelming