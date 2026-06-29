#define MAINPREFIX z
#define PREFIX DSC
#define AUTHOR "Acorn"

#ifndef COMPONENT_BEAUTIFIED
    #define COMPONENT_BEAUTIFIED COMPONENT
#endif
#define COMPONENT_NAME QUOTE(DSC - COMPONENT_BEAUTIFIED)

// Debug Levels:
// 0 = No debug
// 1 = RPT only
// 2 = RPT + screen
#define DEBUGGER 2

// Debug Modes (set ONE of the three below):
//   DEBUG_MODE_MINIMAL = live play         — ERROR() | ERROR_WITH_TITLE()
//   DEBUG_MODE_NORMAL  = playtest          — + INFO() | WARNING()
//   DEBUG_MODE_FULL    = developer debug   — + LOG() | TRACE_n(), debug markers, instrumentation systemChats
//
// Convention used across DSC:
//   ERROR              — bad input / missing required data / unrecoverable
//   WARNING            — degraded but operational (fallback / missing optional data)
//   INFO               — lifecycle milestones (init banners, mission START/END, "X initialized")
//   LOG                — per-event detail (per-zone activation, per-archetype, per-queue event)
//   TRACE_n            — variable inspection on the same per-event detail
//
// Debug markers + spammy systemChats are gated behind #ifdef DEBUG_MODE_FULL.
#define DEBUG_MODE_NORMAL

#include "script_version.hpp"
