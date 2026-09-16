"""
report.py — one-page PDF scan report (ReportLab), per dev_plan spec:
image with crack overlay, big color-coded risk, component, summary sentence.
"""
import io

from PIL import Image, ImageDraw
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import cm
from reportlab.pdfgen import canvas

_RISK_COLORS = {"HIGH": (0.86, 0.16, 0.16), "MEDIUM": (1.0, 0.59, 0.0), "LOW": (0.16, 0.67, 0.24)}
_MAINTENANCE = {"HIGH": "Immediate (0–6 months)", "MEDIUM": "Short-term (6–24 months)", "LOW": "Long-term (2–5 years)"}

def _summary(risk: str, component: str, crack_count: int) -> str:
    c = _COMPONENT_LABEL.get(component, component or "structure").lower()
    if crack_count == 0:
        return f"No significant cracking detected on {c}."
    if risk == "HIGH":
        return f"Significant cracking detected on {c}. Immediate structural inspection recommended."
    if risk == "MEDIUM":
        return f"Moderate cracking detected on {c}. Schedule inspection within 6–24 months."
    return f"Minor cracking detected on {c}. Monitor and reinspect within 2–5 years."


# Display names for the app's component values (matches the app's picker).
_COMPONENT_LABEL = {"wall": "Brick wall", "rc_wall": "RC wall", "beam": "Beam",
                    "column": "Column", "slab": "Slab", "ceiling": "Ceiling"}


def _component(scan: dict) -> str:
    v = scan.get("component_type")
    return _COMPONENT_LABEL.get(v, v or "Not specified")


_STANDARD_REF = {
    "JBDPA": "Graded per JBDPA damage guideline: Nakano, Maeda, Kuramoto & Murakami, 13WCEE 2004, Paper 124 (Tables 2-3).",
    "BRE251": "Graded per BRE Digest 251, Assessment of damage in low-rise buildings (rev. 1995), masonry categories 0-5.",
}


def _width_range(scan: dict, image: Image.Image) -> tuple[float, float]:
    """Recompute the graded width's upper bound from the stored detections and
    the photo, so no extra column is needed. -> (graded_mm, upper_mm)."""
    import numpy as np
    from inference import profile_width_px, _DISAGREE_FACTOR

    graded = scan.get("crack_width_mm") or 0.0
    dets = scan.get("detections") or []
    if not dets or not graded:
        return graded, graded
    d = max(dets, key=lambda x: x.get("area_ratio") or 0)
    poly = np.asarray(d.get("polygon") or [], dtype=float)
    if not d.get("width_px") or len(poly) < 4:
        return graded, graded
    trough = profile_width_px(np.asarray(image.convert("L")), poly)
    if not trough:
        return graded, graded
    # graded came from the trough width, so scale it up by the mask ratio
    upper = graded * d["width_px"] / trough
    return graded, max(upper, graded)


def _assessment(scan: dict, upper: float | None = None) -> str:
    if scan.get("risk_source") != "measured":
        return "Assessment: PRELIMINARY (image area only) - measure crack in AR for a standards-based grade."
    w = scan["crack_width_mm"]
    width = (f"width {w:.2f}-{upper:.2f} mm" if upper and upper > w * _DISAGREE
             else f"width {w:.2f} mm")
    s = (f"Assessment: MEASURED - {width}, "
         f"{scan.get('damage_standard') or 'n/a'} class {scan.get('damage_class') or '-'} "
         f"({scan.get('damage_rating')})")
    if scan.get("residual_capacity_pct") is not None:
        s += f", residual capacity {scan['residual_capacity_pct']:.0f}%"
    return s


_DISAGREE = 2.0
_RANGE_NOTE = ("Width is a range: the photo's intensity profile and the segmentation mask "
               "disagree on this crack. Graded on the lower figure; verify with a crack gauge.")


def _overlay(image_bytes: bytes, detections: list[dict]) -> Image.Image:
    img = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    draw = ImageDraw.Draw(img, "RGBA")
    for d in detections:
        poly = [tuple(p) for p in d["polygon"]]
        if len(poly) >= 3:
            draw.polygon(poly, fill=(255, 40, 40, 80), outline=(255, 40, 40, 255), width=3)
    return img


