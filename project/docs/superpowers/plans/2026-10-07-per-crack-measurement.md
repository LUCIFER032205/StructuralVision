# Per-crack measurement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Grade every crack in a photo separately (biggest first, skip / not a crack, AR or tape per crack), roll them up into a wall grade, and print a per-crack table in the PDF.

**Architecture:** Two new columns on `crack_detections` (`status`, `measurement jsonb`) hold each crack's result. Two per-crack endpoints replace the single measurement endpoint; after each change a pure `summarize()` recomputes the scan-level (wall) fields. The app walks the cracks in size order from the result screen and opens AR for one crack at a time, which returns the tapped length.

**Tech Stack:** FastAPI + Supabase (Python 3.14), ReportLab, Flutter (Dart 3), vendored ar_flutter_plugin_2.

**Spec:** `project/docs/superpowers/specs/2026-10-06-per-crack-measurement-design.md`

## Global Constraints

- Crack numbers: rank **all** detections by `area_ratio` descending; number = rank + 1; never renumber when one is dismissed.
- `status` values: `null` (to do), `measured`, `skipped`, `not_crack`. API takes `todo` to clear.
- Worst crack = highest `risk_level` (LOW < MEDIUM < HIGH), ties broken by larger `width_mm`.
- *Not a crack* is excluded from count, area, risk, overlay GLB, report table (footnote count only).
- Backend tests run as `python test_<name>.py` (no pytest installed), from `project/backend`, with `C:\Python314\python.exe`.
- APK build needs `JAVA_HOME=F:\StructuralVision\tools\jdk-17`, `ANDROID_HOME=ANDROID_SDK_ROOT=F:\android-sdk`.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; branch `device-test-fixes-2026-10-06`.

---

### Task 1: Per-crack grading and the wall summary (backend, pure)

**Files:**
- Modify: `project/backend/inference.py` (`width_from_measurement`, new `crack_measurement`, new `summarize`)
- Test: `project/backend/test_risk.py`

**Interfaces:**
- Produces: `width_from_measurement(length_cm: float, detection: dict, gray=None) -> dict | None` (keys `width_mm, width_mm_upper, uncertain, resolved, mm_per_px, crack_type`);
  `crack_measurement(length_cm: float, detection: dict, component_type: str | None, gray=None) -> dict | None` (the `measurement` json: `length_cm, width_mm, width_mm_upper, uncertain, resolved, mm_per_px, standard, damage_class, rating, residual_capacity_pct, risk_level`);
  `summarize(detections: list[dict], component_type: str | None) -> dict` (keys `crack_count, crack_area_ratio, risk_source, risk_level, crack_width_mm, damage_standard, damage_class, damage_rating, residual_capacity_pct`).

- [ ] **Step 1: Write the failing tests** — in `test_risk.py`, change the import to also take `crack_measurement, summarize`, replace `test_width_from_measurement_uses_largest_crack` and update the two calls in `test_thin_crack_grades_off_the_photo_not_the_bloated_mask`:

```python
from inference import (measured_risk, width_from_measurement,
                       implausible_measurement, crack_measurement, summarize)


def test_width_from_measurement_grades_the_given_crack():
    d = {"area_ratio": 0.01, "length_px": 400.0, "width_px": 2.0, "crack_type": "structural"}
    w = width_from_measurement(20.0, d)                       # 200 mm * 2/400
    assert (round(w["width_mm"], 3), w["crack_type"]) == (1.0, "structural")
    assert w["uncertain"] is False                            # no photo -> mask only
    assert width_from_measurement(20.0, {"area_ratio": 0.01}) is None


def test_crack_measurement_is_the_stored_per_crack_result():
    d = {"area_ratio": 0.01, "length_px": 400.0, "width_px": 2.0, "crack_type": "structural"}
    m = crack_measurement(20.0, d, "column")
    assert (m["length_cm"], round(m["width_mm"], 3), m["damage_class"], m["standard"]) == \
        (20.0, 1.0, "II", "JBDPA")
    assert crack_measurement(20.0, {"area_ratio": 0.01}, "column") is None


def _det(area, status=None, risk=None, width=None):
    d = {"area_ratio": area, "crack_type": "structural", "status": status}
    if status == "measured":
        d["measurement"] = {"risk_level": risk, "width_mm": width, "standard": "JBDPA",
                            "damage_class": "II", "rating": "Moderate",
                            "residual_capacity_pct": 60.0}
    return d


def test_wall_summary_follows_the_worst_measured_crack():
    s = summarize([_det(0.05, "measured", "LOW", 0.1),
                   _det(0.01, "measured", "MEDIUM", 0.6), _det(0.02)], "rc_wall")
    assert (s["risk_source"], s["risk_level"], s["crack_width_mm"], s["crack_count"]) == \
        ("measured", "MEDIUM", 0.6, 3)


def test_not_a_crack_drops_out_of_count_area_and_preliminary_risk():
    # the ceiling-edge false alarm alone makes this column HIGH (0.065 * 1.5)
    assert summarize([_det(0.06), _det(0.005)], "column")["risk_level"] == "HIGH"
    s = summarize([_det(0.06, "not_crack"), _det(0.005)], "column")
    assert s["crack_count"] == 1 and abs(s["crack_area_ratio"] - 0.005) < 1e-9
    assert (s["risk_source"], s["risk_level"], s["crack_width_mm"]) == ("preliminary", "LOW", None)


def test_everything_dismissed_is_zero_cracks_low():
    s = summarize([_det(0.06, "not_crack")], "column")
    assert (s["crack_count"], s["crack_area_ratio"], s["risk_level"]) == (0, 0, "LOW")
```

In `test_thin_crack_grades_off_the_photo_not_the_bloated_mask` replace the two calls with:

```python
    mask_only = width_from_measurement(100.0, dets[0])
    with_photo = width_from_measurement(100.0, dets[0], gray)
```

- [ ] **Step 2: Run, expect failure**

Run: `cd project/backend && /c/Python314/python.exe test_risk.py`
Expected: `ImportError: cannot import name 'crack_measurement'`

- [ ] **Step 3: Implement** — in `inference.py` replace `width_from_measurement` with the single-detection version and add the two new functions right after it:

```python
def width_from_measurement(length_cm: float, detection: dict,
                           gray: "np.ndarray | None" = None) -> dict | None:
    """The real length of THIS crack (AR two-tap or tape) over its pixel length
    gives mm per pixel; that turns its pixel width into mm.

    Two pixel widths are computed because neither is reliable alone (see
    profile_width_px): the photo's intensity trough, which is accurate on thin
    cracks and under-reads on spalled patches, and the segmentation mask, which
    is roughly right on wide cracks and grossly over-reads on hairlines. The
    trough drives the grade when it is readable; the mask is kept as the upper
    bound, and when they disagree past _DISAGREE_FACTOR the caller shows both
    instead of a false-precision single number."""
    length_px, mask_width_px = detection.get("length_px"), detection.get("width_px")
    if not length_px or not mask_width_px:
        return None

    mm_per_px = length_cm * 10 / length_px
    upper = mask_width_px * mm_per_px

    photo_px, resolved = None, False
    if gray is not None:
        poly = np.asarray(detection.get("polygon") or [], dtype=float)
        if len(poly) >= 4:
            photo_px, resolved = profile_width_px(gray, poly)

    width = photo_px * mm_per_px if photo_px else upper
    # A crack that is sub-pixel along its whole length has no resolved section
    # to calibrate core contrast from, so its width is a ceiling, not a value.
    uncertain = bool(photo_px) and (not resolved
                                    or upper > _DISAGREE_FACTOR * width)
    return {"width_mm": width, "width_mm_upper": max(upper, width),
            "uncertain": uncertain, "resolved": resolved,
            "mm_per_px": mm_per_px,
            "crack_type": detection.get("crack_type") or "structural"}


def crack_measurement(length_cm: float, detection: dict, component_type: str | None,
                      gray: "np.ndarray | None" = None) -> dict | None:
    """One crack's stored result (crack_detections.measurement), or None when
    the crack has no measurable length."""
    w = width_from_measurement(length_cm, detection, gray)
    if w is None:
        return None
    g = measured_risk(w["width_mm"], component_type, w["crack_type"])
    return {"length_cm": length_cm, "width_mm": w["width_mm"],
            "width_mm_upper": w["width_mm_upper"], "uncertain": w["uncertain"],
            "resolved": w["resolved"], "mm_per_px": w["mm_per_px"],
            "standard": g["standard"], "damage_class": g["damage_class"],
            "rating": g["rating"], "residual_capacity_pct": g["residual_capacity_pct"],
            "risk_level": g["risk_level"]}


_RISK_RANK = {"LOW": 0, "MEDIUM": 1, "HIGH": 2}


def summarize(detections: list[dict], component_type: str | None) -> dict:
    """Scan-level (wall) fields after a per-crack measurement or status change.

    'Not a crack' drops out of everything. With any crack measured the wall
    takes the worst one's grade; with none, the preliminary area heuristic over
    the cracks that remain, so dismissing a false alarm corrects the risk
    before anything is measured."""
    active = [d for d in detections if d.get("status") != "not_crack"]
    measured = [d["measurement"] for d in active
                if d.get("status") == "measured" and d.get("measurement")]
    out = {"crack_count": len(active),
           "crack_area_ratio": sum(d.get("area_ratio") or 0 for d in active)}
    if measured:
        worst = max(measured, key=lambda m: (_RISK_RANK[m["risk_level"]], m["width_mm"]))
        out.update(risk_source="measured", risk_level=worst["risk_level"],
                   crack_width_mm=worst["width_mm"], damage_standard=worst["standard"],
                   damage_class=worst["damage_class"], damage_rating=worst["rating"],
                   residual_capacity_pct=worst["residual_capacity_pct"])
    else:
        out.update(risk_source="preliminary", risk_level=compute_risk(active, component_type),
                   crack_width_mm=None, damage_standard=None, damage_class=None,
                   damage_rating=None, residual_capacity_pct=None)
    return out
```

- [ ] **Step 4: Run, expect pass**

Run: `cd project/backend && /c/Python314/python.exe test_risk.py`
Expected: every line `ok test_...`, including the three new summary tests.

- [ ] **Step 5: Commit**

```bash
git add project/backend/inference.py project/backend/test_risk.py
git commit -m "Per-crack grading: width for a given crack, stored result, wall summary"
```

---

### Task 2: Per-crack endpoints, storage and migration (backend)

**Files:**
- Modify: `project/backend/db.py` (add `update_scan`, `update_detection`; delete `set_measurement`)
- Modify: `project/backend/main.py` (replace `POST /scan/{id}/measurement` with the two crack endpoints; overlay skips dismissed)
- Modify: `project/backend/schema.sql` (columns + migration note)

**Interfaces:**
- Consumes: `crack_measurement`, `summarize`, `implausible_measurement` (Task 1).
- Produces: `POST /scan/{scan_id}/cracks/{crack_id}/measurement` body `{"length_cm": float}`; `POST /scan/{scan_id}/cracks/{crack_id}/status` body `{"status": "skipped"|"not_crack"|"todo"}`. Both return the scan JSON with `detections[*].id/status/measurement`. 422 body `{"detail": "<reason>"}`.

- [ ] **Step 1: db helpers** — in `db.py` delete `set_measurement` and add:

```python
def update_scan(scan_id: str, fields: dict):
    _conn().table("scans").update(fields).eq("id", scan_id).execute()


def update_detection(detection_id: str, fields: dict):
    _conn().table("crack_detections").update(fields).eq("id", detection_id).execute()
```

- [ ] **Step 2: endpoints** — in `main.py`: import `Literal` (`from typing import Literal`), change the inference import to
`from inference import run_scan, load_models, crack_measurement, summarize, implausible_measurement`,
update the module docstring line to
`POST /scan/{id}/cracks/{crack_id}/measurement|status  JWT -> scan with per-crack grades`,
and replace `class Measurement` + `add_measurement` with:

```python
class Measurement(BaseModel):
    length_cm: float = Field(gt=0, le=1000)   # AR two-tap or tape, along the crack


class CrackStatus(BaseModel):
    status: Literal["skipped", "not_crack", "todo"]


def _crack(scan_id: str, crack_id: str, user_id: str) -> tuple[dict, dict]:
    scan = db.get_scan(scan_id, user_id)
    if scan is None:
        raise HTTPException(404, "scan not found")
    if scan["status"] != "done":
        raise HTTPException(409, f"scan is {scan['status']}")
    det = next((d for d in scan.get("detections") or [] if d["id"] == crack_id), None)
    if det is None:
        raise HTTPException(404, "crack not found")
    return scan, det


def _resummarize(scan: dict, user_id: str) -> dict:
    db.update_scan(scan["id"], summarize(scan["detections"], scan.get("component_type")))
    _overlay_glb.cache_clear()   # overlay drops dismissed cracks, label follows risk
    return db.get_scan(scan["id"], user_id)


@app.post("/scan/{scan_id}/cracks/{crack_id}/measurement")
async def measure_crack(scan_id: str, crack_id: str, m: Measurement,
                        user_id: str = Depends(current_user)):
    """Physical length of one crack -> its width -> its published grade; the
    wall takes the worst graded crack."""
    scan, det = _crack(scan_id, crack_id, user_id)
    gray = None
    try:
        photo = Image.open(io.BytesIO(db.download_image(scan_id)))
        # Taps that land on the floor behind a wall imply an absurd frame size.
        reason = implausible_measurement(m.length_cm, det.get("length_px") or 0, photo.width)
        if reason:
            raise HTTPException(422, reason)
        gray = np.asarray(photo.convert("L"))
    except HTTPException:
        raise
    except Exception:
        pass   # photo unavailable: grade off the mask alone
    meas = crack_measurement(m.length_cm, det, scan.get("component_type"), gray)
    if meas is None:
        raise HTTPException(422, "this crack has no measurable length")
    db.update_detection(crack_id, {"status": "measured", "measurement": meas})
    det.update(status="measured", measurement=meas)
    return _resummarize(scan, user_id)


@app.post("/scan/{scan_id}/cracks/{crack_id}/status")
async def set_crack_status(scan_id: str, crack_id: str, s: CrackStatus,
                           user_id: str = Depends(current_user)):
    """Skip a crack, dismiss it as not a crack, or reset it to to-do."""
    scan, det = _crack(scan_id, crack_id, user_id)
    status = None if s.status == "todo" else s.status
    db.update_detection(crack_id, {"status": status, "measurement": None})
    det.update(status=status, measurement=None)
    return _resummarize(scan, user_id)
```

In `_overlay_glb`, pass only cracks that are not dismissed:

```python
    return overlay.build_overlay_glb(
        image_bytes,
        [d for d in scan.get("detections") or [] if d.get("status") != "not_crack"],
```

- [ ] **Step 3: schema** — in `schema.sql` add to `create table crack_detections` (after `area_delta`):

```sql
    area_delta    double precision,
    -- Per-crack measurement (2026-10-07): null = to do.
    status        text check (status in ('measured','skipped','not_crack')),
    measurement   jsonb             -- length_cm, width_mm(+upper), grade, risk_level
```

and append to the migration notes:

```sql
-- Migration 2026-10-07 (per-crack measurement):
-- alter table crack_detections
--     add column if not exists status text
--         check (status in ('measured','skipped','not_crack')),
--     add column if not exists measurement jsonb;
```

- [ ] **Step 4: Verify** — `python -c "import main"` from `project/backend` imports cleanly; `test_risk.py` and `test_report.py` still pass. (Live endpoint check runs after the migration, Task 7.)

- [ ] **Step 5: Commit**

```bash
git add project/backend/db.py project/backend/main.py project/backend/schema.sql
git commit -m "Per-crack endpoints: measure one crack, skip / not a crack, wall summary"
```

---

### Task 3: Per-crack table in the PDF

**Files:**
- Modify: `project/backend/report.py`
- Test: `project/backend/test_report.py`

**Interfaces:**
- Consumes: detections with `status`, `measurement` (Task 2 shape).
- Produces: `report.numbered(detections) -> list[tuple[int, dict]]` (number, detection), largest area first, over all detections.

- [ ] **Step 1: Failing tests** — in `test_report.py` replace `test_measured_scan_report_shows_width_range` with:

```python
def _meas(w, upper=None, uncertain=False, risk="MEDIUM"):
    return {"length_cm": 42.0, "width_mm": w, "width_mm_upper": upper or w,
            "uncertain": uncertain, "resolved": True, "mm_per_px": 0.3,
            "standard": "JBDPA", "damage_class": "II", "rating": "Moderate",
            "residual_capacity_pct": 60.0, "risk_level": risk}


def _crack(area, status=None, meas=None):
    return {"polygon": [[10, 10], [80, 20], [70, 60]], "area_ratio": area,
            "crack_type": "structural", "status": status, "measurement": meas}


def _measured_scan(dets):
    return {**_scan(1, "MEDIUM", "rc_wall"), "risk_source": "measured",
            "crack_width_mm": 0.61, "damage_standard": "JBDPA", "damage_class": "II",
            "damage_rating": "Moderate", "residual_capacity_pct": 60.0,
            "crack_count": sum(d["status"] != "not_crack" for d in dets),
            "detections": dets}


def test_per_crack_table_numbers_by_size_and_footnotes_dismissed():
    scan = _measured_scan([_crack(0.02, "skipped"), _crack(0.05, "measured", _meas(0.61)),
                           _crack(0.03, "not_crack")])
    _, drawn, _ = _drawn([(scan, _jpeg())])
    assert "42 cm" in drawn and "0.61 mm" in drawn and "JBDPA II · Moderate" in drawn
    assert "not measured" in drawn
    assert "1 detection dismissed as not a crack." in drawn
    assert any("worst crack #1" in t and "1 of 2 cracks measured" in t for t in drawn), drawn


def test_uncertain_crack_width_prints_as_a_range():
    scan = _measured_scan([_crack(0.05, "measured", _meas(0.5, 1.9, uncertain=True))])
    _, drawn, _ = _drawn([(scan, _jpeg())])
    assert "0.50-1.90 mm" in drawn, drawn
```

- [ ] **Step 2: Run, expect failure** — `python test_report.py` fails on `"42 cm" in drawn`.

- [ ] **Step 3: Implement** — in `report.py`:
  1. delete `_width_range` and replace `_assessment` with the version below;
  2. add `numbered` and `_crack_table`;
  3. make `_overlay` take numbered detections and draw the numbers;
  4. in `_scan_page`, draw the overlay from `numbered(...)` and replace everything from `graded, upper = ...` to the end of the function with the new tail.

