"""Batch report: every captured photo is accounted for, failures included.
Run: python test_report.py"""
import io

from PIL import Image

import report

_PAGE = b"/Type /Page" + bytes([10])   # page objects in the PDF body


def _jpeg(w=200, h=150) -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", (w, h), (180, 180, 180)).save(buf, "JPEG")
    return buf.getvalue()


def _scan(i: int, risk: str, component: str, cracks: int = 1) -> dict:
    return {"id": f"{i:08d}-0000-0000-0000-000000000000", "status": "done",
            "created_at": "2026-09-16T09:00:00", "risk_level": risk,
            "component_type": component, "crack_count": cracks,
            "crack_area_ratio": 0.012 * cracks, "risk_source": "preliminary",
            "detections": [{"polygon": [[10, 10], [80, 20], [70, 60]]}] * cracks}


def _drawn(items) -> tuple[bytes, list[str], list[str]]:
    """Build the PDF, capturing left-aligned text and centred text (the risk
    badges) separately."""
    import reportlab.pdfgen.canvas as _c
    left, centred = [], []

    def spy(method, sink):
        def wrapped(self, x, y, text, *a, **k):
            sink.append(text)
            return method(self, x, y, text, *a, **k)
        return wrapped

    orig_s, orig_c = _c.Canvas.drawString, _c.Canvas.drawCentredString
    _c.Canvas.drawString = spy(orig_s, left)
    _c.Canvas.drawCentredString = spy(orig_c, centred)
    try:
        return report.build_batch_pdf(items), left, centred
    finally:
        _c.Canvas.drawString, _c.Canvas.drawCentredString = orig_s, orig_c


def test_batch_pdf_has_summary_page_plus_one_page_per_photo():
    items = [(_scan(1, "LOW", "wall"), _jpeg()),
             (_scan(2, "HIGH", "column", 3), _jpeg()),
             (_scan(3, "MEDIUM", "beam", 2), _jpeg())]
    pdf = report.build_batch_pdf(items)
    assert pdf.startswith(b"%PDF")
    assert pdf.count(_PAGE) == len(items) + 1, "summary page + one per photo"


def test_summary_reports_the_worst_risk_not_the_first():
    # A LOW first photo must not hide a HIGH one later in the same inspection.
    _, _, badges = _drawn([(_scan(1, "LOW", "wall"), _jpeg()),
                           (_scan(2, "HIGH", "column"), _jpeg())])
    assert badges[0] == "HIGH", f"summary badge was {badges[0]!r}"


def test_failed_segments_still_get_a_summary_row():
    # A burst where 2 of 4 failed must still report 4 photos, not 2 — the
    # inspector needs to see which ones were never analyzed.
    items = [(_scan(1, "LOW", "wall"), _jpeg()),
             ({"id": "2", "status": "error", "component_type": "column",
               "created_at": "2026-09-16T09:00:00"}, None),
             ({"id": "3", "status": "missing"}, None),
             (_scan(4, "HIGH", "beam", 2), _jpeg())]
    pdf, drawn, _ = _drawn(items)
    assert "4 photos  ·  3 cracks detected  ·  2 not analyzed" in drawn
    assert "failed" in drawn and "not found" in drawn
    # Detail pages only for the two that have photos, plus the summary page.
    assert pdf.count(_PAGE) == 3


def test_components_print_as_display_labels():
    _, drawn, _ = _drawn([(_scan(1, "LOW", "rc_wall"), _jpeg())])
    assert "RC wall" in drawn and "rc_wall" not in drawn


def test_single_scan_pdf_still_one_page():
    pdf = report.build_pdf(_scan(1, "MEDIUM", "rc_wall"), _jpeg())
    assert pdf.startswith(b"%PDF") and pdf.count(_PAGE) == 1


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
            print("ok", name)
