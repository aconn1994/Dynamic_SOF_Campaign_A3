# Session 10 — Military Presence Rework

**Owner item:** 7
**Model:** Opus spec → Sonnet build
**Status:** ⬜ scope brief only — **owner explicitly parked the detail
discussion.** Work order to be written after Session 09.
**Source material:** `docs/overhauls/Ambient_Elements.md`,
`.crush/presence-manager.md`.

---

## The thesis

The owner's judgment, from play:

> *"Adding a lot of ambient military units honestly did not do a lot for
> immersion other than put factions into random gunfights that affected the
> player's framerate and disrupted the campaign."*
>
> *"Random military garrisons in civilian locations are to be removed. I'd
> prefer to create Observation Posts for military garrisons/units outside of
> military locations for establishing presence. Having a random garrison in a
> city just goes unnoticed and wastes compute."*
>
> *"When we get to military, I want to be very meticulous about why they are
> there instead of just dropping some down randomly."*

**Design rule for this session: every ambient military unit must have a reason
to be where it is, and that reason must be legible to the player.** An OP on a
ridge overlooking a road is legible. A fireteam standing in an alley is not.

---

## Captured direction (owner notes — not yet decisions)

| Topic | Owner's direction |
|---|---|
| OP definition | Presence-manager zone type **or** mission-area element — undecided |
| OP siting | **Terrain-driven preferred.** Can land late in the plan. |
| OP and intel | Could be a primary intel target, or a supporting element of a mission site. Revealed via the Intel Ledger. Wants further discussion. |
| Checkpoints | Interaction-based "would be very cool". Needs its own session(s). |
| What gets deleted | Later discussion |
| Patrols | **"Very good in their current state."** Discuss later; do not touch. |
| Roving manager | Candidate to fold into presence once presence becomes deliberate. Decide here. |

---

## Hard constraints (from `AGENTS.md`)

- **`fnc_presenceHandlerPopulatedArea` has THREE independent military blocks** —
  the `_wantMil` controlling garrison, the ungated irregular indoor garrison,
  and the military overlay patrol. Gating one is not enough. The irregular
  garrison is *deliberately* ungated and is what makes towns dangerous.
- **Microzone projection: suppress the CHANCES, never the STRENGTH.** `strength`
  is overloaded — `strength <= 0` means "unclaimed wilderness, roll a 65% EAST
  insurgent fireteam". Zeroing it makes friendly territory *louder*.
- **Ambient military is only projected from opFor/contested installations**
  today, for cause: the projection is side-blind and bluFor zones spawned
  independent detachments that east treated as hostile, producing two mutually
  hostile ambient armies fighting with no player involvement.
- **C2 init must run before presence + roving**, or provenance stamping silently
  no-ops.
- **C2 provenance is stamped at the dispatcher, not in setup functions.**
- **Presence queues must be mutated in place** (`deleteAt`), never reassigned.
- **New zone types register via `fnc_registerPresenceHandler`** — do not add
  branches to `fnc_activatePresenceZone`.

---

## Parked questions (re-ask when writing the work order)

- **Q17** — Is an OP a **persistent world fixture** (computed once at init from
  influence, same lifecycle as a C2 node — destructible, targetable, a ledger
  subject) or an **ephemeral presence zone**? *Persistent is far more
  interesting and composes with C2 and the ledger.*
- **Q18** — Terrain-driven siting needs an elevation/LOS scoring pass over road
  and settlement networks. Is that its own session?
- **Q19** — Are OPs hidden by default and revealed by intel? Confirm.
- **Q20** — Checkpoints: dressing-with-guards, or a real interaction (stopped
  in a civilian vehicle, bluff / wave-through / search)? The latter rides the
  interaction-site primitive and is a genuine AFO mechanic.
- **Q21** — Confirm the kill list: does `_wantMil` controlling garrison and the
  military overlay patrol go away? Does the ungated irregular garrison stay?
- **Q22** — Patrols: leave alone, or link them (installation → OP → return) so
  C2's existing RTB/check-in machinery becomes visible to the player for the
  first time?
- **Q23** — Fold roving into presence, keep separate, or cut back?
