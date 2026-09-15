"""
inference.py — the crack-detection core for Structural Vision AR.

Model 1: crack segmentation (YOLOv8-seg, ultralytics) -> models/crack_seg.pt

The model loads by file path, so retraining = overwrite the file + restart.

Component type comes from the user, who picks it before capture (see the app's
component-select sheet) and is taken as authoritative. A MobileNetV3 classifier
("Model 2") used to guess it; removed 2026-09-08 — once the user states the
component up front, a second guess at it has no job to do.

Run standalone as the end-to-end sanity check:
    python backend/inference.py            # runs on the demo_kit images
"""
from pathlib import Path
import io
import numpy as np
from PIL import Image

MODELS_DIR = Path(__file__).resolve().parent.parent / "models"
CRACK_PT   = MODELS_DIR / "crack_seg.pt"

# The component types the app offers; the user's pick is authoritative.
COMPONENT_TYPES = ["beam", "ceiling", "column", "rc_wall", "slab", "wall"]  # wall = brick/masonry

_yolo = None


def load_models():
    """Lazy-load the crack model once; reused across scans."""
    global _yolo
    if _yolo is None:
        from ultralytics import YOLO  # heavy import, defer until needed
        _yolo = YOLO(str(CRACK_PT))
    return _yolo


def detect_cracks(img: Image.Image):
    """-> list of {bbox[x1,y1,x2,y2], polygon[[x,y]...], confidence, area_ratio}."""
    yolo = load_models()
    img_area = float(img.width * img.height)
    # conf 0.4: v4 model scores 99.0% image accuracy (199/200 cracks, 3/200 false alarms on SDNET2018);
    # v2 needed 0.5 because 0.25 flagged bag seams / curtain edges as cracks
    res = yolo.predict(img, imgsz=1024, conf=0.4, verbose=False)[0]
    out = []
    if res.masks is None:
        return out
    polys = res.masks.xy                      # list of (N,2) pixel polygons
    boxes = res.boxes
    for i, poly in enumerate(polys):
        conf = float(boxes.conf[i])
        x1, y1, x2, y2 = (float(v) for v in boxes.xyxy[i])
        out.append({
            "bbox": [x1, y1, x2, y2],
            "polygon": poly.tolist(),
            "confidence": conf,
            "area_ratio": float(_polygon_area(poly) / img_area),
            "crack_type": _classify_crack_type(poly, (x1, y1, x2, y2)),
            **_crack_dimensions(poly),
        })
    return out


def _crack_dimensions(poly: np.ndarray) -> dict:
    """Pixel length (major extent) and mean width (area / length) of a crack
    polygon. Client converts to mm using the AR two-tap measurement as scale:
    width_mm = measured_length_cm*10 * (width_px / length_px)."""
    if len(poly) < 3:
        return {"length_px": 0.0, "width_px": 0.0}
    # Length = diagonal of the tight extent along principal axis via PCA.
    centered = poly - poly.mean(axis=0)
    cov = np.cov(centered.T)
    evals, evecs = np.linalg.eigh(cov)
    major = evecs[:, np.argmax(evals)]
    proj = centered @ major
    length = float(proj.max() - proj.min())
    area = _polygon_area(poly)
    width = float(area / length) if length > 1e-6 else 0.0
    return {"length_px": length, "width_px": width}


def _classify_crack_type(poly: np.ndarray, bbox) -> str:
    """Geometric heuristic: structural vs paint crack.
    Structural = elongated (aspect > 3) + straight outline (extent ≈ half the
    perimeter). Paint = compact blob or meandering craze web.
    Note: poly is a CLOSED mask outline, so first/last points are adjacent —
    straightness must use extent/perimeter, not endpoint span.
    ponytail: fixed thresholds — tune if field data shows mis-classification.
    """
    if len(poly) < 4:
        return "structural"
    x1, y1, x2, y2 = bbox
    w, h = max(x2 - x1, 1.0), max(y2 - y1, 1.0)
    aspect = max(w, h) / min(w, h)
    diffs = np.diff(np.vstack([poly, poly[:1]]), axis=0)
    perimeter = float(np.sum(np.linalg.norm(diffs, axis=1))) + 1e-6
    extent = float(np.hypot(w, h))
    # straight thin crack: perimeter ≈ 2*extent -> ratio ≈ 1; craze web << 1
    return "structural" if (aspect > 3.0 and 2 * extent / perimeter > 0.6) else "paint"


