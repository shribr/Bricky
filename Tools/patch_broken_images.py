#!/usr/bin/env python3
"""Patch MinifigureCatalog.json.gz to null out imgURL for figures whose
Rebrickable CDN images return 404.

Usage:
    python3 Tools/patch_broken_images.py Tools/torso-embeddings/missing_images.json

Reads the scan output (missing_images.json) produced by the URL-check step,
then rewrites the compressed catalog with imgURL set to null for every
figure ID in the broken list.
"""

import gzip
import json
import sys
from pathlib import Path

CATALOG = Path("Bricky/Resources/MinifigureCatalog.json.gz")


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 Tools/patch_broken_images.py <missing_images.json>")
        sys.exit(1)

    missing_path = Path(sys.argv[1])
    if not missing_path.exists():
        print(f"Error: {missing_path} not found")
        sys.exit(1)

    with open(missing_path) as f:
        data = json.load(f)
    broken_ids = set(data.get("figIds", []))
    print(f"Loaded {len(broken_ids)} broken figure IDs from {missing_path}")

    if not CATALOG.exists():
        print(f"Error: {CATALOG} not found")
        sys.exit(1)

    with gzip.open(CATALOG, "rt", encoding="utf-8") as f:
        catalog = json.load(f)

    patched = 0
    for fig in catalog:
        if fig.get("id") in broken_ids and fig.get("imgURL"):
            fig["imgURL"] = None
            patched += 1

    print(f"Patched {patched} figures (nulled imgURL)")

    with gzip.open(CATALOG, "wt", encoding="utf-8") as f:
        json.dump(catalog, f, separators=(",", ":"))

    size_kb = CATALOG.stat().st_size / 1024
    print(f"Wrote {CATALOG} ({size_kb:.1f} KB)")


if __name__ == "__main__":
    main()
