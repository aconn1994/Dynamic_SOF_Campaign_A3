// Commander's Tablet — Main dialog
//
// Layout strategy:
//   Bezel image is intentionally NOT used in this iteration. The dialog is a
//   centered panel sized to a comfortable fraction of the screen.
//
// Mission Gen panel architecture:
//   - Single host RscControlsGroup.
//   - Always-visible "core" controls (type/profile/density/faction/distance/
//     QRF/replace/anchor) — shared between Standard and Advanced views.
//   - View toggle [STANDARD] [ADVANCED] flips an Advanced overlay group
//     (`MissionGenAdv`) on/off via DSC_ui_fnc_panelMissionGen_switchView.
//   - Submit reads the core controls always; if Advanced is visible, also
//     reads its fields and merges them into the template.
//
// NOTE: createDialog looks up dialog classes at the ROOT of configFile,
// not inside CfgDialogs. The class is therefore declared top-level here.

// Two-pass stringify so macros expand BEFORE being quoted.
#define DSC_STRINGIFY_(x) #x
#define DSC_STRINGIFY(x) DSC_STRINGIFY_(x)
#define EXPR(x) DSC_STRINGIFY(x)

// --- Panel rect (fraction of safezone, centered) ---
#define SCR_W_PCT 0.66
#define SCR_H_PCT 0.78

#define SCR_W (safezoneW * SCR_W_PCT)
#define SCR_H (safezoneH * SCR_H_PCT)
#define SCR_X (safezoneX + (safezoneW - SCR_W) / 2)
#define SCR_Y (safezoneY + (safezoneH - SCR_H) / 2)

// Standard row height (relative to panel rect)
#define ROW_H (SCR_H * 0.075)

class DSC_Tablet {
        idd = DSC_TABLET_IDD;
        movingEnable = 0;
        enableSimulation = 1;
        enableDisplay = 1;
        onLoad = "uiNamespace setVariable ['DSC_TabletDisplay', _this select 0]; [_this select 0] call DSC_ui_fnc_panelMissionGen_init; [_this select 0, 'bft'] call DSC_ui_fnc_switchPanel;";
        onUnload = "uiNamespace setVariable ['DSC_TabletDisplay', displayNull];";

        class ControlsBackground {

            // Full-screen dim
            class Dim : DSC_RscText {
                idc = -1;
                style = ST_BACKGROUND;
                x = "safezoneX";
                y = "safezoneY";
                w = "safezoneW";
                h = "safezoneH";
                colorBackground[] = { 0, 0, 0, 0.55 };
            };

            // Panel background (opaque dark)
            class Screen : DSC_RscBackground {
                idc = -1;
                x = EXPR(SCR_X);
                y = EXPR(SCR_Y);
                w = EXPR(SCR_W);
                h = EXPR(SCR_H);
                colorBackground[] = { 0.04, 0.06, 0.08, 1.0 };
            };
        };

        class Controls {

            // ----------------------------------------------------------------
            // Header title
            // ----------------------------------------------------------------
            class HeaderTitle : DSC_RscText {
                idc = DSC_TABLET_IDC_HEADER_TITLE;
                style = ST_LEFT;
                font = FONT_B;
                sizeEx = 0.034;
                text = "DSC // COMMANDER";
                x = EXPR(SCR_X + SCR_W * 0.02);
                y = EXPR(SCR_Y + SCR_H * 0.015);
                w = EXPR(SCR_W * 0.30);
                h = EXPR(ROW_H);
                colorText[] = COLOR_ACCENT;
            };

            // ----------------------------------------------------------------
            // Tab bar — BFT first (default landing tab), Mission Debug last
            // ----------------------------------------------------------------
            class TabBft : DSC_RscTabButton {
                idc = DSC_TABLET_IDC_TAB_BFT;
                text = "BFT";
                x = EXPR(SCR_X + SCR_W * 0.36);
                y = EXPR(SCR_Y + SCR_H * 0.015);
                w = EXPR(SCR_W * 0.07);
                h = EXPR(ROW_H * 0.95);
                colorBackground[] = COLOR_ACCENT;
                action = "[(uiNamespace getVariable 'DSC_TabletDisplay'), 'bft'] call DSC_ui_fnc_switchPanel;";
            };
            class TabSupports : DSC_RscTabButton {
                idc = DSC_TABLET_IDC_TAB_SUPPORTS;
                text = "SUPPORTS";
                x = EXPR(SCR_X + SCR_W * 0.435);
                y = EXPR(SCR_Y + SCR_H * 0.015);
                w = EXPR(SCR_W * 0.115);
                h = EXPR(ROW_H * 0.95);
                colorBackground[] = { 0.10, 0.13, 0.16, 0.4 };
                colorText[] = COLOR_TEXT_DIM;
                action = "[(uiNamespace getVariable 'DSC_TabletDisplay'), 'supports'] call DSC_ui_fnc_switchPanel;";
            };
            class TabSquad : DSC_RscTabButton {
                idc = DSC_TABLET_IDC_TAB_SQUAD;
                text = "SQUAD";
                x = EXPR(SCR_X + SCR_W * 0.555);
                y = EXPR(SCR_Y + SCR_H * 0.015);
                w = EXPR(SCR_W * 0.085);
                h = EXPR(ROW_H * 0.95);
                colorBackground[] = { 0.10, 0.13, 0.16, 0.4 };
                colorText[] = COLOR_TEXT_DIM;
                action = "[(uiNamespace getVariable 'DSC_TabletDisplay'), 'squad'] call DSC_ui_fnc_switchPanel;";
            };
            class TabIntel : DSC_RscTabButton {
                idc = DSC_TABLET_IDC_TAB_INTEL;
                text = "INTEL";
                x = EXPR(SCR_X + SCR_W * 0.645);
                y = EXPR(SCR_Y + SCR_H * 0.015);
                w = EXPR(SCR_W * 0.075);
                h = EXPR(ROW_H * 0.95);
                colorBackground[] = { 0.10, 0.13, 0.16, 0.4 };
                colorText[] = COLOR_TEXT_DIM;
                action = "[(uiNamespace getVariable 'DSC_TabletDisplay'), 'intel'] call DSC_ui_fnc_switchPanel;";
            };
            class TabMission : DSC_RscTabButton {
                idc = DSC_TABLET_IDC_TAB_MISSION;
                text = "MISSION DEBUG";
                x = EXPR(SCR_X + SCR_W * 0.725);
                y = EXPR(SCR_Y + SCR_H * 0.015);
                w = EXPR(SCR_W * 0.155);
                h = EXPR(ROW_H * 0.95);
                colorBackground[] = { 0.10, 0.13, 0.16, 0.4 };
                colorText[] = COLOR_TEXT_DIM;
                action = "[(uiNamespace getVariable 'DSC_TabletDisplay'), 'mission'] call DSC_ui_fnc_switchPanel;";
            };

