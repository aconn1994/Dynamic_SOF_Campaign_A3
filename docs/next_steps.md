## What I found (the regression is mine)


I made diplomacy strict ( east ↔ independent  = hostile) but only converted 3 of ~10 side-resolution call sites. The
other seven still spawn  irregulars  on independent — which is now hostile to east — so opFor-aligned factions shoot
each other on spawn. Half a migration is worse than either end state.

New doc  .crush/faction-sides.md  has the full write-up: why independent is double-booked, what changed, the exact
file+line list of every unconverted site, and two resolution paths (finish the migration, or revert to permissive but
add the missing  west↔independent  pair that caused the original one-way-fire bug).

Most likely culprit for what you saw:  fnc_presenceHandlerPopulatedArea  — towns spawn both a  bluForPartner  garrison
and an  irregulars  garrison, and those are now enemies.

## Docs updated



 File                      │ Change
───────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────
  .crush/faction-sides.md  │ New. Side model, the regression, remaining sites, fix options, validation steps
  AGENTS.md                │ Replaced the (now false) "resolver is authoritative" gotcha with a ⚠ warning pointing at
                           │ the new doc
  .crush/c2-network.md     │ F.1–F.3 shipped + all three playtest fix rounds; side section corrected to UNRESOLVED,
                           │ notes the C2-specific impact on node sides
  .crush/roadmap.md        │ Side bug as top-priority known bug; replaced a badly stale "Next up: Sprint A" (shipped
                           │ months ago) with real current state

## Handoff summary


C2 F.1–F.3 are shipped and working. Report timer, radioman multiplier, reach gate, echo suppression, recall + QRF with
real travel — all confirmed in-game across three playtests and eleven fixes.

Next session's order should be:

1. Side regression — until it's fixed, no playtest of anything is trustworthy
2. Road-route + rotary-crash bugs (both currently inject false C2 signals)
3. F.4 ISR/Radio Feed — the network works but is invisible outside the RPT

One note for whichever way you go on sides:  fnc_initC2Network  line ~92 resolves node sides and is on the unconverted
list. Node sides feed  fnc_c2ResolveNode  matching, so if they end up disagreeing with spawn sides, C2 provenance
silently drops with no error.