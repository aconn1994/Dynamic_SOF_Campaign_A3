#include "..\script_component.hpp"

// Revive Settings
respawn = 3;                      // 3 = Respawn at position
respawnDelay = 5;                 // Seconds before respawn
respawnTemplates[] = {"Revive"};  // Enables revive system

reviveMode = 2;                   // 0=disabled, 1=enabled for players only, 2=everyone
reviveDelay = 6;                  // Time before unit becomes incapacitated
reviveForceRespawnDelay = 30;     // Force respawn after X seconds
reviveBleedOutDelay = 300;        // Time until death if not revived
reviveRequiredTrait = 0;          // 0=anyone can revive, 1=medics only
reviveMedicSpeedMultiplier = 2;   // Medics revive faster
reviveUnconsciousStateMode = 0;   // 0=basic, 1=advanced