def _iou(a, b) -> float:
    """IoU of two [x1,y1,x2,y2] boxes."""
    ix1, iy1 = max(a[0], b[0]), max(a[1], b[1])
    ix2, iy2 = min(a[2], b[2]), min(a[3], b[3])
    iw, ih = max(0.0, ix2 - ix1), max(0.0, iy2 - iy1)
    inter = iw * ih
    if inter <= 0:
        return 0.0
    area_a = (a[2] - a[0]) * (a[3] - a[1])
    area_b = (b[2] - b[0]) * (b[3] - b[1])
    return inter / (area_a + area_b - inter)


def diff_detections(prev: list[dict], curr: list[dict], iou_thresh: float = 0.3) -> list[dict]:
    """Match current cracks to a prior scan of the same surface by bbox IoU.
    Tags each current crack: 'new' (no prior match) or 'grown'/'stable' by area.
    ponytail: bbox IoU only — assumes re-scan framed similarly; drifted framing
    reports spurious 'new'. Cloud-anchor pose alignment is the real fix."""
    out = []
    for c in curr:
        best, best_iou = None, iou_thresh
        for p in prev:
            i = _iou(c["bbox"], p["bbox"])
            if i >= best_iou:
                best, best_iou = p, i
        if best is None:
            status, delta = "new", None
        else:
            delta = c["area_ratio"] - best["area_ratio"]
            # >10% relative area increase counts as growth
            status = "grown" if delta > 0.1 * best["area_ratio"] else "stable"
        out.append({**c, "growth_status": status, "area_delta": delta})
    return out


def _polygon_area(pts: np.ndarray) -> float:
    """Shoelace formula."""
    if len(pts) < 3:
        return 0.0
    x, y = pts[:, 0], pts[:, 1]
    return 0.5 * abs(np.dot(x, np.roll(y, 1)) - np.dot(y, np.roll(x, 1)))


# --- Risk model, two tiers ---------------------------------------------------
#
# Tier 1 (scan time, no physical scale) -> risk_source "preliminary".
# IN-HOUSE HEURISTIC, not from a standard. DI = crack_area_ratio x CF x SF. CF
# weights load-bearing members higher (JBDPA ordering: vertical load-bearing >
# horizontal > non-structural finishes); the numeric values and the 0.10/0.25
# thresholds are empirical picks on our own scan history.
# ponytail: no published standard maps pixel area ratio to risk — every one
# grades physical crack width. Tier 2 supersedes this once width is measured.
_CF = {"column": 1.5, "rc_wall": 1.5, "beam": 1.3, "slab": 1.0, "wall": 0.8, "ceiling": 0.2}
_SF = {"structural": 1.0, "paint": 0.2}


def compute_risk(detections, component_type: str | None = None) -> str:
    if not detections:
        return "LOW"
    # Unknown component (older client that sent no selection) gets a neutral
    # weight rather than a guessed one.
    cf = _CF.get(component_type, 1.0)
    di = sum(d["area_ratio"] * cf * _SF.get(d.get("crack_type", "structural"), 1.0)
             for d in detections)
    if di >= 0.25:
        return "HIGH"
    if di >= 0.10:
        return "MEDIUM"
    return "LOW"


# Tier 2 (after the AR two-tap measurement gives physical scale) -> "measured".
#
# RC members (column, beam, slab, rc_wall) — JBDPA post-earthquake damage
# guideline, as published in: Nakano, Maeda, Kuramoto & Murakami, "Guideline
# for Post-Earthquake Damage Evaluation and Rehabilitation of RC Buildings in
# Japan", 13WCEE, Vancouver, 2004, Paper No. 124.
#   Table 2: max residual crack width -> damage class
#            I < 0.2 mm, II 0.2-1.0, III 1.0-2.0, IV > 2.0 (V = rebar buckling,
#            not visible in a photo, so wide cracks cap at IV).
#   Table 3: seismic capacity reduction factor eta per class and member type.
#   Eq. 2-3: residual seismic capacity ratio R = residual / original x 100 %;
#            for a single inspected member R = 100 * eta.
#   Rating:  Slight R>=95, Light 80<=R<95, Moderate 60<=R<80, Heavy R<60
#            (calibrated on 145 school buildings after the 1995 Kobe quake).
# Masonry/brick walls ("wall") — BRE Digest 251 (1990, rev. 1995), damage
# categories by crack width: 0 <0.1, 1 <=1, 2 <=5, 3 5-15, 4 15-25, 5 >25 mm;
# 0-2 aesthetic, 3-4 serviceability, 5 stability.
_ETA = {  # Table 3, classes I..IV
    "brittle_column": (0.95, 0.60, 0.30, 0.0),
    "ductile_column": (0.95, 0.75, 0.50, 0.10),
    "wall":           (0.95, 0.60, 0.30, 0.0),
}
# ponytail: member detailing is unknown from a photo. Columns take the brittle
# (conservative) column; beams/slabs are flexure-dominated so take the ductile
# column; the guideline itself grades beams via their effect on columns.
_MEMBER_ETA = {"column": "brittle_column", "beam": "ductile_column",
               "slab": "ductile_column", "rc_wall": "wall"}
