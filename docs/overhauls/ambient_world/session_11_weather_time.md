# Session 11 — Weather & Time

**Owner item:** 8
**Model:** Opus spec → Sonnet build
**Status:** ⬜ scope brief only — **owner parked the detail discussion.**
**Source material:** `docs/overhauls/Ambient_Elements.md`.

---

## Scope sketch

The owner's notes:

- Dynamic weather.
- Random time of year is picked.
- Weather consistent with the real-world counterpart at that time of year
  (Altis = Lemnos, Greece).

Session 03's `fnc_getMapProfile` already reserves a `climate` block for exactly
this. This session fills it in and builds the resolver that turns
*(climate band, date, time)* into a weather state.

---

## Likely shape

1. **`fnc_getMapProfile` climate block** — per-world monthly envelopes:
   temperature, precipitation probability, fog probability, overcast
   distribution, wind, typical daylight hours.
2. **`fnc_resolveWeather`** — **pure.** `[climate, date, timeOfDay, seed] →
   weather state hashmap`. Pure means the whole thing is Tier-1 testable with
   zero Arma world: "July on Altis is rarely foggy; January is often overcast."
3. **`fnc_applyWeather`** — the one impure applier (`setDate`, `setOvercast`,
   `setFog`, `setWind`, `forceWeatherChange`).
4. **Deployment-level date** — set once at campaign start and drifting day to
   day, rather than rerolled per mission.

---

## Known integration points

- **The C2 ISR drone's coverage radius is already weather-degraded.** Changing
  weather changes what the player can see on the Radio Feed. Verify that an
  ENHANCED coverage area does not silently collapse to BASIC on a foggy
  deployment.
- **C2 telegraphs (illum flare, forced headlights) are night-gated on
  `sunOrMoon > 0.35`.** A seasonal date change moves sunrise/sunset and will
  shift how often those fire.
- **Session 05's civilian night falloff** keys on `sunOrMoon`/`daytime` rather
  than a fixed hour, specifically so it survives this session.
- **Aircraft spawn altitudes are terrain-relative** — heavy fog/low cloud does
  not change that, but roving air behavior in weather is worth a playtest look.

---

## Parked questions (from the planning pass)

- **Q24** — Static per-mission weather drawn from the climate table, or weather
  that **evolves during** a mission? Evolving weather is strong SOF pressure
  (fog rolling in during infil) but interacts with ISR coverage.
- **Q25** — What does time of year drive besides weather? Daylight hours and sun
  angle come free from `setDate`. Also foliage/snow (map-dependent), civilian
  activity density, agricultural activity (harvest season)?
- **Q26** — Per-deployment with day-to-day drift, or per-mission random?
  *Recommendation: per-deployment with drift* — makes the deployment feel like a
  place and a season rather than a slot machine.
- **Q27** — Is making **night operations** more common/favored an explicit goal?
  If so, does the ambient layer need town lights, OP searchlights, and
  illumination considerations?