            class CloseBtn : DSC_RscDangerButton {
                idc = DSC_TABLET_IDC_MGEN_CLOSE;
                text = "X";
                x = EXPR(SCR_X + SCR_W * 0.94);
                y = EXPR(SCR_Y + SCR_H * 0.015);
                w = EXPR(SCR_W * 0.045);
                h = EXPR(ROW_H * 0.95);
                action = "closeDialog 0;";
            };

            // ================================================================
            // Mission Gen Panel — host controls group
            // ================================================================
            class MissionGenPanel : DSC_RscControlsGroup {
                idc = DSC_TABLET_IDC_MGEN_PANEL;
                x = EXPR(SCR_X + SCR_W * 0.02);
                y = EXPR(SCR_Y + SCR_H * 0.085);
                w = EXPR(SCR_W * 0.96);
                h = EXPR(SCR_H * 0.905);
                show = 0;

                class Controls {

                    // --- Title + help ---
                    class TitleLbl : DSC_RscText {
                        idc = -1;
                        font = FONT_B;
                        sizeEx = 0.026;
                        text = "MISSION GENERATOR";
                        x = 0; y = 0;
                        w = 0.5; h = 0.05;
                        colorText[] = COLOR_ACCENT;
                    };
                    class HelpLbl : DSC_RscTextDim {
                        idc = -1;
                        sizeEx = 0.020;
                        text = "Configure parameters and queue the next mission. Empty fields use random / profile defaults.";
                        x = 0; y = 0.05;
                        w = 1.0; h = 0.04;
                    };

                    // --- View toggle (top-right) ---
                    class ViewStdBtn : DSC_RscTabButton {
                        idc = DSC_TABLET_IDC_MGEN_VIEW_STD;
                        text = "STANDARD";
                        x = 0.62; y = 0.00;
                        w = 0.18; h = 0.06;
                        colorBackground[] = COLOR_ACCENT;
                        action = "[(uiNamespace getVariable 'DSC_TabletDisplay'), 'standard'] call DSC_ui_fnc_panelMissionGen_switchView;";
                    };
                    class ViewAdvBtn : DSC_RscTabButton {
                        idc = DSC_TABLET_IDC_MGEN_VIEW_ADV;
                        text = "ADVANCED";
                        x = 0.81; y = 0.00;
                        w = 0.19; h = 0.06;
                        colorBackground[] = { 0.10, 0.13, 0.16, 0.75 };
                        action = "[(uiNamespace getVariable 'DSC_TabletDisplay'), 'advanced'] call DSC_ui_fnc_panelMissionGen_switchView;";
                    };

                    // ============================================================
                    // CORE FIELDS (always visible)
                    // ============================================================

                    // --- Row 1: Type + Profile ---
                    class TypeLbl : DSC_RscText {
                        idc = -1; text = "Mission Type";
                        x = 0; y = 0.11;
                        w = 0.16; h = 0.05;
                    };
                    class TypeCombo : DSC_RscCombo {
                        idc = DSC_TABLET_IDC_MGEN_TYPE;
                        x = 0.16; y = 0.11;
                        w = 0.27; h = 0.05;
                    };
                    class ProfileLbl : DSC_RscText {
                        idc = -1; text = "Profile";
                        x = 0.48; y = 0.11;
                        w = 0.13; h = 0.05;
                    };
                    class ProfileCombo : DSC_RscCombo {
                        idc = DSC_TABLET_IDC_MGEN_PROFILE;
                        x = 0.61; y = 0.11;
                        w = 0.27; h = 0.05;
                    };

