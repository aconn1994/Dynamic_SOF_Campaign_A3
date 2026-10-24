# Session 06 — Ambient Dressing (Animals & Vehicles)

**Owner item:** 3 (continued)
**Model:** Sonnet
**Ships:** Livestock/animals on farms and isolated residential locations;
role-appropriate civilian and work vehicles parked at matching POIs.
**Depends on:** 01, 02, 04, 05.

---

## Scope

Deliberately narrow (owner decision C12: *"farms and isolated residential
locations. No need to go too crazy."*).

### Animals

- **Where:** locations whose `subtypeProfile` contains agricultural subtypes
  (barn, cowshed, feed shack), plus isolated residential compounds.
- **What:** vanilla `Agents` — sheep, goats, cows, hens, rabbits; dogs at
  isolated residential.
- **How:** `createAgent`, small clusters near the anchoring POI, bounded count,
  yield between creates (they are cheap but the convention stands).
- **Despawn:** must be wired into the presence zone's despawn path. Agents are
  **not** units and will not be caught by group-based cleanup — this is the
  most likely leak in the session.

**Open question Q9 — do animals *matter*?** A barking dog raising local
alertness is a strongly SOF-flavored mechanic and would ride the existing C2
noise grading. *Recommendation: ship them as pure dressing this session; log
the dog-alert idea as a Session 08 candidate* (it belongs with spotting, not
with dressing).

### Vehicles

- **Where:** driven by POI subtype — tractors at barns, forklifts/trucks at
  warehouses, an ambulance at a clinic, boats at piers, a van at a shop, cars
  at houses.
- **What:** classes sourced from the map profile + `fnc_extractAssets`'s
  civilian pool, not hardcoded.
- **State:** **real, enterable, drivable, stealable vehicles.** Civilian
  transport is a legitimate AFO tactical option and should not be a prop.
- **Placement:** reuse `fnc_findParkingPosition`; do not write a new one.
- **Fuel/keys:** leave them functional. If theft turns out to trivialize
  missions, that is a Session 08 signature/compromise concern, not a reason to
  make vehicles fake.

---

## Tier-1 test plan (`suite: ambient_dressing`)

Keep the *selection* logic pure; the spawning is not testable.

- `fnc_resolveAmbientAnimals` — pure. `[subtypeProfile, tags, budget] → [[class, count], ...]`
  - Agricultural profile yields livestock; urban profile yields none (or dogs only).
  - Count respects budget; zero budget yields `[]`.
- `fnc_resolveAmbientVehicles` — pure. `[poiSubtypes, mapProfile, budget] → [[class, subtype], ...]`
  - Barn POI yields a tractor-class entry; pier yields a boat.
  - Every returned subtype exists in the Session 01 catalog (**cross-table integrity**).
  - No vehicle is proposed for a subtype with no parking affinity.

---

## Gotchas

- **`createAgent` entities are not in `allUnits`** and are not groups. Zone
  despawn must track them explicitly or they leak for the whole campaign.
- **Agents still cost simulation.** Cap them hard and enable dynamic simulation
  where it applies.
- **Empty vehicles have their own dyn-sim category** (`EmptyVehicle`, 500m —
  see `AGENTS.md`). Parked vehicles should opt in.
- **Yield convention** — `fnc_setupVehicles` already `uiSleep 0.2`s. Match it.
- **Do not let parked vehicles collide with mission placement.**
  `fnc_findParkingPosition` is shared; confirm mission AO population still gets
  usable parking after ambient vehicles claim spots.

---

## Definition of done

- New resolvers registered; `hemtt check` clean; Tier-1 `ambient_dressing` passing.
- Zone despawn removes animals and ambient vehicles — verified by driving away
  and back, then checking entity counts in RPT.
- Playtest: a farm has livestock and a tractor; an isolated house has a dog and
  a car; a clinic has an ambulance; a pier has a boat.
- No measurable frame regression vs the Session 05 baseline.
- `.crush/presence-manager.md` + `.crush/vehicle-systems.md` updated.
