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
PREP_SUB(data,getFactionAssets);
PREP_SUB(data,getStructurePositions);
PREP_SUB(data,getStructureTypes);
PREP_SUB(data,getStructureVariants);
PREP_SUB(data,recordStructurePositions);
PREP_SUB(data,spawnAtStructurePosition);

// Debug
PREP_SUB(debug,mapPositionsOnMilLocations);
PREP_SUB(debug,scanMapStructures);

// Faction
PREP_SUB(faction,extractGroups);
PREP_SUB(faction,getGroupsByTag);

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
PREP_SUB(locations,getAreaStructures);
PREP_SUB(locations,getCivilianLocations);
PREP_SUB(locations,getGuardPosts);
PREP_SUB(locations,getMapStructures);
PREP_SUB(locations,getMilitaryLocations);
PREP_SUB(locations,getPerimeterPositions);
PREP_SUB(locations,scanLocations);

// Validators
PREP_SUB(validators,groupActive);
