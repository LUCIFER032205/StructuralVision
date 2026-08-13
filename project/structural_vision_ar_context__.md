# Structural Vision AR --- Project Context

> Upload this at the start of any new chat to skip re-explaining. Last
> updated: July 9, 2026

------------------------------------------------------------------------

## About Me

-   Engineering student, 6th sem (7th sem officially starts July 20,
    ends Nov 9, 2026)
-   Laptop: Dell Inspiron, i7-1360P 13th gen, 16GB DDR5, 1TB SSD, Intel
    Iris Xe (CPU-only, no discrete GPU)
-   Python level: \~30-40%, learning actively as part of project prep
-   Tone preference: direct, no sugarcoating, caveman mode friendly
-   Personal dream (side-context, not project scope): build a custom AI
    assistant, JARVIS-style
-   Coordinator sets unrealistic deadlines then moves them when they
    prove impossible --- plan around my own realistic dates, not his
    stated ones

------------------------------------------------------------------------

## Project Title

**Structural Vision AR: Intelligent Structural Health Assessment &
Virtual Building Preview Platform**

-   College: SVIT
-   Team: Kishore, Kiran, Sanjana, Sujan
-   Guide: Prof. Deepika G \| Co-guide: Dr. Manjunath T N
-   Guides do not know the platform decision below has been finalized
    --- not looping them in, just proceeding

------------------------------------------------------------------------

## Platform Decision --- LOCKED (Web dropped entirely)

**Mobile app only. Flutter + ARCore.** No longer evaluating
web/React/MindAR --- that option is dropped, not "pending," not
documented as an alternative going forward.

  Layer                Tech
  -------------------- ----------------------------------------
  Frontend             Flutter
  AR                   ARCore + Flutter AR plugin
  3D Models            Blender → GLB/GLTF
  Backend              Python + FastAPI
  ML Model             YOLOv8-seg (single model, ONNX export)
  Image Processing     OpenCV
  Database + Storage   Supabase (free tier)
  Model Training       Local (CPU, Dell Inspiron)
  PDF Generation       ReportLab (Python)

**Why locked to mobile:** AR quality (ARCore) is the project's core
defensibility argument vs. WebAR (MindAR), and there's no timeline slack
left to keep both options open. If jury asks why mobile over web → AR
quality argument.

**Requires:** a physical ARCore-compatible Android device (7.0+) for
daily testing --- confirm this is in hand, it's a blocker if not.

------------------------------------------------------------------------

## Core Idea (Unchanged)

### ML Module