                    // --- Row 2: Density + Faction ---
                    class DensityLbl : DSC_RscText {
                        idc = -1; text = "Density";
                        x = 0; y = 0.18;
                        w = 0.16; h = 0.05;
                    };
                    class DensityCombo : DSC_RscCombo {
                        idc = DSC_TABLET_IDC_MGEN_DENSITY;
                        x = 0.16; y = 0.18;
                        w = 0.27; h = 0.05;
                    };
                    class FactionLbl : DSC_RscText {
                        idc = -1; text = "Target Faction";
                        x = 0.48; y = 0.18;
                        w = 0.13; h = 0.05;
                    };
                    class FactionCombo : DSC_RscCombo {
                        idc = DSC_TABLET_IDC_MGEN_FACTION;
                        x = 0.61; y = 0.18;
                        w = 0.27; h = 0.05;
                    };

                    // --- Row 3: Distances ---
                    class MinDistLbl : DSC_RscText {
                        idc = -1; text = "Min Distance (m)";
                        x = 0; y = 0.25;
                        w = 0.16; h = 0.05;
                    };
                    class MinDistEdit : DSC_RscEdit {
                        idc = DSC_TABLET_IDC_MGEN_MIN_DIST;
                        x = 0.16; y = 0.25;
                        w = 0.12; h = 0.05;
                        text = "500";
                    };
                    class MaxDistLbl : DSC_RscText {
                        idc = -1; text = "Max Distance (m)";
                        x = 0.48; y = 0.25;
                        w = 0.13; h = 0.05;
                    };
                    class MaxDistEdit : DSC_RscEdit {
                        idc = DSC_TABLET_IDC_MGEN_MAX_DIST;
                        x = 0.61; y = 0.25;
                        w = 0.12; h = 0.05;
                        text = "8000";
                    };

                    // --- Row 4: Anchor + QRF + Replace ---
                    class AtPlayerCheck : DSC_RscCheckbox {
                        idc = DSC_TABLET_IDC_MGEN_AT_PLAYER;
                        x = 0; y = 0.32;
                        w = 0.04; h = 0.05;
                        checked = 1;
                    };
                    class AtPlayerLbl : DSC_RscText {
                        idc = -1; text = "Anchor distance to my position";
                        x = 0.05; y = 0.32;
                        w = 0.40; h = 0.05;
                    };
                    class QrfCheck : DSC_RscCheckbox {
                        idc = DSC_TABLET_IDC_MGEN_QRF;
                        x = 0.48; y = 0.32;
                        w = 0.04; h = 0.05;
                    };
                    class QrfLbl : DSC_RscText {
                        idc = -1; text = "QRF enabled";
                        x = 0.53; y = 0.32;
                        w = 0.20; h = 0.05;
                    };
                    class ReplaceCheck : DSC_RscCheckbox {
                        idc = DSC_TABLET_IDC_MGEN_REPLACE;
                        x = 0.75; y = 0.32;
                        w = 0.04; h = 0.05;
                    };
                    class ReplaceLbl : DSC_RscText {
                        idc = -1; text = "Replace current";
                        x = 0.80; y = 0.32;
                        w = 0.20; h = 0.05;
                    };

                    // ============================================================
                    // ADVANCED OVERLAY (hidden in Standard view)
                    // ============================================================
                    class MissionGenAdv : DSC_RscControlsGroup {
                        idc = DSC_TABLET_IDC_MGEN_ADV_PANEL;
                        x = 0.0; y = 0.39;
                        w = 1.0; h = 0.50;
                        show = 0;

                        class Controls {

                            // --- Section: LOCATION ---
                            class SecLocLbl : DSC_RscText {
                                idc = -1;
                                font = FONT_B;
                                sizeEx = 0.022;
                                text = "LOCATION";
                                x = 0; y = 0;
                                w = 1.0; h = 0.04;
                                colorText[] = COLOR_ACCENT;
                            };

                            class SpecLocLbl : DSC_RscTextDim {
                                idc = -1;
                                sizeEx = 0.020;
                                text = "Use Min/Max Distance + tag filters below to constrain location selection.";
                                x = 0; y = 0.05;
                                w = 0.66; h = 0.05;
                            };
                            class MinBldgLbl : DSC_RscText {
                                idc = -1; text = "Min Buildings";
                                x = 0.66; y = 0.05;
                                w = 0.16; h = 0.05;
                            };
                            class MinBldgEdit : DSC_RscEdit {
                                idc = DSC_TABLET_IDC_MGEN_ADV_MIN_BLDG;
                                x = 0.83; y = 0.05;
                                w = 0.10; h = 0.05;
                                text = "3";
                            };

                            class ReqTagsLbl : DSC_RscText {
                                idc = -1; text = "Required Tags";
                                x = 0; y = 0.12;
                                w = 0.18; h = 0.05;
                                tooltip = "Comma-separated, e.g. 'isolated, low_density'. At least one must match.";
                            };
                            class ReqTagsEdit : DSC_RscEdit {
                                idc = DSC_TABLET_IDC_MGEN_ADV_REQ_TAGS;
                                x = 0.18; y = 0.12;
                                w = 0.32; h = 0.05;
                                text = "";
                                tooltip = "Comma-separated tags. Location must match at least one.";
                            };
                            class ExcTagsLbl : DSC_RscText {
                                idc = -1; text = "Exclude Tags";
                                x = 0.52; y = 0.12;
                                w = 0.14; h = 0.05;
                            };
                            class ExcTagsEdit : DSC_RscEdit {
                                idc = DSC_TABLET_IDC_MGEN_ADV_EXC_TAGS;
                                x = 0.66; y = 0.12;
                                w = 0.34; h = 0.05;
                                text = "";
                                tooltip = "Comma-separated tags. Location must match none.";
                            };

