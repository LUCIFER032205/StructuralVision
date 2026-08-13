# Guided Burst Capture (video-style UX) — Design

Date: 2026-08-07
Status: approved by user

## Problem

The video scan mode is broken in practice on real devices (Vivo Y200 field test):

1. `startVideoRecording()` gives no feedback while awaiting (1–2 s) — user thinks nothing happened.
2. Short clips degenerate to 1 sampled frame → a single result, but with mp4 compression artifacts (worse than a plain photo).
3. The backend throws the video away anyway — it samples ~1 frame/sec, max 8 frames (`_sample_video_frames` in `project/backend/main.py`).

Separately, gallery multi-select already exists in code (`pickMultiImage()` in `camera_screen.dart`); the single-image behavior the user saw was likely an old APK. No change needed — re-test with a fresh build.

## Decision

Replace real video recording with **guided burst capture behind the same video-style UI**. Users tap the familiar record button; under the hood the app takes full-resolution still photos at intervals and submits them through the existing multi-image batch pipeline.

Rationale: same ~1 shot/sec output the backend produced from video, but with full-quality JPEGs (better crack detection input), no mp4 upload, no server-side decode, no flaky `startVideoRecording()`.

## UX / Behavior

- Videocam FAB keeps its exact look. Tap → button turns red with stop icon, "REC · 0" counter overlay appears immediately.
- **Start delay:** first shot fires after `_burstStartDelay = 1 s` (users hit record before aiming — often while the phone is on their lap/ground).
- **Interval:** subsequent shots every `_burstInterval = 2.5 s` — enough time to reposition to the next angle. Both are file-level consts, one-line tunable after field testing.
- Counter increments per shot ("REC · 3") so each captured frame is visible feedback.
- Tap stop → capture ends, shots upload via existing `submitScan()` per image → existing `BatchScreen` opens (already labels items "Segments", so the video metaphor holds end-to-end).
- **Cap:** 8 shots (matches old video cap). Auto-stop at cap → proceeds to upload as if stopped.
- Stopping with 0 shots captured (tapped stop within the start delay): cancel silently back to idle, no upload.
- 1 shot captured: still goes through batch upload path → BatchScreen with one segment (keeps the flow uniform; no special-casing).

## Changes

### Flutter (`project/app/lib/`)

- `screens/camera_screen.dart`:
  - Replace `_toggleRecording()` video logic with burst logic: `Timer` for start delay + `Timer.periodic(_burstInterval)` calling `ctrl.takePicture()`, accumulating `Uint8List` shots.
  - Track burst state (`_burstShots`, timer handles) instead of `ctrl.value.isRecordingVideo` for the red/stop button state.
  - "REC · n" overlay while bursting.
  - On stop: upload each shot via `scanApi.submitScan()`, collect ids, `_openBatch(ids)` (existing).
  - Cancel timers in `dispose()`.
- `scan_api.dart`: delete `submitVideoScan()`.

### Backend (`project/backend/main.py`)

- Delete `/scan/video` endpoint and `_sample_video_frames()`.
- `merge_video_detections` in `inference.py`: check callers; delete if now unused.

### No changes

- `BatchScreen`, `submitScan`, gallery multi-select, models, DB, overlay/report.

## Error handling

- `takePicture()` throw mid-burst: skip that shot, keep bursting (transient camera hiccups shouldn't kill the run); if the controller is gone, stop the burst.
- Upload failure of one shot: existing `submitScan` already retries once; if it still fails, abort remaining uploads and show the existing snackbar error (shots are lost — acceptable for v1, same as today's photo flow).
- Navigation away / dispose during burst: timers cancelled, shots discarded.

## Paper framing (user concern: is the video metaphor misleading?)

Not deceptive if described accurately. In the paper, name it "guided burst capture" / "interval-based multi-frame acquisition presented through a familiar video-recording interaction." Do not claim video analysis (no temporal tracking exists — and never did; the old pipeline also just sampled stills). Full-res stills vs compressed video frames is a defensible design contribution.

## Testing

- Existing `test/` unaffected (no model/API-contract changes on the image path).
- Manual field test on Vivo Y200: record-feel responsiveness, start delay, interval pacing, cap auto-stop, batch results.
