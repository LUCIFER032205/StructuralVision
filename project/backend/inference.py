"""
inference.py — the shared 2-model core for Structural Vision AR.

Model 1: crack segmentation (YOLOv8-seg, ultralytics)  -> models/crack_seg.pt
Model 2: component classifier (MobileNetV3-Small, ONNX) -> models/component.onnx

Both models load by file path, so retraining = overwrite the file + restart.

Run standalone as the end-to-end sanity check:
    python backend/inference.py            # runs on one val image per class
"""
from pathlib import Path
import io
import numpy as np
from PIL import Image
import onnxruntime as ort

MODELS_DIR = Path(__file__).resolve().parent.parent / "models"
CRACK_PT   = MODELS_DIR / "crack_seg.pt"
COMPONENT_ONNX = MODELS_DIR / "component.onnx"

# ImageFolder alphabetical order — baked into component.onnx at train time.
COMPONENT_CLASSES = ["beam", "ceiling", "column", "slab", "wall"]

IMAGENET_MEAN = np.array([0.485, 0.456, 0.406], dtype=np.float32)
IMAGENET_STD  = np.array([0.229, 0.224, 0.225], dtype=np.float32)

_yolo = None
_ort_sess = None


def load_models():
    """Lazy-load both models once; reused across scans."""
    global _yolo, _ort_sess
    if _yolo is None:
        from ultralytics import YOLO  # heavy import, defer until needed
        _yolo = YOLO(str(CRACK_PT))
    if _ort_sess is None:
        _ort_sess = ort.InferenceSession(str(COMPONENT_ONNX))
    return _yolo, _ort_sess


def _preprocess_classifier(img: Image.Image) -> np.ndarray:
    """Resize(256) -> CenterCrop(224) -> ToTensor -> ImageNet norm. Must match training val_tf."""
    img = img.convert("RGB")
    w, h = img.size
    scale = 256 / min(w, h)
    img = img.resize((round(w * scale), round(h * scale)), Image.BILINEAR)
    w, h = img.size
    left, top = (w - 224) // 2, (h - 224) // 2
    img = img.crop((left, top, left + 224, top + 224))
    x = np.asarray(img, dtype=np.float32) / 255.0        # HWC, [0,1]
    x = (x - IMAGENET_MEAN) / IMAGENET_STD
    x = x.transpose(2, 0, 1)[None]                        # 1,C,H,W
    return np.ascontiguousarray(x, dtype=np.float32)


def classify_component(img: Image.Image):
    """-> (component_type, confidence)."""
    _, sess = load_models()
    x = _preprocess_classifier(img)
    logits = sess.run(None, {sess.get_inputs()[0].name: x})[0][0]
    e = np.exp(logits - logits.max())
    probs = e / e.sum()
    idx = int(probs.argmax())
    return COMPONENT_CLASSES[idx], float(probs[idx])


def detect_cracks(img: Image.Image):
    """-> list of {bbox[x1,y1,x2,y2], polygon[[x,y]...], confidence, area_ratio}."""
    yolo, _ = load_models()
    img_area = float(img.width * img.height)
    # conf 0.5: default 0.25 flagged bag seams / curtain edges as cracks
    res = yolo.predict(img, conf=0.5, verbose=False)[0]
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
# Tier 1 (scan time, no physical scale): IN-HOUSE HEURISTIC, not from a
# standard. DI = crack_area_ratio x CF x SF. CF weights load-bearing members
# higher (ordering inspired by JBDPA member classification: vertical
# load-bearing > horizontal > non-structural finishes); the numeric values and
# the 0.10/0.25 thresholds are empirical picks on our own scan history.
# ponytail: no citable standard maps pixel area ratio to risk — physical crack
# width is what the standards use; tier 2 supersedes this once width is known.
_CF = {"column": 1.5, "beam": 1.3, "slab": 1.0, "wall": 0.8, "ceiling": 0.2}
_SF = {"structural": 1.0, "paint": 0.2}


def compute_risk(detections, component_type: str = "wall", component_confidence: float = 1.0) -> str:
    if not detections:
        return "LOW"
    cf = _CF.get(component_type, 1.0) if component_confidence >= 0.6 else 1.0
    di = sum(d["area_ratio"] * cf * _SF.get(d.get("crack_type", "structural"), 1.0)
             for d in detections)
    if di >= 0.25:
        return "HIGH"
    if di >= 0.10:
        return "MEDIUM"
    return "LOW"


# Tier 2 (after AR two-tap measure gives physical scale): JBDPA damage class
# from max residual crack width, per "Standard for Post-earthquake Damage
# Level Classification" (JBDPA 2001, rev. 2015). English refs: Nakano, Maeda,
# Kuramoto & Murakami, 13WCEE paper No.124; Maeda, Nakano & Lee, 13WCEE
# paper No.1179. Class bands (RC members, max residual crack width):
#   I  < 0.2 mm   II  0.2-1.0 mm   III  1.0-2.0 mm   IV  > 2.0 mm
# Class V (rebar buckling / core crushing) is not detectable from imagery, so
# widths beyond class IV still report IV. For context, Eurocode 2 (EN 1992-1-1
# Table 7.1N) and ACI 224R-01 put the RC serviceability limit at ~0.3 mm,
# inside class II.
def jbdpa_damage_class(width_mm: float) -> int:
    if width_mm < 0.2:
        return 1
    if width_mm <= 1.0:
        return 2
    if width_mm <= 2.0:
        return 3
    return 4


def risk_from_width(width_mm: float, crack_type: str = "structural") -> str:
    """Width-based risk per JBDPA class: I->LOW, II->MEDIUM, III/IV->HIGH.
    Paint/surface cracks are cosmetic regardless of width."""
    if crack_type == "paint":
        return "LOW"
    return {1: "LOW", 2: "MEDIUM", 3: "HIGH", 4: "HIGH"}[jbdpa_damage_class(width_mm)]


def run_scan(image_bytes: bytes) -> dict:
    """Full pipeline: bytes -> component + cracks + risk."""
    img = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    component, comp_conf = classify_component(img)
    detections = detect_cracks(img)
    return {
        "component_type": component,
        "component_confidence": comp_conf,
        "crack_count": len(detections),
        "crack_area_ratio": sum(d["area_ratio"] for d in detections),
        "risk_level": compute_risk(detections, component, comp_conf),
        "detections": detections,
    }


if __name__ == "__main__":
    # Sanity check: one real val image per class, end to end.
    val = Path(r"F:\StructuralVision\datasets\prepared\model2_classifier\val")
    for cls in COMPONENT_CLASSES:
        f = next((val / cls).iterdir())
        result = run_scan(f.read_bytes())
        print(f"[{cls:8s}] pred={result['component_type']:8s} "
              f"({result['component_confidence']:.2f})  "
              f"cracks={result['crack_count']:2d}  "
              f"ratio={result['crack_area_ratio']:.4f}  "
              f"risk={result['risk_level']}")
    print("\nSanity check complete.")