-   **Input:** Building/wall image (camera capture or upload)
-   **Detection + Segmentation:** Single YOLOv8-seg model --- crack
    detection + pixel-level segmentation heatmap overlay in one pass
    (not two separate models --- CPU training budget doesn't allow it)
-   **Risk Classification:** Low / Medium / High
-   **Component ID:** Wall / Beam / Column / Foundation (different risk
    weights per component)
-   **Output --- Maintenance Window Prediction:**
    -   Immediate (0--6 months)
    -   Short-term (6--24 months)
    -   Long-term (2--5 years)
    -   *(Original idea was "years to survive" --- jury-approved,
        reframed as Maintenance Window to stay defensible. Do NOT
        suggest removing it.)*

### App Features

-   Camera capture or image upload
-   Send image to backend, display risk score + heatmap
-   PDF inspection report generation (auto)
-   Scan history per building (track crack progression over time)
-   AR building placement on empty site --- **demo scope: one preset 3D
    model, static placement, no animation**
-   AR annotation pins on detected crack zones

### Dropped / Modified Features

-   Exact "years to survive" prediction → replaced with Maintenance
    Window
-   AR crack depth visualization → replaced with AR annotation pins
    (depth needs LiDAR, not feasible)
-   Web/React/MindAR platform option → dropped entirely, mobile-only now
-   Two-model (separate detection + segmentation) architecture → dropped
    in favor of single YOLOv8-seg model

------------------------------------------------------------------------

## ML Training --- Actual Status

-   **First training run:** Roboflow-only dataset → **71.02% accuracy**
    --- not good enough
-   **Current work:** merging two datasets --- **Crack500 + a Roboflow
    dataset** --- to retrain
    -   SDNET2018 fully dropped from the plan (was in early planning
        docs, never actually used for a training run)
    -   Dataset merge is in progress right now (as of July 9); training
        on merged set has not started yet
-   **Stated target (for docs/presentation):** 90%+ / kept ambitious at
    \~96% --- do not lowball this publicly
-   **Realistic near-term expectation:** first merged-dataset run likely
    lands \~80--85% given CPU-only training and compressed timeline
-   **Plan for guide conversation:** report actual current accuracy
    honestly when available (e.g. "currently at 80-85%, here's the
    improvement plan"), request more time if needed --- do not
    understate the target, do state the real current number
-   Training hardware: CPU-only (Intel Iris Xe), no GPU --- expect
    \~5--6 hrs per full training run
-   Export target: ONNX, for FastAPI backend inference

------------------------------------------------------------------------

## Timeline --- Real Target: Demo-Ready by Aug 25, 2026

Coordinator's stated deadlines are not reliable (see "About Me") ---
this is the self-set realistic target, not his.

  ------------------------------------------------------------------------------
  Week                    Dates                   Task
  ----------------------- ----------------------- ------------------------------
  1                       Jul 9--13               Finish dataset merge + label
                                                  cleanup, kick off first
                                                  training run

  2                       Jul 14--20              Evaluate training run,
                                                  retrain/tune if needed; start
                                                  Flutter project + Android
                                                  Studio setup; FastAPI skeleton
                                                  in parallel

  3                       Jul 21--27              Backend: load ONNX model,
                                                  build
                                                  upload/detect/risk-score/PDF
                                                  endpoints

  4                       Jul 28--Aug 3           Flutter frontend skeleton,
                                                  wire to backend, get
                                                  end-to-end flow (image →
                                                  result) working
                                                  ugly-but-functional

  5                       Aug 4--10               Frontend: scan history, PDF
                                                  display, risk UI polish

  6                       Aug 11--17              AR: minimal scope --- ARCore +
                                                  Flutter AR plugin, one preset
                                                  GLB model, static placement,
                                                  crack pins only

  7                       Aug 18--24              Bug fixes, end-to-end test
                                                  runs, build demo script/flow

  ---                     Aug 25                  Demo
  ------------------------------------------------------------------------------

**Note:** Backend and frontend need to run in parallel from week 3
onward, not strictly sequential --- the original "AR always last, fully
sequential" build order assumed a full semester's slack, which no longer
exists. Blender→GLB export for the demo building model should happen
before week 6, not during it --- can be done in parallel anytime.

**Official 7th semester:** starts July 20, 2026, ends Nov 9, 2026.
Whatever isn't demo-ready by Aug 25 continues through the rest of the
semester as planned polish/improvement work.

------------------------------------------------------------------------

## Functional Requirements (Mobile)

-   User upload/capture building image
-   System detect cracks + highlight with segmentation overlay
-   System classify risk → Low / Medium / High
-   System identify affected structural component
    (wall/beam/column/foundation)
-   System output maintenance window prediction
-   Generate downloadable PDF inspection report
-   Store scan history per building
-   AR mode: place 3D building models on empty site
-   AR mode: show annotation pins on crack locations

------------------------------------------------------------------------

## System Design Flow

User captures/uploads image → Flutter app → FastAPI backend → OpenCV
(image preprocessing) → YOLOv8-seg (crack detection + segmentation,
ONNX) → Risk score + heatmap returned → Stored in Supabase → PDF report
generated (ReportLab) → AR mode: ARCore → render 3D model / annotation
pins

------------------------------------------------------------------------

## Research Gap (USP for presentation)

Most implementations do crack detection OR AR visualization --- none
combine crack detection + risk scoring + maintenance prediction + AR
building preview on empty site. This combo is the project's unique
contribution.

**Commercial references:** Doxel, Reconstruct, Cape Analytics,
Structural Monitoring Solutions (SMS) **Research references:**
CNN/ResNet/YOLO-based crack detection papers, SDNET2018 dataset paper
(historical reference only, dataset itself not used), "Autonomous
Structural Visual Inspection Using Region-Based Deep Learning" **AR in
construction precedents:** Trimble XR10, Autodesk BIM 360 + HoloLens,
Bentley Systems **AR tech evaluated:** ARCore (chosen), MindAR (dropped
with web option), 8thwall (evaluated, rejected as paid/expensive ---
worth mentioning in presentation as "evaluated but chose open-source
flexibility")

------------------------------------------------------------------------

## Presentation Notes

-   Jury has seen 2 rounds --- they know the project concept
-   Survival prediction was jury-approved --- keep it, reframed as
    Maintenance Window
-   Next presentation = literature survey round 2
-   Platform is locked to mobile --- if jury asks why mobile over web →
    AR quality argument (ARCore vs WebAR)
-   Guides have not been told the platform is finalized yet --- this is
    proceeding without that conversation for now

------------------------------------------------------------------------

## Resources

-   Python: CS50P (Harvard, free)
-   ML: fast.ai Part 1, Ultralytics YOLOv8 official docs
-   FastAPI: FastAPI official docs
-   Flutter: flutter.dev codelabs
-   AR: ARCore official docs

------------------------------------------------------------------------

## Quick Reference (Specs)

-   Target accuracy (stated): 90%+ (stretch 96%) \| Realistic near-term:
    \~80-85%
-   Inference time: \<3 sec per image
-   PDF gen time: \<5 sec
-   App size: \<100MB
-   Offline AR, Android 8.0+, secure storage
-   Database: Supabase free tier
-   Training time (CPU): \~5-6 hours per full run
