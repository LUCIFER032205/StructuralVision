# StructuralVision AR — ML Improvement Plan (v3)

*Last updated: 2026-08-13*

---

## Current State (v2 baseline)

| Metric | Value |
|---|---|
| Model | YOLOv8m-seg |
| Training resolution | 1024px (but evaluated at 640px — bug) |
| mAP50 | 0.741 |
| Precision | 0.851 |
| Recall | 0.700 |
| Inference (CPU, 640px) | ~390ms |

**Root cause of plateau:** Both false positives and false negatives present in real scans on Vivo Y200. Model is data-bound — training set is too narrow (single Roboflow source, ~3,500 images). Precision already good; recall is the primary gap to the 90%+ target.

---

## Target (v3 / v4)

| Metric | v3 target | v4 stretch |
|---|---|---|
| mAP50 | 0.85+ | 0.90+ |
| Precision | 0.82+ | 0.85+ |
| Recall | 0.82+ | 0.88+ |
| Inference (CPU, 1024px) | ~800ms | same |

Precision target is slightly lower than current — intentional tradeoff: recovering recall matters more for structural safety (missing a crack is worse than a false alarm).

---

## Compute

- **Kaggle dual accounts** (T4/P100 GPU) — runtime is not a constraint
- Local machine: Intel Iris Xe, CPU-only — used for data prep and ONNX export only
- Training moves fully to Kaggle from v3 onwards

---

## The 4 Levers (in order of impact)

### 1. More & Better Data (highest ROI)

Target: **8,000–12,000 training images** (up from ~3,500).

#### Datasets to add

