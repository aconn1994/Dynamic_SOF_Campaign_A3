// AI
PREP_SUB(ai,addCombatActivation);
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
PREP_SUB(data,getStructureVariants);
PREP_SUB(data,recordStructurePositions);
PREP_SUB(data,spawnAtStructurePosition);

// Debug
PREP_SUB(debug,mapPositionsOnMilLocations);

// Faction
PREP_SUB(faction,extractGroups);
PREP_SUB(faction,getGroupsByTag);

// Init
PREP_SUB(init,initServer);
PREP_SUB(init,initPlayerLocal);

// Location
PREP_SUB(locations,getAreaStructures);
PREP_SUB(locations,getGuardPosts);
PREP_SUB(locations,getMilitaryLocations);
PREP_SUB(locations,getPerimeterPositions);

// Validators
PREP_SUB(validators,groupActive);
