"""Build the face-region training dataset.

Downloads (or re-uses cached) Rebrickable figure renders and crops the
face band (rows 0.17..0.35 of the centered subject), one image per
figure. This captures the printed face cylinder — expressions, skin
tone, glasses, facial hair — while excluding hair pieces, helmets,
and hats which sit above the face.

Output layout:

    {OUTPUT_DIR}/
        figures/
            fig-000001.jpg
            fig-000002.jpg
            ...
        manifest.json   # { "figures": [{ "id": "fig-000001", ... }] }

Mirrors build-torso-dataset.py but targets the face region.
Figures with generic yellow faces still get included — the contrastive
trainer will learn that they're all similar (which is the correct
embedding behavior), and the runtime can gate on how distinctive
a face is before trusting the face encoder's vote.
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
DEFAULT_OUTPUT = Path(__file__).resolve().parent / "data-face"
FACE_TOP = 0.17
FACE_BOTTOM = 0.35
TARGET_SIZE = 224
USER_AGENT = "BrickyFaceDatasetBuilder/1.0 (+https://github.com/shribr/Bricky)"


def load_catalog() -> list[dict]:
    with gzip.open(CATALOG_PATH, "rb") as f:
        data = json.load(f)
    figs = data["figures"] if isinstance(data, dict) else data
    return [f for f in figs if (f.get("imgURL") or "").strip()]


def download(url: str, timeout: float = 10, retries: int = 2) -> bytes | None:
    import socket
    for attempt in range(1, retries + 1):
        old_timeout = socket.getdefaulttimeout()
        socket.setdefaulttimeout(timeout)
        try:
            req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.read()
        except Exception as e:
            print(f"  ! download failed (attempt {attempt}): {url} ({e})",
                  file=sys.stderr, flush=True)
            if attempt < retries:
                time.sleep(2 * attempt)  # back off before retry
        finally:
            socket.setdefaulttimeout(old_timeout)
    return None


def crop_face(raw: bytes) -> Image.Image | None:
    try:
        img = Image.open(io.BytesIO(raw)).convert("RGB")
    except Exception:
        return None
    w, h = img.size
    if w < 32 or h < 64:
        return None
    top = int(h * FACE_TOP)
    bottom = int(h * FACE_BOTTOM)
    band = img.crop((0, top, w, bottom))
    band.thumbnail((TARGET_SIZE, TARGET_SIZE), Image.LANCZOS)
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
    parser.add_argument("--reuse-torso-cache", type=Path, default=None,
                        help="Path to the torso data/ dir. If a figure's "
                             "full-render image was already downloaded there, "
                             "we can re-crop the head from it instead of "
                             "re-downloading from Rebrickable.")
    args = parser.parse_args()
    print(f"Face crop region: {FACE_TOP*100:.0f}%–{FACE_BOTTOM*100:.0f}% (excluding hair/helmets/hats)")

    figures = load_catalog()
    if args.limit:
        figures = figures[: args.limit]
    out_root: Path = args.output
    figs_dir = out_root / "figures"
    figs_dir.mkdir(parents=True, exist_ok=True)

    # If the torso pipeline already cached full renders, reuse them.
    torso_cache: dict[str, Path] | None = None
    if args.reuse_torso_cache and (args.reuse_torso_cache / "figures").is_dir():
        # The torso pipeline saves cropped torsos, not full renders.
        # We can't re-crop heads from torso crops. Must re-download.
        torso_cache = None

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
        crop = crop_face(raw)
        if crop is None:
            skipped += 1
            continue
        crop.save(out_path, "JPEG", quality=85)
        manifest.append({"id": fig_id, "name": fig.get("name", "")})
        if (i + 1) % 100 == 0:
            print(f"  {i + 1}/{len(figures)} processed ({skipped} skipped)", flush=True)
        time.sleep(args.sleep)

    manifest_path = out_root / "manifest.json"
    manifest_path.write_text(json.dumps({"figures": manifest}, separators=(",", ":")))
    print(f"Wrote {len(manifest)} face crops to {figs_dir}")
    print(f"Manifest: {manifest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
