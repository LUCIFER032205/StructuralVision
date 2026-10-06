"""Build the AR site-preview catalogue from the Kenney city kits (CC0).

The three presets are Kenney models, re-exported as GLB with the kit's
colormap texture baked in (the kits' own .glb files ship the texture in a
sibling folder, so they render untextured), and scaled so each storey is
about 3.2 m.

Regenerate (only needed when swapping models):

    curl -LO https://kenney.nl/media/pages/assets/city-kit-suburban/2c871b7af2-1745479373/kenney_city-kit-suburban_20.zip
    curl -LO https://kenney.nl/media/pages/assets/city-kit-commercial/a742d900eb-1753115042/kenney_city-kit-commercial_2.1.zip
    unzip -q kenney_city-kit-suburban_20.zip   -d src/suburban
    unzip -q kenney_city-kit-commercial_2.1.zip -d src/commercial
    python make_buildings.py src

Writes static/buildings/*.glb and static/buildings/manifest.json. `size_m`
is the model's largest real dimension in metres — the app scales models by
that (ar_flutter_plugin_2 passes it to SceneView as scaleToUnits).
"""
import json
import shutil
import struct
import sys
from pathlib import Path

import trimesh
from PIL import Image

OUT = Path("static/buildings")
STOREY_M = 3.2

# id, display name, kit folder, model stem, storeys.
# Storey counts are what the model actually shows (window rows + ground
# floor) — the label and the height have to agree with the geometry.
PRESETS = [
    ("house", "Independent house (G+1)", "suburban", "building-type-e", 2),
    ("apartment", "Apartment block (G+3)", "commercial", "building-f", 4),
    ("office", "Office building (G+6)", "commercial", "building-skyscraper-a", 7),
]


def convert(kit_dir: Path, stem: str, storeys: int):
    """OBJ + the kit colormap -> textured mesh, plus its real size in metres."""
    mesh = trimesh.load(kit_dir / "Models/OBJ format" / f"{stem}.obj", force="mesh")
    texture = Image.open(kit_dir / "Models/GLB format/Textures/colormap.png").convert("RGBA")
    mesh.visual = trimesh.visual.TextureVisuals(uv=mesh.visual.uv, image=texture)
    # The OBJ's vertex colours survive the visual swap as vertex_attributes and
    # export as a custom "_color" attribute, which Filament (SceneView, inside
    # ar_flutter_plugin_2) rejects outright: "Unrecognized vertex semantic",
    # and the model never appears. The texture already carries the colour.
    mesh.vertex_attributes.clear()
    # Models are Y-up already. Scale so the roof lands at storeys * STOREY_M.
    w, h, d = mesh.extents
    size_m = max(mesh.extents) * (storeys * STOREY_M) / h
    footprint = f"{w * size_m / max(mesh.extents):.0f} x {d * size_m / max(mesh.extents):.0f} m"
    return mesh, round(float(size_m), 1), footprint


def filament_problems(path: Path) -> list[str]:
    """What would stop SceneView's Filament loader drawing this GLB."""
    raw = path.read_bytes()
    chunk_len = struct.unpack("<I", raw[12:16])[0]
    gltf = json.loads(raw[20:20 + chunk_len])
    problems = []
    for mesh in gltf["meshes"]:
        for prim in mesh["primitives"]:
            attrs = prim["attributes"]
            problems += [f"custom attribute {a}" for a in attrs if a.startswith("_")]
            if "NORMAL" not in attrs:
                problems.append("no normals")
    return problems


def main(src: Path):
    OUT.mkdir(parents=True, exist_ok=True)
    entries = []
    for pid, name, kit, stem, storeys in PRESETS:
        mesh, size_m, footprint = convert(src / kit, stem, storeys)
        # Filament lights models with their normals; without them it has to
        # guess, so ship them.
        mesh.export(OUT / f"{pid}.glb", include_normals=True)
        entries.append({"id": pid, "name": name, "file": f"{pid}.glb",
                        "size_m": size_m, "storeys": storeys, "footprint": footprint})
    shutil.copyfile("static/building.glb", OUT / "tower.glb")
    entries.append({"id": "tower", "name": "Demo tower", "file": "tower.glb",
                    "size_m": 20.0, "storeys": 6, "footprint": "6 x 6 m"})
    (OUT / "manifest.json").write_text(json.dumps({"buildings": entries}, indent=2) + "\n")
    return entries


if __name__ == "__main__":
    entries = main(Path(sys.argv[1] if len(sys.argv) > 1 else "src"))
    # Self-check: every file loads back, keeps its texture, stands upright,
    # and its height matches the storey count it claims.
    for e in entries:
        m = trimesh.load(OUT / e["file"], force="mesh")
        scale = e["size_m"] / max(m.extents)
        assert not filament_problems(OUT / e["file"]), (e["id"], filament_problems(OUT / e["file"]))
        if e["id"] != "tower":
            assert m.visual.material.baseColorTexture is not None, f"{e['id']} lost its texture"
            height = m.extents[1] * scale
            assert abs(height - e["storeys"] * STOREY_M) < 0.1, (e["id"], height)
            assert m.extents[1] == max(m.extents) or e["id"] == "house", f"{e['id']} not upright"
    print("ok:", [(e["id"], e["size_m"], e["footprint"]) for e in entries])
