# Structural Vision AR — Post-Demo Architecture Improvements

> Feed this file to Claude Code at the start of any improvement session.
> Based on a full codebase review + LLM council analysis conducted 2026-08-13.
> Demo is complete. This is the improvement roadmap, no hard deadline.

---

## Context: What Was Decided and Why

The team debated two UX architectures:

**Option A (rejected):** User stands in center of room, sweeps camera, wide/zoomed-out shots, both models auto-run. "Holistic room-level report."

**Option B (correct direction):** Guided capture — user selects component type before shooting, frames the element to fill the shot, models run on a properly framed image.

Option A is dead. The ML report documents Model 2 (MobileNetV3) misclassifying a bedroom wall as "ceiling" at 0.98 confidence on exactly the kind of wide, cluttered shot Option A requires. That is not a corner case — it is the dominant real-world condition for Option A. Option A cannot be salvaged at the UX layer.

Option B is correct but needs refinement so it doesn't feel bureaucratic.

---

## Locked Architectural Decisions (do not re-litigate)

- Wide-angle room sweeps as primary input: **dropped**
- Zoomed-in, element-framed shots: **required for both models to function correctly**
- User pre-selection of component type: **required, and it is the authoritative label**
- Model 2 (MobileNetV3) role: **consistency check only, NOT primary classifier**
- Confidence score as the gate for confirmation prompts: **explicitly rejected** — Model 2 fails WITH high confidence (0.98 on wrong predictions). Confidence threshold cannot catch this. The gate is disagreement between user label and model prediction, not confidence score.

---

## What to Build (in priority order)

### 1. Component Selection Screen (highest priority)

Add a screen/step before camera capture where the user selects the component they are about to photograph: `wall | beam | column | slab | ceiling`.

- This selection is the **authoritative ground truth label** for the scan
- Pass it through to the backend alongside the image
- Backend stores it as the confirmed `component_type` regardless of what Model 2 says
- Three hours of Flutter work, unblocks everything else

**Implementation notes:**
- Simple grid of 5 cards with icons, one tap to select
- Store selection in local state, pass as a form field in the `POST /scan` multipart request (new field: `confirmed_component`)
- Backend: if `confirmed_component` is provided, skip Model 2 classification and use that value directly. Still run Model 2 in background for the consistency check below.

---

### 2. Framing Guidance Overlay

Add a visual framing guide to the camera screen when in guided capture mode.

- Show a bounding box overlay indicating the target fill zone
- The structural element should occupy approximately 60%+ of the frame
- This is what Model 1 (crack detection) needs — it was trained on element-filling shots. A wall that is 20% of a wide frame makes hairline crack detection much worse.
- Simple `CustomPainter` overlay on the `CameraPreview`, similar to the existing `_ViewfinderGuide` corner brackets but with a larger inner fill target indicator

---

### 3. Model 2 as Consistency Check (not primary classifier)

After capture, run Model 2 on the image as normal. Compare its prediction to the user's pre-selected component.

**Logic:**
```
if model2_prediction == user_selected_component:
    proceed silently — no prompt shown
else:
    show one-tap confirmation: 
    "You selected [Wall] — model sees [Ceiling]. Confirm your selection?"
    default action = keep user's selection
    model2 prediction shown as secondary info only
```

This eliminates the calibration problem entirely. Model 2's confidence score is not used as a decision signal. The disagreement between user label and model prediction is the signal.

**Backend change needed:** `POST /scan` needs to accept `confirmed_component` as an optional field. If present, use it as `component_type` in the scan result. Still run Model 2 and store its prediction + confidence separately for the consistency check display and for future training data.

---

### 4. Redefine Burst Mode

Current burst mode: up to 8 frames at 2.5s intervals — designed as a room sweep. This is Option A behavior. It needs to be repurposed.

**New burst mode behavior:** 8 frames of the **same selected component** at the same framing. User selects component first (Step 1 above), then enters burst mode to capture multiple angles or patches of that one element.

