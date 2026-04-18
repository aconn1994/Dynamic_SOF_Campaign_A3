// AI
PREP_SUB(ai,addCombatActivation);
PREP_SUB(ai,applySkillProfile);
PREP_SUB(ai,convergePatrols);
PREP_SUB(ai,getSkillProfile);
PREP_SUB(ai,persistentUAV);
PREP_SUB(ai,populateAO);
PREP_SUB(ai,setupGarrison);
PREP_SUB(ai,setupGuards);
PREP_SUB(ai,setupPatrols);

// Classification
PREP_SUB(classification,classifyUnit);
PREP_SUB(classification,classifyGroup);
PREP_SUB(classification,classifyGroups);

// Data
PREP_SUB(data,getStructureTypes);

// Debug

// Faction
PREP_SUB(faction,extractAssets);
PREP_SUB(faction,extractGroups);
PREP_SUB(faction,getGroupsByTag);
PREP_SUB(faction,initFactionData);

// Init
PREP_SUB(init,initServer);
PREP_SUB(init,initPlayerLocal);

// Base (player base actions, recruitment, insertions)
PREP_SUB(base,haloJump);
PREP_SUB(base,handlePlayerDown);
PREP_SUB(base,recruitMedic);
PREP_SUB(base,requestExtraction);
PREP_SUB(base,simulateFastTravel);
PREP_SUB(base,spawnTransportHelo);

// Missions
PREP_SUB(missions,createMissionBriefing);
PREP_SUB(missions,generateKillCaptureMission);
PREP_SUB(missions,cleanupMission);

// Location
PREP_SUB(locations,getMapStructures);
PREP_SUB(locations,initInfluence);
PREP_SUB(locations,scanLocations);
PREP_SUB(locations,updateInfluence);

// Validators
PREP_SUB(validators,groupActive);