```python
from PIL import Image, ImageDraw, ImageFont


def numbered(detections: list[dict]) -> list[tuple[int, dict]]:
    """(crack number, detection), largest first. Numbers run over every
    detection so dismissing one never renumbers the rest (matches the app)."""
    order = sorted(detections, key=lambda d: d.get("area_ratio") or 0, reverse=True)
    return list(enumerate(order, 1))


def _assessment(scan: dict, rows: list[tuple[int, dict]]) -> str:
    if scan.get("risk_source") != "measured":
        return "Assessment: PRELIMINARY (image area only) - measure the cracks for a standards-based grade."
    grade = (f"{scan.get('damage_standard') or 'n/a'} class {scan.get('damage_class') or '-'} "
             f"({scan.get('damage_rating')})")
    measured = [(n, d) for n, d in rows if d.get("status") == "measured" and d.get("measurement")]
    if not measured:   # graded the old way, one length for the whole scan
        return f"Assessment: MEASURED - width {scan['crack_width_mm']:.2f} mm, {grade}"
    # Same rule as inference.summarize (risk, then width) on the per-crack
    # results: scans.crack_width_mm is a float4, so matching it back fails.
    rank = {"LOW": 0, "MEDIUM": 1, "HIGH": 2}
    worst_n, worst = max(measured, key=lambda nd: (rank[nd[1]["measurement"]["risk_level"]],
                                                   nd[1]["measurement"]["width_mm"]))
    s = (f"Assessment: MEASURED - worst crack #{worst_n}: "
         f"{worst['measurement']['width_mm']:.2f} mm, {grade}")
    if scan.get("residual_capacity_pct") is not None:
        s += f", residual capacity {scan['residual_capacity_pct']:.0f}%"
    return s + f". {len(measured)} of {len(rows)} cracks measured."


def _width_text(m: dict) -> str:
    if m.get("uncertain") and m["width_mm_upper"] > m["width_mm"]:
        return f"{m['width_mm']:.2f}-{m['width_mm_upper']:.2f} mm"
    return f"{m['width_mm']:.2f} mm"


def _grade_text(m: dict) -> str:
    if not m.get("standard"):
        return "Cosmetic"
    std = "BRE 251 cat." if m["standard"] == "BRE251" else "JBDPA"
    return f"{std} {m['damage_class']} · {m['rating']}"


def _crack_table(c, rows: list[tuple[int, dict]], y: float) -> float:
    """# | Length | Width | Grade | Risk, one row per crack; spills onto a new
    page when long. -> y below the table."""
    w, h = A4
    cols = (2 * cm, 3.2 * cm, 6 * cm, 10 * cm, 16.5 * cm)
    c.setFillColorRGB(0, 0, 0)
    c.setFont("Helvetica-Bold", 10)
    for x, label in zip(cols, ("#", "Length", "Width", "Grade", "Risk")):
        c.drawString(x, y, label)
    c.setLineWidth(0.5)
    c.line(2 * cm, y - 0.15 * cm, w - 2 * cm, y - 0.15 * cm)
    c.setFont("Helvetica", 10)
    for n, d in rows:
        y -= 0.55 * cm
        if y < 2 * cm:
            c.showPage()
            c.setFont("Helvetica", 10)
            y = h - 2.5 * cm
        c.setFillColorRGB(0, 0, 0)
        c.drawString(cols[0], y, str(n))
        m = d.get("measurement") if d.get("status") == "measured" else None
        if m is None:
            c.setFillColorRGB(0.45, 0.45, 0.45)
            c.drawString(cols[1], y, "—")
            c.drawString(cols[2], y, "—")
            c.drawString(cols[3], y, "not measured")
            continue
        c.drawString(cols[1], y, f"{m['length_cm']:.0f} cm")
        c.drawString(cols[2], y, _width_text(m))
        c.drawString(cols[3], y, _grade_text(m))
        c.setFillColorRGB(*_RISK_COLORS.get(m["risk_level"], (0.5, 0.5, 0.5)))
        c.drawString(cols[4], y, m["risk_level"])
    c.setFillColorRGB(0, 0, 0)
    return y - 0.5 * cm


def _overlay(image_bytes: bytes, rows: list[tuple[int, dict]]) -> Image.Image:
    img = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    draw = ImageDraw.Draw(img, "RGBA")
    font = ImageFont.load_default(size=max(14, img.width // 40))
    for n, d in rows:
        poly = [tuple(p) for p in d["polygon"]]
        if len(poly) >= 3:
            draw.polygon(poly, fill=(255, 40, 40, 80), outline=(255, 40, 40, 255), width=3)
            x, y = min(p[0] for p in poly), min(p[1] for p in poly)
            draw.text((x, y), str(n), fill=(255, 255, 255, 255), font=font,
                      stroke_width=3, stroke_fill=(0, 0, 0, 255), anchor="rb")
    return img
```

In `_scan_page`, right after the date line:

```python
    rows = [(n, d) for n, d in numbered(scan.get("detections", []))
            if d.get("status") != "not_crack"]
    dismissed = len(scan.get("detections", [])) - len(rows)
    img = _overlay(image_bytes, rows)
```

(replacing `img = _overlay(image_bytes, scan.get("detections", []))`), and replace the tail from `graded, upper = (...)` onwards with:

```python
    c.drawString(2 * cm, y - 3.2 * cm, _assessment(scan, rows))
    below = y - 4.0 * cm
    if rows:
        below = _crack_table(c, rows, below)
    c.setFont("Helvetica-Oblique", 9)
    if any(d.get("measurement") and d["measurement"].get("uncertain") for _, d in rows):
        c.drawString(2 * cm, below, _RANGE_NOTE)
        below -= 0.45 * cm
    if dismissed:
        c.drawString(2 * cm, below,
                     f"{dismissed} detection{'s' if dismissed != 1 else ''} dismissed as not a crack.")
        below -= 0.45 * cm
    standards = {d["measurement"]["standard"] for _, d in rows
                 if d.get("measurement") and d["measurement"].get("standard")}
    if scan.get("damage_standard"):
        standards.add(scan["damage_standard"])
    c.setFont("Helvetica", 8)
    for std in sorted(standards):
        c.drawString(2 * cm, below, _STANDARD_REF[std])
        below -= 0.4 * cm
```

