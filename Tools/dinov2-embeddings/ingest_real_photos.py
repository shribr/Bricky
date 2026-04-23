"""Ingest real-world minifigure photos into the DINOv2 evaluation and
embedding pipelines.

This script bridges the domain gap between catalog renders (CG images
on cream backgrounds) and real-world phone photos (variable lighting,
shadows, wood-grain backgrounds, etc.).

It does three things:

1. **Map** each photo filename to one or more candidate catalog figure
   IDs by fuzzy-matching the descriptive filename against catalog
   names and themes.  Writes a mapping JSON that can be reviewed and
   hand-corrected before proceeding.

2. **Augment the embedding index** by computing DINOv2 embeddings for
   the real photos and appending them to an existing index.  Each
   figure gets an extra vector from the real photo so that future
   queries of real figures land closer in embedding space.

3. **Build an eval ground-truth file** from the real photos so that
   ``evaluate_retrieval.py`` can score the index against actual
   camera captures instead of synthetic variants only.

Usage
-----
Step 1 — generate the mapping (review & fix before step 2):

    python ingest_real_photos.py map \
        --photos ../../images/figurines \
        --out Tools/dinov2-embeddings/real_photos

Step 2 — augment an existing index:

    python ingest_real_photos.py augment \
        --mapping Tools/dinov2-embeddings/real_photos/mapping.json \
        --index Tools/dinov2-embeddings/index/dinov2_vitl14 \
        --out Tools/dinov2-embeddings/index/dinov2_vitl14_augmented

Step 3 — build an eval set from real photos:

    python ingest_real_photos.py eval \
        --mapping Tools/dinov2-embeddings/real_photos/mapping.json \
        --out Tools/dinov2-embeddings/real_photos/eval

Step 4 — score the index against real photos:

    python evaluate_retrieval.py \
        --index Tools/dinov2-embeddings/index/dinov2_vitl14_augmented \
        --eval Tools/dinov2-embeddings/real_photos/eval \
        --report Tools/dinov2-embeddings/reports/real_photos_vitl14.json
"""

from __future__ import annotations

import argparse
import gzip
import json
import re
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image

BRICKY_ROOT = Path(__file__).resolve().parents[2]
CATALOG_PATH = BRICKY_ROOT / "Bricky" / "Resources" / "MinifigureCatalog.json.gz"
DEFAULT_PHOTOS = BRICKY_ROOT / "images" / "figurines"


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

def load_catalog() -> list[dict]:
    with gzip.open(CATALOG_PATH, "rb") as f:
        data = json.load(f)
    return data["figures"] if isinstance(data, dict) else data


def tokenize(text: str) -> set[str]:
    """Lowercase, split on non-alphanumeric, drop empties."""
    return {t for t in re.split(r"[^a-z0-9]+", text.lower()) if t}


def filename_to_search_terms(name: str) -> tuple[str, set[str]]:
    """Extract a BrickLink-style ID prefix and descriptive tokens
    from a filename like 'sp002_blacktron_two_astronaut.jpeg'.

    Returns (prefix, tokens) where prefix is e.g. 'sp002' and tokens
    is {'blacktron', 'two', 'astronaut'}.
    """
    stem = Path(name).stem
    # Handle 'uncertain_' prefix
    if stem.startswith("uncertain_"):
        stem = stem[len("uncertain_"):]
    parts = stem.split("_", 1)
    prefix = parts[0]
    description = parts[1] if len(parts) > 1 else ""
    tokens = tokenize(description)
    tokens.add(prefix.lower())
    return prefix, tokens


def score_match(fig: dict, prefix: str, tokens: set[str]) -> float:
    """Score how well a catalog figure matches filename tokens.
    Higher = better match.  Returns 0 if clearly unrelated."""
    name_tokens = tokenize(fig.get("name", ""))
    theme_tokens = tokenize(fig.get("theme", ""))
    all_tokens = name_tokens | theme_tokens

    # Exact prefix in name (e.g. 'sp002' appears in fig name)
    prefix_bonus = 2.0 if prefix.lower() in fig.get("name", "").lower() else 0.0

    # Token overlap (Jaccard-ish but weighted toward recall)
    if not tokens:
        return prefix_bonus
    overlap = tokens & all_tokens
    if not overlap:
        return prefix_bonus * 0.5  # prefix-only match is weak
    # Fraction of filename tokens found in catalog entry
    recall = len(overlap) / len(tokens)
    # Bonus for matching more descriptive words
    score = recall * 10 + len(overlap) + prefix_bonus
    return score


