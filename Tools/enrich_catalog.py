#!/usr/bin/env python3
"""Enrich the MinifigureCatalog with data from Rebrickable CSVs and fill missing images.

Usage:
    # Analyze gaps between catalog and Rebrickable CSV
    python3 enrich_catalog.py analyze

    # Download missing images (1,678 figures without local images)
    python3 enrich_catalog.py fill-images --limit 200

    # Full enrichment report
    python3 enrich_catalog.py report
"""

from __future__ import annotations

import argparse
import csv
import gzip
import json
import os
import sys
import time
import urllib.request
import urllib.error
from pathlib import Path

BRICKY_ROOT = Path(__file__).resolve().parents[1]
CATALOG_PATH = BRICKY_ROOT / "Bricky" / "Resources" / "MinifigureCatalog.json.gz"
IMAGES_ROOT = BRICKY_ROOT / "Bricky" / "Resources" / "MinifigImages"
MINIFIGS_CSV = Path(__file__).resolve().parent / "datasets" / "minifigs.csv.gz"
INVENTORY_CSV = Path(__file__).resolve().parent / "datasets" / "inventory_minifigs.csv.gz"

# Rebrickable API key (for fetching detailed minifig info if needed)
REBRICKABLE_API_KEY = "f80c762a9866cefa7111f5cabd5556dd"


def _load_catalog() -> tuple[dict, list]:
    """Load catalog, return (dict by id, raw list)."""
    with gzip.open(str(CATALOG_PATH), "rt") as f:
        cat = json.load(f)
    figures = cat["figures"] if isinstance(cat, dict) and "figures" in cat else cat
    by_id = {fig["id"]: fig for fig in figures}
    return by_id, figures


def _load_rebrickable_csv() -> dict:
    """Load Rebrickable minifigs.csv, return dict by fig_num."""
    with gzip.open(str(MINIFIGS_CSV), "rt") as f:
        reader = csv.DictReader(f)
        return {row["fig_num"]: row for row in reader}


def cmd_analyze(args):
    """Analyze gaps between catalog and Rebrickable data."""
    catalog, _ = _load_catalog()
    rebrickable = _load_rebrickable_csv()

    cat_ids = set(catalog.keys())
    rb_ids = set(rebrickable.keys())

    only_catalog = cat_ids - rb_ids
    only_rebrickable = rb_ids - cat_ids
    both = cat_ids & rb_ids

    print(f"Catalog figures:        {len(cat_ids):>6}")
    print(f"Rebrickable figures:    {len(rb_ids):>6}")
    print(f"In both:                {len(both):>6}")
    print(f"Only in catalog:        {len(only_catalog):>6}")
    print(f"Only in Rebrickable:    {len(only_rebrickable):>6}")

    # Check local images
    img_files = set(os.listdir(str(IMAGES_ROOT))) if IMAGES_ROOT.is_dir() else set()
    no_image = [fid for fid in catalog if f"{fid}.jpg" not in img_files]
    print(f"\nCatalog figures without local images: {len(no_image)}")

    # Check which missing images have Rebrickable URLs
    have_rb_url = 0
    have_cat_url = 0
    for fid in no_image:
        if fid in rebrickable and rebrickable[fid].get("img_url"):
            have_rb_url += 1
        if catalog[fid].get("imgURL"):
            have_cat_url += 1
    print(f"  - with Rebrickable img_url: {have_rb_url}")
    print(f"  - with catalog imgURL:      {have_cat_url}")

    # Show sample of what's only in Rebrickable
    if only_rebrickable:
        print(f"\nSample figures only in Rebrickable (first 10):")
        for fid in sorted(only_rebrickable)[:10]:
            row = rebrickable[fid]
            print(f"  {fid}: {row['name']} (parts={row['num_parts']})")


