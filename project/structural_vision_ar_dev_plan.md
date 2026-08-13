# Structural Vision AR — Development Plan & CC Prompt

> Feed this file to Claude Code at the start of a dev session. It defines scope,
> order of work, and constraints. Do not deviate from locked decisions without
> asking first. Last updated: July 10, 2026.

---

## How to use this file

This is a working spec, not a wishlist. Build in the phase order below. Do not
jump ahead to AR or polish while backend/ML core is unstable. Do not add
features, endpoints, or tables beyond what's listed — this is a 7-week solo/
small-team build on CPU-only hardware, scope creep is the main risk, not lack
of ideas.

If something in here conflicts with what you find in the codebase, stop and
ask rather than silently picking one.

---

## Locked stack (do not re-litigate)

| Layer | Tech |
|---|---|
| Frontend | Flutter |
| AR | ARCore + Flutter AR plugin |
| 3D Models | Blender → GLB/GLTF |
| Backend | Python + FastAPI |
| ML Model | YOLOv8-seg (single model, ONNX export) |
| Image Processing | OpenCV |
| Database + Storage | Supabase (free tier) |
| Model Training | Local, CPU-only (Intel Iris Xe, no discrete GPU) |
| PDF Generation | ReportLab (Python) |

Web/React/MindAR is dropped. Do not suggest it. Two-model architecture
(separate detection + segmentation) is dropped in favor of single
YOLOv8-seg. Do not suggest splitting it back out.

---

## Current status (as of July 10, 2026)

- Dataset merge (Crack500 + Roboflow set) reported complete at
  `F:\datasets_new\merged_dataset` — **not yet verified**. Before training,
  confirm:
  - Class taxonomy matches across both source sets (same crack categories,
    not e.g. "crack" vs "structural_crack")
  - Annotation format is consistent YOLO-seg polygon format throughout
    (Crack500 source is often pixel masks, Roboflow exports are usually
    YOLO polygons — these do not merge cleanly without conversion)
  - Do this by loading a random sample of ~10-15 images with their labels
    and visually overlaying the masks/polygons on the images. If they look
    wrong, fix the conversion before burning a 5-6 hour training run on bad
    labels.
- First (pre-merge, Roboflow-only) training run: 71.02% accuracy — not
  acceptable, this is why the merge happened.
- Realistic target for first merged-dataset run: ~80-85% (CPU-only,
  compressed timeline). Stated/public target: 90%+, stretch 96% — do not
  lowball this in docs/presentation, but do report the real number to
  guides honestly once available.
- ARCore-compatible physical Android device: **confirmed** — Vivo Y200 5G
  (model V2307) is on Google's official ARCore supported device list
  (Snapdragon SM4375, Adreno 619, Android API 33). This is the daily test
  device for Phase 5. Still verify "Google Play Services for AR" actually
  installs and opens cleanly on this specific unit before Phase 5 starts —
  Vivo ships its own app store by default, so Play Store access isn't
  guaranteed out of the box even though the hardware qualifies.

---

## Phased build order (conservative — includes buffer)

Target demo-ready date: **Aug 25, 2026**. This plan is padded beyond that
internally so a slipped week doesn't blow the whole schedule. Anything not
demo-ready by Aug 25 continues as polish through the rest of 7th semester
(ends Nov 9, 2026). Coordinator's stated deadlines are unreliable — work to
these dates, not his.

### Phase 0 — Dataset verification (before anything else)
- Verify merged dataset labels as described above
- Fix class taxonomy / format mismatches if found
- Confirm ARCore device availability (see above) — resolve now if missing

### Phase 1 — ML training (Jul 10–16)
- Kick off first training run on merged dataset
- YOLOv8-seg, CPU-only, expect ~5-6 hrs per run — budget for at least 2
  full runs (first pass + one retrain/tune) inside this window
- Export best checkpoint to ONNX
- Do not chase 90%+ before backend work starts — a working ~80% model
  integrated end-to-end beats a perfect model sitting unused. Retraining
  can continue in parallel with backend/frontend work in later phases.

### Phase 2 — Backend core (Jul 17–27)
- FastAPI skeleton
- Supabase schema setup (see below)
- ONNX model loading + inference wrapper
- OpenCV preprocessing pipeline
- Core endpoints: `POST /scan`, `GET /scan/{id}`, `POST /building`,
  `GET /building/{id}/scans`
- Risk classification logic (Low/Medium/High) + component ID (wall/beam/
  column/foundation) + maintenance window mapping (Immediate 0-6mo /
  Short-term 6-24mo / Long-term 2-5yr)
- Test with Postman/curl before touching Flutter — backend must work
  standalone first

