# Structural Vision AR — Revised Design Spec
**Date:** 2026-07-12  
**Status:** Draft — awaiting user approval  
**Based on:** structural_vision_ar_dev_plan.md + dataset analysis session

---

## 1. What Changed From the Original Dev Plan

| Area | Original Plan | Revised Design | Reason |
|---|---|---|---|
| ML models | Single YOLOv8-seg | YOLOv8n-seg + MobileNetV3 classifier | Component type can't come from seg model (single class only) |
| Component detection | Undefined | Auto-detected by classifier | Jury requirement |
| Component classes | wall/beam/column/foundation | wall/beam/column/slab/ceiling | Foundation rarely visible at inspection distance |
| Training dataset | Crack500 + Roboflow merged | Roboflow crack.yolov8 + crack-wall only | Crack500 is road asphalt — wrong domain |
| Model size | Unspecified | YOLOv8n-seg (nano) | CPU-only inference, <3 sec budget |
| crack_detections schema | bbox only | bbox + polygon_points jsonb | AR pin placement needs polygon coords |
| POST /scan behaviour | Synchronous | Async + polling | Inference + upload chain too slow to block on |
| Auth | Unspecified | JWT middleware (Supabase tokens) | Every endpoint touches user data |
| Flutter state mgmt | Unspecified | Riverpod | Needed for async scan state + AR |
| Accuracy metric | Unspecified | mAP50 (seg), top-1 accuracy (classifier) | Apples-to-apples retrain comparisons |
| Risk classification | Unspecified | Crack area ratio + confidence rules (see §5) | Core business logic, must be defined before coding |

---

## 2. System Architecture

```
Flutter App
  │
  ├── Camera screen → compress to max 1280px → upload
  │
  ├── POST /scan → returns scan_id immediately
  │
  ├── polls GET /scan/{id} every 2s until status != 'processing'
  │
  └── Results screen → heatmap overlay, risk badge, component label
        └── AR mode → ARCore plane detection → pin placement from polygon_points

FastAPI Backend
  │
  ├── JWT middleware (validates Supabase JWT on every request)
  │
  ├── POST /scan
  │     ├── Receive image → store original in Supabase Storage
  │     ├── OpenCV preprocess (resize to 640×640, normalize)
  │     ├── YOLOv8n-seg ONNX → crack polygons + confidences
  │     ├── MobileNetV3 ONNX → component class (wall/beam/column/slab/ceiling)
  │     ├── Risk classification logic (§5)
  │     ├── Generate heatmap overlay → store in Supabase Storage
  │     ├── Insert scans row + crack_detections rows
  │     └── Mark scan complete (risk_score populated)
  │
  ├── GET /scan/{id} → return scan row (polling target)
  ├── GET /scan/{id}/report → generate PDF via ReportLab (cached)
  ├── POST /building → create building
  └── GET /building/{id}/scans → scan history

Supabase
  ├── Auth (JWT source)
  ├── Storage (original images, heatmaps, PDFs)
  └── Database (buildings, scans, crack_detections, reports)
```

---

## 3. ML Models

### Model 1 — YOLOv8n-seg (crack detection + segmentation)

**Task:** Detect crack locations, output polygon masks  
**Classes:** 1 — `crack`  
**Input:** 640×640 RGB  
**Output:** bounding boxes + polygon coordinates + confidence per crack instance  
**Export:** ONNX (opset 12)  
**Inference budget:** <2 sec on Intel Iris Xe CPU  

**Training data:**
| Source | Images (train) | Notes |
|---|---|---|
| Roboflow crack.yolov8 | 1,239 | Structural walls/concrete, polygon labels |
| crack-wall (Roboflow Universe) | ~1,518 | Wall crack seg, same YOLO format |
| **Total** | **~2,757** | Single class, polygon seg format throughout |

**Training config:**
```yaml
model: yolov8n-seg.pt
epochs: 150
imgsz: 640
batch: 8          # CPU-safe batch size
patience: 30      # early stopping
augment: true     # mosaic, flips, HSV — keep defaults
```

