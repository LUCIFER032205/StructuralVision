# Per-crack measurement — design

*2026-10-06/07. Approved in chat in three parts (user flow, backend, report + AR).*

## Why

Today one AR/tape measurement grades a whole photo: the backend takes the
**largest** crack, turns the tapped length into mm-per-pixel, and grades that one
crack. Every other crack in the photo is ignored, and false alarms (the
ceiling-edge line on scan 4ddc4f3e) can't be removed. Inspectors need a report
on the wall they photographed: every crack, its length, width and grade, and a
wall grade that follows the worst of them.

## User flow

### Result screen

- Detections are **numbered by size**: Crack 1 is the largest by area. The
  number is drawn next to each outline on the photo. Numbers are assigned over
  *all* detections and never change, so dismissing one doesn't renumber the rest.
- **Measure cracks** starts a walkthrough at the first crack still to do. That
  crack is highlighted on the photo; the panel says *Crack 2 of 3* and offers:
  - **Measure in AR** (floors, slabs, desks) or **Enter length** (tape, for
    walls, columns, beams) — chosen per crack.
  - **Skip** — stays in the report as *not measured*.
  - **Not a crack** — false alarm: removed from the count, area, risk and
    report (listed only as a footnote count).
- After each crack the walkthrough moves to the next one still to do. When
  none are left, the panel shows the wall result.
- **Details** lists every crack, e.g. `1 · 42 cm · 0.6 mm · JBDPA II`,
  `2 · skipped`, `3 · not a crack`. **Tapping a row** re-measures it or changes
  its status (Skip / Not a crack / Reset). This also replaces "measure again".
- The summary line shows the wall result: worst measured crack's width and
  grade, plus `2 of 3 measured` when some are skipped or still to do.

### AR

- AR measuring handles **one crack per visit**: the result screen opens AR for
  crack N; two taps; AR closes and hands the length back. The result screen
  submits it and moves on. (Staying in AR across cracks is out of scope.)
- The "Find this crack" card highlights **only the crack being measured**, and
  the AR top card says *Crack N of M*.
- **View in AR** only projects. Its Measure button is removed: measuring
  happens through the walkthrough only.
- **True-size projection**: once at least one crack is measured, the projected
  crack pattern is drawn at real size — photo's largest side in pixels times the
  median mm-per-pixel of the measured cracks. Before that it stays 1 m wide and
  the AR card says *Not to scale — measure a crack to show real size*.
- Cracks marked *not a crack* are left out of the projection.

## Backend

### Database (one additive migration)

```sql
alter table crack_detections
    add column if not exists status text
        check (status in ('measured','skipped','not_crack')),   -- null = to do
    add column if not exists measurement jsonb;
```

`measurement` holds the whole per-crack result, always read as a unit:

```json
{"length_cm": 42.0, "width_mm": 0.61, "width_mm_upper": 1.9, "uncertain": true,
 "resolved": true, "mm_per_px": 0.31, "standard": "JBDPA", "damage_class": "II",
 "rating": "Moderate", "residual_capacity_pct": 60.0, "risk_level": "MEDIUM"}
```

`scans` is unchanged; its width/grade columns become the **wall summary**.
`schema.sql` gets the same columns. Existing rows keep `status` null (to do).

### Endpoints

`POST /scan/{id}/measurement` is **replaced** by:

- `POST /scan/{id}/cracks/{crack_id}/measurement` `{length_cm}`
  - 404 unknown scan/crack, 409 scan not done, 422 if
    `implausible_measurement(length_cm, this crack's length_px, image_width)`
    (taps behind a wall still come back with the reason), 422 if the crack has
    no measurable length.
  - Width from **this crack** (same trough/mask method), graded with
    `measured_risk`, stored in `measurement`, `status = 'measured'`.
- `POST /scan/{id}/cracks/{crack_id}/status` `{status: skipped|not_crack|todo}`
  - Sets the status (`todo` clears it). Leaving `measured` clears `measurement`.

Both recompute the wall summary and return the full scan (with detections),
so the app just redraws. Both clear the overlay-GLB cache.

### Code changes

- `inference.width_from_measurement(length_cm, detection, gray)` grades **one
  given detection** instead of picking the largest.
- New pure `inference.summarize(detections, component_type) -> dict` of scan
  fields:
  - *not a crack* excluded from `crack_count` and `crack_area_ratio`.
  - Any measured crack: `risk_source = measured`; risk, width, standard,
    class, rating, residual capacity from the **worst** measured crack (highest
    risk, then widest).
  - None measured: `risk_source = preliminary`, risk = `compute_risk` over the
    remaining detections (so dismissing the false alarm corrects the risk
    before any measurement), grade fields cleared.
  - All dismissed: 0 cracks, LOW.
- `db.update_detection(id, fields)` and `db.update_scan(id, fields)`;
  `set_measurement` goes away.
- `overlay.build_overlay_glb` skips *not a crack* detections.

### Legacy scans

Scans measured the old way keep their scan-level grade until a crack is
measured or dismissed; then `summarize` takes over. Their cracks show as to do.

## Report

- Photo: each remaining crack outlined **and numbered**; *not a crack* not drawn.
- Per-crack table under the summary: `# | Length | Width | Grade | Risk`.
  Width shows a range when uncertain (existing "verify with a crack gauge"
  note), paint cracks grade as *Cosmetic*, skipped / to do rows say
  *not measured*. Footnote: *N detections dismissed as not a crack*. Long tables
  continue on the next page.
- Overall line: *Measured — worst crack #1: 0.64 mm, JBDPA II (Moderate). 2 of 3
  cracks measured.* Unchanged *Preliminary* line before any measurement.
- `_width_range` (re-reading the photo to rebuild the range) is deleted: each
  crack stores its own range. Legacy scans print their width without a range.
- Batch summary page: unchanged (uses the scan's count and risk).

## App changes

- `models.dart`: `CrackDetection` gains `id`, `status`, `measurement` (+ getters
  for width summary, grade summary, risk). `ScanResult` gains the size-ordered
  numbering and the worst measured crack; scan-level width/range now come from
  that crack, falling back to the legacy columns.
- `scan_api.dart`: `submitCrackMeasurement(scanId, crackId, cm)` and
  `setCrackStatus(scanId, crackId, status)`; old `submitMeasurement` removed.
- `result_screen.dart`: numbered outlines, walkthrough panel, per-crack Details
  rows with a per-row action sheet.
- `ar_screen.dart`: measure mode takes the crack to measure, highlights it,
  shows *Crack N of M*, pins the first tap, and pops with the length; no
  submitting inside AR. View mode: no Measure button, true-size scale,
  *not to scale* note.

## Testing

- `test_risk.py`: `summarize` — worst crack wins; *not a crack* excluded from
  count and area; nothing measured falls back to preliminary on the remaining
  cracks; all dismissed gives 0 / LOW. `width_from_measurement` on a given
  detection.
- `test_report.py`: per-crack rows, dismissed footnote, preliminary line
  unchanged, measured scan still renders.
- App: `flutter analyze`; device test on walls with real cracks (2026-10-07
  evening): walkthrough order, skip, not a crack (risk updates), AR one crack per
  visit, tape per crack, re-measure from Details, PDF table, true-size projection.

## Out of scope

Staying in AR across cracks; fixing the wall-plane crash; crack numbers inside
the AR projection; crack growth across re-scans.
