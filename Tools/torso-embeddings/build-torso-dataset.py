"""Build the torso-embedding training dataset.

Downloads (or re-uses cached) Rebrickable figure renders and crops the
torso band (rows 0.30..0.70 of the centered subject), one image per
figure. Output layout:

    {OUTPUT_DIR}/
        figures/
            fig-000001.jpg
            fig-000002.jpg
            ...
        manifest.json   # { "figures": [{ "id": "fig-000001", "torsoColor": "...", ... }] }

The manifest carries the fields the trainer needs to do *stratified*
sampling (so every minibatch contains a mix of color buckets and not
just whatever happens to be alphabetically first).

This is intentionally separate from build-reference-set.py — that
script optimizes for **bundle size** and ships ~3K curated renders,
while this one optimizes for **training coverage** and pulls every
figure with a usable image (~16K).
"""

from __future__ import annotations

import argparse
import gzip
import io
import json
import os
import sys
import time
import urllib.request
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # pragma: no cover
    sys.exit("Pillow is required: pip install Pillow")


CATALOG_PATH = Path(__file__).resolve().parents[2] / "Bricky" / "Resources" / "MinifigureCatalog.json.gz"
DEFAULT_OUTPUT = Path(__file__).resolve().parent / "data"
TORSO_TOP = 0.30
TORSO_BOTTOM = 0.70
TARGET_SIZE = 224  # square crop fed to the encoder
USER_AGENT = "BrickyTorsoDatasetBuilder/1.0 (+https://github.com/shribr/Bricky)"


def load_catalog() -> list[dict]:
    with gzip.open(CATALOG_PATH, "rb") as f:
        data = json.load(f)
    figs = data["figures"] if isinstance(data, dict) else data
    return [f for f in figs if (f.get("imgURL") or "").strip()]


def download(url: str, timeout: float = 15) -> bytes | None:
    try:
        req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.read()
    except Exception as e:
        print(f"  ! download failed: {url} ({e})", file=sys.stderr)
        return None


def crop_torso(raw: bytes) -> Image.Image | None:
    try:
        img = Image.open(io.BytesIO(raw)).convert("RGB")
    except Exception:
        return None
    w, h = img.size
    if w < 32 or h < 64:
        return None
    # Vision saliency on the workstation isn't worth the dependency
    # weight here — Rebrickable renders are already centered with a
    # white background, so a fixed vertical band slice matches the
    # runtime crop closely enough for training.
    top = int(h * TORSO_TOP)
    bottom = int(h * TORSO_BOTTOM)
    band = img.crop((0, top, w, bottom))
    band.thumbnail((TARGET_SIZE, TARGET_SIZE), Image.LANCZOS)
    # Pad to square so the encoder always sees a fixed shape.
    sq = Image.new("RGB", (TARGET_SIZE, TARGET_SIZE), (244, 244, 244))
    bw, bh = band.size
    sq.paste(band, ((TARGET_SIZE - bw) // 2, (TARGET_SIZE - bh) // 2))
    return sq


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--limit", type=int, default=0,
                        help="Cap to N figures (for smoke tests).")
    parser.add_argument("--sleep", type=float, default=0.05,
                        help="Polite delay between downloads (sec).")
    args = parser.parse_args()

    figures = load_catalog()
    if args.limit:
        figures = figures[: args.limit]
    out_root: Path = args.output
    figs_dir = out_root / "figures"
    figs_dir.mkdir(parents=True, exist_ok=True)

    manifest: list[dict] = []
    skipped = 0
    for i, fig in enumerate(figures):
        fig_id = fig["id"]
        out_path = figs_dir / f"{fig_id}.jpg"
        if out_path.exists():
            manifest.append({"id": fig_id, "name": fig.get("name", "")})
            continue
        raw = download(fig["imgURL"])
        if not raw:
            skipped += 1
            continue
        crop = crop_torso(raw)
        if crop is None:
            skipped += 1
            continue
        crop.save(out_path, "JPEG", quality=85)
        manifest.append({"id": fig_id, "name": fig.get("name", "")})
        if (i + 1) % 100 == 0:
            print(f"  {i + 1}/{len(figures)} processed ({skipped} skipped)")
        time.sleep(args.sleep)

    manifest_path = out_root / "manifest.json"
    manifest_path.write_text(json.dumps({"figures": manifest}, separators=(",", ":")))
    print(f"Wrote {len(manifest)} torso crops to {figs_dir}")
    print(f"Manifest: {manifest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