| # | Dataset | URL | ~Images | Notes |
|---|---|---|---|---|
| 1 | Roboflow "Creacks" | [link](https://universe.roboflow.com/roboflow-jvuqo/creacks-eapny) | ~4,030 | Native YOLOv8-seg export, zero conversion |
| 2 | CrackSeg9k | [link](https://doi.org/10.7910/DVN/EGIEBY) | ~9,160 | Binary PNG masks → needs polygon conversion |
| 3 | BuildCrack / CrackUDA | [link](https://zenodo.org/records/14544429) | ~800 | Drone/facade angles, high realism, needs conversion |
| 4 | KangchengLiu UAV Dataset | [link](https://github.com/KangchengLiu/Crack-Detection-and-Segmentation-Dataset-for-UAV-Inspection) | ~11,298 | Largest, varied scale/angles, needs conversion |
| 5 | Ultralytics crack-seg | [link](https://universe.roboflow.com/university-bswxt/crack-bphdr) | ~4,029 | Zero conversion — but verify not same as existing crack.yolov8 |

**Download priority:** #1 and #5 first (no conversion), then #2 (volume), then #3 and #4.

⚠️ **Dataset #5 check:** if `university-bswxt/crack-bphdr` is the same workspace as your existing `crack.yolov8`, substitute with [zenodo.org/records/15187675](https://zenodo.org/records/15187675) (Multi-temporal Concrete Crack, 1,356 images, CC BY 4.0).

**SDNET2018 — excluded.** Previously trialled, decided poor fit for this project. Do not re-add.

#### Label audit (before training)
- Visually inspect ~100 random training images with mask overlays
- Look for: unlabeled cracks (teaches model to ignore them), over-segmented joints/shadows
- Fix before running any training — bad labels waste a full Kaggle session

#### Hard negative mining (after v3 training)
- Run inference on 200 images the model got wrong (high-confidence false positives)
- Add those images with correct empty labels to training set
- Most effective single fix for phantom crack detections

---

### 2. Train AND Evaluate at 1024px (free win)

v2 was trained at 1024px but evaluated at 640px — hairline cracks disappear at 640. Fix:

```yaml
imgsz: 1024   # in both training config AND FastAPI inference call
```

Inference time at 1024px: ~150ms on GPU (Kaggle), ~800ms on CPU (still under 3s budget).

---

### 3. Model Size + Hyperparameters

Upgrade from YOLOv8m-seg → **YOLOv8l-seg**. GPU makes this feasible; the larger neck preserves fine spatial detail better for thin cracks.

**Recommended v3 training config:**

```yaml
model: yolov8l-seg.pt
imgsz: 1024
epochs: 150
batch: 8                   # fits T4 VRAM at 1024px
optimizer: AdamW
lr0: 0.001
weight_decay: 0.0005
mosaic: 1.0
copy_paste: 0.3            # synthetically creates thin-crack instances
degrees: 10.0
```

`copy_paste: 0.3` is especially important — it pastes crack segments into new backgrounds, generating the under-represented hairline crack cases synthetically.

---

### 4. Confidence Threshold Tuning (do last)

Current precision headroom (0.85) means lowering the confidence threshold will recover recall without destroying precision.

- After v3 training, plot the precision-recall curve
- Find threshold where precision stays ≥ 0.75 and recall is maximised
- Typically recovers 5–8 recall points at zero training cost
- Do this AFTER data + model work — no point tuning thresholds on a weaker model

---

## Execution Timeline

```
Week 1
  Day 1–2  Download datasets #1–5, verify label formats, run merge script
  Day 3    Label audit on existing data, fix mislabels
  Day 4–5  v3 training: yolov8l-seg, 1024px, 150 epochs (Kaggle Account 1)
           Switch to Account 2 if runtime runs out mid-run
  Day 6    Evaluate v3: mAP50, precision, recall vs validation set
  Day 7    Hard negative mining: find FP images, label, add to dataset

Week 2
  Day 1–3  v4 training with hard negatives added
  Day 4    Threshold tuning on PR curve
  Day 5    Export best checkpoint to ONNX, test on Vivo Y200
  Day 6–7  Swap model in backend, field test real scans
```

---

## Mask → YOLOv8-seg Conversion (for datasets 2, 3, 4)

```python
import cv2, numpy as np

def mask_to_yolo_seg(mask_path, img_w, img_h, class_id=0):
    mask = cv2.imread(str(mask_path), cv2.IMREAD_GRAYSCALE)
    _, binary = cv2.threshold(mask, 127, 255, cv2.THRESH_BINARY)
    contours, _ = cv2.findContours(binary, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    lines = []
    for cnt in contours:
        if cv2.contourArea(cnt) < 20:  # skip noise
            continue
        pts = cnt.reshape(-1, 2).astype(float)
        pts[:, 0] /= img_w
        pts[:, 1] /= img_h
        coords = " ".join(f"{x:.6f} {y:.6f}" for x, y in pts)
        lines.append(f"{class_id} {coords}")
    return lines
```

Ask Claude Code to generate the full merge + conversion script once all datasets are downloaded.

---

## Key Constraints (do not change)

- Single YOLOv8-seg model — do not split back into detection + segmentation
- Inference budget: < 3s per image on CPU (backend)
- ONNX export required for FastAPI deployment
- Model swap = overwrite file + restart server, zero code change
- Training target in presentation materials: 90%+ (stretch 96%) — report real numbers to guides privately

---

## Open Items

- [x] Download datasets #1–5 from list above
- [x] Write dataset merge + conversion script (`fix_local_dataset.py`, `fix_problem_images.py`) → 9,816 train images
- [x] Run label audit on existing crack.yolov8 data (`find_problem_images.py`)
- [x] Kick off v3 training on Kaggle: v3 (YOLOv8l-seg) rejected at 0.618 mask mAP50 / 4.3 s CPU; v4 (YOLOv8m-seg fine-tune) deployed 2026-09-13 at 99.0% image-level accuracy
- [x] Re-tune risk score thresholds (2026-09-15): duplicate masks deduped (NMS iou 0.45), preliminary DI thresholds 0.10/0.25 → 0.03/0.07, fit on demo_kit
