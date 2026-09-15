"""
overlay.py — per-scan crack-overlay GLB for the AR screen.

Builds a flat quad (image aspect ratio, largest dimension = 1.0 so the app's
scaleToUnits value maps directly to meters) textured with the scan's crack
polygons on a transparent background. Placed on the tapped plane in AR, it
shows the crack pattern itself instead of a generic pin.
"""
import io

import numpy as np
import trimesh
from PIL import Image, ImageDraw, ImageFont

from inference import compute_risk

_TEX_MAX = 1024

_SEV_COLORS = {"HIGH": (255, 40, 40), "MEDIUM": (255, 160, 0), "LOW": (60, 200, 60)}


def _severity(detections: list[dict], component_type: str | None = None) -> str:
    # Scan-level risk over ALL detections — identical to the scan-result screen,
    # so the AR labels can never disagree with it. (Per-crack risk was wrong:
    # two cracks summing to MEDIUM each labeled LOW individually.)
    return compute_risk(detections, component_type)


def build_overlay_glb(
    image_bytes: bytes,
    detections: list[dict],
    component_type: str | None = None,
    risk_level: str | None = None,   # stored scan risk (measured wins over preliminary)
) -> bytes:
    img = Image.open(io.BytesIO(image_bytes))
    w, h = img.size

    scale = _TEX_MAX / max(w, h)
    tw, th = round(w * scale), round(h * scale)
    tex = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    draw = ImageDraw.Draw(tex)
    font = ImageFont.load_default(size=36)
    sev = risk_level or _severity(detections, component_type)
    rgb = _SEV_COLORS[sev]
    for i, d in enumerate(detections, 1):
        poly = [(p[0] * scale, p[1] * scale) for p in d["polygon"]]
        if len(poly) < 3:
            continue
        draw.polygon(poly, fill=rgb + (170,), outline=rgb + (255,), width=3)
        label = f"{i} {sev}"
        lx = min(p[0] for p in poly)
        ly = min(p[1] for p in poly) - 44
        box = draw.textbbox((lx, ly), label, font=font)
        box = (box[0] - 6, box[1] - 4, box[2] + 6, box[3] + 4)
        # Clamp label into the texture
        dx = max(0, -box[0]) - max(0, box[2] - tw)
        dy = max(0, -box[1]) - max(0, box[3] - th)
        box = (box[0] + dx, box[1] + dy, box[2] + dx, box[3] + dy)
        draw.rectangle(box, fill=rgb + (230,))
        draw.text((lx + dx, ly + dy), label, font=font, fill=(255, 255, 255, 255))

    # Quad in the XZ plane (Y-up glTF), normal +Y, largest dim 1.0.
    qw, qh = (1.0, h / w) if w >= h else (w / h, 1.0)
    vertices = np.array([
        [-qw / 2, 0, -qh / 2],
        [ qw / 2, 0, -qh / 2],
        [ qw / 2, 0,  qh / 2],
        [-qw / 2, 0,  qh / 2],
    ])
    faces = np.array([[0, 2, 1], [0, 3, 2]])  # CCW from +Y
    # trimesh UV origin is bottom-left; image row 0 (top) -> far edge (-Z)
    uv = np.array([[0.0, 1.0], [1.0, 1.0], [1.0, 0.0], [0.0, 0.0]])

    material = trimesh.visual.material.PBRMaterial(
        baseColorTexture=tex,
        alphaMode="BLEND",
        doubleSided=True,
    )
    mesh = trimesh.Trimesh(
        vertices=vertices,
        faces=faces,
        visual=trimesh.visual.TextureVisuals(uv=uv, material=material),
        process=False,
    )
    return mesh.export(file_type="glb")


if __name__ == "__main__":
    # Self-check: build from a solid test image + a fake triangle crack,
    # re-load the GLB and assert geometry + texture survived the round trip.
    buf = io.BytesIO()
    Image.new("RGB", (800, 600), (120, 120, 120)).save(buf, "JPEG")
    dets = [{"polygon": [[100, 100], [700, 120], [400, 500]],
             "area_ratio": 0.20, "confidence": 0.9}]
    glb = build_overlay_glb(buf.getvalue(), dets, "column")
    assert glb[:4] == b"glTF", "not a GLB"

    scene = trimesh.load(io.BytesIO(glb), file_type="glb")
    geom = next(iter(scene.geometry.values()))
    assert len(geom.faces) == 2
    ext = geom.bounding_box.extents
    assert abs(max(ext) - 1.0) < 1e-6, f"largest dim {max(ext)} != 1.0"
    tex = geom.visual.material.baseColorTexture
    assert tex is not None and tex.mode == "RGBA"
    assert np.asarray(tex)[:, :, 3].max() > 0, "texture fully transparent"
    assert _severity([dets[0]], "column") == "HIGH"           # 0.20*1.5 = 0.30
    # demo_kit high_1 (wide spalled crack, 5.73% area, one mask after the
    # iou=0.45 dedupe): 0.0573*1.5 = 0.086 -> HIGH, same in AR as on screen.
    assert _severity([{"area_ratio": 0.0573, "confidence": 0.8}], "column") == "HIGH"
    assert _severity([{"area_ratio": 0.025, "confidence": 0.9}], "column") == "MEDIUM"
    # Two cracks that only together cross the MEDIUM threshold must both
    # label MEDIUM — the scan-level risk, not per-crack.
    assert _severity([{"area_ratio": 0.012, "confidence": 0.9},
                      {"area_ratio": 0.012, "confidence": 0.9}], "column") == "MEDIUM"
    # No component selected -> neutral weight (cf 1.0), not a guessed one
    # (as a column the same crack would be HIGH).
    assert _severity([{"area_ratio": 0.05, "confidence": 0.9}], None) == "MEDIUM"
    print(f"overlay self-check OK — {len(glb)} bytes, extents {ext}")