_RATING_RISK = {"Slight": "LOW", "Light": "LOW", "Moderate": "MEDIUM", "Heavy": "HIGH"}


def _jbdpa_class(width_mm: float) -> int:
    """Table 2 -> 0..3 for classes I..IV."""
    return 0 if width_mm < 0.2 else 1 if width_mm <= 1.0 else 2 if width_mm <= 2.0 else 3


def _bre251_category(w: float) -> int:
    return 0 if w < 0.1 else 1 if w <= 1.0 else 2 if w <= 5.0 else 3 if w <= 15.0 else 4 if w <= 25.0 else 5


def measured_risk(width_mm: float, component_type: str | None,
                  crack_type: str = "structural") -> dict:
    """Crack width (mm) -> published damage grade -> LOW/MEDIUM/HIGH."""
    if component_type == "ceiling" or crack_type == "paint":
        # Out of both standards' scope: finishes, not structural members.
        return {"standard": None, "damage_class": None, "residual_capacity_pct": None,
                "rating": "Cosmetic", "risk_level": "LOW"}
    if component_type == "wall":
        cat = _bre251_category(width_mm)
        rating = "Aesthetic" if cat <= 2 else "Serviceability" if cat <= 4 else "Stability"
        return {"standard": "BRE251", "damage_class": str(cat), "residual_capacity_pct": None,
                "rating": rating,
                "risk_level": {"Aesthetic": "LOW", "Serviceability": "MEDIUM", "Stability": "HIGH"}[rating]}
    # Unknown component (older client) is graded as the conservative RC column.
    k = _jbdpa_class(width_mm)
    r = round(100 * _ETA[_MEMBER_ETA.get(component_type, "brittle_column")][k], 1)
    rating = "Slight" if r >= 95 else "Light" if r >= 80 else "Moderate" if r >= 60 else "Heavy"
    return {"standard": "JBDPA", "damage_class": ("I", "II", "III", "IV")[k],
            "residual_capacity_pct": r, "rating": rating, "risk_level": _RATING_RISK[rating]}


def width_from_measurement(length_cm: float, detections: list[dict]):
    """AR two-tap gives the real length of the largest crack; its px width/length
    ratio converts that to a width in mm. -> (width_mm, crack_type) or (None, None)."""
    if not detections:
        return None, None
    d = max(detections, key=lambda d: d.get("area_ratio") or 0)
    if not d.get("length_px") or not d.get("width_px"):
        return None, None
    return length_cm * 10 * d["width_px"] / d["length_px"], d.get("crack_type") or "structural"


def run_scan(image_bytes: bytes, component_type: str | None = None) -> dict:
    """Full pipeline: bytes -> cracks + risk, for the user-selected component.

    component_type comes from the app's pre-capture selection and is taken as
    given. None means the client sent no selection (an older build): the scan
    still runs, and risk falls back to a neutral component weight.
    """
    img = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    detections = detect_cracks(img)
    return {
        "component_type":   component_type,
        "crack_count":      len(detections),
        "crack_area_ratio": sum(d["area_ratio"] for d in detections),
        "risk_level":       compute_risk(detections, component_type),
        "risk_source":      "preliminary",   # becomes "measured" after AR measurement
        "detections":       detections,
    }


if __name__ == "__main__":
    # Sanity check: the curated demo kit, end to end.
    # ponytail: the risk levels in demo_kit/README.md predate the current DI
    # risk formula, so this is a smoke test, not a regression assertion.
    kit = Path(__file__).resolve().parent.parent / "demo_kit"
    for f in sorted(kit.glob("*.jpg")):
        result = run_scan(f.read_bytes(), "wall")
        print(f"[{f.name:12s}] risk={result['risk_level']:6s}  "
              f"cracks={result['crack_count']:2d}  "
              f"ratio={result['crack_area_ratio']:.4f}")
    print("Sanity check complete.")
