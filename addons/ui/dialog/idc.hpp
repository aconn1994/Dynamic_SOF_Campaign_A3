// Commander's Tablet — IDC constants only (safe to include from SQF)
//
// Keep this file free of any class definitions or config-only constructs.
// defines.hpp pulls this in for the dialog; SQF panels include this directly.

#ifndef DSC_TABLET_IDD

#define DSC_TABLET_IDD                   9000
#define DSC_TABLET_IDC_BACKGROUND        9001
#define DSC_TABLET_IDC_HEADER_TITLE      9002
#define DSC_TABLET_IDC_FOOTER_STATE      9003

#define DSC_TABLET_IDC_TAB_GROUP         9010
#define DSC_TABLET_IDC_TAB_MISSION       9011
#define DSC_TABLET_IDC_TAB_SUPPORTS      9012
#define DSC_TABLET_IDC_TAB_BFT           9013
#define DSC_TABLET_IDC_TAB_SQUAD         9014
#define DSC_TABLET_IDC_TAB_INTEL         9015

#define DSC_TABLET_IDC_PANEL_HOST        9020

#define DSC_TABLET_IDC_MGEN_PANEL        9100
#define DSC_TABLET_IDC_MGEN_TYPE         9101
#define DSC_TABLET_IDC_MGEN_PROFILE      9102
#define DSC_TABLET_IDC_MGEN_DENSITY      9103
#define DSC_TABLET_IDC_MGEN_MIN_DIST     9104
#define DSC_TABLET_IDC_MGEN_MAX_DIST     9105
#define DSC_TABLET_IDC_MGEN_FACTION      9106
#define DSC_TABLET_IDC_MGEN_QRF          9107
#define DSC_TABLET_IDC_MGEN_REPLACE      9108
#define DSC_TABLET_IDC_MGEN_AT_PLAYER    9109
#define DSC_TABLET_IDC_MGEN_GENERATE     9110
#define DSC_TABLET_IDC_MGEN_ABORT        9111
#define DSC_TABLET_IDC_MGEN_REFRESH      9112
#define DSC_TABLET_IDC_MGEN_CLOSE        9113
#define DSC_TABLET_IDC_MGEN_STATUS       9120

// View toggle
#define DSC_TABLET_IDC_MGEN_VIEW_STD     9130
#define DSC_TABLET_IDC_MGEN_VIEW_ADV     9131

// Standard panel container (shared row block: type/profile/density/faction/qrf/replace/anchor/dist)
#define DSC_TABLET_IDC_MGEN_STD_PANEL    9140

// Advanced-only panel container
#define DSC_TABLET_IDC_MGEN_ADV_PANEL    9150

// Advanced controls — Location section
#define DSC_TABLET_IDC_MGEN_ADV_LOCATION   9151
#define DSC_TABLET_IDC_MGEN_ADV_REQ_TAGS   9152
#define DSC_TABLET_IDC_MGEN_ADV_EXC_TAGS   9153
#define DSC_TABLET_IDC_MGEN_ADV_MIN_BLDG   9154

// Advanced controls — Population section
#define DSC_TABLET_IDC_MGEN_ADV_GAR_MIN    9160
#define DSC_TABLET_IDC_MGEN_ADV_GAR_MAX    9161
#define DSC_TABLET_IDC_MGEN_ADV_PATROLS    9162
#define DSC_TABLET_IDC_MGEN_ADV_VEHICLES   9163
#define DSC_TABLET_IDC_MGEN_ADV_VEH_ARMED  9164
#define DSC_TABLET_IDC_MGEN_ADV_AREA_PRES  9165
#define DSC_TABLET_IDC_MGEN_ADV_GUARD_COV  9166

// Advanced controls — Mission feel section
#define DSC_TABLET_IDC_MGEN_ADV_SKILL      9170
#define DSC_TABLET_IDC_MGEN_ADV_QRF_MIN    9171
#define DSC_TABLET_IDC_MGEN_ADV_QRF_MAX    9172

// Slider value labels (live readout next to each slider)
#define DSC_TABLET_IDC_MGEN_ADV_VEH_ARMED_LBL  9180
#define DSC_TABLET_IDC_MGEN_ADV_AREA_PRES_LBL  9181
#define DSC_TABLET_IDC_MGEN_ADV_GUARD_COV_LBL  9182

// ============================================================================
// Blue Force Tracker panel (Phase B, BFT-1)
// ============================================================================
#define DSC_TABLET_IDC_BFT_PANEL               9200
#define DSC_TABLET_IDC_BFT_MAP                 9201
#define DSC_TABLET_IDC_BFT_STATUS              9202
#define DSC_TABLET_IDC_BFT_RECENTER            9203
#define DSC_TABLET_IDC_BFT_LEGEND              9204
#define DSC_TABLET_IDC_BFT_TITLE               9205
#define DSC_TABLET_IDC_BFT_FILTER              9206

// BFT info card (BFT-2: click-to-select)
#define DSC_TABLET_IDC_BFT_INFO_GROUP          9210
#define DSC_TABLET_IDC_BFT_INFO_BG             9211
#define DSC_TABLET_IDC_BFT_INFO_TITLE          9212
#define DSC_TABLET_IDC_BFT_INFO_BODY           9213
#define DSC_TABLET_IDC_BFT_INFO_CLEAR          9214

// BFT info card — value labels (one per field, filled by panelBft_populateInfo)
#define DSC_TABLET_IDC_BFT_INFO_VAL_CATEGORY   9220
#define DSC_TABLET_IDC_BFT_INFO_VAL_SIDE       9221
#define DSC_TABLET_IDC_BFT_INFO_VAL_FACTION    9222
#define DSC_TABLET_IDC_BFT_INFO_VAL_STRENGTH   9223
#define DSC_TABLET_IDC_BFT_INFO_VAL_VEHICLE    9224
#define DSC_TABLET_IDC_BFT_INFO_VAL_DIST       9225
#define DSC_TABLET_IDC_BFT_INFO_VAL_DIST_OBJ   9226

// BFT info card — key labels (one per field, static labels)
#define DSC_TABLET_IDC_BFT_INFO_KEY_CATEGORY   9230
#define DSC_TABLET_IDC_BFT_INFO_KEY_SIDE       9231
#define DSC_TABLET_IDC_BFT_INFO_KEY_FACTION    9232
#define DSC_TABLET_IDC_BFT_INFO_KEY_STRENGTH   9233
#define DSC_TABLET_IDC_BFT_INFO_KEY_VEHICLE    9234
#define DSC_TABLET_IDC_BFT_INFO_KEY_DIST       9235
#define DSC_TABLET_IDC_BFT_INFO_KEY_DIST_OBJ   9236

// BFT command buttons (BFT-3: high command)
#define DSC_TABLET_IDC_BFT_CMD_HEADER          9240
#define DSC_TABLET_IDC_BFT_CMD_TAKE            9241
#define DSC_TABLET_IDC_BFT_CMD_MOVE_HERE       9242
#define DSC_TABLET_IDC_BFT_CMD_MOVE_OBJ        9243
#define DSC_TABLET_IDC_BFT_CMD_QRF             9244
#define DSC_TABLET_IDC_BFT_CMD_RELEASE         9245

// Debug HUD (always-on overlay)
#define DSC_DEBUG_HUD_IDD                      9300
#define DSC_DEBUG_HUD_IDC_FPS                  9301
#define DSC_DEBUG_HUD_IDC_STATE                9302
#define DSC_DEBUG_HUD_IDC_COUNTS               9303
#define DSC_DEBUG_HUD_IDC_CUSTOM               9304

#endif
