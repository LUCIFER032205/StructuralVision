"""zip_dataset.py — zips prepared crack dataset for Colab upload"""
import zipfile
from pathlib import Path

SRC = Path(r"F:\StructuralVision\datasets\crack.yolov8")
OUT = Path(r"F:\StructuralVision\project\crack_dataset.zip")

with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as zf:
    for f in SRC.rglob("*"):
        if f.is_file():
            zf.write(f, f.relative_to(SRC.parent))

print(f"Done: {OUT}  ({OUT.stat().st_size/1e6:.1f} MB)")
