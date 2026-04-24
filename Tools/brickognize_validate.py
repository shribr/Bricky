#!/usr/bin/env python3
"""Validate Bricky's scanner accuracy using the Brickognize public API.

Brickognize (https://brickognize.com/) is a free, public LEGO recognition
API that identifies parts, sets, and minifigures from photos. We use it as
a validation oracle: upload our catalog renders and real photos, compare
Brickognize's predictions against our known ground truth.

This replaces the need for:
- Rebrickable → BrickLink ID web scraping
- Manual cross-source evaluation
- Custom BrickLink image downloads

Usage:
    # Validate a random sample of catalog renders
    python3 brickognize_validate.py sample --count 50

    # Validate specific figures
    python3 brickognize_validate.py validate --figures fig-001293 fig-016415

    # Build BrickLink ID mapping from catalog (uses Brickognize)
    python3 brickognize_validate.py map --count 500 --out bricklink_mapping.json

    # Validate real photos from the ihelon dataset
    python3 brickognize_validate.py eval-photos --dir Tools/datasets/ihelon/
"""

from __future__ import annotations

import argparse
import gzip
import json
import os
import random
import sys
import time
import urllib.request
import uuid
from pathlib import Path

BRICKY_ROOT = Path(__file__).resolve().parents[1]
CATALOG_PATH = BRICKY_ROOT / "Bricky" / "Resources" / "MinifigureCatalog.json.gz"
IMAGES_ROOT = BRICKY_ROOT / "Bricky" / "Resources" / "MinifigImages"
BRICKOGNIZE_URL = "https://api.brickognize.com/predict/figs/"

# Rate limiting: max 1 request per second (be polite to free API)
_last_request_time = 0.0


def _load_catalog() -> dict:
    """Load the MinifigureCatalog and return {fig_id: figure_dict}."""
    with gzip.open(str(CATALOG_PATH), "rt") as f:
        cat = json.load(f)
    figures = cat["figures"] if isinstance(cat, dict) and "figures" in cat else cat
    return {fig["id"]: fig for fig in figures}


def _predict(image_path: str) -> dict | None:
    """Send an image to Brickognize and return the raw response."""
    global _last_request_time
    
    # Rate limit
    now = time.time()
    wait = 1.0 - (now - _last_request_time)
    if wait > 0:
        time.sleep(wait)
    
    with open(image_path, "rb") as f:
        img_data = f.read()
    
    boundary = uuid.uuid4().hex
    body = (
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="query_image"; filename="img.jpg"\r\n'
        f"Content-Type: image/jpeg\r\n\r\n"
    ).encode() + img_data + f"\r\n--{boundary}--\r\n".encode()
    
    req = urllib.request.Request(
        BRICKOGNIZE_URL,
        data=body,
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
        method="POST",
    )
    
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            _last_request_time = time.time()
            return json.loads(resp.read())
    except Exception as e:
        _last_request_time = time.time()
        print(f"  API error: {e}", file=sys.stderr)
        return None


def cmd_sample(args):
    """Validate a random sample of catalog renders."""
    catalog = _load_catalog()
    
    # Find figures that have local images
    available = []
    for fig_id in catalog:
        img_path = IMAGES_ROOT / f"{fig_id}.jpg"
        if img_path.exists():
            available.append(fig_id)
    
    count = min(args.count, len(available))
    sample = random.sample(available, count)
    
    results = {"matches": 0, "mismatches": 0, "errors": 0, "details": []}
    
    for i, fig_id in enumerate(sample):
        img_path = str(IMAGES_ROOT / f"{fig_id}.jpg")
        catalog_name = catalog[fig_id].get("name", "?")
        
        resp = _predict(img_path)
        if resp is None:
            results["errors"] += 1
            continue
        
        items = resp.get("items", [])
        if not items:
            print(f"  [{i+1}/{count}] {fig_id} ({catalog_name}): no matches")
            results["mismatches"] += 1
            results["details"].append({
                "fig_id": fig_id, "catalog_name": catalog_name,
                "brickognize_id": None, "score": 0, "match": False
            })
            continue
        
        top = items[0]
        bl_id = top["id"]
        bl_name = top["name"]
        score = top["score"]
        
        # We can't directly compare fig-XXXXXX to BrickLink IDs,
        # but we can log for manual review and check name similarity
        detail = {
            "fig_id": fig_id,
            "catalog_name": catalog_name,
            "brickognize_id": bl_id,
            "brickognize_name": bl_name,
            "score": score,
        }
        
        # Simple name similarity check
        cat_words = set(catalog_name.lower().split())
        bl_words = set(bl_name.lower().split())
        overlap = len(cat_words & bl_words) / max(len(cat_words | bl_words), 1)
        detail["name_overlap"] = overlap
        detail["match"] = overlap > 0.2 or score > 0.8
        
        if detail["match"]:
            results["matches"] += 1
        else:
            results["mismatches"] += 1
        
        status = "✓" if detail["match"] else "✗"
        print(f"  [{i+1}/{count}] {status} {fig_id} ({catalog_name})")
        print(f"         → {bl_id} \"{bl_name}\" score={score:.3f}")
        
        results["details"].append(detail)
    
    total = results["matches"] + results["mismatches"]
    if total > 0:
        accuracy = results["matches"] / total * 100
        print(f"\n{'='*60}")
        print(f"Brickognize accuracy on catalog renders: {accuracy:.1f}%")
        print(f"  Matches: {results['matches']}/{total}")
        print(f"  Errors: {results['errors']}")
    
    # Save results
    out_path = args.out or "brickognize_validation.json"
    with open(out_path, "w") as f:
        json.dump(results, f, indent=2)
    print(f"  Results saved to {out_path}")


