"""
prepare_datasets.py
Prepares both training datasets for Structural Vision AR.

Model 1 — YOLOv8n-seg  : writes data.yaml with absolute paths
Model 2 — MobileNetV3  : copies images into classifier/train|val/{class}/

Run from anywhere:
    python prepare_datasets.py
"""

import random
import shutil
from pathlib import Path

DATASETS_ROOT = Path(r"F:\StructuralVision\datasets")
PROJECT_ROOT  = Path(r"F:\StructuralVision\project")
OUT           = DATASETS_ROOT / "prepared"
SEED          = 42
VAL_SPLIT     = 0.20

# ── Model 1: crack segmentation (YOLOv8n-seg) ─────────────────────────────────

def prepare_model1():
    src = DATASETS_ROOT / "crack.yolov8"
    out = OUT / "model1_crack"
    out.mkdir(parents=True, exist_ok=True)

    # Write absolute-path data.yaml (ultralytics needs this when CWD varies)
    yaml_text = f"""\
path: {out}
train: {src / 'train' / 'images'}
val:   {src / 'valid' / 'images'}
test:  {src / 'test'  / 'images'}

nc: 1
names: ['crack']
"""
    yaml_path = out / "data.yaml"
    yaml_path.write_text(yaml_text)

    # Count for sanity check
    counts = {
        split: len(list((src / split / "images").glob("*.*")))
        for split in ("train", "valid", "test")
    }
    print(f"[Model 1] data.yaml -> {yaml_path}")
    print(f"          train={counts['train']}  val={counts['valid']}  test={counts['test']}")


# ── Model 2: component classifier (MobileNetV3-Small) ─────────────────────────

# (class_name, list_of_source_dirs)
CLASSIFIER_SOURCES = {
    "wall":    [
        DATASETS_ROOT / "SDNET2018" / "Walls" / "Cracked",
        DATASETS_ROOT / "SDNET2018" / "Walls" / "Non-cracked",
    ],
    "slab":    [
        DATASETS_ROOT / "SDNET2018" / "Decks" / "Cracked",
        DATASETS_ROOT / "SDNET2018" / "Decks" / "Non-cracked",
    ],
    "beam":    [DATASETS_ROOT / "Beam" / "train" / "images"],
    "ceiling": [
        DATASETS_ROOT / "Ceiling" / "train" / "images",
        DATASETS_ROOT / "Ceiling" / "valid" / "images",
    ],
    "column":  list((DATASETS_ROOT / "column_scraped").iterdir()),  # all subdirs
}

IMG_EXTS = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}

def gather_images(dirs: list[Path]) -> list[Path]:
    imgs = []
    for d in dirs:
        if d.is_dir():
            imgs.extend(p for p in d.iterdir() if p.suffix.lower() in IMG_EXTS)
    return imgs

def prepare_model2():
    rng = random.Random(SEED)
    class_out = OUT / "model2_classifier"

    totals = {}
    for cls, src_dirs in CLASSIFIER_SOURCES.items():
        imgs = gather_images(src_dirs)
        rng.shuffle(imgs)

        n_val   = max(1, int(len(imgs) * VAL_SPLIT))
        val_set = imgs[:n_val]
        trn_set = imgs[n_val:]

        for split, subset in (("train", trn_set), ("val", val_set)):
            dest = class_out / split / cls
            dest.mkdir(parents=True, exist_ok=True)
            for img in subset:
                shutil.copy2(img, dest / img.name)

        totals[cls] = (len(trn_set), len(val_set))
        print(f"[Model 2] {cls:10s}  train={len(trn_set):5d}  val={len(val_set):4d}")

    # Write a summary yaml for reference
    summary = "# Model 2 — component classifier\n"
    summary += f"path: {class_out}\n"
    summary += f"nc: {len(totals)}\n"
    summary += f"names: {list(totals.keys())}\n"
    (class_out / "info.yaml").write_text(summary)
    print(f"[Model 2] info.yaml -> {class_out / 'info.yaml'}")


# ── Main ───────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    print("=== Preparing Model 1 (crack segmentation) ===")
    prepare_model1()
    print("\n=== Preparing Model 2 (component classifier) ===")
    prepare_model2()
    print("\nDone.")