def _scan_page(c, scan: dict, image_bytes: bytes, title: str) -> None:
    """Draw one scan onto the current page of canvas [c]."""
    risk = scan.get("risk_level") or "LOW"
    color = _RISK_COLORS.get(risk, (0.5, 0.5, 0.5))
    w, h = A4

    c.setFillColorRGB(0, 0, 0)
    c.setFont("Helvetica-Bold", 20)
    c.drawString(2 * cm, h - 2.5 * cm, title)
    c.setFont("Helvetica", 11)
    c.drawString(2 * cm, h - 3.3 * cm, f"Scan ID: {scan['id']}")
    c.drawString(2 * cm, h - 3.9 * cm, f"Date: {scan.get('created_at', '')[:19].replace('T', ' ')}")

    img = _overlay(image_bytes, scan.get("detections", []))
    img_buf = io.BytesIO()
    img.save(img_buf, "JPEG", quality=85)
    img_buf.seek(0)
    max_w, max_h = w - 4 * cm, 11 * cm
    scale = min(max_w / img.width, max_h / img.height)
    iw, ih = img.width * scale, img.height * scale
    from reportlab.lib.utils import ImageReader
    c.drawImage(ImageReader(img_buf), (w - iw) / 2, h - 4.7 * cm - ih, iw, ih)

    y = h - 5.7 * cm - max_h
    c.setFillColorRGB(*color)
    c.roundRect(2 * cm, y - 0.4 * cm, 5 * cm, 1.6 * cm, 0.2 * cm, stroke=0, fill=1)
    c.setFillColorRGB(1, 1, 1)
    c.setFont("Helvetica-Bold", 22)
    c.drawCentredString(4.5 * cm, y + 0.1 * cm, risk)

    c.setFillColorRGB(0, 0, 0)
    c.setFont("Helvetica", 12)
    c.drawString(8 * cm, y + 0.6 * cm,
                 f"Component: {_component(scan)}")
    c.drawString(8 * cm, y,
                 f"Cracks: {scan.get('crack_count', 0)}   "
                 f"Area: {(scan.get('crack_area_ratio') or 0) * 100:.2f}%")

    c.setFont("Helvetica-Oblique", 12)
    c.drawString(2 * cm, y - 1.6 * cm, _summary(risk, scan.get("component_type"), scan.get("crack_count", 0)))
    c.setFont("Helvetica", 11)
    c.drawString(2 * cm, y - 2.4 * cm, f"Maintenance window: {_MAINTENANCE.get(risk, '')}")
    graded, upper = ((0.0, 0.0) if scan.get("risk_source") != "measured"
                     else _width_range(scan, img))
    c.drawString(2 * cm, y - 3.2 * cm, _assessment(scan, upper))
    below = y - 3.8 * cm
    if upper > graded * _DISAGREE:
        c.setFont("Helvetica-Oblique", 9)
        c.drawString(2 * cm, below, _RANGE_NOTE)
        below -= 0.5 * cm
    if scan.get("damage_standard"):
        c.setFont("Helvetica", 8)
        c.drawString(2 * cm, below, _STANDARD_REF[scan["damage_standard"]])


_RISK_ORDER = {"LOW": 0, "MEDIUM": 1, "HIGH": 2}
_NOT_ANALYZED = {"error": "failed", "pending": "pending", "missing": "not found",
                 "no_photo": "photo lost"}


def _is_done(scan: dict) -> bool:
    return scan.get("status", "done") == "done"