def cmd_fill_images(args):
    """Download missing images from Rebrickable CDN."""
    catalog, _ = _load_catalog()
    rebrickable = _load_rebrickable_csv()

    img_files = set(os.listdir(str(IMAGES_ROOT))) if IMAGES_ROOT.is_dir() else set()
    missing = []
    for fid, fig in catalog.items():
        if f"{fid}.jpg" not in img_files:
            # Prefer catalog URL, fall back to Rebrickable CSV URL
            url = fig.get("imgURL") or (rebrickable.get(fid, {}).get("img_url"))
            if url:
                missing.append((fid, url))

    limit = args.limit or len(missing)
    to_fetch = missing[:limit]
    print(f"Downloading {len(to_fetch)} of {len(missing)} missing images...")

    IMAGES_ROOT.mkdir(parents=True, exist_ok=True)
    downloaded = 0
    errors = 0

    for i, (fid, url) in enumerate(to_fetch):
        out_path = IMAGES_ROOT / f"{fid}.jpg"
        try:
            req = urllib.request.Request(url, headers={
                "User-Agent": "Bricky/1.0 (LEGO minifigure scanner app)"
            })
            with urllib.request.urlopen(req, timeout=15) as resp:
                data = resp.read()
                if len(data) < 100:
                    print(f"  [{i+1}/{len(to_fetch)}] {fid}: too small ({len(data)}B), skipping")
                    errors += 1
                    continue
                with open(out_path, "wb") as f:
                    f.write(data)
                downloaded += 1
                if (i + 1) % 50 == 0:
                    print(f"  [{i+1}/{len(to_fetch)}] downloaded {downloaded}, errors {errors}")
        except Exception as e:
            errors += 1
            if (i + 1) % 50 == 0 or args.verbose:
                print(f"  [{i+1}/{len(to_fetch)}] {fid}: {e}")

        # Rate limit: 5 requests per second for CDN
        time.sleep(0.2)

    print(f"\nDone: downloaded {downloaded}, errors {errors}")
    print(f"Total local images now: {len(img_files) + downloaded}")


def cmd_report(args):
    """Full enrichment report."""
    catalog, _ = _load_catalog()
    rebrickable = _load_rebrickable_csv()
    img_files = set(os.listdir(str(IMAGES_ROOT))) if IMAGES_ROOT.is_dir() else set()

    # Load inventory data
    inv_figs = set()
    with gzip.open(str(INVENTORY_CSV), "rt") as f:
        reader = csv.DictReader(f)
        for row in reader:
            inv_figs.add(row["fig_num"])

    print("=" * 60)
    print("CATALOG ENRICHMENT REPORT")
    print("=" * 60)

    print(f"\n--- Coverage ---")
    print(f"Catalog figures:      {len(catalog):>6}")
    print(f"Rebrickable figures:  {len(rebrickable):>6}")
    print(f"In Rebrickable sets:  {len(inv_figs):>6} (appear in official sets)")

    print(f"\n--- Images ---")
    with_img = sum(1 for fid in catalog if f"{fid}.jpg" in img_files)
    without_img = len(catalog) - with_img
    print(f"With local image:     {with_img:>6}")
    print(f"Without local image:  {without_img:>6}")

    # Downloadable
    downloadable = 0
    for fid in catalog:
        if f"{fid}.jpg" not in img_files:
            url = catalog[fid].get("imgURL") or rebrickable.get(fid, {}).get("img_url")
            if url:
                downloadable += 1
    print(f"Downloadable:         {downloadable:>6}")

    print(f"\n--- Themes ---")
    themes = {}
    for fig in catalog.values():
        t = fig.get("theme", "Unknown")
        themes[t] = themes.get(t, 0) + 1
    for theme, count in sorted(themes.items(), key=lambda x: -x[1])[:15]:
        print(f"  {theme:30s} {count:>5}")

    print(f"\n--- Year Distribution ---")
    years = {}
    for fig in catalog.values():
        y = fig.get("year", 0)
        decade = (y // 10) * 10 if y else 0
        years[decade] = years.get(decade, 0) + 1
    for decade, count in sorted(years.items()):
        if decade > 0:
            print(f"  {decade}s: {count:>5}")


def main():
    parser = argparse.ArgumentParser(description="Enrich MinifigureCatalog")
    sub = parser.add_subparsers(dest="command")

    sub.add_parser("analyze", help="Analyze catalog vs Rebrickable gaps")

    p_fill = sub.add_parser("fill-images", help="Download missing images")
    p_fill.add_argument("--limit", type=int, help="Max images to download")
    p_fill.add_argument("--verbose", action="store_true")

    sub.add_parser("report", help="Full enrichment report")

    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        sys.exit(1)

    if args.command == "analyze":
        cmd_analyze(args)
    elif args.command == "fill-images":
        cmd_fill_images(args)
    elif args.command == "report":
        cmd_report(args)


if __name__ == "__main__":
    main()