- The batch screen already handles multiple scan results cleanly — no changes needed there
- All burst frames inherit the same `confirmed_component` from the pre-selection step
- This preserves burst mode's utility for covering large surfaces (e.g., a long wall) without breaking the guided flow

---

### 5. Detection Disclaimer on Result Screen

Add a visible disclaimer to the result screen and PDF report:

> "This scan detects approximately 70–74% of cracks. Manually re-inspect any flagged zones. Not a substitute for professional structural assessment."

Model 1 is at 74% mAP50 with ~30% miss rate on recall. This is the actual liability. No UX architecture fixes it — it's a model training problem (see Model Improvements below). Being transparent about it is both honest and defensible.

---

### 6. Optional: Two-Capture Mode (post-Step-1 improvement)

The two models have conflicting optimal inputs:
- **Model 2** (component classifier) needs the element to fill the frame
- **Model 1** (crack detector) may benefit from some spatial context around the crack, not an extreme close-up

A two-capture flow resolves this cleanly:
1. User takes a component-framed shot (element fills the frame) → feeds Model 2
2. User takes a close-up of the crack area → feeds Model 1
3. Backend runs them separately and merges results

This is not required for the immediate improvements sprint. Implement Steps 1–5 first. Log this as the next architectural step after those are stable.

---

## Model Improvement Track (separate from UX work, run in parallel)

These are training/ML tasks, not UX tasks. They can proceed independently.

### Model 1 — Crack Detection (current: 74% mAP50, ~30% miss rate)

The miss rate is the dominant risk. Precision is at 0.85 (fixed from v1), recall is stuck at 0.70. The v2 training already showed that generic "more data" gave its win. The next gains require:

1. **Targeted data collection:** Run the current model over the validation set, inspect false negatives specifically. Hairline cracks and low-contrast cracks are the documented failure patterns. Label new images of exactly those cases.
2. **Label audit on existing training data:** Public crack datasets have unlabeled real cracks — those teach the model to miss. Clean existing labels before adding new ones.
3. **Deploy at 1024px instead of 640px:** The model was trained at 1024px. Evaluating at 640px shrinks hairlines below detectability. Try this first — it's a config change, free experiment, ~2–4× inference time but still within the <3s budget.
4. **Lower confidence threshold:** With precision at 0.85 there is headroom to lower from 0.5 toward 0.3–0.4 and trade some precision for recall. Test on the validation set.

### Model 2 — Component Classifier (current: 97% val accuracy, calibration problem in real world)

The documented failure is a **calibration failure**, not just accuracy. The model outputs high confidence on wrong predictions (0.98 on a wrong class). This means:

- The confidence score cannot be trusted as a reliability signal
- Fixing this requires adding real-world OOD (out-of-distribution) shots to the training set — specifically the cluttered domestic wall shots that currently break it
- Every scan where the user's confirmed component differs from Model 2's prediction is a labeled training sample. Collect these and use them for fine-tuning.
- Consider temperature scaling as a post-training calibration step — it does not change accuracy but makes confidence scores more reliable

---

## What NOT to Change

- Do not revert to a single-model architecture. The 2-model split (YOLOv8-seg + MobileNetV3) is correct and is already built.
- Do not propose using confidence score as the gate for Model 2 confirmation prompts — the failure mode is high-confidence wrong answers.
- Do not use burst mode as a room sweep — redefine it as per-component burst only.
- Do not remove the maintenance window prediction — it is jury-approved.
- Do not add tables, endpoints, or features outside what is listed here without flagging it as a scope change.

---

## Stack Reference (unchanged)

| Layer | Tech |
|---|---|
| Frontend | Flutter |
| AR | ARCore + Flutter AR plugin |
| Backend | Python + FastAPI |
| ML Models | YOLOv8m-seg (crack detection) + MobileNetV3-Small (component classifier) |
| Image Processing | OpenCV |
| Database + Storage | Supabase (free tier) |
| PDF Generation | ReportLab |
| Model Format | ONNX (both models) |

Backend runs at: `cd project/backend && python -m uvicorn main:app --host 0.0.0.0`
Tunnel: `ngrok.exe http 8000`