# ---------------------------------------------------------------------------
# Command: map
# ---------------------------------------------------------------------------

def cmd_map(args: argparse.Namespace) -> int:
    """Fuzzy-match photo filenames to catalog figure IDs."""
    photos_dir = Path(args.photos)
    if not photos_dir.exists():
        sys.exit(f"Photos directory not found: {photos_dir}")

    photo_files = sorted(
        p for p in photos_dir.iterdir()
        if p.suffix.lower() in {".jpg", ".jpeg", ".png"}
    )
    if not photo_files:
        sys.exit(f"No image files found in {photos_dir}")

    catalog = load_catalog()
    print(f"Loaded {len(catalog)} catalog figures, {len(photo_files)} photos")

    mapping: list[dict] = []
    for pf in photo_files:
        prefix, tokens = filename_to_search_terms(pf.name)
        scored = [(score_match(f, prefix, tokens), f) for f in catalog]
        scored.sort(key=lambda x: -x[0])
        top = scored[:5]

        # Auto-pick if the top score is reasonable and clearly ahead of
        # candidates from *different* base figures.  Ties between variants
        # of the same figure (e.g. "Ice Planet - White Hair" vs "Ice Planet
        # - Red Hair") are fine — we just need any correct base figure.
        best_score = top[0][0]
        runner_up = top[1][0] if len(top) > 1 else 0
        confident = best_score >= 6.0 and (
            best_score > runner_up * 1.3 or best_score >= 9.0
        )

        entry = {
            "filename": pf.name,
            "search_prefix": prefix,
            "search_tokens": sorted(tokens),
            "figure_id": top[0][1]["id"] if confident else None,
            "figure_name": top[0][1]["name"] if confident else None,
            "confident": confident,
            "uncertain": pf.stem.startswith("uncertain"),
            "candidates": [
                {
                    "id": f["id"],
                    "name": f["name"],
                    "theme": f.get("theme", ""),
                    "score": round(s, 2),
                }
                for s, f in top
                if s > 0
            ],
        }
        status = "✓" if confident else "?"
        print(f"  {status} {pf.name}")
        if confident:
            print(f"      → {top[0][1]['id']}  {top[0][1]['name']}")
        else:
            print(f"      Top candidates:")
            for s, f in top[:3]:
                if s > 0:
                    print(f"        {f['id']}  {f['name']}  (score={s:.1f})")

        mapping.append(entry)

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    mapping_path = out_dir / "mapping.json"
    mapping_path.write_text(json.dumps(mapping, indent=2))

    matched = sum(1 for m in mapping if m["figure_id"])
    unmatched = len(mapping) - matched
    print(f"\nWrote {mapping_path}")
    print(f"  {matched} auto-matched, {unmatched} need manual review")
    if unmatched:
        print(f"\n  Edit {mapping_path} and fill in 'figure_id' for unmatched entries,")
        print(f"  then run the 'augment' or 'eval' commands.")
    return 0


# ---------------------------------------------------------------------------
# Command: augment
# ---------------------------------------------------------------------------

