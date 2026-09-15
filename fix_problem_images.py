"""Fix problematic images in the dataset."""
import os
import shutil
from pathlib import Path
from PIL import Image
import numpy as np

Image.MAX_IMAGE_PIXELS = None

def fix_image(img_path, max_pixels=89000000, max_dimension=15000):
    """
    Fix problematic image by:
    1. Converting multi-frame to single frame
    2. Resizing if too large
    3. Re-saving in standard format

    Returns: (success, action_taken)
    """
    try:
        with Image.open(img_path) as img:
            # Convert to RGB if needed
            if img.mode not in ['RGB', 'L']:
                img = img.convert('RGB')

            # Get first frame only (fixes multi-frame issues)
            if hasattr(img, 'n_frames') and img.n_frames > 1:
                img.seek(0)
                img = img.copy()
                action = "converted_multiframe"
            else:
                action = "none"

            # Check if too large
            width, height = img.size
            pixels = width * height

            if pixels > max_pixels or width > max_dimension or height > max_dimension:
                # Calculate resize ratio
                ratio = min(
                    max_dimension / width,
                    max_dimension / height,
                    (max_pixels / pixels) ** 0.5
                )

                new_width = int(width * ratio)
                new_height = int(height * ratio)

                img = img.resize((new_width, new_height), Image.LANCZOS)
                action = f"resized_{width}x{height}_to_{new_width}x{new_height}"

            # Save back (overwrite original)
            backup_path = str(img_path) + '.backup'
            shutil.copy2(img_path, backup_path)

            # Save as high-quality JPEG
            if img.mode == 'L':
                img.save(img_path, 'JPEG', quality=95)
            else:
                img.save(img_path, 'JPEG', quality=95)

            return True, action

    except Exception as e:
        return False, f"error: {e}"

def remove_image_and_label(img_path):
    """Remove both image and its corresponding label file."""
    try:
        # Remove image
        if os.path.exists(img_path):
            os.remove(img_path)

        # Find and remove label
        label_path = str(img_path).replace('/images/', '/labels/').replace('\\images\\', '\\labels\\')
        for ext in ['.txt']:
            label_file = Path(label_path).with_suffix(ext)
            if label_file.exists():
                os.remove(label_file)

        return True
    except Exception as e:
        print(f"Error removing {img_path}: {e}")
        return False

def main(dataset_path, problem_images_file, action='fix'):
    """
    Fix or remove problematic images.

    action: 'fix' = try to fix, 'remove' = delete problematic images
    """

    # Read problem images
    with open(problem_images_file, 'r') as f:
        problem_paths = [line.strip() for line in f if line.strip()]

    print(f"Processing {len(problem_paths)} problematic images...")
    print(f"Action: {action}\n")

    results = {'fixed': 0, 'removed': 0, 'failed': 0}

    for img_path in problem_paths:
        img_path = Path(img_path)

        if not img_path.exists():
            print(f"⚠️  Not found: {img_path}")
            continue

        if action == 'fix':
            success, action_taken = fix_image(img_path)
            if success:
                print(f"✅ Fixed: {img_path.name} ({action_taken})")
                results['fixed'] += 1
            else:
                print(f"❌ Failed: {img_path.name} ({action_taken})")
                results['failed'] += 1

        elif action == 'remove':
            if remove_image_and_label(img_path):
                print(f"🗑️  Removed: {img_path.name}")
                results['removed'] += 1
            else:
                results['failed'] += 1

    print(f"\n{'='*60}")
    print(f"Results:")
    print(f"  Fixed: {results['fixed']}")
    print(f"  Removed: {results['removed']}")
    print(f"  Failed: {results['failed']}")
    print(f"{'='*60}")

    # Clear cache files so they get regenerated
    for split in ['train', 'valid']:
        cache_file = Path(dataset_path) / split / 'labels.cache'
        if cache_file.exists():
            cache_file.unlink()
            print(f"Deleted cache: {cache_file}")

if __name__ == "__main__":
    dataset_path = "/kaggle/working/fixed_dataset"
    problem_images_file = "problem_images.txt"

    # Change action to 'remove' if you want to delete problematic images instead
    action = 'fix'  # 'fix' or 'remove'

    main(dataset_path, problem_images_file, action=action)
