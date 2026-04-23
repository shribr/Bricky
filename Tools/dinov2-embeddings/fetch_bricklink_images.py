#!/usr/bin/env python3
"""Fetch BrickLink minifigure renders for cross-source evaluation.

The index is built from Rebrickable CDN renders. This tool downloads the
*same* figures' renders from BrickLink's CDN, which uses a different
rendering style (camera angle, lighting, background). Evaluating the
encoder on BrickLink queries against the Rebrickable index tests whether
it generalises across render sources — a much harder (and more realistic)
test than same-source synthetic augmentation.

Usage:
    # Full pipeline: fetch images, build eval set
    python3 fetch_bricklink_images.py fetch --figures 200 --out bricklink_images/
    python3 fetch_bricklink_images.py eval  --images bricklink_images/ --out eval_bricklink/

The BrickLink image URL pattern:
    https://img.bricklink.com/ItemImage/MN/0/{BL_ID}.png
    where BL_ID is the BrickLink minifigure ID (e.g. "sw0012").

Mapping from Rebrickable fig-XXXXXX to BrickLink ID is scraped from the
"External Sites" section of each figure's Rebrickable web page. No API
key is required — the mapping is cached in bricklink_mapping.json so
each figure is only scraped once.
"""

from __future__ import annotations

import argparse
import gzip
import json
import os
import re
import sys
import time
import urllib.request
import urllib.error
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("Missing dependency: pip install Pillow")
    sys.exit(1)

try:
    import cloudscraper
except ImportError:
    print("Missing dependency: pip install cloudscraper")
    sys.exit(1)

BRICKY_ROOT = Path(__file__).resolve().parents[2]
CATALOG_PATH = BRICKY_ROOT / "Bricky" / "Resources" / "MinifigureCatalog.json.gz"
IMAGES_ROOT = BRICKY_ROOT / "Bricky" / "Resources" / "MinifigImages"
DEFAULT_OUT = Path(__file__).resolve().parent / "bricklink_images"
DEFAULT_EVAL_OUT = Path(__file__).resolve().parent / "eval_bricklink"
MAPPING_CACHE = Path(__file__).resolve().parent / "bricklink_mapping.json"

BL_IMAGE_URL = "https://img.bricklink.com/ItemImage/MN/0/{bl_id}.png"
REBRICKABLE_MINIFIG_PAGE = "https://rebrickable.com/minifigs/{fig_id}/"


# ---------------------------------------------------------------------------
# Rebrickable → BrickLink ID mapping (web scrape — no API key needed)
# ---------------------------------------------------------------------------

# Pattern to find the BrickLink ID in the "External Sites" table on the page.
# The HTML has: <td>BrickLink</td><td><a href="...?M=sw0607&...">sw0607</a></td>
# We extract the ID from the catalogitem URL parameter M=
_BL_ID_PATTERN = re.compile(
    r'BrickLink\s*</td>\s*<td[^>]*>\s*(?:<[^>]*>)?\s*'
    r'(?:.*?catalogitem\.page\?M=([A-Za-z0-9_-]+)|([A-Za-z0-9_-]+))',
    re.IGNORECASE | re.DOTALL,
)

# Shared scraper session (created lazily)
_scraper = None


def _get_scraper():
    global _scraper
    if _scraper is None:
        _scraper = cloudscraper.create_scraper()
    return _scraper


def fetch_bl_id(fig_id: str) -> str | None:
    """Scrape the BrickLink ID from a Rebrickable minifig web page."""
    url = REBRICKABLE_MINIFIG_PAGE.format(fig_id=fig_id)
    try:
        r = _get_scraper().get(url, timeout=15)
        if r.status_code == 200:
            m = _BL_ID_PATTERN.search(r.text)
            if m:
                return m.group(1) or m.group(2)
        elif r.status_code == 429:
            print("  Rate limited, waiting 30s...", flush=True)
            time.sleep(30)
            return fetch_bl_id(fig_id)  # retry
        elif r.status_code == 404:
            return None
    except Exception:
        pass
    return None


def load_or_build_mapping(fig_ids: list[str]) -> dict[str, str]:
    """Load cached mapping or scrape Rebrickable pages to build it."""
    cache: dict[str, str | None] = {}
    if MAPPING_CACHE.exists():
        cache = json.loads(MAPPING_CACHE.read_text())
        print(f"Loaded {len(cache)} cached mappings from {MAPPING_CACHE.name}")

    missing = [fid for fid in fig_ids if fid not in cache]
    if missing:
        print(f"Scraping Rebrickable pages for {len(missing)} unmapped figures...")
        for i, fid in enumerate(missing):
            bl_id = fetch_bl_id(fid)
            cache[fid] = bl_id
            if bl_id:
                print(f"  [{i+1}/{len(missing)}] {fid} → {bl_id}")
            else:
                print(f"  [{i+1}/{len(missing)}] {fid} → (no BrickLink ID)")
            time.sleep(1.0)  # polite delay for web scraping
            # Save periodically
            if (i + 1) % 50 == 0:
                MAPPING_CACHE.write_text(json.dumps(cache, indent=2))
        MAPPING_CACHE.write_text(json.dumps(cache, indent=2))
        print(f"Saved mapping cache to {MAPPING_CACHE.name}")

    return {k: v for k, v in cache.items() if v is not None}


# ---------------------------------------------------------------------------
# BrickLink image download
# ---------------------------------------------------------------------------

def download_bl_image(bl_id: str, out_path: Path) -> bool:
    """Download a BrickLink render. Returns True on success."""
    url = BL_IMAGE_URL.format(bl_id=bl_id)
    req = urllib.request.Request(url, headers={
        "User-Agent": "Bricky-DINOv2-Eval/1.0",
    })
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = resp.read()
        if len(data) < 500:
            # Likely a placeholder/error image
            return False
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_bytes(data)
        return True
    except (urllib.error.HTTPError, urllib.error.URLError):
        return False


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