def cmd_augment(args: argparse.Namespace) -> int:
    """Embed real photos and append to an existing index."""
    import torch
    import torch.nn.functional as F
    from torchvision import transforms
    from embed_catalog import torso_crop, load_dinov2

    mapping_path = Path(args.mapping)
    mapping = json.loads(mapping_path.read_text())
    photos_dir = mapping_path.parent if not args.photos else Path(args.photos)

    # Fall back to the original photos directory
    if not (photos_dir / mapping[0]["filename"]).exists():
        photos_dir = DEFAULT_PHOTOS

    # Load existing index
    index_dir = Path(args.index)
    meta = json.loads((index_dir / "torso_embeddings_index.json").read_text())
    raw = (index_dir / "torso_embeddings.bin").read_bytes()
    np_dtype = {"float16": np.float16, "float32": np.float32}[meta.get("dtype", "float16")]
    existing = np.frombuffer(raw, dtype=np_dtype).reshape(meta["count"], meta["dim"]).copy()
    existing_ids = list(meta["ids"])
    encoder_name = meta["encoder"]
    dim = meta["dim"]

    # Filter to mapped photos
    valid = [(m["filename"], m["figure_id"]) for m in mapping if m.get("figure_id")]
    if not valid:
        sys.exit("No mapped photos found. Run 'map' first and fill in figure_ids.")
    print(f"Augmenting index with {len(valid)} real photos using {encoder_name}")

    device = args.device
    model = load_dinov2(encoder_name, device, random_init=args.random_init)
    tx = transforms.Compose([
        transforms.ToTensor(),
        transforms.Normalize(mean=[0.485, 0.456, 0.406],
                             std=[0.229, 0.224, 0.225]),
    ])

    new_rows: list[np.ndarray] = []
    new_ids: list[str] = []
    skipped = 0

    for fname, fid in valid:
        p = photos_dir / fname
        if not p.exists():
            print(f"  ! skip {fname}: file not found at {p}")
            skipped += 1
            continue
        try:
            img = Image.open(p).convert("RGB")
            # Real photos: detect the figure bounding box first, then torso-crop.
            # This handles the fact that real photos have the figure occupying a
            # variable portion of the frame (unlike catalog renders which are tightly
            # cropped).
            img = img.crop(detect_figure_bbox(img))
            crop = torso_crop(img)
            tensor = tx(crop).unsqueeze(0).to(device)
            with torch.no_grad():
                emb = F.normalize(model(tensor), dim=-1).cpu().numpy().astype(np.float32)
            new_rows.append(emb)
            new_ids.append(fid)
        except Exception as e:
            print(f"  ! skip {fname}: {e}")
            skipped += 1

    if not new_rows:
        sys.exit("No photos could be embedded.")

    new_matrix = np.concatenate(new_rows, axis=0)
    combined = np.concatenate([existing.astype(np.float32), new_matrix], axis=0)
    combined_ids = existing_ids + new_ids

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    combined_f16 = combined.astype(np.float16)
    (out_dir / "torso_embeddings.bin").write_bytes(combined_f16.tobytes())
    (out_dir / "torso_embeddings_index.json").write_text(json.dumps({
        "dim": dim,
        "count": int(combined.shape[0]),
        "dtype": "float16",
        "ids": combined_ids,
        "encoder": encoder_name,
        "augmented_with_real_photos": len(new_ids),
    }, separators=(",", ":")))

    print(f"\nWrote augmented index to {out_dir}")
    print(f"  Original: {existing.shape[0]} entries")
    print(f"  Added:    {len(new_ids)} real-photo entries")
    print(f"  Total:    {combined.shape[0]} entries")
    if skipped:
        print(f"  Skipped:  {skipped}")
    return 0


# ---------------------------------------------------------------------------
# Command: eval
# ---------------------------------------------------------------------------

def cmd_eval(args: argparse.Namespace) -> int:
    """Build an eval ground-truth set from real photos.

    Creates the same directory structure evaluate_retrieval.py expects:
        eval/ground_truth.json
        eval/variants/<figure_id>/<filename>
    """
    mapping_path = Path(args.mapping)
    mapping = json.loads(mapping_path.read_text())
    photos_dir = mapping_path.parent if not args.photos else Path(args.photos)
    if not (photos_dir / mapping[0]["filename"]).exists():
        photos_dir = DEFAULT_PHOTOS

    valid = [(m["filename"], m["figure_id"]) for m in mapping if m.get("figure_id")]
    if not valid:
        sys.exit("No mapped photos. Run 'map' first and fill in figure_ids.")

    out_dir = Path(args.out)
    variants_dir = out_dir / "variants"

    # Group by figure ID
    from collections import defaultdict
    by_fig: dict[str, list[str]] = defaultdict(list)
    for fname, fid in valid:
        by_fig[fid].append(fname)

    ground_truth = []
    for fid, fnames in sorted(by_fig.items()):
        fig_dir = variants_dir / fid
        fig_dir.mkdir(parents=True, exist_ok=True)
        variant_names = []
        for fname in fnames:
            src = photos_dir / fname
            if not src.exists():
                print(f"  ! skip {fname}: not found")
                continue
            dst = fig_dir / fname
            shutil.copy2(src, dst)
            variant_names.append(fname)
        if variant_names:
            ground_truth.append({
                "figure_id": fid,
                "variants": variant_names,
            })

    gt_data = {
        "description": "Real-world photos for retrieval evaluation",
        "source": "images/figurines (iPhone captures)",
        "held_out": [],  # These aren't held out — they test the full index
        "ground_truth": ground_truth,
    }
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "ground_truth.json").write_text(json.dumps(gt_data, indent=2))

    total_variants = sum(len(e["variants"]) for e in ground_truth)
    print(f"Wrote eval set to {out_dir}")
    print(f"  {len(ground_truth)} figures, {total_variants} variants")
    return 0


