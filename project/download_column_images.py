"""
Downloads concrete structural column images using DuckDuckGo (ddgs).
Install: pip install ddgs requests
Run:     python download_column_images.py
"""

import os
import requests
import time
import random
from ddgs import DDGS

BASE_DIR = r"F:\StructuralVision\datasets\column_scraped"
os.makedirs(BASE_DIR, exist_ok=True)

QUERIES = [
    ("parking_garage",   "parking garage concrete column pillar"),
    ("col_spalling",     "concrete column spalling damage reinforced"),
    ("col_rebar",        "concrete pillar rebar exposed crack"),
    ("col_bridge",       "bridge pier concrete column inspection"),
    ("col_building",     "building concrete structural column pillar"),
    ("col_earthquake",   "earthquake damaged reinforced concrete column"),
    ("col_corrosion",    "concrete column corrosion deterioration"),
    ("col_construction", "reinforced concrete column construction bare"),
]

TARGET_PER_QUERY = 60

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/125.0.0.0 Safari/537.36"
    )
}

def download_image(url, filepath, timeout=10):
    try:
        r = requests.get(url, headers=HEADERS, timeout=timeout, stream=True)
        ct = r.headers.get("Content-Type", "")
        if r.status_code == 200 and "image" in ct:
            with open(filepath, "wb") as f:
                for chunk in r.iter_content(8192):
                    f.write(chunk)
            # reject suspiciously small files (< 5 KB = probably an error page)
            if os.path.getsize(filepath) > 5_000:
                return True
            os.remove(filepath)
    except Exception:
        pass
    return False

def search_with_retry(ddgs, query, max_results, retries=3):
    for attempt in range(retries):
        try:
            results = list(ddgs.images(query, max_results=max_results))
            return results
        except Exception as e:
            wait = 10 * (attempt + 1) + random.uniform(1, 5)
            print(f"  Attempt {attempt+1} failed ({e}). Waiting {wait:.0f}s...")
            time.sleep(wait)
    return []

total = 0
ddgs = DDGS()

for folder_name, query in QUERIES:
    out_dir = os.path.join(BASE_DIR, folder_name)
    os.makedirs(out_dir, exist_ok=True)
    count = 0
    print(f"\n[{folder_name}] Searching: {query}")

    # wait between queries to avoid rate limiting
    time.sleep(random.uniform(3, 6))

    results = search_with_retry(ddgs, query, TARGET_PER_QUERY)
    if not results:
        print("  No results — skipping.")
        continue

    print(f"  Got {len(results)} URLs, downloading...")
    for i, result in enumerate(results):
        url = result.get("image", "")
        if not url:
            continue
        filepath = os.path.join(out_dir, f"{folder_name}_{i+1:03d}.jpg")
        if download_image(url, filepath):
            count += 1
            print(f"  [{count}] saved")
        time.sleep(0.15)

    print(f"  Done: {count} images in {out_dir}")
    total += count

print(f"\n{'='*50}")
print(f"Total downloaded: {total}")
print(f"Location: {BASE_DIR}")
print("\nReview subfolders — delete anything that is NOT a bare concrete structural column.")