                            // --- Section: POPULATION ---
                            class SecPopLbl : DSC_RscText {
                                idc = -1;
                                font = FONT_B;
                                sizeEx = 0.022;
                                text = "POPULATION";
                                x = 0; y = 0.20;
                                w = 1.0; h = 0.04;
                                colorText[] = COLOR_ACCENT;
                            };

                            class GarrLbl : DSC_RscText {
                                idc = -1; text = "Garrison Anchors";
                                x = 0; y = 0.25;
                                w = 0.18; h = 0.05;
                                tooltip = "[min, max] anchor buildings garrisoned at the target cluster.";
                            };
                            class GarrMinEdit : DSC_RscEdit {
                                idc = DSC_TABLET_IDC_MGEN_ADV_GAR_MIN;
                                x = 0.18; y = 0.25;
                                w = 0.06; h = 0.05;
                                text = "";
                                tooltip = "Min";
                            };
                            class GarrMaxEdit : DSC_RscEdit {
                                idc = DSC_TABLET_IDC_MGEN_ADV_GAR_MAX;
                                x = 0.25; y = 0.25;
                                w = 0.06; h = 0.05;
                                text = "";
                                tooltip = "Max";
                            };

                            class PatrolLbl : DSC_RscText {
                                idc = -1; text = "Patrols";
                                x = 0.34; y = 0.25;
                                w = 0.10; h = 0.05;
                            };
                            class PatrolEdit : DSC_RscEdit {
                                idc = DSC_TABLET_IDC_MGEN_ADV_PATROLS;
                                x = 0.44; y = 0.25;
                                w = 0.06; h = 0.05;
                                text = "";
                            };

                            class VehLbl : DSC_RscText {
                                idc = -1; text = "Max Vehicles";
                                x = 0.53; y = 0.25;
                                w = 0.14; h = 0.05;
                            };
                            class VehEdit : DSC_RscEdit {
                                idc = DSC_TABLET_IDC_MGEN_ADV_VEHICLES;
                                x = 0.67; y = 0.25;
                                w = 0.06; h = 0.05;
                                text = "";
                            };

                            // --- Sliders row (vehicle armed / area presence / guard coverage) ---
                            class VehArmedLbl : DSC_RscText {
                                idc = -1; text = "Veh Armed %";
                                x = 0; y = 0.32;
                                w = 0.13; h = 0.05;
                            };
                            class VehArmedSlider : DSC_RscSlider {
                                idc = DSC_TABLET_IDC_MGEN_ADV_VEH_ARMED;
                                x = 0.13; y = 0.32;
                                w = 0.16; h = 0.05;
                                onSliderPosChanged = "_this call DSC_ui_fnc_panelMissionGen_sliderLabel;";
                            };
                            class VehArmedVal : DSC_RscTextDim {
                                idc = DSC_TABLET_IDC_MGEN_ADV_VEH_ARMED_LBL;
                                text = "--";
                                x = 0.29; y = 0.32;
                                w = 0.05; h = 0.05;
                            };

                            class AreaPresLbl : DSC_RscText {
                                idc = -1; text = "Area Pres %";
                                x = 0.36; y = 0.32;
                                w = 0.13; h = 0.05;
                            };
                            class AreaPresSlider : DSC_RscSlider {
                                idc = DSC_TABLET_IDC_MGEN_ADV_AREA_PRES;
                                x = 0.49; y = 0.32;
                                w = 0.16; h = 0.05;
                                onSliderPosChanged = "_this call DSC_ui_fnc_panelMissionGen_sliderLabel;";
                            };
                            class AreaPresVal : DSC_RscTextDim {
                                idc = DSC_TABLET_IDC_MGEN_ADV_AREA_PRES_LBL;
                                text = "--";
                                x = 0.65; y = 0.32;
                                w = 0.05; h = 0.05;
                            };

                            class GuardCovLbl : DSC_RscText {
                                idc = -1; text = "Guard Cov %";
                                x = 0.72; y = 0.32;
                                w = 0.13; h = 0.05;
                            };
                            class GuardCovSlider : DSC_RscSlider {
                                idc = DSC_TABLET_IDC_MGEN_ADV_GUARD_COV;
                                x = 0.85; y = 0.32;
                                w = 0.10; h = 0.05;
                                onSliderPosChanged = "_this call DSC_ui_fnc_panelMissionGen_sliderLabel;";
                            };
                            class GuardCovVal : DSC_RscTextDim {
                                idc = DSC_TABLET_IDC_MGEN_ADV_GUARD_COV_LBL;
                                text = "--";
                                x = 0.95; y = 0.32;
                                w = 0.05; h = 0.05;
                            };

                            // --- Section: MISSION FEEL ---
                            class SecFeelLbl : DSC_RscText {
                                idc = -1;
                                font = FONT_B;
                                sizeEx = 0.022;
                                text = "MISSION FEEL";
                                x = 0; y = 0.40;
                                w = 1.0; h = 0.04;
                                colorText[] = COLOR_ACCENT;
                            };

                            class SkillLbl : DSC_RscText {
                                idc = -1; text = "AI Skill";
                                x = 0; y = 0.45;
                                w = 0.10; h = 0.05;
                            };
                            class SkillCombo : DSC_RscCombo {
                                idc = DSC_TABLET_IDC_MGEN_ADV_SKILL;
                                x = 0.10; y = 0.45;
                                w = 0.27; h = 0.05;
                            };