Also change `_RANGE_NOTE` to the per-crack wording:

```python
_RANGE_NOTE = ("A width range means the photo's intensity profile and the segmentation mask "
               "disagree on that crack. Graded on the lower figure; verify with a crack gauge.")
```

and delete the now-unused `_DISAGREE = 2.0`.

- [ ] **Step 4: Run, expect pass** — `python test_report.py`: all `ok`, including the existing batch tests.

- [ ] **Step 5: Commit**

```bash
git add project/backend/report.py project/backend/test_report.py
git commit -m "Report: numbered cracks and a per-crack table, dismissed cracks footnoted"
```

---

### Task 4: App model and API for per-crack data

**Files:**
- Modify: `project/app/lib/models.dart`
- Modify: `project/app/lib/scan_api.dart`

**Interfaces:**
- Produces (Dart):
  - `CrackDetection`: `String id`, `String? status`, `Map<String, dynamic>? measurement`, getters `bool isDismissed`, `bool isMeasured`, `bool isSkipped`, `bool isTodo`, `double? lengthCm`, `double? mmPerPx`, `bool uncertain`, `bool resolved`, `String? riskLevel`, `String? widthSummary`, `String? gradeSummary`.
  - `ScanResult`: `List<int> bySize` (detection indices, largest first), `int numberOf(int i)`, `List<int> activeBySize`, `int? get nextToMeasure`, `CrackDetection? get worstMeasured`, `int get measuredCount`, `double? get trueSizeMmPerPx` (median over measured); existing `widthSummary`, `gradeSummary`, `widthUncertain`, `resolutionHint` now read the worst measured crack (legacy scan columns as fallback).
  - `ScanApi.submitCrackMeasurement(String scanId, String crackId, double lengthCm) -> Future<ScanResult>` (throws `MeasurementRejected` on 422), `ScanApi.setCrackStatus(String scanId, String crackId, String status) -> Future<ScanResult>`.

- [ ] **Step 1: models** — replace `CrackDetection` and the derived-width part of `ScanResult` in `models.dart` with:

```dart
class CrackDetection {
  final String id;
  final List<double> bbox; // [x1,y1,x2,y2] pixels
  final List<List<double>> polygon; // [[x,y],...] pixels
  final double confidence;
  final double areaRatio;
  final double lengthPx;
  final double widthPx;
  final String? growthStatus; // new | grown | stable (only on re-scan)
  final String crackType; // structural | paint
  /// null = to do; measured | skipped | not_crack
  final String? status;
  /// This crack's graded result once measured (see backend crack_measurement).
  final Map<String, dynamic>? measurement;

  CrackDetection({
    this.id = '',
    required this.bbox,
    required this.polygon,
    required this.confidence,
    required this.areaRatio,
    this.lengthPx = 0,
    this.widthPx = 0,
    this.growthStatus,
    this.crackType = 'structural',
    this.status,
    this.measurement,
  });

  bool get isDismissed => status == 'not_crack';
  bool get isSkipped => status == 'skipped';
  bool get isTodo => status == null;
  bool get isMeasured => status == 'measured' && measurement != null;

  double? _num(String k) => (measurement?[k] as num?)?.toDouble();
  double? get lengthCm => _num('length_cm');
  double? get mmPerPx => _num('mm_per_px');
  bool get uncertain => measurement?['uncertain'] as bool? ?? false;
  bool get resolved => measurement?['resolved'] as bool? ?? true;
  String? get riskLevel => measurement?['risk_level'] as String?;

  /// "0.42 mm" or "0.42–2.10 mm" when the photo and the mask disagree.
  String? get widthSummary {
    final w = _num('width_mm');
    if (!isMeasured || w == null) return null;
    final upper = _num('width_mm_upper');
    return uncertain && upper != null && upper > w
        ? '${w.toStringAsFixed(2)}–${upper.toStringAsFixed(2)} mm'
        : '${w.toStringAsFixed(2)} mm';
  }

  /// "JBDPA II · Moderate", "BRE 251 cat. 2 · Aesthetic", or "Cosmetic".
  String? get gradeSummary {
    if (!isMeasured) return null;
    final std = measurement!['standard'] as String?;
    if (std == null) return 'Cosmetic';
    return '${std == 'BRE251' ? 'BRE 251 cat.' : 'JBDPA'} '
        '${measurement!['damage_class']} · ${measurement!['rating']}';
  }

  factory CrackDetection.fromJson(Map<String, dynamic> j) => CrackDetection(
        id: j['id'] as String? ?? '',
        bbox: (j['bbox'] as List).map((e) => (e as num).toDouble()).toList(),
        polygon: (j['polygon'] as List)
            .map((p) =>
                (p as List).map((e) => (e as num).toDouble()).toList())
            .toList(),
        confidence: (j['confidence'] as num).toDouble(),
        areaRatio: (j['area_ratio'] as num).toDouble(),
        lengthPx: (j['length_px'] as num?)?.toDouble() ?? 0,
        widthPx: (j['width_px'] as num?)?.toDouble() ?? 0,
        growthStatus: j['growth_status'] as String?,
        crackType: j['crack_type'] as String? ?? 'structural',
        status: j['status'] as String?,
        measurement: j['measurement'] as Map<String, dynamic>?,
      );
}
```

In `ScanResult`: remove the fields and constructor params `widthMmUpper`, `widthUncertain`, `widthResolved`, `mmPerPx` and their `fromJson` lines (the backend no longer sends them), and replace `resolutionHint` and `widthSummary` with:

