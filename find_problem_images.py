"""Find problematic images in the dataset."""
import os
from pathlib import Path
from PIL import Image
import numpy as np

# Increase PIL limit temporarily to read huge images
Image.MAX_IMAGE_PIXELS = None

def check_image(img_path):
    """Check if image has issues."""
    issues = []

    try:
        with Image.open(img_path) as img:
            # Check number of frames
            n_frames = getattr(img, 'n_frames', 1)
            if n_frames > 1:
                issues.append(f"Multi-frame: {n_frames} frames")

                # Check if frames have consistent dimensions
                frames_shapes = []
                for i in range(n_frames):
                    img.seek(i)
                    frames_shapes.append(img.size)

                if len(set(frames_shapes)) > 1:
                    issues.append(f"Inconsistent frame sizes: {frames_shapes}")

            # Check pixel count (decompression bomb)
            pixels = img.size[0] * img.size[1]
            if pixels > 89478485:  # PIL's default limit
                issues.append(f"Huge size: {img.size[0]}×{img.size[1]} = {pixels:,} pixels")

            # Check if image loads properly
            img.seek(0)
            np.array(img)

    except Exception as e:
        issues.append(f"Error reading: {e}")

    return issues

def scan_dataset(dataset_path):
    """Scan entire dataset for problematic images."""
    problem_images = []

    for split in ['train', 'valid']:
        img_dir = Path(dataset_path) / split / 'images'
        if not img_dir.exists():
            print(f"Skipping {split} (not found)")
            continue

        print(f"\nScanning {split}...")
        images = list(img_dir.glob('*.*'))

        for i, img_path in enumerate(images):
            if img_path.suffix.lower() not in ['.jpg', '.jpeg', '.png', '.bmp', '.tiff', '.tif']:
                continue

            issues = check_image(img_path)
            if issues:
                problem_images.append({
                    'path': str(img_path),
                    'split': split,
                    'issues': issues
                })

            if (i + 1) % 500 == 0:
                print(f"  Checked {i + 1}/{len(images)} images...")

    return problem_images

if __name__ == "__main__":
    dataset_path = "/kaggle/working/fixed_dataset"  # Update this path

    print("Scanning dataset for problematic images...")
    problems = scan_dataset(dataset_path)

    if problems:
        print(f"\n{'='*80}")
        print(f"Found {len(problems)} problematic images:")
        print(f"{'='*80}\n")

        for p in problems:
            print(f"📁 {p['path']}")
            for issue in p['issues']:
                print(f"   ⚠️  {issue}")
            print()

        # Save to file
        with open('problem_images.txt', 'w') as f:
            for p in problems:
                f.write(f"{p['path']}\n")

        print(f"\nProblem image paths saved to: problem_images.txt")
    else:
        print("\n✅ No problematic images found!")