                            class QrfDelayLbl : DSC_RscText {
                                idc = -1; text = "QRF Delay (s)";
                                x = 0.42; y = 0.45;
                                w = 0.16; h = 0.05;
                                tooltip = "[min, max] seconds before QRF responds when combat starts.";
                            };
                            class QrfMinEdit : DSC_RscEdit {
                                idc = DSC_TABLET_IDC_MGEN_ADV_QRF_MIN;
                                x = 0.58; y = 0.45;
                                w = 0.08; h = 0.05;
                                text = "";
                                tooltip = "Min";
                            };
                            class QrfMaxEdit : DSC_RscEdit {
                                idc = DSC_TABLET_IDC_MGEN_ADV_QRF_MAX;
                                x = 0.67; y = 0.45;
                                w = 0.08; h = 0.05;
                                text = "";
                                tooltip = "Max";
                            };
                        };
                    };

                    // ============================================================
                    // STATUS + ACTIONS (always visible)
                    // ============================================================
                    class StatusFrame : DSC_RscFrame {
                        idc = -1;
                        text = " STATE ";
                        x = 0; y = 0.90;
                        w = 1.0; h = 0.07;
                    };
                    class StatusText : DSC_RscTextDim {
                        idc = DSC_TABLET_IDC_MGEN_STATUS;
                        sizeEx = 0.020;
                        text = "Loading...";
                        x = 0.02; y = 0.91;
                        w = 0.96; h = 0.06;
                    };

                    class GenerateBtn : DSC_RscButton {
                        idc = DSC_TABLET_IDC_MGEN_GENERATE;
                        text = "QUEUE NEXT MISSION";
                        x = 0; y = 0.985;
                        w = 0.30; h = 0.055;
                        colorBackground[] = { 0.20, 0.55, 0.30, 0.85 };
                        colorBackgroundActive[] = { 0.30, 0.70, 0.40, 0.95 };
                        action = "[(uiNamespace getVariable 'DSC_TabletDisplay')] call DSC_ui_fnc_panelMissionGen_submit;";
                    };
                    class AbortBtn : DSC_RscDangerButton {
                        idc = DSC_TABLET_IDC_MGEN_ABORT;
                        text = "ABORT CURRENT";
                        x = 0.32; y = 0.985;
                        w = 0.22; h = 0.055;
                        action = "[(uiNamespace getVariable 'DSC_TabletDisplay')] call DSC_ui_fnc_panelMissionGen_abort;";
                    };
                    class RefreshBtn : DSC_RscButton {
                        idc = DSC_TABLET_IDC_MGEN_REFRESH;
                        text = "REFRESH";
                        x = 0.56; y = 0.985;
                        w = 0.20; h = 0.055;
                        action = "[(uiNamespace getVariable 'DSC_TabletDisplay')] call DSC_ui_fnc_panelMissionGen_refreshState;";
                    };
                    class CloseBtn2 : DSC_RscButton {
                        idc = -1;
                        text = "CLOSE";
                        x = 0.80; y = 0.985;
                        w = 0.20; h = 0.055;
                        action = "closeDialog 0;";
                    };
                };
            };

            // ================================================================
            // Blue Force Tracker — chrome (title / status / recenter) sit as
            // top-level controls outside the map's rect, and the map lives in
            // its own dedicated controls group sized to the empty middle.
            // RscMapControl renders reliably as a controls-group child filling
            // 0..1, and top-level chrome means nothing overlaps the map area.
            // switchPanel toggles ctrlShow on the whole set together.
            // ================================================================
            class BftTitleLbl : DSC_RscText {
                idc = DSC_TABLET_IDC_BFT_TITLE;
                style = ST_LEFT;
                font = FONT_B;
                sizeEx = 0.026;
                text = "BLUE FORCE TRACKER";
                x = EXPR(SCR_X + SCR_W * 0.02);
                y = EXPR(SCR_Y + SCR_H * 0.090);
                w = EXPR(SCR_W * 0.40);
                h = EXPR(SCR_H * 0.045);
                colorText[] = COLOR_ACCENT;
                show = 0;
            };

            class BftStatusText : DSC_RscTextDim {
                idc = DSC_TABLET_IDC_BFT_STATUS;
                sizeEx = 0.020;
                text = "Loading...";
                x = EXPR(SCR_X + SCR_W * 0.40);
                y = EXPR(SCR_Y + SCR_H * 0.095);
                w = EXPR(SCR_W * 0.32);
                h = EXPR(SCR_H * 0.040);
                show = 0;
            };

            // Clutter filter — toggles between showing every track (ALL,
            // default) and just commanded groups + squad + objective (MINE).
            // Useful when the ambient world fills the map with garrisons /
            // patrols and you want to manage your high command at a glance.
            class BftFilterBtn : DSC_RscButton {
                idc = DSC_TABLET_IDC_BFT_FILTER;
                text = "ALL";
                x = EXPR(SCR_X + SCR_W * 0.73);
                y = EXPR(SCR_Y + SCR_H * 0.090);
                w = EXPR(SCR_W * 0.12);
                h = EXPR(SCR_H * 0.050);
                action = "[(uiNamespace getVariable 'DSC_TabletDisplay')] call DSC_ui_fnc_panelBft_toggleFilter;";
                show = 0;
            };

