#!/usr/bin/env python3
"""
Download LEGO minifigure datasets for Bricky scanner training.

Datasets:
1. HuggingFace Armaggheddon/lego_minifigure_captions — 12,966 Rebrickable images with IDs
2. Kaggle ihelon/lego-minifigures-classification — 498 real photos, 4 themes
3. Kaggle datasciencedonut/lego-minifigures — 241 images on black backgrounds

Usage:
    python3 Tools/download_datasets.py huggingface   # Download HuggingFace dataset
    python3 Tools/download_datasets.py kaggle-class   # Download Kaggle classification
    python3 Tools/download_datasets.py kaggle-donut   # Download Kaggle minifigures
    python3 Tools/download_datasets.py all            # Download all
"""

import os
import sys
import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DATASETS_DIR = REPO_ROOT / "Tools" / "datasets"


def download_huggingface():
    """Download Armaggheddon/lego_minifigure_captions — 12,966 images with fig_num IDs."""
    from datasets import load_dataset
    
    out_dir = DATASETS_DIR / "huggingface-lego-captions"
    images_dir = out_dir / "images"
    images_dir.mkdir(parents=True, exist_ok=True)
    
    print("Loading HuggingFace dataset (streaming to avoid full download)...")
    ds = load_dataset("Armaggheddon/lego_minifigure_captions", split="train")
    
    metadata = []
    total = len(ds)
    print(f"Processing {total} images...")
    
    for i, item in enumerate(ds):
        fig_num = item.get("fig_num", f"unknown_{i}")
        short_caption = item.get("short_caption", "")
        caption = item.get("caption", "")
        num_parts = item.get("num_parts", 0)
        
        # Save image as JPEG
        img = item["image"]
        safe_fig = str(fig_num).replace("/", "_")
        img_path = images_dir / f"{safe_fig}.jpg"
        
        if not img_path.exists():
            img.save(str(img_path), "JPEG", quality=90)
        
        metadata.append({
            "fig_num": fig_num,
            "short_caption": short_caption,
            "caption": caption,
            "num_parts": num_parts,
            "filename": f"{safe_fig}.jpg"
        })
        
        if (i + 1) % 500 == 0 or i == total - 1:
            print(f"  {i+1}/{total} images saved")
    
    # Save metadata
    meta_path = out_dir / "metadata.json"
    with open(meta_path, "w") as f:
        json.dump(metadata, f, indent=2)
    
    print(f"Done! {len(metadata)} images saved to {images_dir}")
    print(f"Metadata saved to {meta_path}")


def download_kaggle_classification():
    """Download ihelon/lego-minifigures-classification — 498 real photos."""
    out_dir = DATASETS_DIR / "kaggle-minifigures-classification"
    out_dir.mkdir(parents=True, exist_ok=True)
    
    try:
        from kaggle.api.kaggle_api_extended import KaggleApi
        api = KaggleApi()
        api.authenticate()
        
        print("Downloading Kaggle dataset: ihelon/lego-minifigures-classification...")
        api.dataset_download_files(
            "ihelon/lego-minifigures-classification",
            path=str(out_dir),
            unzip=True
        )
        print(f"Done! Files saved to {out_dir}")
    except Exception as e:
        print(f"Kaggle download failed: {e}")
        print("Trying alternative: huggingface_hub download...")
        _download_kaggle_via_hf("ihelon/lego-minifigures-classification", out_dir)


def download_kaggle_donut():
    """Download datasciencedonut/lego-minifigures — 241 images."""
    out_dir = DATASETS_DIR / "kaggle-minifigures"
    out_dir.mkdir(parents=True, exist_ok=True)
    
    try:
        from kaggle.api.kaggle_api_extended import KaggleApi
        api = KaggleApi()
        api.authenticate()
        
        print("Downloading Kaggle dataset: datasciencedonut/lego-minifigures...")
        api.dataset_download_files(
            "datasciencedonut/lego-minifigures",
            path=str(out_dir),
            unzip=True
        )
        print(f"Done! Files saved to {out_dir}")
    except Exception as e:
        print(f"Kaggle download failed: {e}")
        print("Trying alternative: huggingface_hub download...")
        _download_kaggle_via_hf("datasciencedonut/lego-minifigures", out_dir)


def _download_kaggle_via_hf(dataset_name, out_dir):
    """Fallback: some Kaggle datasets are mirrored on HuggingFace."""
    print(f"Note: Kaggle API auth not configured. Please either:")
    print(f"  1. Set up ~/.kaggle/kaggle.json with your API key")
    print(f"  2. Or manually download from https://www.kaggle.com/datasets/{dataset_name}")
    print(f"     and extract to {out_dir}")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    
    cmd = sys.argv[1].lower()
    
    if cmd in ("huggingface", "hf"):
        download_huggingface()
    elif cmd in ("kaggle-class", "kaggle-classification"):
        download_kaggle_classification()
    elif cmd in ("kaggle-donut", "kaggle-minifigures"):
        download_kaggle_donut()
    elif cmd == "all":
        download_huggingface()
        download_kaggle_classification()
        download_kaggle_donut()
    else:
        print(f"Unknown command: {cmd}")
        print(__doc__)
        sys.exit(1)


if __name__ == "__main__":
    main()
