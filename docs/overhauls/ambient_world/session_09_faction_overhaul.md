# Session 09 — Faction Overhaul

**Owner item:** 6
**Model:** Opus spec → Sonnet build
**Status:** ⬜ scope brief only — work order to be written after Session 08.
**Source material:** `.crush/faction-autoscan.md` (designed, deferred),
`.crush/faction-sides.md`, `docs/overhauls/Ambient_Elements.md`.

---

## Scope sketch

The owner's note: *"Overhaul use of factions. This is TBD, right now I have them
hardcoded as profiles based on mod-set that is loaded. Probably a better way,
will probably be influenced by some of the above features."*

Two candidate scopes, to be chosen when the work order is written:

1. **Map-profile-driven casting (narrow).** `fnc_getMapProfile` (Session 03)
   supplies civilian / police / host-nation factions per world; the hardcoded
   mod-set profiles keep handling the combatant roles. Low risk, high immediate
   value, and already half-built by Session 03.
2. **Faction autoscan (wide).** Build the designed-but-deferred inverted
   `CfgGroups` walk from `.crush/faction-autoscan.md` — faction catalog, role
   scoring heuristics, and a Campaign Setup panel on the Commander's Tablet.
   Kills the mod-set desync table entirely.

*Recommendation: do (1) as this session, and treat (2) as its own program.*
Autoscan is a large, self-contained subsystem; bundling it here would stall the
ambient program behind it.

---

## Police as a first-class concept

The owner's briefing example requires something the current model cannot
express:

> *"The hostage will be transported through the airport. Altis police runs
> security for the airport terminal and are on the payroll, expect them to be
> hostile."*

That implies a faction whose **disposition varies per mission** — police neutral
in mission A, hostile in mission B. Today role sides are normalized **once** at
`fnc_initServer` (`fnc_resolveRoleSide`) and are fixed for the whole deployment,
deliberately, because per-site resolution caused months of same-faction
fratricide bugs.

**This is the single riskiest change in the program.** It must not re-introduce
per-site side resolution. Likely shape: police stay on one engine side for the
whole deployment, and *mission-scoped hostility* is expressed through a separate
mechanism (mission-local `setFriend`-free targeting, or casting the compromised
police as a distinct faction instance) rather than by moving them between sides.

---

## Hard constraints (from `AGENTS.md`, non-negotiable)

- **Role sides are normalized once, in `fnc_initServer`.** Do not re-introduce
  per-call-site side resolution.
- **Side diplomacy is set once in `fnc_initPresenceManager`, symmetrically, and
  never mutated per-mission.** The old per-mission `setFriend` calls are deleted
  for cause; do not re-add them.
- **INDEPENDENT is reserved for `bluForPartner`.** Hostile roles collapse onto
  east.
- **Faction roles are cast by behaviour, not by config side.** Police and
  peacekeepers belong in `environmentalActors`, not a partner role.
- **`group createUnit` does not set unit side — always `joinSilent`.**

---

## Parked questions

- **Q14** — Narrow (map-profile casting) or wide (autoscan) scope?
- **Q15** — Do you want **per-mission faction disposition** as a real feature,
  and if so is "police can be hostile this mission" the only case, or is it
  general (any `environmentalActor` / `bluForPartner` can be compromised)?
- **Q16** — Should the map profile *override* the mod-set profile for civilian
  and police roles, or *merge* with it?
