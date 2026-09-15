# StructuralVision AR — Finish Plan (target: 2026-09-30)

*Written 2026-09-12. 18 days left. No demo deadline — the demo was given last month.*

---

## The scope call

"Finished" here means: **the app works and is documented, the model is decided and frozen, and the repo is clean enough to hand over.** It does not mean production-hardened for daily use by professional inspectors.

That single decision cuts the most expensive item on the UI/UX list. See §4.

---

## Block 1 — Sep 12–17: close the model, fix the app's worst UI

**Model — finish it tonight and stop.**
- Run `kaggle_tomo/finetune_medium.ipynb` (~10 h, all guards on).
- Cell 5 gives the verdict against v2's 0.675. Two outcomes, both are endings:
  - **Wins** → time one CPU predict, swap `project/models/crack_seg.pt`, done.
  - **Doesn't win** → keep v2, done.
- Either way, **no further training runs after this one.** The model has consumed two sessions and ~35 GPU-hours; it is not where the remaining value is.

**Re-tune the risk thresholds.** The last open item in `ml_updated_plan.md`, and the only one still real — the report notes v2 skews toward MEDIUM, so nearly everything lands in one bucket. A risk score that always says the same thing is worse than no risk score. Cheap to fix, visible in every single scan.

**App — the 2-hour slice** from `ui_ux_plan.md`: contrast fix (P0.1), tap feedback + haptics (P0.2), pinch-zoom results (P1.3), zero-crack empty state (P1.5).

## Block 2 — Sep 18–24: the parts that get graded

**Confidence display (P1.2).** The most defensible UI feature you can add — it's the standard AI-trust pattern, and it's honest about a model at ~0.68 mask mAP. Also gives the paper something to discuss beyond raw metrics.

**Component chip instead of the modal (P1.1).** Cuts a scan from 3 taps to 1. Small, and very visible in any walkthrough.

**Paper + reports.** `StructuralVisionAR_DraftPaper_v2.docx` has uncommitted edits. The real numbers to write up:
- v2 baseline: box mAP50 0.833, mask mAP50 0.675, ~1.0 s CPU
- v3 (YOLOv8l-seg): mask mAP50 0.618, ~4.3 s CPU → rejected on both accuracy and latency
- The NaN collapse and what was ruled out — this is a genuine methods contribution, not a failure to hide
- Dataset expansion: ~3.5k → 9,816 training images across 5 sources

Update `model_evolution_report.md` with the same numbers so the docs agree.

## Block 3 — Sep 25–30: tidy and buffer

- **Resolve the `presentation/` deletions.** The whole folder is deleted in the working tree but still tracked. Either restore it or commit the removal — don't leave the repo in this state.
- **Protect the repo from the big files.** `kaggle_tomo/` holds ~4.4 GB (three .pt checkpoints plus `fixed_dataset.zip`), and `project/backend/static/structural_vision_ar.apk` is untracked. Add them to `.gitignore` before any bulk `git add`. A previous commit already had to remove an APK for being too large.
- **Commit the real work.** There are uncommitted changes across the Flutter app and the FastAPI backend right now.
- **Fix the stale plan doc.** Four of the five open items in `ml_updated_plan.md` are already done; leaving them unticked makes the project look unfinished when it isn't.
- Leave the last 2–3 days as buffer. Something always slips.

---

## 4. Explicitly cut — and why

| Cut | Why |
|---|---|
| **Offline scan queue** (was P0.3, half a day) | Field-hardening for daily professional use. Invisible in a report or walkthrough. The scope call above rules it out. |
| **Sunlight / high-contrast light mode** | Same reason. The P0.1 contrast fix captures most of the benefit for 15 minutes of work. |
| **Voice notes** | Real field-tool feature, zero academic value here. |
| **Torch + tap-to-focus** (P1.4) | Genuinely useful, but 1–2 h that competes with the paper. Do it only if Block 2 finishes early. |
| **More training runs** | 0.85 was never reachable on this data, and the target was set against a differently-measured baseline. |
| **ONNX export** | `ml_updated_plan.md` lists it as required, but `inference.py` loads the `.pt` directly and meets the latency budget. Moot unless the model swap changes that. |

---

## 5. The one thing that could change this plan

What has to physically exist on Sep 30 — a submitted paper, a code + report submission, a viva, or just "it works and I'm done"? Block 2 and Block 3 swap priority depending on the answer. Everything else above holds regardless.
