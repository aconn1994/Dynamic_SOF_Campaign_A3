# Session 12 — Actionable Infrastructure

**Owner item:** new (raised answering Q2, October 2026)
**Model:** Opus spec → Sonnet build
**Status:** ⬜ scope brief only.
**Depends on:** 01 (subtypes + flags), 02 (POI registry incl. non-occupiable),
interaction-site primitive (campaign overhaul S5, shipped), C2 network (shipped).

---

## Origin

Owner, answering Q2:

> *"I wanted power stations marked so I could eventually put side-tasks to shut
> down the power to certain areas, either by action at a power station or
> destroying it. And for comms towers I wanted to bring those in as elements for
> AFO such as hacking to gain intel or sabotaging to impede comms for QRFs."*

This is not a tagging question — tagging it is trivial. It is a **systems**
question, and it turns out most of the plumbing already exists.

---

## The finding: C2 already has the hook, unread

`DSC_c2Nodes` node schema (from `.crush/c2-network.md`) already carries:

```
"infraLinks"  <ARRAY>  infrastructureNode ids this node depends on
```

**It is written and never read.** And C2 Sprint F.5 ("Counterplay", designed,
never built) already specifies exactly what the owner just asked for:

| Designed F.5 archetype | Quiet effect | Destroyed effect |
|---|---|---|
| `RADIO_RELAY` | links severed ~10 min, AMBER at next check-in | links severed long, **BLACK regionally** |
| `CELL_TOWER` | reliability −40% | reliability −70% |
| `POWER_SUBSTATION` | lights out | BLACK |

So "sabotage a comms tower to impede QRFs" is **F.5 with a physical anchor** —
the missing piece was never the C2 side, it was that no POI existed to attach it
to. Session 02's POI registry supplies that.

Relevant C2 mechanics that make this bite:

- Propagation is a **static neighbour walk over `links`** with a per-hop
  reliability roll. There is **no rerouting, no store-and-forward, no path
  recomputation.** Severing links genuinely isolates a branch — and everything
  downstream of it.
- Grade degrades one rank per hop (RED reaches 1 hop, BLACK 2), so cutting a
  relay has a disproportionate effect on how far an alarm travels.
- A node with no reachable neighbours cannot escalate, so its QRF ladder caps
  out. **That is the player's reward, and it is already modelled.**

---

## The hard part: service relationships

Tagging a substation is free. Knowing **what it serves** is not — Arma provides
no such data, and power-line objects are not a traversable graph.

Two relationships are needed:

1. **Power station / substation → locations served.** For "shut down power to
   this area".
2. **Comms tower → C2 node(s) fed.** For `infraLinks`.

Only tractable approach: **compute a proximity-based service area once at
init**, after `fnc_scanLocations` and before/alongside `fnc_initC2Network`.
Nearest-N-within-radius, or a Voronoi-ish assignment over infrastructure POIs.
It is an approximation, but it is *believable* and it is deterministic, which is
what matters. Do **not** attempt to trace actual power-line object chains.

**Ordering constraint:** `fnc_initC2Network` is STEP 4c and must run before
presence/roving (`AGENTS.md`). Infrastructure→node binding must therefore happen
**at or before 4c**, not bolted on later.

---

## Effects worth building (owner to prioritise)

| Action | Target subtype | Effect | Rides |
|---|---|---|---|
| Sabotage / destroy | `power_station`, `power_substation` | Lights out across served locations; night ops get darker; C2 node → BLACK or degraded | existing C2 + a lighting pass |
| Shut down (reversible) | `power_station` | Same, but temporary and non-destructive — an AFO-flavoured option | interaction site |
| Hack / exploit | `comms_tower`, `comms_relay` | **Intel token** — reveals node roster, callsigns, alert states, or grants temporary ENHANCED ISR coverage | Intel Ledger + C2 ISR tiers |
| Sabotage | `comms_tower`, `comms_relay` | Sever `links` for N minutes → QRF ladder capped, alarm propagation truncated | C2 F.5 |
| Destroy | `comms_tower` | Long sever, regional BLACK | C2 F.5 |

**The hack-for-intel case is the strongest AFO content in the whole program.**
It is a non-violent objective with a real mechanical payoff, it produces an
Intel Ledger token, and it makes the C2 network — currently a mostly invisible
simulation — directly legible to the player.

---

## Scope boundaries

- **Lighting.** "Lights out" sounds simple and is not. Arma town lights are
  per-object and there is no global switch. Scope this carefully or cut it to a
  C2/gameplay effect with no visual component in v1.
- **Do not build a power-line graph.** Proximity service areas only.
- **Reversible vs destructive** should both exist — it is the cleanest
  AFO-vs-DA expression in the program (quietly disable vs blow it up), and it
  feeds Session 08's compromise model directly.

---

## Parked questions

- **Q28** — Is "lights out" a real visual effect, or a gameplay-only state in v1?
- **Q29** — Should infrastructure sabotage be a **side objective** attached to
  existing missions, a **standalone mission type**, or both?
  *Recommendation: side objective first* — it composes with everything and needs
  no new mission plumbing.
- **Q30** — Does hacking a comms tower grant a **token** (persistent, decays via
  the ledger) or a **timed buff** (temporary ENHANCED ISR)? Token is more
  consistent with the existing architecture.
- **Q31** — Should destroyed infrastructure **stay destroyed** across the
  deployment (campaign persistence) or reset per mission?
