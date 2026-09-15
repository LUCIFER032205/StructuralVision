"""
Fix local dataset - copy and remap class IDs to 0
This replicates what Kaggle did in fixed_dataset
"""

import shutil
from pathlib import Path

# Paths
src_root = Path(r"F:\StructuralVision\datasets\merged_yolo_crack_seg")
dst_root = Path(r"F:\StructuralVision\datasets\fixed_dataset")

print("=" * 60)
print("DATASET FIX SCRIPT")
print("=" * 60)
print(f"Source: {src_root}")
print(f"Destination: {dst_root}")
print()

# Check source exists
if not src_root.exists():
    print(f"❌ ERROR: Source dataset not found at {src_root}")
    exit(1)

# Check if destination already exists
if dst_root.exists():
    response = input(f"⚠️  {dst_root} already exists. Delete and recreate? (yes/no): ")
    if response.lower() == 'yes':
        print("Deleting existing fixed_dataset...")
        shutil.rmtree(dst_root)
    else:
        print("Aborted.")
        exit(0)

# Copy dataset
print("📦 Copying dataset to fixed_dataset...")
shutil.copytree(src_root, dst_root)
print("✓ Copy complete")

# Fix class IDs: remap any non-zero class_id -> 0
print("\n🔧 Fixing class IDs (remapping all to 0)...")
fixed = 0
total_labels = 0

for label_file in dst_root.rglob("labels/*.txt"):
    total_labels += 1
    lines = label_file.read_text().splitlines()
    new_lines = []
    changed = False

    for line in lines:
        line = line.strip()
        if not line:
            continue
        parts = line.split()
        if parts and parts[0] != "0":
            # Remap to class 0
            new_lines.append("0 " + " ".join(parts[1:]))
            changed = True
        else:
            new_lines.append(line)

    if changed:
        label_file.write_text("\n".join(new_lines))
        fixed += 1

print(f"✓ Fixed {fixed} label files out of {total_labels} total")

# Create data.yaml
data_yaml_content = f"""names:
  0: crack
nc: 1
path: {str(dst_root).replace(chr(92), '/')}
test: test/images
train: train/images
val: valid/images
"""

data_yaml_path = dst_root / "data.yaml"
data_yaml_path.write_text(data_yaml_content)
print(f"\n✓ Created {data_yaml_path}")

# Verify structure
print("\n" + "=" * 60)
print("VERIFICATION")
print("=" * 60)
train_imgs = len(list((dst_root / "train/images").glob("*")))
train_lbls = len(list((dst_root / "train/labels").glob("*.txt")))
valid_imgs = len(list((dst_root / "valid/images").glob("*")))
valid_lbls = len(list((dst_root / "valid/labels").glob("*.txt")))
test_imgs = len(list((dst_root / "test/images").glob("*"))) if (dst_root / "test/images").exists() else 0

print(f"Train images: {train_imgs}")
print(f"Train labels: {train_lbls}")
print(f"Valid images: {valid_imgs}")
print(f"Valid labels: {valid_lbls}")
print(f"Test images: {test_imgs}")

# Match Kaggle output
if train_imgs == 9816 and valid_imgs == 1239 and test_imgs == 1417:
    print("\n✅ SUCCESS! Dataset matches Kaggle's fixed_dataset structure")
else:
    print("\n⚠️  WARNING: Image counts don't match Kaggle")
    print("   Expected: Train=9816, Valid=1239, Test=1417")

print("\n" + "=" * 60)
print(f"Fixed dataset ready at: {dst_root}")
print("=" * 60)
