"""Batch report: every photo gets a page, the summary carries the worst risk.
Run: python test_report.py"""
import io

from PIL import Image

import report


def _jpeg(w=200, h=150) -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", (w, h), (180, 180, 180)).save(buf, "JPEG")
    return buf.getvalue()


def _scan(i: int, risk: str, component: str, cracks: int = 1) -> dict:
    return {"id": f"{i:08d}-0000-0000-0000-000000000000", "created_at": "2026-09-16T09:00:00",
            "risk_level": risk, "component_type": component, "crack_count": cracks,
            "crack_area_ratio": 0.012 * cracks, "risk_source": "preliminary",
            "detections": [{"polygon": [[10, 10], [80, 20], [70, 60]]}] * cracks}


def test_batch_pdf_has_summary_page_plus_one_page_per_photo():
    items = [(_scan(1, "LOW", "wall"), _jpeg()),
             (_scan(2, "HIGH", "column", 3), _jpeg()),
             (_scan(3, "MEDIUM", "beam", 2), _jpeg())]
    pdf = report.build_batch_pdf(items)
    assert pdf.startswith(b"%PDF")
    assert pdf.count(b"/Type /Page\n") == len(items) + 1, "summary page + one per photo"


def test_summary_reports_the_worst_risk_not_the_first():
    # A LOW first photo must not hide a HIGH one later in the same inspection.
    import reportlab.pdfgen.canvas as _c
    seen = []
    orig = _c.Canvas.drawCentredString
    _c.Canvas.drawCentredString = lambda self, x, y, t, *a, **k: (seen.append(t), orig(self, x, y, t, *a, **k))[1]
    try:
        report.build_batch_pdf([(_scan(1, "LOW", "wall"), _jpeg()),
                                (_scan(2, "HIGH", "column"), _jpeg())])
    finally:
        _c.Canvas.drawCentredString = orig
    assert seen[0] == "HIGH", f"summary badge was {seen[0]!r}"


def test_single_scan_pdf_still_one_page():
    pdf = report.build_pdf(_scan(1, "MEDIUM", "rc_wall"), _jpeg())
    assert pdf.startswith(b"%PDF") and pdf.count(b"/Type /Page\n") == 1


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
            print("ok", name)