**Validation metric:** mAP50 (mask). Target: ≥80% for demo, ≥90% stated target.

**Pre-training checklist (Phase 0):**
- [ ] Merge crack-wall dataset into Roboflow set (confirm single class, same format)
- [ ] Visual spot-check: load 15 random images with label overlay, confirm polygons align
- [ ] Benchmark nano ONNX inference on CPU before committing — if >2.5 sec, switch to YOLOv8n-seg with `half=False` explicitly

---

### Model 2 — MobileNetV3-Small (component classifier)

**Task:** Classify structural component type from full inspection image  
**Classes:** 5 — `wall`, `column`, `beam`, `slab`, `ceiling`  
**Input:** 224×224 RGB  
**Output:** single class label + confidence  
**Export:** ONNX  
**Inference budget:** <0.5 sec on CPU  

**Training data:**
| Class | Source | Images (approx) |
|---|---|---|
| wall | SDNET2018 Walls/Cracked + Non-cracked | 3,851 + 14,287 |
| slab | SDNET2018 Decks/Cracked + Non-cracked | 2,025 + 11,595 |
| column | To be sourced (Roboflow Universe / web) | 300–500 target |
| beam | To be sourced (Roboflow Universe / web) | 300–500 target |
| ceiling | To be sourced (Roboflow Universe / web) | 300–500 target |

**Important:** SDNET2018 is heavily imbalanced (18k wall, 13k slab vs ~300-500 per new class). Downsample wall and slab to ~2,000 each during training, or use weighted loss. Do not train on all 18k wall images — the classifier will overfit to that class.

**Training config (PyTorch / torchvision):**
```python
model = mobilenet_v3_small(pretrained=True)  # ImageNet pretrained
model.classifier[-1] = nn.Linear(1024, 5)    # replace head for 5 classes
# Fine-tune last 2 layers only for CPU training speed
epochs = 30
lr = 0.001
batch_size = 32
```

**Validation metric:** Top-1 accuracy. Target: ≥85% for demo.

---

## 4. Revised Database Schema

Changes from original plan marked with `-- CHANGED` or `-- NEW`.

```sql
-- users: handled by Supabase Auth

create table buildings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) not null,
  name text not null,
  location text,
  created_at timestamptz default now()
);

create table scans (
  id uuid primary key default gen_random_uuid(),
  building_id uuid references buildings(id) not null,
  image_url text not null,
  heatmap_url text,
  component_type text check (component_type in (
    'wall','beam','column','slab','ceiling'  -- CHANGED: foundation→slab+ceiling
  )),
  component_confidence float,              -- NEW: classifier confidence score
  risk_score text check (risk_score in ('low','medium','high')),
  maintenance_window text check (maintenance_window in (
    'immediate','short_term','long_term'
  )),
  status text default 'processing' check (status in (
    'processing','complete','failed'        -- NEW: async status field
  )),
  error_message text,                      -- NEW: populated on status='failed'
  created_at timestamptz default now()
);

create table crack_detections (
  id uuid primary key default gen_random_uuid(),
  scan_id uuid references scans(id) not null,
  bbox jsonb,                              -- [x1,y1,x2,y2] pixels
  polygon jsonb,                           -- [[x,y],...] pixels
  confidence float,
  area_ratio float,
  crack_type text,                         -- NEW (2026-07-29): structural | paint
  length_px float, width_px float,         -- NEW: PCA extent + area/length; client → mm via AR two-tap
  growth_status text,                      -- NEW: new | grown | stable (only on re-scan vs prev_scan_id)
  area_delta float                         -- NEW: area_ratio change vs matched prior crack
);

create table reports (
  id uuid primary key default gen_random_uuid(),
  scan_id uuid references scans(id) not null,
  pdf_url text not null,
  generated_at timestamptz default now()
);
```

---

## 5. Risk Classification Logic

