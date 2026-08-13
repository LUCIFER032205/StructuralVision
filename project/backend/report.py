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
    c = component or "structure"
    if crack_count == 0:
        return f"No significant cracking detected on {c}."
    if risk == "HIGH":
        return f"Significant cracking detected on {c}. Immediate structural inspection recommended."
    if risk == "MEDIUM":
        return f"Moderate cracking detected on {c}. Schedule inspection within 6–24 months."
    return f"Minor cracking detected on {c}. Monitor and reinspect within 2–5 years."


def _overlay(image_bytes: bytes, detections: list[dict]) -> Image.Image:
    img = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    draw = ImageDraw.Draw(img, "RGBA")
    for d in detections:
        poly = [tuple(p) for p in d["polygon"]]
        if len(poly) >= 3:
            draw.polygon(poly, fill=(255, 40, 40, 80), outline=(255, 40, 40, 255), width=3)
    return img


def build_pdf(scan: dict, image_bytes: bytes) -> bytes:
    risk = scan.get("risk_level") or "LOW"
    color = _RISK_COLORS.get(risk, (0.5, 0.5, 0.5))

    buf = io.BytesIO()
    c = canvas.Canvas(buf, pagesize=A4)
    w, h = A4

    c.setFont("Helvetica-Bold", 20)
    c.drawString(2 * cm, h - 2.5 * cm, "Structural Vision AR — Scan Report")
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
    conf = scan.get("component_confidence") or 0
    c.drawString(8 * cm, y + 0.6 * cm,
                 f"Component: {scan.get('component_type', '?')} ({conf * 100:.0f}%)")
    c.drawString(8 * cm, y,
                 f"Cracks: {scan.get('crack_count', 0)}   "
                 f"Area: {(scan.get('crack_area_ratio') or 0) * 100:.2f}%")

    c.setFont("Helvetica-Oblique", 12)
    c.drawString(2 * cm, y - 1.6 * cm, _summary(risk, scan.get("component_type"), scan.get("crack_count", 0)))
    c.setFont("Helvetica", 11)
    c.drawString(2 * cm, y - 2.4 * cm, f"Maintenance window: {_MAINTENANCE.get(risk, '')}")

    c.showPage()
    c.save()
    return buf.getvalue()
