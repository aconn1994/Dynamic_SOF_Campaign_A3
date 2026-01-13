// Global toggles for caching/logging
#define DISABLE_COMPILE_CACHE
// #define DEBUG_MODE_FULL
#define DEBUG_SYNCHRONOUS

#include "\z\DSC\addons\main\includes\script_macros_common.hpp"
#include "\z\DSC\addons\main\includes\script_xeh.hpp"

#define QQUOTE(var1) QUOTE(QUOTE(var1))

#define DFUNC(var1) TRIPLES(ADDON,fnc,var1)

#ifdef DISABLE_COMPILE_CACHE
  #undef PREP
  #define PREP(fncName) DFUNC(fncName) = compile preprocessFileLineNumbers QPATHTOF(functions\DOUBLES(fnc,fncName).sqf)
  #define PREP_RECOMPILE_START    if (isNil "DSC_fnc_recompile") then {DSC_recompiles = []; DSC_fnc_recompile = {{call _x} forEach DSC_recompiles;}}; private _recomp = {
  #define PREP_RECOMPILE_END      }; call _recomp; DSC_recompiles pushBack _recomp;
#else
  #undef PREP
  #define PREP(fncName) [QPATHTOF(functions\DOUBLES(fnc,fncName).sqf), QFUNC(fncName)] call CBA_fnc_compileFunction
  #define PREP_RECOMPILE_START ; /* disabled */
  #define PREP_RECOMPILE_END ; /* disabled */
#endif