Defined here so it is coded consistently in backend and displayed consistently in Flutter.

```
crack_area_ratio = sum(polygon areas) / (image_width × image_height)
max_confidence   = max(confidence scores across all detections)
crack_count      = number of crack instances detected

if crack_count == 0:
    risk_score = 'low'
    maintenance_window = 'long_term'

elif crack_area_ratio > 0.15 OR max_confidence > 0.90:
    risk_score = 'high'
    maintenance_window = 'immediate'

elif crack_area_ratio > 0.05 OR max_confidence > 0.70:
    risk_score = 'medium'
    maintenance_window = 'short_term'

else:
    risk_score = 'low'
    maintenance_window = 'long_term'
```

**Maintenance window mapping (fixed, not derived separately):**
| Risk | Maintenance Window | Label shown to user |
|---|---|---|
| high | immediate | Immediate (0–6 months) |
| medium | short_term | Short-term (6–24 months) |
| low | long_term | Long-term (2–5 years) |

**Summary sentence template (for PDF):**
- high: "Significant cracking detected on {component}. Immediate structural inspection recommended."
- medium: "Moderate cracking detected on {component}. Schedule inspection within 6–24 months."
- low: "Minor cracking detected on {component}. Monitor and reinspect within 2–5 years."
- no cracks: "No significant cracking detected on {component}."

---

## 6. FastAPI Endpoint Contracts (revised)

### POST /scan (async)
**Request:** multipart — `image` (file) + `building_id` (string)  
**Response (immediate, ~200ms):**
```json
{ "scan_id": "uuid", "status": "processing" }
```
**Background processing:**
1. Store original image → Supabase Storage
2. OpenCV: decode, resize short-side to 640, normalize
3. YOLOv8n-seg ONNX inference → crack instances
4. MobileNetV3 ONNX inference → component class + confidence
5. Risk classification (§5)
6. Generate heatmap overlay (OpenCV — draw polygon masks in red/yellow/green)
7. Store heatmap → Supabase Storage
8. Insert `scans` row (status='complete') + `crack_detections` rows

On failure: update scan status='failed', store error in a `error_message text` field (add to schema).

### GET /scan/{id}
Returns full scan row. Flutter polls this every 2 seconds until `status != 'processing'`.

### GET /scan/{id}/report
Generates PDF via ReportLab if not cached (`reports` table empty for this scan_id), stores in Supabase Storage, inserts `reports` row, returns PDF URL. Budget: <5 sec.

### POST /building
Body: `{name, location}`. Returns `{id}`.

### GET /building/{id}/scans
Returns scan list sorted by `created_at` desc. Excludes status='failed' from default view (Flutter can add a filter toggle later).

### Auth middleware (all endpoints)
Extract `Authorization: Bearer <token>` header → validate against Supabase JWT secret → inject `user_id` into request context. Reject with 401 if missing or invalid.

---

## 7. Flutter App Structure

**State management:** Riverpod

**Screens:**
1. **Auth** — Supabase Auth UI (email/password, no custom auth)
2. **Buildings list** — list user's buildings, create new building
3. **Scan capture** — camera, compress to max 1280px, upload, show processing spinner, poll until complete
4. **Scan result** — heatmap overlay image, risk badge (red/yellow/green), component label, maintenance window, PDF download button
5. **Scan history** — list scans for a building, tap to view result
6. **AR view** — ARCore plane detection, place annotation pins from `crack_detections.polygon_points` centroids

**Image upload flow:**
```
Camera capture → flutter_image_compress (max 1280px, quality 85)
→ POST /scan (multipart) → receive scan_id
→ start polling GET /scan/{scan_id} every 2s
→ on status='complete': navigate to result screen
→ on status='failed': show error, allow retry
```

**Riverpod providers needed:**
- `buildingsProvider` — AsyncNotifier, list of buildings
- `scanUploadProvider` — StateNotifier, upload + poll lifecycle
- `scanResultProvider(scanId)` — FutureProvider, single scan result
- `scanHistoryProvider(buildingId)` — FutureProvider, list of scans

