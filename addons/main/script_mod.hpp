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
#define DEBUG_MODE_MINIMAL // DEBUG_MODE_FULL
#define DEBUGGER 2

#include "script_version.hpp"
