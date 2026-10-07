"""Write the AR site-preview catalogue (static/buildings/manifest.json) from
the shipped models, and check each one will actually load on the phone.

The house, apartment, office and tower are CC-BY models from Sketchfab (see
static/buildings/CREDITS.txt), shrunk for a budget phone with
tools/shrink_glb.mjs: ground boards dropped, meshes merged per material
(the apartment went from 1,295 draw calls to 3), opaque textures turned into
JPEG and capped at 2048 px (1024 for the apartment), the apartment simplified
from 197k to 160k triangles and made unlit (9 -> 29 fps at 80 cm: the phone
is fill-rate bound, not triangle bound). To redo one, from a folder with
`npm i @gltf-transform/cli@4` installed:

    DROP='^Plane001' node shrink_glb.mjs indian_house_model.glb house.glb 2048
    DROP='^Object_11$' node shrink_glb.mjs modern_office_building.glb office.glb 2048
    UNLIT=1 NO_TANGENTS=1 ERR=0.003 node shrink_glb.mjs procedural_hong_kong_building.glb apartment.glb 1024 0.35

then run `python make_buildings.py`.

`size_m` is the model's largest real dimension in metres; the app scales by
it (ar_flutter_plugin_2 passes it to SceneView as scaleToUnits).
"""
import json
import struct
from pathlib import Path

import trimesh

OUT = Path("static/buildings")

# id, display name, file, storeys, metres per model unit.
# The house and office were modelled in metres. The apartment's units are
# arbitrary: 8.1 units for a G+6 block with roof tanks, so 3 m/unit puts its
# floors at ~3 m and the roofline at ~24 m.
PRESETS = [
    ("house", "Independent house (G+1)", "house.glb", 2, 1.0),
    ("apartment", "Apartment block (G+6)", "apartment.glb", 7, 3.0),
    ("office", "Office building (G+2)", "office.glb", 3, 1.0),
    # Modelled in cm: 161 m to the crown, ~40 slab levels at 3.7 m. Shipped
    # as downloaded (3.6k triangles, one 1024 px texture, 1.3 MB).
    ("tower", "High-rise tower (~40 floors)", "tower.glb", 40, 0.01),
]


def filament_problems(path: Path) -> list[str]:
    """What would stop SceneView's Filament loader drawing this GLB."""
    raw = path.read_bytes()
    chunk_len = struct.unpack("<I", raw[12:16])[0]
    gltf = json.loads(raw[20:20 + chunk_len])
    problems = [f"requires {e}" for e in gltf.get("extensionsRequired", [])]
    for mesh in gltf["meshes"]:
        for prim in mesh["primitives"]:
            attrs = prim["attributes"]
            # trimesh exports OBJ vertex colours as "_color"; Filament rejects
            # any custom attribute ("Unrecognized vertex semantic").
            problems += [f"custom attribute {a}" for a in attrs if a.startswith("_")]
            if "NORMAL" not in attrs:
                problems.append("no normals")
    return problems


def main():
    entries = []
    for pid, name, file, storeys, mpu in PRESETS:
        w, h, d = trimesh.load(OUT / file).extents * mpu
        entries.append({"id": pid, "name": name, "file": file,
                        "size_m": round(float(max(w, h, d)), 1), "storeys": storeys,
                        "footprint": f"{w:.0f} x {d:.0f} m"})
    (OUT / "manifest.json").write_text(json.dumps({"buildings": entries}, indent=2) + "\n")
    return entries


if __name__ == "__main__":
    entries = main()
    # Self-check: every model loads on Filament, stays phone-sized, and its
    # height reads as the storeys it claims (2.8-4 m a floor, roof extras ok).
    for e in entries:
        path = OUT / e["file"]
        assert not filament_problems(path), (e["id"], filament_problems(path))
        assert path.stat().st_size < 12_000_000, f"{e['id']} too big for the phone"
        mpu = next(p[4] for p in PRESETS if p[0] == e["id"])
        height = trimesh.load(path).extents[1] * mpu
        assert 2.8 * e["storeys"] <= height <= 4.0 * e["storeys"] + 4, (e["id"], height)
    print("ok:", [(e["id"], e["size_m"], e["footprint"]) for e in entries])
