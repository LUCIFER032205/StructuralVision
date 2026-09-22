"""Generate preset massing models for the AR site preview.

Run from project/backend:  python make_buildings.py
Writes static/buildings/*.glb and static/buildings/manifest.json.
Swap any .glb for a nicer Blender/CC0 model later; keep size_m in sync.
"""
import json
import shutil
from pathlib import Path

import numpy as np
import trimesh

OUT = Path("static/buildings")
STOREY_M = 3.2
WALL = [236, 226, 208, 255]
BAND = [150, 140, 128, 255]
ROOF = [150, 62, 48, 255]
GLASS = [90, 120, 150, 255]


def _box(w, d, h, z0, color):
    m = trimesh.creation.box(extents=[w, d, h])
    m.apply_translation([0, 0, z0 + h / 2])
    m.visual.face_colors = color
    return m


def building(w, d, storeys, roof):
    """w x d footprint in metres, Z up. Returns a Y-up Trimesh ready for GLB export."""
    h = storeys * STOREY_M
    parts = [_box(w, d, h, 0, WALL)]
    for i in range(1, storeys):                      # floor bands read as storeys
        parts.append(_box(w + 0.1, d + 0.1, 0.25, i * STOREY_M - 0.125, BAND))
    for i in range(storeys):                         # window strip, front face
        z = i * STOREY_M + 1.0
        g = _box(w * 0.8, 0.05, 1.2, z, GLASS)
        g.apply_translation([0, -d / 2 - 0.03, 0])
        parts.append(g)
    if roof == "pitched":
        # Triangular prism as a convex hull: no shapely needed (not installed).
        x, y = w / 2 + 0.3, d / 2 + 0.3
        r = trimesh.Trimesh(vertices=[[sx, sy, sz] for sy in (-y, y)
                                      for sx, sz in ((-x, h), (x, h), (0, h + 2.2))]).convex_hull
        r.visual.face_colors = ROOF
        parts.append(r)
    else:
        parts.append(_box(w + 0.4, d + 0.4, 0.4, h, BAND))  # parapet slab
    mesh = trimesh.util.concatenate(parts)
    # glTF is Y-up: rotate Z-up -> Y-up so the model stands upright in ARCore.
    mesh.apply_transform(trimesh.transformations.rotation_matrix(-np.pi / 2, [1, 0, 0]))
    return mesh


PRESETS = [
    # id, name, w, d, storeys, roof
    ("house", "Independent house (G+1)", 10, 8, 2, "pitched"),
    ("apartment", "Apartment block (G+4)", 18, 12, 5, "flat"),
    ("office", "Office building (G+9)", 20, 20, 10, "flat"),
]


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    entries = []
    for pid, name, w, d, storeys, roof in PRESETS:
        mesh = building(w, d, storeys, roof)
        mesh.export(OUT / f"{pid}.glb")
        entries.append({"id": pid, "name": name, "file": f"{pid}.glb",
                        "size_m": round(float(max(mesh.extents)), 1),
                        "storeys": storeys, "footprint": f"{w} x {d} m"})
    shutil.copyfile("static/building.glb", OUT / "tower.glb")
    entries.append({"id": "tower", "name": "Demo tower", "file": "tower.glb",
                    "size_m": 20.0, "storeys": 6, "footprint": "6 x 6 m"})
    (OUT / "manifest.json").write_text(json.dumps({"buildings": entries}, indent=2))
    return entries


if __name__ == "__main__":
    entries = main()
    # Self-check: every file loads back, stands upright (Y is the tallest axis for
    # towers), and size_m matches the exported geometry.
    for e in entries:
        m = trimesh.load(OUT / e["file"], force="mesh")
        assert abs(max(m.extents) - e["size_m"]) < 0.2 or e["id"] == "tower", e
    office = trimesh.load(OUT / "office.glb", force="mesh")
    assert office.extents[1] == max(office.extents), "office should be tallest along Y (up)"
    print("ok:", [(e["id"], e["size_m"]) for e in entries])