            class BftRecenterBtn : DSC_RscButton {
                idc = DSC_TABLET_IDC_BFT_RECENTER;
                text = "RECENTER";
                x = EXPR(SCR_X + SCR_W * 0.86);
                y = EXPR(SCR_Y + SCR_H * 0.090);
                w = EXPR(SCR_W * 0.12);
                h = EXPR(SCR_H * 0.050);
                action = "[(uiNamespace getVariable 'DSC_TabletDisplay')] call DSC_ui_fnc_panelBft_init;";
                show = 0;
            };

            // --- Map host (controls group dedicated to the map only) ---
            // The group rect IS the map rect. Map child fills 0..1 of the group.
            class BftPanel : DSC_RscControlsGroup {
                idc = DSC_TABLET_IDC_BFT_PANEL;
                x = EXPR(SCR_X + SCR_W * 0.02);
                y = EXPR(SCR_Y + SCR_H * 0.150);
                w = EXPR(SCR_W * 0.66);
                h = EXPR(SCR_H * 0.795);
                show = 0;

                class Controls {
                    class BftMap : DSC_RscMapControl {
                        idc = DSC_TABLET_IDC_BFT_MAP;
                        x = 0; y = 0; w = 1.0; h = 1.0;
                    };
                };
            };

            // --- Compact legend strip below the map (matches map width) ---
            class BftLegendLbl : DSC_RscTextDim {
                idc = DSC_TABLET_IDC_BFT_LEGEND;
                sizeEx = 0.018;
                text = "BLUE: NATO   GREEN: Partner   CYAN: ISR Drone   WHITE: Squad   YELLOW: Objective";
                x = EXPR(SCR_X + SCR_W * 0.02);
                y = EXPR(SCR_Y + SCR_H * 0.950);
                w = EXPR(SCR_W * 0.66);
                h = EXPR(SCR_H * 0.030);
                show = 0;
            };

            // --- Track info card (BFT-2) ---
            // 17 top-level sibling controls (BG + title + clear + 7 key + 7 val).
            // Hosted directly under DSC_Tablet so coordinates are absolute
            // safezone units and rendering is predictable — previous attempt
            // using a controls-group host was silently clipping rows past
            // the 4th. switchPanel.sqf toggles ctrlShow on the whole set.

            // --- Track info card (BFT-2) ---
            // Narrow right-side sidebar, flush to the dialog's right edge.
            // The map's rendered terrain bleeds ~0.10 SCR_W past its allocated
            // rect (RscMapControl renders on a higher layer than sibling
            // RscText controls regardless of declaration order); pulling the
            // sidebar well past 0.78 SCR_W keeps it clear of that bleed.
            // Each row is a right-aligned key + left-aligned value pair so
            // the column reads as a tight right-justified table.
            //
            // 17 top-level sibling controls (BG + title + clear + 7 key + 7 val).
            // switchPanel.sqf toggles ctrlShow on the whole set when entering
            // / leaving the BFT tab. populateInfo / clearSelection only
            // overwrite the value labels — they don't show/hide controls.

            #define BFT_IC_X      EXPR(SCR_X + SCR_W * 0.83)
            #define BFT_IC_W      EXPR(SCR_W * 0.15)
            #define BFT_IC_KEY_X  EXPR(SCR_X + SCR_W * 0.84)
            #define BFT_IC_KEY_W  EXPR(SCR_W * 0.05)
            #define BFT_IC_VAL_X  EXPR(SCR_X + SCR_W * 0.89)
            #define BFT_IC_VAL_W  EXPR(SCR_W * 0.08)
            #define BFT_IC_ROW_H  EXPR(SCR_H * 0.034)

            class BftInfoBg : DSC_RscBackground {
                idc = DSC_TABLET_IDC_BFT_INFO_BG;
                x = BFT_IC_X;
                y = EXPR(SCR_Y + SCR_H * 0.150);
                w = BFT_IC_W;
                h = EXPR(SCR_H * 0.795);
                colorBackground[] = { 0.05, 0.07, 0.09, 0.92 };
                show = 0;
            };

            class BftInfoTitle : DSC_RscText {
                idc = DSC_TABLET_IDC_BFT_INFO_TITLE;
                style = ST_RIGHT;
                font = FONT_B;
                sizeEx = 0.022;
                text = "TRACK INFO";
                x = EXPR(SCR_X + SCR_W * 0.84);
                y = EXPR(SCR_Y + SCR_H * 0.165);
                w = EXPR(SCR_W * 0.10);
                h = EXPR(SCR_H * 0.040);
                colorText[] = COLOR_ACCENT;
                show = 0;
            };

            class BftInfoClear : DSC_RscDangerButton {
                idc = DSC_TABLET_IDC_BFT_INFO_CLEAR;
                text = "X";
                sizeEx = 0.020;
                x = EXPR(SCR_X + SCR_W * 0.95);
                y = EXPR(SCR_Y + SCR_H * 0.163);
                w = EXPR(SCR_W * 0.025);
                h = EXPR(SCR_H * 0.045);
                action = "[(uiNamespace getVariable 'DSC_TabletDisplay')] call DSC_ui_fnc_panelBft_clearSelection;";
                show = 0;
            };