def _summary_page(c, scans: list[dict]) -> None:
    """Front page of a multi-scan report: one row per photo (component, risk,
    cracks, area) plus the worst risk found across the whole inspection.
    Every captured photo gets a row, including ones that failed to analyze —
    a report that silently drops them would under-count the inspection."""
    w, h = A4
    graded = [s for s in scans if _is_done(s)]
    worst = max((s.get("risk_level") or "LOW" for s in graded),
                key=lambda r: _RISK_ORDER.get(r, 0)) if graded else "LOW"
    total_cracks = sum(s.get("crack_count", 0) or 0 for s in graded)
    failed = len(scans) - len(graded)

    c.setFillColorRGB(0, 0, 0)
    c.setFont("Helvetica-Bold", 20)
    c.drawString(2 * cm, h - 2.5 * cm, "Structural Vision AR — Inspection Report")
    c.setFont("Helvetica", 11)
    c.drawString(2 * cm, h - 3.3 * cm,
                 f"Date: {(scans[0].get('created_at') or '')[:19].replace('T', ' ')}")
    line = f"{len(scans)} photos  ·  {total_cracks} cracks detected"
    if failed:
        line += f"  ·  {failed} not analyzed"
    c.drawString(2 * cm, h - 3.9 * cm, line)

    y = h - 5.6 * cm
    c.setFillColorRGB(*_RISK_COLORS.get(worst, (0.5, 0.5, 0.5)))
    c.roundRect(2 * cm, y - 0.4 * cm, 5 * cm, 1.6 * cm, 0.2 * cm, stroke=0, fill=1)
    c.setFillColorRGB(1, 1, 1)
    c.setFont("Helvetica-Bold", 22)
    c.drawCentredString(4.5 * cm, y + 0.1 * cm, worst)
    c.setFillColorRGB(0, 0, 0)
    c.setFont("Helvetica", 12)
    c.drawString(8 * cm, y + 0.3 * cm, "Highest risk across all photos")

    y -= 2.4 * cm
    c.setFont("Helvetica-Bold", 11)
    for x, label in ((2 * cm, "#"), (3 * cm, "Component"), (8 * cm, "Risk"),
                     (11 * cm, "Cracks"), (14 * cm, "Area"), (17 * cm, "Basis")):
        c.drawString(x, y, label)
    c.setLineWidth(0.5)
    c.line(2 * cm, y - 0.2 * cm, w - 2 * cm, y - 0.2 * cm)

    c.setFont("Helvetica", 11)
    for i, s in enumerate(scans, 1):
        y -= 0.75 * cm
        if y < 3 * cm:            # spill onto another page for long inspections
            c.showPage()
            c.setFont("Helvetica", 11)
            y = h - 3 * cm
        c.setFillColorRGB(0, 0, 0)
        c.drawString(2 * cm, y, str(i))
        c.drawString(3 * cm, y, _component(s))
        if not _is_done(s):
            c.setFillColorRGB(0.45, 0.45, 0.45)
            c.drawString(8 * cm, y, "n/a")
            c.drawString(11 * cm, y, "—")
            c.drawString(14 * cm, y, "—")
            c.drawString(17 * cm, y, _NOT_ANALYZED.get(s.get("status"), "failed"))
            continue
        risk = s.get("risk_level") or "LOW"
        c.setFillColorRGB(*_RISK_COLORS.get(risk, (0.5, 0.5, 0.5)))
        c.drawString(8 * cm, y, risk)
        c.setFillColorRGB(0, 0, 0)
        c.drawString(11 * cm, y, str(s.get("crack_count", 0) or 0))
        c.drawString(14 * cm, y, f"{(s.get('crack_area_ratio') or 0) * 100:.2f}%")
        c.drawString(17 * cm, y,
                     "measured" if s.get("risk_source") == "measured" else "prelim.")

    c.setFillColorRGB(0, 0, 0)   # last row may have left the fill grey
    c.setFont("Helvetica-Oblique", 9)
    c.drawString(2 * cm, 2 * cm,
                 "Per-photo detail on the following pages. Preliminary risk is "
                 "image-area based; measure a crack in AR for a standards-based grade.")


def build_pdf(scan: dict, image_bytes: bytes) -> bytes:
    """Single-scan report — one page."""
    buf = io.BytesIO()
    c = canvas.Canvas(buf, pagesize=A4)
    _scan_page(c, scan, image_bytes, "Structural Vision AR — Scan Report")
    c.showPage()
    c.save()
    return buf.getvalue()


def build_batch_pdf(items: list[tuple[dict, bytes | None]]) -> bytes:
    """Whole-inspection report: summary table of every photo captured and the
    component it was scanned as, then one detail page per photo.

    An entry with image_bytes None (analysis failed, or the photo was never
    stored) still gets its summary row — it just has no detail page to draw."""
    buf = io.BytesIO()
    c = canvas.Canvas(buf, pagesize=A4)
    _summary_page(c, [s for s, _ in items])
    c.showPage()
    for i, (scan, image_bytes) in enumerate(items, 1):
        if image_bytes is None or not _is_done(scan):
            continue
        _scan_page(c, scan, image_bytes,
                   f"Photo {i} of {len(items)} — {_component(scan)}")
        c.showPage()
    c.save()
    return buf.getvalue()