### Phase 3 — Flutter frontend skeleton (Jul 28–Aug 3)
- Project setup, Android Studio config
- Camera capture + image upload UI
- Wire to `POST /scan`, display raw result (risk score, heatmap, component)
- Goal: ugly-but-functional end-to-end flow, image in → result out
- Backend and frontend work happen in parallel from this point on, not
  strictly sequential

### Phase 4 — Frontend polish + reporting (Aug 4–10)
- Scan history screen (`GET /building/{id}/scans`)
- PDF report generation (`GET /scan/{id}/report`) — see spec below
- Risk UI polish (color-coded: red/yellow/green)
- Building creation flow

### Phase 5 — AR (Aug 11–17)
- Requires confirmed ARCore device from Phase 0 — do not start this phase
  without it
- ARCore + Flutter AR plugin integration
- One preset 3D building model (Blender → GLB) — export this model before
  this phase starts, ideally during Phase 2/3 downtime, not during Phase 5
- Static placement only, no animation
- AR annotation pins on detected crack zones (from stored bbox/polygon
  data, not live depth — depth needs LiDAR, out of scope)

### Phase 6 — Integration + bug fixing (Aug 18–24)
- End-to-end test runs, full flow: capture → detect → score → report → AR
- Fix breakage from phase integration
- Build and rehearse demo script/flow

### Phase 7 — Demo (Aug 25)

### Post-demo (Aug 26 – Nov 9)
- Continue improving model accuracy toward stated 90%+ target
- Any features/polish not finished by Aug 25 continue here
- This is slack time, not new-scope time — finish what's planned before
  adding anything new

---

## Supabase schema

Keep this minimal. Do not add tables beyond this list without a concrete
reason tied to a feature already in scope.

```sql
-- users: handled by Supabase Auth, don't build custom auth

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
  component_type text check (component_type in ('wall','beam','column','foundation')),
  risk_score text check (risk_score in ('low','medium','high')),
  maintenance_window text check (maintenance_window in ('immediate','short_term','long_term')),
  created_at timestamptz default now()
);

create table crack_detections (
  id uuid primary key default gen_random_uuid(),
  scan_id uuid references scans(id) not null,
  bbox_x float, bbox_y float, bbox_w float, bbox_h float,
  confidence float,
  class_label text
);

create table reports (
  id uuid primary key default gen_random_uuid(),
  scan_id uuid references scans(id) not null,
  pdf_url text not null,
  generated_at timestamptz default now()
);
```

`crack_detections` exists to back AR annotation pins (per-crack location
data) — needed for Phase 5, don't skip it thinking it's optional.

---

## FastAPI endpoint contracts (v1 — do not exceed)

- `POST /building` — create a building. Body: `{name, location}`. Returns
  building id.
- `GET /building/{id}/scans` — scan history for a building, sorted by
  `created_at` desc.
- `POST /scan` — multipart image upload + `building_id`. Runs OpenCV
  preprocessing → YOLOv8-seg ONNX inference → risk/component/maintenance
  classification → stores image + heatmap in Supabase storage → inserts
  `scans` row + `crack_detections` rows → returns full scan result
  (scan_id, risk_score, component_type, maintenance_window, heatmap_url,
  crack detections list).
- `GET /scan/{id}` — retrieve one scan result.
- `GET /scan/{id}/report` — generate (if not cached) and return PDF via
  ReportLab.

Inference time budget: <3 sec per image. PDF gen budget: <5 sec.

---

## PDF report spec

One page. Sections, top to bottom:
1. Building name, location, scan date
2. Image with heatmap overlay
3. Risk score — large, color-coded (red/yellow/green)
4. Component type
5. Maintenance window
6. One-line plain-English summary sentence

Do not add more sections. A one-page report reads as finished in a demo; a
multi-page dump reads as unfinished.

---

## Non-negotiables / things not to suggest

- Do not propose web/React/MindAR as an alternative or fallback
- Do not propose splitting YOLOv8-seg back into two models
- Do not propose removing Maintenance Window prediction (jury-approved,
  keep it framed this way, not as "years to survive")
- Do not propose AR crack depth visualization (needs LiDAR, out of scope —
  annotation pins are the replacement)
- Do not add endpoints, tables, or features beyond what's listed here
  without flagging it as a scope change first
- Training target stays stated as 90%+ (stretch 96%) in anything
  presentation-facing, even while actual working number is lower —
  report real numbers privately/to guides, not publicly

---

## Open items to resolve before/at Phase 0

- [ ] Verify merged dataset label format/taxonomy consistency
- [x] Confirm physical ARCore-compatible Android device is in hand — Vivo Y200 5G confirmed