            // -------- Row 1: Category --------
            class BftInfoKeyCategory : DSC_RscTextDim {
                idc = DSC_TABLET_IDC_BFT_INFO_KEY_CATEGORY;
                style = ST_RIGHT; sizeEx = 0.022; text = "Category";
                x = BFT_IC_KEY_X;
                y = EXPR(SCR_Y + SCR_H * 0.230);
                w = BFT_IC_KEY_W;
                h = BFT_IC_ROW_H;
                show = 0;
            };
            class BftInfoValCategory : DSC_RscText {
                idc = DSC_TABLET_IDC_BFT_INFO_VAL_CATEGORY;
                style = ST_LEFT; sizeEx = 0.022; text = "—";
                x = BFT_IC_VAL_X;
                y = EXPR(SCR_Y + SCR_H * 0.230);
                w = BFT_IC_VAL_W;
                h = BFT_IC_ROW_H;
                show = 0;
            };

            // -------- Row 2: Side --------
            class BftInfoKeySide : DSC_RscTextDim {
                idc = DSC_TABLET_IDC_BFT_INFO_KEY_SIDE;
                style = ST_RIGHT; sizeEx = 0.022; text = "Side";
                x = BFT_IC_KEY_X;
                y = EXPR(SCR_Y + SCR_H * 0.275);
                w = BFT_IC_KEY_W;
                h = BFT_IC_ROW_H;
                show = 0;
            };
            class BftInfoValSide : DSC_RscText {
                idc = DSC_TABLET_IDC_BFT_INFO_VAL_SIDE;
                style = ST_LEFT; sizeEx = 0.022; text = "—";
                x = BFT_IC_VAL_X;
                y = EXPR(SCR_Y + SCR_H * 0.275);
                w = BFT_IC_VAL_W;
                h = BFT_IC_ROW_H;
                show = 0;
            };

            // -------- Row 3: Faction --------
            class BftInfoKeyFaction : DSC_RscTextDim {
                idc = DSC_TABLET_IDC_BFT_INFO_KEY_FACTION;
                style = ST_RIGHT; sizeEx = 0.022; text = "Faction";
                x = BFT_IC_KEY_X;
                y = EXPR(SCR_Y + SCR_H * 0.320);
                w = BFT_IC_KEY_W;
                h = BFT_IC_ROW_H;
                show = 0;
            };
            class BftInfoValFaction : DSC_RscText {
                idc = DSC_TABLET_IDC_BFT_INFO_VAL_FACTION;
                style = ST_LEFT; sizeEx = 0.022; text = "—";
                x = BFT_IC_VAL_X;
                y = EXPR(SCR_Y + SCR_H * 0.320);
                w = BFT_IC_VAL_W;
                h = BFT_IC_ROW_H;
                show = 0;
            };

            // -------- Row 4: Strength --------
            class BftInfoKeyStrength : DSC_RscTextDim {
                idc = DSC_TABLET_IDC_BFT_INFO_KEY_STRENGTH;
                style = ST_RIGHT; sizeEx = 0.022; text = "Strength";
                x = BFT_IC_KEY_X;
                y = EXPR(SCR_Y + SCR_H * 0.365);
                w = BFT_IC_KEY_W;
                h = BFT_IC_ROW_H;
                show = 0;
            };
            class BftInfoValStrength : DSC_RscText {
                idc = DSC_TABLET_IDC_BFT_INFO_VAL_STRENGTH;
                style = ST_LEFT; sizeEx = 0.022; text = "—";
                x = BFT_IC_VAL_X;
                y = EXPR(SCR_Y + SCR_H * 0.365);
                w = BFT_IC_VAL_W;
                h = BFT_IC_ROW_H;
                show = 0;
            };

            // -------- Row 5: Vehicle --------
            class BftInfoKeyVehicle : DSC_RscTextDim {
                idc = DSC_TABLET_IDC_BFT_INFO_KEY_VEHICLE;
                style = ST_RIGHT; sizeEx = 0.022; text = "Vehicle";
                x = BFT_IC_KEY_X;
                y = EXPR(SCR_Y + SCR_H * 0.410);
                w = BFT_IC_KEY_W;
                h = BFT_IC_ROW_H;
                show = 0;
            };
            class BftInfoValVehicle : DSC_RscText {
                idc = DSC_TABLET_IDC_BFT_INFO_VAL_VEHICLE;
                style = ST_LEFT; sizeEx = 0.022; text = "—";
                x = BFT_IC_VAL_X;
                y = EXPR(SCR_Y + SCR_H * 0.410);
                w = BFT_IC_VAL_W;
                h = BFT_IC_ROW_H;
                show = 0;
            };

            // -------- Row 6: Distance (small visual separator before it) --------
            class BftInfoKeyDist : DSC_RscTextDim {
                idc = DSC_TABLET_IDC_BFT_INFO_KEY_DIST;
                style = ST_RIGHT; sizeEx = 0.022; text = "Distance";
                x = BFT_IC_KEY_X;
                y = EXPR(SCR_Y + SCR_H * 0.475);
                w = BFT_IC_KEY_W;
                h = BFT_IC_ROW_H;
                show = 0;
            };
            class BftInfoValDist : DSC_RscText {
                idc = DSC_TABLET_IDC_BFT_INFO_VAL_DIST;
                style = ST_LEFT; sizeEx = 0.022; text = "—";
                x = BFT_IC_VAL_X;
                y = EXPR(SCR_Y + SCR_H * 0.475);
                w = BFT_IC_VAL_W;
                h = BFT_IC_ROW_H;
                show = 0;
            };

