#!/usr/bin/env python3
"""Fetch replacement image URLs from the Rebrickable API for figures whose
CDN images are broken (404).

Usage:
    export REBRICKABLE_API_KEY="your-key-here"
    python3 Tools/fetch_replacement_images.py Tools/torso-embeddings/missing_images.json

Requires a free Rebrickable API key from https://rebrickable.com/api/

For each broken figure, queries GET /api/v3/lego/minifigs/{fig-XXXXXX}/
and extracts set_img_url. If a replacement is found, the figure's imgURL
in the catalog is updated.
"""

import gzip
import json
import os
import sys
import time
import urllib.request
from pathlib import Path

CATALOG = Path("Bricky/Resources/MinifigureCatalog.json.gz")
API_BASE = "https://rebrickable.com/api/v3/lego/minifigs"


def main():
    api_key = os.environ.get("REBRICKABLE_API_KEY", "")
    if not api_key:
        print("Error: Set REBRICKABLE_API_KEY environment variable")
        print("Get a free key at https://rebrickable.com/api/")
        sys.exit(1)

    if len(sys.argv) < 2:
        print("Usage: python3 Tools/fetch_replacement_images.py <missing_images.json>")
        sys.exit(1)

    missing_path = Path(sys.argv[1])
    with open(missing_path) as f:
        data = json.load(f)
    broken_ids = data.get("figIds", [])
    print(f"Loaded {len(broken_ids)} broken figure IDs")

    # Load catalog
    with gzip.open(CATALOG, "rt", encoding="utf-8") as f:
        catalog = json.load(f)
    figures = catalog["figures"] if isinstance(catalog, dict) and "figures" in catalog else catalog
    fig_map = {fig["id"]: fig for fig in figures}

    found = 0
    not_found = 0
    errors = 0
    replacements = {}

    for i, fig_id in enumerate(broken_ids):
        # Rebrickable uses the format "fig-XXXXXX" as set_num
        set_num = fig_id
        url = f"{API_BASE}/{set_num}/?key={api_key}"

        try:
            req = urllib.request.Request(url, headers={"Accept": "application/json"})
            with urllib.request.urlopen(req, timeout=10) as resp:
                result = json.loads(resp.read())
                img_url = result.get("set_img_url", "")
                if img_url:
                    replacements[fig_id] = img_url
                    found += 1
                else:
                    not_found += 1
        except urllib.error.HTTPError as e:
            if e.code == 404:
                not_found += 1
            elif e.code == 429:
                print(f"  Rate limited at {i+1}, waiting 60s...", flush=True)
                time.sleep(60)
                continue  # retry
            else:
                errors += 1
        except Exception:
            errors += 1

        if (i + 1) % 100 == 0:
            print(f"  checked {i+1}/{len(broken_ids)}: {found} found, {not_found} not found, {errors} errors", flush=True)

        time.sleep(0.5)  # Rebrickable free tier: 1 req/sec

    print(f"\nResults: {found} replacements, {not_found} not found, {errors} errors")

    # Apply replacements to catalog
    patched = 0
    for fig_id, new_url in replacements.items():
        if fig_id in fig_map:
            fig_map[fig_id]["imgURL"] = new_url
            patched += 1

    if patched > 0:
        with gzip.open(CATALOG, "wt", encoding="utf-8") as f:
            json.dump(catalog, f, separators=(",", ":"))
        print(f"Patched {patched} figures in {CATALOG}")
    else:
        print("No replacements to apply")

    # Save replacement map for reference
    out_path = Path("Tools/torso-embeddings/replacement_images.json")
    with open(out_path, "w") as f:
        json.dump({"count": len(replacements), "replacements": replacements}, f, indent=2)
    print(f"Saved replacement map to {out_path}")


if __name__ == "__main__":
    main()
