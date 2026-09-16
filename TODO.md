# Structural Vision AR — TODO (updated 2026-09-16)

Plan to finish: `project/docs/finish_plan.md` (target 2026-09-30).

## Done 2026-09-15
- All app + backend work committed; `.gitignore` fixed (apk rule was quoted and never matched; `kaggle_tomo/` now ignored).
- App: confidence floor 0.5 → 0.4 in the result-screen outline shading (matches backend conf 0.4).
- Backend: duplicate crack masks merged (NMS iou 0.45). v4 was drawing 2 masks on one crack, doubling area and risk.
- Risk thresholds re-fit 0.10/0.25 → 0.03/0.07 on demo_kit (see `project/demo_kit/README.md`).
- Rescan of all 63 stored app scans with v4: all 8 v2 false alarms (curtains, bag, laptop) are now clean;
  6 remaining false alarms are straight architectural edges (table edge, beam edges, projector, TV).

## Tonight's test findings (2026-09-15, backend log + scans 91d83184 → 4e3e8cb0)
- Non-cracks: 11/12 correct. 1 false alarm = overhead cable across a wall (44013866, conf 0.59) —
  thin diagonal wire, the fill>0.6 edge filter would NOT catch it.
- 2nd false-alarm type: tiny round blobs on a perforated dark cabinet panel (cba3bd4f, 3 dets 0.42-0.73)
  → needs a minimum-elongation check (cracks are long/thin); edge filter won't catch it either.
- Final tally 32 scans: non-cracks 17 correct / 2 false alarms; all crack photos found.
  Passed: burst (8 shots → batch), gallery upload, PDF report, History, AR overlay. Crashed: wall mode.
- Cracks: every crack photo found; real building crack found too (5c83b0fe). Misses thin hairline
  branches next to a thick crack (scans 18-21, upper crack never outlined).
- Preliminary risk depends on framing: same high_1 crack = LOW 1.9% / MEDIUM 2.8% / MEDIUM 3.0% by distance.
- AR overlay + two-tap measure work (3 measurements, no errors).
- **BUG: measurement gives absurd lengths → absurd widths/grades** (15: 18.8 mm, 22: hairline → 5.5 mm → HIGH).
  Main cause (user report): in the default floor-plane mode a crack on a wall/screen has no plane, so the
  two taps hit the desk/floor behind it. Plus the overlay is removed while measuring (ar_screen.dart
  `_setOverlayHidden`), so the user has no guide. Measuring wall cracks needs wall-plane mode (crash test).
  Fixes: hint "switch to wall mode to measure"; reject implausible lengths (e.g. > 2x crack extent);
  keep a visible guide. Secondary: mask outline is several px thick, so hairline width is still
  over-estimated even with correct taps (`width_from_measurement`, inference.py) — report "< resolution".

- **Wall-plane mode (PlaneDetectionConfig.vertical) CRASHES the Vivo Y200** — confirmed tonight, same as
  horizontalAndVertical. → AR measuring can't hit wall/column/beam cracks on this phone.
  Plan: remove the wall toggle; add "Enter length with a ruler (cm)" on the result screen → same
  /scan/{id}/measurement endpoint; keep AR Measure for floor/slab cracks only. (Check first: update
  "Google Play Services for AR" and retry once; grab `adb logcat` over USB if it still crashes.)

## Done 2026-09-16 (all code landed; nothing left but the test session)

**Measurement chain — root cause was the mask, not the taps.** Both absurd readings
reproduce exactly from plausible tap distances (50 cm, 14.7 cm) using the stored mask
width. YOLOv8-seg draws mask prototypes at imgsz/4, so the thinnest mask it can emit is
~10 image px on a 2560 px photo; real crack masks measured a median of 56 px. On a 1.5 m
hairline that is ~280x the true width.
- `inference.profile_width_px()` measures the crack off the photo (median full-width-
  half-minimum of the dark trough, sampled perpendicular to the crack). Validated against
  zoomed crops: 4.0 px on a thin crack where the mask says 23.8 px.
- It under-reads on broad spalled patches, so both figures are kept: the trough grades,
  the mask is the upper bound, and past 2x disagreement the width prints as a RANGE with
  a "verify with a crack gauge" note instead of a false-precision number.
- `implausible_measurement()` rejects a two-tap distance implying a frame outside
  5 cm - 15 m, with the reason shown in the app (typed `MeasurementRejected`).

**AR surfaces.** Desks and tables always worked — ARCore reports desk/table/floor/slab/
ceiling all as horizontal planes. Only the copy said "floor", which is why the demo looked
floor-only. Reworded. Wall planes are back as an opt-in with a crash guard: a flag is set
before switching to horizontalAndVertical and cleared once the session survives 8 s or
exits cleanly; finding it still set on a later launch means the app died there and wall
mode is hidden permanently on that device.