```dart
  /// Detection indices, largest crack first. Crack number = position + 1,
  /// over every detection, so dismissing one never renumbers the rest.
  List<int> get bySize => List.generate(detections.length, (i) => i)
    ..sort((a, b) => detections[b].areaRatio.compareTo(detections[a].areaRatio));
  int numberOf(int i) => bySize.indexOf(i) + 1;
  List<int> get activeBySize =>
      bySize.where((i) => !detections[i].isDismissed).toList();
  int? get nextToMeasure {
    for (final i in activeBySize) {
      if (detections[i].isTodo) return i;
    }
    return null;
  }

  int get measuredCount => detections.where((d) => d.isMeasured).length;

  /// The crack the wall grade comes from (backend summarize: risk, then width).
  CrackDetection? get worstMeasured {
    const rank = {'LOW': 0, 'MEDIUM': 1, 'HIGH': 2};
    CrackDetection? worst;
    for (final d in detections.where((d) => d.isMeasured)) {
      if (worst == null ||
          (rank[d.riskLevel] ?? 0) > (rank[worst.riskLevel] ?? 0) ||
          ((rank[d.riskLevel] ?? 0) == (rank[worst.riskLevel] ?? 0) &&
              (d.measurement!['width_mm'] as num) > (worst.measurement!['width_mm'] as num))) {
        worst = d;
      }
    }
    return worst;
  }

  /// Median mm-per-pixel over the measured cracks: the photo's real scale,
  /// for the true-size AR projection. Null until something is measured.
  double? get trueSizeMmPerPx {
    final v = detections.map((d) => d.mmPerPx).whereType<double>().toList()..sort();
    return v.isEmpty ? null : v[v.length ~/ 2];
  }

  bool get widthUncertain => worstMeasured?.uncertain ?? false;

  /// Advice when the worst crack is finer than the photo can resolve.
  String? get resolutionHint {
    final w = worstMeasured;
    if (w == null || w.resolved) return null;
    final mmpp = w.mmPerPx;
    return mmpp == null
        ? 'Crack is finer than this photo can resolve — re-shoot closer.'
        : 'Crack is finer than this photo can resolve '
            '(1 pixel ≈ ${mmpp.toStringAsFixed(2)} mm). Width shown is an upper '
            'bound — re-shoot closer or zoom in for a real measurement.';
  }

  /// Worst crack's width; legacy scans (one length for the whole photo) fall
  /// back to the stored scan width.
  String? get widthSummary =>
      worstMeasured?.widthSummary ??
      (crackWidthMm == null ? null : '${crackWidthMm!.toStringAsFixed(2)} mm');
```

(`gradeSummary` on `ScanResult` stays as it is: it reads the scan-level columns, which `summarize` keeps equal to the worst crack.)

- [ ] **Step 2: API** — in `scan_api.dart` replace `submitMeasurement` with:

```dart
  /// POST /scan/{id}/cracks/{crackId}/measurement — one crack's real length
  /// (AR two-tap or tape); backend grades that crack and the wall.
  Future<ScanResult> submitCrackMeasurement(
      String scanId, String crackId, double lengthCm) =>
      _postCrack('$scanId/cracks/$crackId/measurement', {'length_cm': lengthCm});

  /// POST /scan/{id}/cracks/{crackId}/status — skipped | not_crack | todo.
  Future<ScanResult> setCrackStatus(String scanId, String crackId, String status) =>
      _postCrack('$scanId/cracks/$crackId/status', {'status': status});

  Future<ScanResult> _postCrack(String path, Map<String, dynamic> body) async {
    final res = await http
        .post(
          Uri.parse('${AppConfig.apiBase}/scan/$path'),
          headers: {
            'Authorization': 'Bearer $_jwt',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode == 422) {
      final decoded = jsonDecode(res.body);
      final detail = decoded is Map ? decoded['detail'] : null;
      throw MeasurementRejected(
          detail is String ? detail : 'That measurement does not look right.');
    }
    if (res.statusCode != 200) {
      throw Exception('request failed (${res.statusCode}): ${res.body}');
    }
    return ScanResult.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }
```

- [ ] **Step 3: Verify** — `flutter analyze lib/models.dart lib/scan_api.dart` reports only the expected errors in `result_screen.dart`/`ar_screen.dart` callers (fixed in Tasks 5–6); no errors inside these two files.