def cmd_fetch(args) -> int:
    """Download BrickLink renders for catalog figures."""
    # Load catalog — only figures that have local Rebrickable renders
    with gzip.open(CATALOG_PATH, "rb") as f:
        data = json.load(f)
    figs = data["figures"] if isinstance(data, dict) else data
    available = []
    for f in figs:
        fid = f["id"]
        if (IMAGES_ROOT / f"{fid}.jpg").exists():
            available.append(fid)
    print(f"Catalog has {len(available)} figures with local renders")

    # Select which figures to fetch
    if args.figures and args.figures < len(available):
        import random
        rng = random.Random(args.seed)
        available = rng.sample(available, args.figures)
        print(f"Selected {args.figures} figures (seed={args.seed})")

    # Get BrickLink IDs
    mapping = load_or_build_mapping(available)
    print(f"{len(mapping)} figures have BrickLink IDs")

    # Download images
    out_dir = args.out
    out_dir.mkdir(parents=True, exist_ok=True)
    downloaded = 0
    skipped = 0
    failed = 0

    to_fetch = [(fid, bl_id) for fid, bl_id in mapping.items() if fid in set(available)]
    for i, (fid, bl_id) in enumerate(to_fetch):
        out_path = out_dir / f"{fid}.png"
        if out_path.exists():
            skipped += 1
            continue
        ok = download_bl_image(bl_id, out_path)
        if ok:
            downloaded += 1
        else:
            failed += 1
        if (i + 1) % 20 == 0:
            print(f"  [{i+1}/{len(to_fetch)}] downloaded={downloaded} skipped={skipped} failed={failed}",
                  flush=True)
        time.sleep(0.3)  # polite delay

    print(f"\nDone: {downloaded} downloaded, {skipped} already existed, {failed} failed")

    # Write an index mapping fig_id → bl_id for successfully downloaded images
    index = {}
    for fid, bl_id in mapping.items():
        p = out_dir / f"{fid}.png"
        if p.exists():
            index[fid] = {"bl_id": bl_id, "file": f"{fid}.png"}
    (out_dir / "index.json").write_text(json.dumps(index, indent=2))
    print(f"Wrote index.json with {len(index)} entries")
    return 0


def cmd_eval(args) -> int:
    """Build a cross-source eval set from downloaded BrickLink images.

    Creates ground_truth.json + variants/ directory compatible with
    evaluate_retrieval.py. Each BrickLink render becomes a single
    "variant" for its figure — no synthetic augmentation needed since
    the render-style difference IS the domain gap we're testing.
    """
    bl_dir = args.images
    index_path = bl_dir / "index.json"
    if not index_path.exists():
        print(f"No index.json in {bl_dir}. Run 'fetch' first.")
        return 1

    index = json.loads(index_path.read_text())
    # Optionally exclude held-out figures from the main eval set
    # to avoid overlap
    exclude = set()
    main_eval = Path(__file__).resolve().parent / "eval" / "ground_truth.json"
    if main_eval.exists():
        gt = json.loads(main_eval.read_text())
        exclude = {e["figure_id"] for e in gt["ground_truth"]}
        print(f"Excluding {len(exclude)} figures already in main eval set")

    out_dir = args.out
    out_dir.mkdir(parents=True, exist_ok=True)
    variants_dir = out_dir / "variants"
    variants_dir.mkdir(exist_ok=True)

    ground_truth = []
    count = 0

    for fid, info in sorted(index.items()):
        if args.exclude_main_eval and fid in exclude:
            continue
        src = bl_dir / info["file"]
        if not src.exists():
            continue

        # Convert PNG (possibly with alpha) to RGB JPEG
        img = Image.open(src).convert("RGB")
        fig_dir = variants_dir / fid
        fig_dir.mkdir(exist_ok=True)
        out_path = fig_dir / "bricklink.jpg"
        img.save(out_path, "JPEG", quality=90)

        ground_truth.append({
            "figure_id": fid,
            "variants": ["bricklink.jpg"],
        })
        count += 1

    gt_doc = {
        "description": "Cross-source eval: BrickLink renders queried against Rebrickable index",
        "source": "BrickLink CDN (img.bricklink.com)",
        "held_out": [],
        "ground_truth": ground_truth,
    }
    (out_dir / "ground_truth.json").write_text(json.dumps(gt_doc, indent=2))
    print(f"Built cross-source eval set: {count} figures in {out_dir}")
    print(f"Run: python evaluate_retrieval.py --eval {out_dir}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    sub = parser.add_subparsers(dest="command")

    p_fetch = sub.add_parser("fetch", help="Download BrickLink renders")
    p_fetch.add_argument("--out", type=Path, default=DEFAULT_OUT,
                         help="Output directory for downloaded images")
    p_fetch.add_argument("--figures", type=int, default=None,
                         help="Limit to N randomly-selected figures (default: all)")
    p_fetch.add_argument("--seed", type=int, default=42,
                         help="Random seed for figure selection")

    p_eval = sub.add_parser("eval", help="Build cross-source eval set")
    p_eval.add_argument("--images", type=Path, default=DEFAULT_OUT,
                        help="Directory with downloaded BrickLink images")
    p_eval.add_argument("--out", type=Path, default=DEFAULT_EVAL_OUT,
                        help="Output eval directory")
    p_eval.add_argument("--exclude-main-eval", action="store_true",
                        help="Exclude figures already in the main synthetic eval set")

    args = parser.parse_args()
    if args.command == "fetch":
        return cmd_fetch(args)
    elif args.command == "eval":
        return cmd_eval(args)
    else:
        parser.print_help()
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