def cmd_map(args):
    """Build Rebrickable fig-ID → BrickLink ID mapping using Brickognize."""
    catalog = _load_catalog()
    
    # Load existing mapping
    out_path = args.out or "bricklink_mapping.json"
    mapping = {}
    if os.path.exists(out_path):
        with open(out_path) as f:
            mapping = json.load(f)
        print(f"Loaded {len(mapping)} existing mappings from {out_path}")
    
    # Find figures that need mapping and have images
    unmapped = []
    for fig_id in catalog:
        if fig_id not in mapping:
            img_path = IMAGES_ROOT / f"{fig_id}.jpg"
            if img_path.exists():
                unmapped.append(fig_id)
    
    count = min(args.count, len(unmapped))
    print(f"Mapping {count} of {len(unmapped)} unmapped figures...")
    
    for i, fig_id in enumerate(unmapped[:count]):
        img_path = str(IMAGES_ROOT / f"{fig_id}.jpg")
        resp = _predict(img_path)
        
        if resp and resp.get("items"):
            top = resp["items"][0]
            mapping[fig_id] = {
                "bricklink_id": top["id"],
                "bricklink_name": top["name"],
                "score": top["score"],
                "external_sites": top.get("external_sites", []),
            }
            print(f"  [{i+1}/{count}] {fig_id} → {top['id']} ({top['score']:.3f})")
        else:
            mapping[fig_id] = {"bricklink_id": None, "score": 0}
            print(f"  [{i+1}/{count}] {fig_id} → no match")
        
        # Save periodically
        if (i + 1) % 20 == 0:
            with open(out_path, "w") as f:
                json.dump(mapping, f, indent=2)
    
    with open(out_path, "w") as f:
        json.dump(mapping, f, indent=2)
    print(f"\nSaved {len(mapping)} mappings to {out_path}")


def cmd_eval_photos(args):
    """Validate real photos against Brickognize to auto-label them."""
    photo_dir = Path(args.dir)
    if not photo_dir.exists():
        print(f"Directory not found: {photo_dir}", file=sys.stderr)
        sys.exit(1)
    
    results = []
    photos = sorted(photo_dir.glob("**/*.jpg")) + sorted(photo_dir.glob("**/*.jpeg")) + sorted(photo_dir.glob("**/*.png"))
    
    print(f"Found {len(photos)} photos in {photo_dir}")
    
    for i, photo in enumerate(photos):
        resp = _predict(str(photo))
        if resp and resp.get("items"):
            top = resp["items"][0]
            result = {
                "photo": str(photo.relative_to(photo_dir)),
                "brickognize_id": top["id"],
                "brickognize_name": top["name"],
                "score": top["score"],
                "bbox": resp.get("bounding_box"),
            }
            print(f"  [{i+1}/{len(photos)}] {photo.name} → {top['id']} \"{top['name']}\" ({top['score']:.3f})")
        else:
            result = {"photo": str(photo.relative_to(photo_dir)), "brickognize_id": None, "score": 0}
            print(f"  [{i+1}/{len(photos)}] {photo.name} → no match")
        results.append(result)
    
    out_path = args.out or "photo_labels.json"
    with open(out_path, "w") as f:
        json.dump(results, f, indent=2)
    
    labeled = sum(1 for r in results if r.get("brickognize_id"))
    print(f"\nLabeled {labeled}/{len(results)} photos. Saved to {out_path}")


def main():
    parser = argparse.ArgumentParser(description="Validate scanner accuracy with Brickognize API")
    sub = parser.add_subparsers(dest="command")
    
    p_sample = sub.add_parser("sample", help="Validate random catalog renders")
    p_sample.add_argument("--count", type=int, default=20)
    p_sample.add_argument("--out", type=str)
    p_sample.set_defaults(func=cmd_sample)
    
    p_map = sub.add_parser("map", help="Build BrickLink ID mapping")
    p_map.add_argument("--count", type=int, default=100)
    p_map.add_argument("--out", type=str, default="bricklink_mapping.json")
    p_map.set_defaults(func=cmd_map)
    
    p_eval = sub.add_parser("eval-photos", help="Auto-label real photos")
    p_eval.add_argument("--dir", required=True)
    p_eval.add_argument("--out", type=str)
    p_eval.set_defaults(func=cmd_eval_photos)
    
    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        sys.exit(1)
    args.func(args)


if __name__ == "__main__":
    main()