            // -------- Row 7: To Objective --------
            class BftInfoKeyDistObj : DSC_RscTextDim {
                idc = DSC_TABLET_IDC_BFT_INFO_KEY_DIST_OBJ;
                style = ST_RIGHT; sizeEx = 0.022; text = "To Obj";
                x = BFT_IC_KEY_X;
                y = EXPR(SCR_Y + SCR_H * 0.520);
                w = BFT_IC_KEY_W;
                h = BFT_IC_ROW_H;
                show = 0;
            };
            class BftInfoValDistObj : DSC_RscText {
                idc = DSC_TABLET_IDC_BFT_INFO_VAL_DIST_OBJ;
                style = ST_LEFT; sizeEx = 0.022; text = "—";
                x = BFT_IC_VAL_X;
                y = EXPR(SCR_Y + SCR_H * 0.520);
                w = BFT_IC_VAL_W;
                h = BFT_IC_ROW_H;
                show = 0;
            };

            // ============================================================
            // BFT-3 command buttons — Take Command / Move / QRF / Release.
            // Stacked vertically below the info rows; full sidebar width.
            // Enabled only when the selected track carries `commandable=true`
            // (handled at populate / clearSelection time, not in config).
            // ============================================================
            #define BFT_CMD_X      EXPR(SCR_X + SCR_W * 0.84)
            #define BFT_CMD_W      EXPR(SCR_W * 0.13)
            #define BFT_CMD_H      EXPR(SCR_H * 0.042)

            class BftCmdHeader : DSC_RscTextDim {
                idc = DSC_TABLET_IDC_BFT_CMD_HEADER;
                style = ST_RIGHT;
                font = FONT_B;
                sizeEx = 0.020;
                text = "HIGH COMMAND";
                x = BFT_CMD_X;
                y = EXPR(SCR_Y + SCR_H * 0.585);
                w = BFT_CMD_W;
                h = EXPR(SCR_H * 0.030);
                colorText[] = COLOR_ACCENT;
                show = 0;
            };

            class BftCmdTake : DSC_RscButton {
                idc = DSC_TABLET_IDC_BFT_CMD_TAKE;
                text = "TAKE CMD";
                sizeEx = 0.022;
                x = BFT_CMD_X;
                y = EXPR(SCR_Y + SCR_H * 0.625);
                w = BFT_CMD_W;
                h = BFT_CMD_H;
                colorBackground[] = { 0.18, 0.45, 0.30, 0.85 };
                colorBackgroundActive[] = { 0.25, 0.60, 0.40, 0.95 };
                action = "[(uiNamespace getVariable 'DSC_TabletDisplay'), 'take'] call DSC_ui_fnc_panelBft_command;";
                show = 0;
            };

            class BftCmdMoveHere : DSC_RscButton {
                idc = DSC_TABLET_IDC_BFT_CMD_MOVE_HERE;
                text = "MOVE HERE";
                sizeEx = 0.022;
                x = BFT_CMD_X;
                y = EXPR(SCR_Y + SCR_H * 0.675);
                w = BFT_CMD_W;
                h = BFT_CMD_H;
                action = "[(uiNamespace getVariable 'DSC_TabletDisplay'), 'moveHere'] call DSC_ui_fnc_panelBft_command;";
                show = 0;
            };

            class BftCmdMoveObj : DSC_RscButton {
                idc = DSC_TABLET_IDC_BFT_CMD_MOVE_OBJ;
                text = "MOVE TO OBJ";
                sizeEx = 0.022;
                x = BFT_CMD_X;
                y = EXPR(SCR_Y + SCR_H * 0.725);
                w = BFT_CMD_W;
                h = BFT_CMD_H;
                action = "[(uiNamespace getVariable 'DSC_TabletDisplay'), 'moveObj'] call DSC_ui_fnc_panelBft_command;";
                show = 0;
            };

            class BftCmdQrf : DSC_RscButton {
                idc = DSC_TABLET_IDC_BFT_CMD_QRF;
                text = "SET AS QRF";
                sizeEx = 0.022;
                x = BFT_CMD_X;
                y = EXPR(SCR_Y + SCR_H * 0.775);
                w = BFT_CMD_W;
                h = BFT_CMD_H;
                action = "[(uiNamespace getVariable 'DSC_TabletDisplay'), 'qrf'] call DSC_ui_fnc_panelBft_command;";
                show = 0;
            };

            class BftCmdRelease : DSC_RscDangerButton {
                idc = DSC_TABLET_IDC_BFT_CMD_RELEASE;
                text = "RELEASE";
                sizeEx = 0.022;
                x = BFT_CMD_X;
                y = EXPR(SCR_Y + SCR_H * 0.825);
                w = BFT_CMD_W;
                h = BFT_CMD_H;
                action = "[(uiNamespace getVariable 'DSC_TabletDisplay'), 'release'] call DSC_ui_fnc_panelBft_command;";
                show = 0;
            };

            // ----------------------------------------------------------------
            // Footer (bottom edge of screen rect)
            // ----------------------------------------------------------------
            class FooterText : DSC_RscTextDim {
                idc = DSC_TABLET_IDC_FOOTER_STATE;
                sizeEx = 0.020;
                text = "";
                x = EXPR(SCR_X + SCR_W * 0.02);
                y = EXPR(SCR_Y + SCR_H * 0.965);
                w = EXPR(SCR_W * 0.96);
                h = EXPR(ROW_H * 0.7);
            };
        };
};
