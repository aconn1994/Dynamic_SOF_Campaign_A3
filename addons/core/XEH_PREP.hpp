// AI
PREP_SUB(ai,addCombatActivation);
PREP_SUB(ai,applySkillProfile);
PREP_SUB(ai,buildRoadRoute);
PREP_SUB(ai,convergePatrols);
PREP_SUB(ai,findParkingPosition);
PREP_SUB(ai,getSkillProfile);
PREP_SUB(ai,persistentUAV);
PREP_SUB(ai,populateAO);
PREP_SUB(ai,setupGarrison);
PREP_SUB(ai,setupGuards);
PREP_SUB(ai,setupPatrols);
PREP_SUB(ai,setupStaticDefenses);
PREP_SUB(ai,setupVehiclePatrol);
PREP_SUB(ai,setupVehicles);
PREP_SUB(ai,vehiclePatrolLoop);

// Classification
PREP_SUB(classification,classifyUnit);
PREP_SUB(classification,classifyGroup);
PREP_SUB(classification,classifyGroups);

// Data
PREP_SUB(data,getBriefingFragments);
PREP_SUB(data,getCompletionTypes);
PREP_SUB(data,getEntityArchetypes);
PREP_SUB(data,getMissionProfiles);
PREP_SUB(data,getObjectArchetypes);
PREP_SUB(data,getStructureTypes);

// Debug

// Faction
PREP_SUB(faction,extractAssets);
PREP_SUB(faction,extractGroups);
PREP_SUB(faction,getGroupsByTag);
PREP_SUB(faction,initFactionData);
PREP_SUB(faction,resolveEntityClass);

// Init
PREP_SUB(init,initBases);
PREP_SUB(init,initServer);
PREP_SUB(init,initServerDebug);
PREP_SUB(init,initPlayerLocal);
PREP_SUB(init,initPlayerLocalDebug);
PREP_SUB(init,setupBase);

// Base (player base actions, recruitment, insertions)
PREP_SUB(base,haloJump);
PREP_SUB(base,handlePlayerDown);
PREP_SUB(base,recruitMedic);
PREP_SUB(base,requestExtraction);
PREP_SUB(base,simulateFastTravel);
PREP_SUB(base,spawnTransportHelo);

// Markers
PREP_SUB(markers,drawCompoundMarkers);

// Placement strategies
PREP_SUB(placement,placeInDeepBuilding);
PREP_SUB(placement,placeInterior);
PREP_SUB(placement,placeObjects);
PREP_SUB(placement,placeOnGround);
PREP_SUB(placement,placeOutdoorPile);

// Missions
PREP_SUB(missions,addInteractionHandler);
PREP_SUB(missions,buildMissionOutcome);
PREP_SUB(missions,createMissionBriefing);
PREP_SUB(missions,evaluateCompletion);
PREP_SUB(missions,generateMission);
PREP_SUB(missions,generateRaidMission);
PREP_SUB(missions,resolveMissionConfig);
PREP_SUB(missions,selectMission);
PREP_SUB(missions,cleanupMission);

// Location
PREP_SUB(locations,getMapStructures);
PREP_SUB(locations,initInfluence);
PREP_SUB(locations,scanLocations);
PREP_SUB(locations,updateInfluence);

// Validators
PREP_SUB(validators,groupActive);