---

## 8. AR Implementation (Phase 5)

**Constraint:** No LiDAR, no real depth — annotation pins only, not 3D crack geometry.

**User flow:**
1. View scan result → tap "View in AR"
2. ARCore initialises, asks user to point phone at the scanned surface
3. ARCore detects a vertical/horizontal plane
4. App projects crack polygon centroids (stored as normalised 0–1 coords in `crack_detections.polygon_points`) onto the detected plane
5. Pins placed at projected positions — each pin shows risk colour + confidence

**Coordinate mapping:**
```
image_x_norm, image_y_norm (from polygon centroid, 0-1)
→ plane_x = plane.width  × image_x_norm
→ plane_y = plane.height × image_y_norm
→ place AR anchor at (plane_x, 0, plane_y) relative to plane origin
```

This is an approximation — pins won't be pixel-perfect on the real surface, but they'll be on the right surface in the right rough region. Accurate enough for a demo.

**3D model:** One preset Blender GLB building model. Static placement, no animation. Export during Phase 2/3 downtime. Do not wait until Phase 5.

**AR hello-world spike (Phase 2/3 downtime, ~half a day):**
- Flutter ARCore plugin installed
- Plane detection working on physical device
- A cube placed on detected plane
- This de-risks Phase 5 entirely — do not skip

---

## 9. PDF Report Spec (unchanged from dev plan)

One page. Top to bottom:
1. Building name, location, scan date
2. Image with heatmap overlay
3. Risk score — large, colour-coded (red/yellow/green)
4. Component type (from classifier)
5. Maintenance window
6. Summary sentence (from §5 template)

---

## 10. Phase Timeline (revised)

| Phase | Work | Dates | Notes |
|---|---|---|---|
| 0 | Dataset prep + device confirm | Jul 12–13 | Merge crack-wall into Roboflow set, verify labels |
| 1 | ML training — both models | Jul 13–18 | YOLOv8n-seg first, MobileNetV3 second (faster) |
| 2 | Backend core | Jul 17–27 | Async POST /scan, both ONNX wrappers, JWT middleware |
| 2/3 | AR spike (half day, any downtime) | Jul 17–Aug 3 | ARCore hello-world on physical device |
| 3 | Flutter skeleton | Jul 28–Aug 3 | Camera → upload → poll → result |
| 4 | Frontend polish + reporting | Aug 4–10 | History, PDF, risk colours, building flow |
| 5 | AR full integration | Aug 11–17 | Pins from polygon centroids, GLB model |
| 6 | Integration + bug fix | Aug 18–24 | End-to-end runs, demo rehearsal |
| 7 | Demo | Aug 25 | |
| Post | Polish + accuracy push | Aug 26–Nov 9 | Hit stated 90%+ mAP50 target |

---

## 11. Open Items (must resolve before Phase 1)

- [ ] Download crack-wall dataset, merge with Roboflow set, spot-check 15 images
- [ ] Source column / beam / ceiling images for classifier (~300-500 each)
- [ ] Confirm ARCore-compatible physical Android device (Settings → About Phone, or install "Google Play Services for AR" from Play Store)
- [ ] Decide: use SDNET2018 Non-cracked images in classifier training or cracked-only? (Recommendation: include both — classifier needs to handle images without visible cracks too)

---

## 12. Constraints Carried Forward (do not re-litigate)

- Flutter frontend only (no web/React/MindAR)
- YOLOv8-seg single segmentation model (no separate detection model)
- CPU-only training (Intel Iris Xe)
- Supabase Auth — no custom auth
- Supabase free tier for storage + database
- ReportLab for PDF
- One-page PDF report
- Maintenance Window prediction stays (jury-approved framing)
- No AR crack depth visualisation (needs LiDAR)
- No endpoints, tables, or features beyond this spec without flagging as scope change
- Stated accuracy target: 90%+ (stretch 96%) in presentation-facing material
