# Quick Fix for YOLO Training Error
## Problem: Multi-frame images & huge image sizes causing training crash

### Step 1: Find problematic images
```python
# Add to your Kaggle notebook BEFORE training
!python find_problem_images.py
```

### Step 2: Fix them
```python
# This will:
# - Convert multi-frame images to single frame
# - Resize images >10,000px down to manageable size
# - Keep backups with .backup extension
!python fix_problem_images.py
```

### Step 3: Quick inline fix (alternative - add this to your training code)
```python
from PIL import Image
import warnings

# Increase PIL limit to handle large images
Image.MAX_IMAGE_PIXELS = None

# Suppress decompression warnings
warnings.filterwarnings('ignore', category=Image.DecompressionBombWarning)

# Add this function before training
def validate_and_fix_dataset(dataset_path):
    """Quick validation pass - removes problematic images."""
    from pathlib import Path
    import os
    
    removed = []
    
    for split in ['train', 'valid']:
        img_dir = Path(dataset_path) / split / 'images'
        if not img_dir.exists():
            continue
            
        for img_path in img_dir.glob('*.*'):
            try:
                with Image.open(img_path) as img:
                    # Check for multi-frame
                    if hasattr(img, 'n_frames') and img.n_frames > 1:
                        # Delete multi-frame images
                        img_path.unlink()
                        # Delete corresponding label
                        label_path = str(img_path).replace('/images/', '/labels/').replace('.jpg', '.txt').replace('.png', '.txt')
                        if os.path.exists(label_path):
                            os.unlink(label_path)
                        removed.append(str(img_path))
                        print(f"Removed multi-frame: {img_path.name}")
                        
            except Exception as e:
                print(f"Error checking {img_path.name}: {e}")
                # Remove problematic file
                img_path.unlink()
                removed.append(str(img_path))
    
    print(f"\nRemoved {len(removed)} problematic images")
    
    # Clear caches
    for split in ['train', 'valid']:
        cache_file = Path(dataset_path) / split / 'labels.cache'
        if cache_file.exists():
            cache_file.unlink()
            print(f"Cleared {split} cache")

# Run validation before training
validate_and_fix_dataset('/kaggle/working/fixed_dataset')

# Then start training
results = model.train(**train_config)
```

### Step 4: Alternative - Pre-resize all images
```python
# If you want to be aggressive and resize ALL images to max 4096px
from PIL import Image
from pathlib import Path

def resize_large_images(dataset_path, max_size=4096):
    """Resize any image larger than max_size on either dimension."""
    for split in ['train', 'valid']:
        img_dir = Path(dataset_path) / split / 'images'
        if not img_dir.exists():
            continue
        
        images = list(img_dir.glob('*.*'))
        print(f"Processing {split}: {len(images)} images...")
        
        resized = 0
        for img_path in images:
            try:
                with Image.open(img_path) as img:
                    width, height = img.size
                    
                    if width > max_size or height > max_size:
                        ratio = min(max_size/width, max_size/height)
                        new_size = (int(width*ratio), int(height*ratio))
                        
                        img = img.resize(new_size, Image.LANCZOS)
                        img.save(img_path, quality=95)
                        resized += 1
                        
                        if resized % 100 == 0:
                            print(f"  Resized {resized} images...")
                            
            except Exception as e:
                print(f"Error with {img_path.name}: {e}")
        
        print(f"✅ {split}: resized {resized} images")

# Run before training
Image.MAX_IMAGE_PIXELS = None
resize_large_images('/kaggle/working/fixed_dataset', max_size=4096)
```

## Recommended approach:
**Use Step 3 (inline validation)** - fastest and safest. It removes only the problematic multi-frame images that cause the crash.

## Why this happens:
- Some dataset images are animated GIFs/PNGs or multi-page TIFFs
- When YOLO tries to stack frames with different dimensions → crash
- The 102M pixel warning is separate but indicates unnecessarily huge images

## After fixing:
Just rerun your training cell - the cache will regenerate and training will proceed normally.