# ---------------------------------------------------------------------------
# Figure bbox detection (handles real photos with background)
# ---------------------------------------------------------------------------

def detect_figure_bbox(img: Image.Image) -> tuple[int, int, int, int]:
    """Detect the bounding box of the minifigure in a real-world photo.

    Real photos have a background (wood table, carpet, etc.) while the
    pipeline expects tightly-cropped figure images.  We use the corner
    pixels to estimate the background color and find the figure as the
    region that differs from it.
    """
    arr = np.asarray(img.convert("RGB"), dtype=np.float32)
    # Sample corners to learn the background
    corners = np.concatenate([
        arr[0:5].reshape(-1, 3),
        arr[-5:].reshape(-1, 3),
        arr[:, 0:5].reshape(-1, 3),
        arr[:, -5:].reshape(-1, 3),
    ])
    bg = corners.mean(axis=0)
    dist = np.sqrt(((arr - bg) ** 2).sum(axis=2))
    # Threshold — real photos have more background variation than renders
    ys, xs = np.where(dist > 50)
    if len(xs) == 0:
        return (0, 0, img.width, img.height)
    pad = 8
    return (
        max(0, int(xs.min()) - pad),
        max(0, int(ys.min()) - pad),
        min(img.width, int(xs.max()) + pad),
        min(img.height, int(ys.max()) + pad),
    )


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(
        description="Ingest real-world minifigure photos into the DINOv2 pipeline.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    sub = parser.add_subparsers(dest="command")

    # map
    p_map = sub.add_parser("map", help="Fuzzy-match filenames to catalog figure IDs")
    p_map.add_argument("--photos", type=str, default=str(DEFAULT_PHOTOS))
    p_map.add_argument("--out", type=str,
                       default=str(Path(__file__).resolve().parent / "real_photos"))

    # augment
    p_aug = sub.add_parser("augment", help="Add real-photo embeddings to an existing index")
    p_aug.add_argument("--mapping", type=str, required=True)
    p_aug.add_argument("--photos", type=str, default=None,
                       help="Photos directory (defaults to same dir as mapping.json)")
    p_aug.add_argument("--index", type=str, required=True)
    p_aug.add_argument("--out", type=str, required=True)
    p_aug.add_argument("--device", default="cuda" if _has_cuda() else "cpu")
    p_aug.add_argument("--random-init", action="store_true")

    # eval
    p_eval = sub.add_parser("eval", help="Build eval ground-truth from real photos")
    p_eval.add_argument("--mapping", type=str, required=True)
    p_eval.add_argument("--photos", type=str, default=None)
    p_eval.add_argument("--out", type=str,
                        default=str(Path(__file__).resolve().parent / "real_photos" / "eval"))

    args = parser.parse_args()
    if args.command == "map":
        return cmd_map(args)
    elif args.command == "augment":
        return cmd_augment(args)
    elif args.command == "eval":
        return cmd_eval(args)
    else:
        parser.print_help()
        return 1


def _has_cuda() -> bool:
    try:
        import torch
        return torch.cuda.is_available()
    except ImportError:
        return False


if __name__ == "__main__":
    raise SystemExit(main())