- [ ] **Step 4: Commit** (together with Task 5, since the app doesn't compile in between).

---

### Task 5: Result screen — numbered cracks, walkthrough, per-crack rows

**Files:**
- Modify: `project/app/lib/screens/result_screen.dart`

**Interfaces:**
- Consumes: Task 4 model/API; `ArScreen(result:, photo:, measureCrack: int?)` returning `Future<double?>` (Task 6).
- Produces: `CrackOverlayPainter(ui.Image image, List<CrackDetection> detections, Color color, int? selected, {List<int>? numbers})` — `numbers[i]` is the crack number of detection `i`; dismissed detections are not drawn.

- [ ] **Step 1: Painter** — replace `CrackOverlayPainter` with:

```dart
class CrackOverlayPainter extends CustomPainter {
  final ui.Image         image;
  final List<CrackDetection> detections;
  final Color            color;
  final int?             selected;
  /// Crack number per detection index (largest = 1); null draws no numbers.
  final List<int>?       numbers;

  CrackOverlayPainter(this.image, this.detections, this.color, this.selected,
      {this.numbers});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImage(image, Offset.zero, Paint());
    // Stroke scales with image size so it stays visible on 4000px photos.
    final unit = size.longestSide / 1024;

    for (var i = 0; i < detections.length; i++) {
      final d = detections[i];
      if (d.polygon.length < 3 || d.isDismissed) continue;
      // Backend keeps detections at conf >= 0.4: map 0.4..1 -> 0..1 so a
      // weak detection draws thin and faint, a strong one thick and solid.
      final t = ((d.confidence - 0.4) / 0.6).clamp(0.0, 1.0);
      final c = d.crackType == 'paint' ? Colors.blueGrey : color;
      final isSel = i == selected;
      final path = _pathOf(d.polygon);
      canvas.drawPath(path, Paint()..color = c.withValues(alpha: 0.15 + 0.25 * t));
      canvas.drawPath(
          path,
          Paint()
            ..color = isSel ? Colors.white : c.withValues(alpha: 0.45 + 0.55 * t)
            ..style = PaintingStyle.stroke
            ..strokeWidth = (isSel ? 5.0 : 1.5 + 3.5 * t) * unit);
      final n = numbers?[i];
      if (n != null) _label(canvas, '$n', path.getBounds().topLeft, unit, isSel);
    }
  }

  void _label(Canvas canvas, String text, Offset at, double unit, bool sel) {
    final r = 16 * unit;
    final centre = at.translate(-r * 0.4, -r * 0.4);
    canvas.drawCircle(centre, r, Paint()..color = sel ? Colors.white : Colors.black87);
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(
              color: sel ? Colors.black : Colors.white,
              fontSize: 18 * unit,
              fontWeight: FontWeight.w700)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, centre - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant CrackOverlayPainter old) =>
      old.image != image ||
      old.detections != detections ||
      old.selected != selected ||
      old.color != color ||
      old.numbers != numbers;
}
```

- [ ] **Step 2: State and actions** — in `_ResultScreenState` replace `_enterLengthManually`, `_openAr`, `_chooseMeasureMethod` with the per-crack versions, and add `_walk` (detection index being walked, null when not walking):

```dart
  int? _walk; // detection index the walkthrough is on; null = not walking
  List<int> get _numbers =>
      List.generate(result.detections.length, (i) => result.numberOf(i));

  /// Tape reading for one crack: the only route for wall, column and beam
  /// cracks, since ARCore's vertical-plane mode SIGSEGVs on the vivo.
  Future<double?> _askLength(int i) async {
    final controller = TextEditingController();
    return showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Crack ${result.numberOf(i)} length'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Measure this crack end to end with a tape and enter it in '
              'centimetres. This scales the photo so its width can be graded.',
              style: AppTextStyles.bodySm,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Length', suffixText: 'cm'),
              onSubmitted: (v) =>
                  Navigator.of(ctx).pop(double.tryParse(v.trim().replaceAll(',', '.'))),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(ctx)
                .pop(double.tryParse(controller.text.trim().replaceAll(',', '.'))),
            child: const Text('Grade'),
          ),
        ],
      ),
    );
  }

  Future<void> _measure(int i, {required bool ar}) async {
    final double? cm;
    if (ar) {
      final photo = await _image;
      if (!mounted) return;
      cm = await Navigator.of(context).push<double>(MaterialPageRoute(
          builder: (_) => ArScreen(result: result, photo: photo, measureCrack: i)));
    } else {
      cm = await _askLength(i);
    }
    if (cm == null || !mounted) return;
    if (cm <= 0 || cm > 1000) {
      _snack('Enter a length between 0 and 1000 cm');
      return;
    }
    await _send(() => scanApi.submitCrackMeasurement(
        result.id, result.detections[i].id, cm!));
  }

  Future<void> _setStatus(int i, String status) =>
      _send(() => scanApi.setCrackStatus(result.id, result.detections[i].id, status));

  /// One request, then redraw and, mid-walkthrough, move to the next crack.
  Future<void> _send(Future<ScanResult> Function() call) async {
    setState(() => _grading = true);
    try {
      final updated = await call();
      if (!mounted) return;
      setState(() {
        result = updated;
        if (_walk != null) {
          _walk = result.nextToMeasure;
          if (_walk == null) _snack('All cracks done');
        }
      });
    } on MeasurementRejected catch (e) {
      _snack(e.message, seconds: 5);
    } catch (e) {
      _snack('Could not save: $e');
    } finally {
      if (mounted) setState(() => _grading = false);
    }
  }

  Future<void> _openAr() async {
    final photo = await _image;
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ArScreen(result: result, photo: photo)));
  }

  /// Per-crack actions from a Details row.
  Future<void> _crackActions(int i) async {
    final d = result.detections[i];
    final pick = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (ctx) {
        Widget tile(String v, IconData icon, String title, String sub) => ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: kPagePadding),
              leading: Icon(icon, color: AppColors.accent),
              title: Text(title, style: AppTextStyles.titleMd),
              subtitle: Text(sub, style: AppTextStyles.bodySm),
              onTap: () => Navigator.of(ctx).pop(v),
            );
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            tile('ar', Icons.view_in_ar, 'Measure in AR', 'Floor and slab cracks'),
            tile('tape', Icons.edit_outlined, 'Enter length', 'Walls, columns, beams — tape'),
            if (!d.isSkipped)
              tile('skipped', Icons.redo_rounded, 'Skip', 'Keep it, mark not measured'),
            if (!d.isDismissed)
              tile('not_crack', Icons.block_rounded, 'Not a crack', 'Remove a false alarm'),
            if (!d.isTodo)
              tile('todo', Icons.undo_rounded, 'Reset', 'Back to to-do'),
          ]),
        );
      },
    );
    if (pick == null || !mounted) return;
    if (pick == 'ar' || pick == 'tape') {
      await _measure(i, ar: pick == 'ar');
    } else {
      await _setStatus(i, pick);
    }
  }
```

Also: `_onImageTap` keeps setting `_selected`; the painter call becomes
`CrackOverlayPainter(img, result.detections, color, _walk ?? _selected, numbers: _numbers)`.

- [ ] **Step 3: Panel** — in `build`, set `final noCracks = result.activeBySize.isEmpty;` and replace the block from `// Preliminary -> measured` through the `Measure crack` button with:

```dart
                    if (_walk != null)
                      _walkPanel(_walk!)
                    else if (result.nextToMeasure != null) ...[
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        icon: const Icon(Icons.straighten, size: 18),
                        label: Text(result.measuredCount == 0
                            ? 'Measure cracks'
                            : 'Continue measuring'),
                        onPressed: _grading
                            ? null
                            : () => setState(() => _walk = result.nextToMeasure),
                      ),
                    ],
```

and add:

```dart
  Widget _walkPanel(int i) {
    final active = result.activeBySize;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Crack ${result.numberOf(i)} · ${active.indexOf(i) + 1} of ${active.length}',
              style: AppTextStyles.titleMd),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.view_in_ar, size: 18),
                label: const Text('AR'),
                onPressed: _grading ? null : () => _measure(i, ar: true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                icon: _grading
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.bg))
                    : const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Tape'),
                onPressed: _grading ? null : () => _measure(i, ar: false),
              ),
            ),
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            TextButton(
                onPressed: _grading ? null : () => _setStatus(i, 'skipped'),
                child: const Text('Skip')),
            TextButton(
                onPressed: _grading ? null : () => _setStatus(i, 'not_crack'),
                child: const Text('Not a crack')),
            TextButton(
                onPressed: () => setState(() => _walk = null),
                style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
                child: const Text('Stop')),
          ]),
        ],
      ),
    );
  }
```

Replace `_summary` with:

```dart
  String _summary(bool noCracks) {
    if (noCracks) {
      return result.detections.isEmpty
          ? 'No cracks detected. Hairlines in poor light can be missed, '
              're-scan closer if you can see one.'
          : 'Every detection was dismissed as not a crack.';
    }
    final active = result.activeBySize.length;
    if (result.isMeasured) {
      final worst = result.worstMeasured;
      final head = worst == null
          ? 'Measured: ${result.widthSummary} · ${result.gradeSummary}'
          : 'Worst: crack ${result.numberOf(result.detections.indexOf(worst))} · '
              '${worst.widthSummary} · ${result.gradeSummary}';
      return '$head · ${result.measuredCount} of $active measured';
    }
    final area = ((result.crackAreaRatio ?? 0) * 100).toStringAsFixed(2);
    return '$active crack${active == 1 ? '' : 's'} · $area% of surface · preliminary';
  }
```

and in `_details()` put the per-crack rows first (before the paint/tap tips):

```dart
        for (final i in result.bySize)
          InkWell(
            onTap: _grading ? null : () => _crackActions(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(children: [
                SizedBox(
                  width: 28,
                  child: Text('${result.numberOf(i)}', style: AppTextStyles.titleSm),
                ),
                Expanded(child: Text(_rowText(result.detections[i]),
                    style: result.detections[i].isDismissed
                        ? AppTextStyles.bodySm.copyWith(
                            decoration: TextDecoration.lineThrough)
                        : AppTextStyles.bodyMd)),
                if (result.detections[i].riskLevel != null)
                  RiskBadge(result.detections[i].riskLevel!),
                const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
              ]),
            ),
          ),
```

with

```dart
  String _rowText(CrackDetection d) {
    if (d.isDismissed) return 'not a crack';
    if (d.isSkipped) return 'skipped';
    if (!d.isMeasured) return 'to do';
    return '${d.lengthCm!.toStringAsFixed(0)} cm · ${d.widthSummary} · ${d.gradeSummary}';
  }
```

The Details toggle shows whenever `result.detections.isNotEmpty` (not only when cracks remain), so a dismissed crack can be restored.

- [ ] **Step 4: Verify** — `flutter analyze lib` clean after Task 6.

---

### Task 6: AR — one crack per visit, true-size projection

**Files:**
- Modify: `project/app/lib/screens/ar_screen.dart`

**Interfaces:**
- Consumes: Task 4 model (`numberOf`, `activeBySize`, `trueSizeMmPerPx`), Task 5 painter (`numbers:`).
- Produces: `ArScreen({required ScanResult result, ui.Image? photo, int? measureCrack})`; in measure mode the route pops with the tapped length in cm (`double`), or null when backed out.

- [ ] **Step 1:** Constructor: replace `startMeasuring` with `final int? measureCrack;` (doc: *detection index to measure; null = view mode*). `late bool _measuring = widget.measureCrack != null;`. Delete `_submitMeasurement`, `_grading`, `_measureCm`, `_setOverlayHidden`, the `PopScope` wrapper and the `floatingActionButton`. Keep `_result` as `widget.result` (final).

- [ ] **Step 2:** In `_onTap`, the measuring branch becomes:

```dart
    if (_measuring) {
      final p = hit.worldTransform.getTranslation();
      if (_measureStart == null) {
        setState(() => _measureStart = p);
        _dropStartPin(hit.worldTransform);
        _toast('Point 1 set — tap the other end of the crack');
      } else {
        // One crack per visit: hand the length back; the result screen
        // submits it and moves the walkthrough on.
        Navigator.of(context).pop(_measureStart!.distanceTo(p) * 100);
      }
      return;
    }
```

- [ ] **Step 3:** True size. Add:

```dart
  /// Real size of the projected crack pattern once any crack is measured:
  /// the photo's longest side times the photo's measured mm-per-pixel.
  double? get _trueSizeM {
    final mmpp = widget.result.trueSizeMmPerPx;
    final photo = widget.photo;
    if (mmpp == null || photo == null) return null;
    return (photo.width > photo.height ? photo.width : photo.height) * mmpp / 1000;
  }
```

and use `scale: vm.Vector3.all(_hasCracks ? (_trueSizeM ?? 1.0) : 0.2)` for the placed node. `_hasCracks` becomes `widget.result.activeBySize.isNotEmpty`.

- [ ] **Step 4:** Card text. Measuring line:

```dart
                    if (_measuring)
                      Text(
                          _measureStart == null
                              ? 'Crack ${widget.result.numberOf(widget.measureCrack!)} of '
                                  '${widget.result.activeBySize.length}: point the camera at '
                                  'the real crack shown bottom-left, then tap one end'
                              : 'Now tap the other end of the same crack',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
```

After placement in view mode, when `_trueSizeM == null`: add a line
`'Not to scale — measure a crack to show real size'` (white70, italic).
Delete the `else if (_measureCm != null)` branch.

- [ ] **Step 5:** Reference card: pass `selected: widget.measureCrack` and the numbers to `_CrackReference`, which forwards them:
`CrackOverlayPainter(photo, detections, color, selected, numbers: numbers)`; numbers = `List.generate(result.detections.length, result.numberOf)`.

- [ ] **Step 6: Verify** — `flutter analyze` clean; build APK.

- [ ] **Step 7: Commit (Tasks 4–6)**

```bash
git add project/app/lib
git commit -m "App: measure every crack, biggest first; skip / not a crack; one crack per AR visit; true-size projection"
```

---

### Task 7: Migrate, deploy, smoke-test

- [ ] **Step 1:** Show the user the migration SQL (Task 2 Step 3) and get an explicit yes before applying it to the live Supabase project (`apply_migration`).
- [ ] **Step 2:** Restart the backend; run a smoke test with FastAPI `TestClient` (current_user overridden to the scan owner) on one existing scan: status `not_crack` on its largest crack → `crack_count` drops and risk recomputes; status `todo` restores it; a measurement on a crack returns `status: measured` with a `measurement` object; an absurd length (e.g. 400 cm for a short crack) returns 422 with a reason. Reset the crack afterwards.
- [ ] **Step 3:** Build + install the APK (copy to `backend/static/structural_vision_ar.apk`).
- [ ] **Step 4:** Leave the device checklist (spec "Testing") for the user's evening session.
