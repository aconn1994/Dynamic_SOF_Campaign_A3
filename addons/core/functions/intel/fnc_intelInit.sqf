#include "..\..\script_component.hpp"
/*
 * Function: DSC_core_fnc_intelInit
 * Description:
 *     Creates (or wipes) the persistent Intel Ledger, `DSC_intelLedger` — a
 *     HASHMAP keyed by token id -> token (see `fnc_intelAdd`'s header for the
 *     full token schema, `.crush/campaign-overhaul.md` §4.1).
 *
 *     Intel is per-deployment (§11 decision 2): the ledger is created with
 *     the deployment and dies with it — no cross-deployment carryover.
 *     Call this once at deployment/session start (production: `fnc_initServer`
 *     STEP 0; harness: the "globals" step of `fnc_initTestScenario`).
 *
 *     Idempotent — safe to call more than once. Each call simply replaces
 *     `DSC_intelLedger` with a fresh empty hashmap; it never errors on a
 *     pre-existing ledger.
 *
 * Arguments: None
 *
 * Return Value:
 *     <HASHMAP> - the new, empty ledger (also published to DSC_intelLedger)
 *
 * Example:
 *     [] call DSC_core_fnc_intelInit;
 */

private _ledger = createHashMap;
missionNamespace setVariable ["DSC_intelLedger", _ledger, true];

INFO("intelInit - DSC_intelLedger created/cleared");

_ledger
