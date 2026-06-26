// Tablet shell
PREP_SUB(tablet,openTablet);
PREP_SUB(tablet,closeTablet);
PREP_SUB(tablet,switchPanel);

// Mission Gen panel
PREP_SUB(tablet,panelMissionGen_init);
PREP_SUB(tablet,panelMissionGen_switchView);
PREP_SUB(tablet,panelMissionGen_sliderLabel);
PREP_SUB(tablet,panelMissionGen_readTemplate);
PREP_SUB(tablet,panelMissionGen_submit);
PREP_SUB(tablet,panelMissionGen_abort);
PREP_SUB(tablet,panelMissionGen_refreshState);

// Blue Force Tracker panel (BFT-1: read-only tracker, BFT-2: click select, BFT-3: high command, BFT-5: filter)
PREP_SUB(tablet,panelBft_init);
PREP_SUB(tablet,panelBft_draw);
PREP_SUB(tablet,panelBft_buildTracks);
PREP_SUB(tablet,panelBft_select);
PREP_SUB(tablet,panelBft_clearSelection);
PREP_SUB(tablet,panelBft_populateInfo);
PREP_SUB(tablet,panelBft_infoIdcs);
PREP_SUB(tablet,panelBft_command);
PREP_SUB(tablet,panelBft_toggleFilter);

// Debug HUD overlay
PREP_SUB(tablet,toggleDebugHud);