**Capture resolution.** `ResolutionPreset.high` is 1280x720, not 1080p as the old comment
claimed — every 09-15 scan came back 720x1280, so the model was UPSCALING to imgsz 1024.
Now `veryHigh` (1920x1080). Inference cost unchanged.

**False alarms — elongation filter shipped, edge filter dropped.** On 19 labelled
non-crack photos from the 09-15 session:

| filter | false alarms | cracks found |
|---|---|---|
| none (before) | 2/19 | 13/13 |
| **min elongation >= 4 (shipped)** | **1/19** | **13/13** |
| fill <= 0.6 (was pending) | 1/19 | 12/13 — loses a crack |
| tiled inference | 8/19 | 13/13 |

Blobs measured 1.1-1.9, thinnest real crack 25.2; cutoff flat from 2 to 15. Costs nothing
on eval200 (199/200 kept) or SDNET (0 FA), and demo_kit calibration is unchanged.

**Tiling is ruled out.** Its only win was `demo_kit/missed.jpeg` (0 detections full-frame
-> the band crack at 0.77 tiled). On the labelled negatives it quadruples false alarms
(2 -> 8 of 19) while gaining nothing, because full-frame already found all 13 cracks.
Six extra false alarms to buy one crack is a bad trade.

**imgsz is ruled out.** 1024/1280/1600 all give 199/200 on eval200; 1600 adds a false
alarm and is 2.6x slower.

**Whole-inspection report.** `GET /report?ids=...` — summary table (component, risk,
cracks, area, worst risk overall) then a page per photo. Covers video burst, multi-capture
and gallery upload. Every id gets a row, including failed/pending ones.

**Camera.** Video burst kept; multi-capture added beside it (manual shutter, component
re-pickable between shots). Pinch-zoom + zoom slider. Component sheet is a full-width
list. Batch list no longer cut off by the nav bar.

## Saturday — one test session, everything in one APK

Setup: `1. Check setup` -> `2. Start backend` -> (other network) `3. ngrok tunnel`.
APK is already built and copied to `backend/static/`.

### A. The four UI changes
- [ ] Component sheet: full-width rows, no wrapped labels, tick on the current pick
- [ ] Pinch-zoom + zoom slider on the camera
- [ ] Video burst still works exactly as before (8 shots, REC badge)
- [ ] Multi: shutter queues, component chip changeable between shots, thumbnails show
      each photo's component, tap to drop one, tick to analyze
- [ ] Batch list: last card fully visible above the nav bar

### B. Report covers everything
- [ ] Video burst -> "Share full report" -> summary table lists every photo + component
- [ ] Multi with 3 different components -> all three named correctly in the PDF
- [ ] Kill the backend mid-burst: failed segments still get rows marked "failed",
      and the button stays locked until all segments settle

### C. Measurement (the numbers that were wrong)
- [ ] Floor/slab crack -> Measure in AR -> width is sane, no 18 mm hairlines
- [ ] Wall crack -> "Enter length" with a tape -> same grade path
- [ ] Deliberately tap the floor behind a wall crack -> rejected with a reason, no grade
- [ ] A hairline -> width shows as a RANGE + "verify with a crack gauge"
- [ ] Measuring crosshair visible while measuring

### D. AR surfaces
- [ ] Place on a DESK (this is the demo case) — should just work
- [ ] Place on the floor
- [ ] Wall-plane toggle: if it crashes, reopen the app — the toggle should be GONE
      and never come back. That is the guard working, not a bug.
- [ ] Site preview: building places on a desk

### E. Detection
- [ ] Rescan the perforated cabinet panel -> no more blob false alarms
- [ ] Rescan the overhead cable -> STILL a false alarm, expected, not a regression
- [ ] A/B the resolution change: same crack, old APK vs new, see if 1080p finds more
- [ ] `demo_kit/missed.jpeg` off a screen -> still missed at conf 0.4, expected

## Still open after Saturday
- **Paper + `model_evolution_report.md`** — the only graded deliverable, untouched.
  Numbers to write up: v2 -> v3 rejected -> v4, image-level accuracy, the NaN
  investigation, 9,816 images, and now the mask-width finding (a genuine methods
  contribution: segmentation masks cannot measure hairline crack width).
- Overhead-cable false alarm — elongation can't catch it, needs a different idea.
- `lib/screens/_backup/` — 5 dead files, the only `flutter analyze` errors in the repo.

## Reference
- Run backend: `cd project/backend && /c/Python314/python -m uvicorn main:app --host 0.0.0.0`
- Tunnel: `F:\StructuralVision\tools\ngrok.exe http 8000` → `https://purr-decline-paycheck.ngrok-free.dev`
- APK share link: Supabase bucket `app-releases` (re-upload after rebuilds, arm64 split only)
