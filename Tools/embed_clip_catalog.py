#!/usr/bin/env python3
"""Embed minifigure datasets with the LEGO-specific CLIP encoder.

Model: Armaggheddon/clip-vit-base-patch32_lego-minifigure
  - Fine-tuned CLIP ViT-B/32 on 12,966 LEGO minifigure images
  - 512-D L2-normalized embeddings
  - MIT license

Produces the same .bin + .json layout that the iOS runtime expects
(see Bricky/Services/TorsoEmbeddingIndex.swift), so the CLIP embeddings
can be loaded by the same index class with minimal Swift changes.

By default this builds a unified index from:
    - Bundled catalog renders in Bricky/Resources/MinifigImages/
    - HuggingFace caption-dataset images that fill missing catalog IDs
    - Reviewed real phone photos from Tools/dinov2-embeddings/real_photos/mapping.json

Output (to Bricky/Resources/ClipEmbeddings/):
    clip_embeddings.bin          — Float16 matrix, row-major, count × 512
    clip_embeddings_index.json   — { dim, count, dtype, ids[] }

Usage:
    python3 Tools/embed_clip_catalog.py [--batch-size 64] [--device cpu|cuda|mps]
"""

from __future__ import annotations

import argparse
import gzip
import json
import time
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import torch
from PIL import Image

BRICKY_ROOT = Path(__file__).resolve().parents[1]
CATALOG_PATH = BRICKY_ROOT / "Bricky" / "Resources" / "MinifigureCatalog.json.gz"
IMAGES_ROOT = BRICKY_ROOT / "Bricky" / "Resources" / "MinifigImages"
DEFAULT_OUT = BRICKY_ROOT / "Bricky" / "Resources" / "ClipEmbeddings"
DEFAULT_HF_DATASET = BRICKY_ROOT / "Tools" / "datasets" / "huggingface-lego-captions"
DEFAULT_REAL_PHOTO_MAPPING = BRICKY_ROOT / "Tools" / "dinov2-embeddings" / "real_photos" / "mapping.json"
DEFAULT_REAL_PHOTO_DIR = BRICKY_ROOT / "images" / "figurines"

MODEL_NAME = "Armaggheddon/clip-vit-base-patch32_lego-minifigure"
EMBEDDING_DIM = 512
INPUT_SIZE = 224


@dataclass(frozen=True)
class ImageEntry:
    figure_id: str
    image_path: Path
    source: str


def detect_figure_bbox(img: Image.Image) -> tuple[int, int, int, int]:
    """Return a foreground crop for real photos with visible background."""
    arr = np.asarray(img.convert("RGB"), dtype=np.float32)
    corners = np.concatenate([
        arr[0:5].reshape(-1, 3),
        arr[-5:].reshape(-1, 3),
        arr[:, 0:5].reshape(-1, 3),
        arr[:, -5:].reshape(-1, 3),
    ])
    bg = corners.mean(axis=0)
    dist = np.sqrt(((arr - bg) ** 2).sum(axis=2))
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


def load_catalog_ids() -> list[ImageEntry]:
    """Return (fig_id, image_path) for every figure with a bundled image."""
    with gzip.open(CATALOG_PATH, "rb") as f:
        data = json.load(f)
    figs = data["figures"] if isinstance(data, dict) else data
    out: list[ImageEntry] = []
    for fig in figs:
        fid = fig["id"]
        p = IMAGES_ROOT / f"{fid}.jpg"
        if p.exists():
            out.append(ImageEntry(fid, p, "catalog_render"))
    return out


def load_huggingface_gap_fill_ids(existing_ids: set[str], dataset_dir: Path) -> list[ImageEntry]:
    """Return HuggingFace images for catalog IDs missing from bundled renders.

    The HuggingFace caption dataset mostly mirrors Rebrickable renders, so
    duplicates add index noise rather than new training signal. Missing IDs are
    still useful because they expand offline coverage.
    """
    metadata_path = dataset_dir / "metadata.json"
    images_dir = dataset_dir / "images"
    if not metadata_path.exists() or not images_dir.exists():
        return []

    metadata = json.loads(metadata_path.read_text())
    out: list[ImageEntry] = []
    seen: set[str] = set()
    for row in metadata:
        fid = row.get("fig_num")
        filename = row.get("filename")
        if not fid or not filename or fid in existing_ids or fid in seen:
            continue
        image_path = images_dir / filename
        if image_path.exists():
            out.append(ImageEntry(fid, image_path, "huggingface_gap_fill"))
            seen.add(fid)
    return out


def load_real_photo_ids(mapping_path: Path, photos_dir: Path) -> list[ImageEntry]:
    """Return reviewed real-photo entries from an ingest_real_photos mapping."""
    if not mapping_path.exists() or not photos_dir.exists():
        return []

    mapping = json.loads(mapping_path.read_text())
    out: list[ImageEntry] = []
    for row in mapping:
        fid = row.get("figure_id")
        filename = row.get("filename")
        if not fid or not filename:
            continue
        image_path = photos_dir / filename
        if image_path.exists():
            out.append(ImageEntry(fid, image_path, "real_photo"))
    return out


def load_entries(args: argparse.Namespace) -> list[ImageEntry]:
    catalog_entries = load_catalog_ids()
    entries = list(catalog_entries)
    existing_ids = {entry.figure_id for entry in catalog_entries}

    if args.include_huggingface:
        entries.extend(load_huggingface_gap_fill_ids(existing_ids, Path(args.huggingface_dataset)))

    if args.include_real_photos:
        entries.extend(load_real_photo_ids(Path(args.real_photo_mapping), Path(args.real_photo_dir)))

    return entries


def main():
    parser = argparse.ArgumentParser(description="Generate CLIP embeddings for minifigure catalog")
    parser.add_argument("--batch-size", type=int, default=64)
    parser.add_argument("--device", type=str, default="auto",
                        choices=["auto", "cpu", "cuda", "mps"])
    parser.add_argument("--output", type=str, default=str(DEFAULT_OUT))
    parser.add_argument("--no-huggingface", dest="include_huggingface", action="store_false",
                        help="Do not include HuggingFace gap-fill images.")
    parser.add_argument("--huggingface-dataset", type=str, default=str(DEFAULT_HF_DATASET))
    parser.add_argument("--no-real-photos", dest="include_real_photos", action="store_false",
                        help="Do not include reviewed real-phone photos.")
    parser.add_argument("--real-photo-mapping", type=str, default=str(DEFAULT_REAL_PHOTO_MAPPING))
    parser.add_argument("--real-photo-dir", type=str, default=str(DEFAULT_REAL_PHOTO_DIR))
    parser.set_defaults(include_huggingface=True, include_real_photos=True)
    args = parser.parse_args()

    out_dir = Path(args.output)
    out_dir.mkdir(parents=True, exist_ok=True)

    # Select device
    if args.device == "auto":
        if torch.cuda.is_available():
            device = torch.device("cuda")
        elif hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
            device = torch.device("mps")
        else:
            device = torch.device("cpu")
    else:
        device = torch.device(args.device)
    print(f"Device: {device}")

    # Load model
    print(f"Loading CLIP model: {MODEL_NAME}")
    from transformers import CLIPModel, CLIPProcessor
    model = CLIPModel.from_pretrained(MODEL_NAME)
    processor = CLIPProcessor.from_pretrained(MODEL_NAME)
    model.eval()
    model.to(device)

    # Load datasets
    entries = load_entries(args)
    source_counts: dict[str, int] = {}
    for entry in entries:
        source_counts[entry.source] = source_counts.get(entry.source, 0) + 1
    print(f"Found {len(entries)} images")
    for source, count in sorted(source_counts.items()):
        print(f"  {source}: {count}")

    # Process in batches
    all_ids: list[str] = []
    all_embeddings: list[np.ndarray] = []
    batch_size = args.batch_size
    t0 = time.time()

    for batch_start in range(0, len(entries), batch_size):
        batch = entries[batch_start:batch_start + batch_size]
        images = []
        ids = []
        for entry in batch:
            try:
                img = Image.open(entry.image_path).convert("RGB")
                if entry.source == "real_photo":
                    img = img.crop(detect_figure_bbox(img))
                images.append(img)
                ids.append(entry.figure_id)
            except Exception as e:
                print(f"  SKIP {entry.figure_id} ({entry.image_path}): {e}")
                continue

        if not images:
            continue

        # Process through CLIP
        inputs = processor(images=images, return_tensors="pt", padding=True)
        inputs = {k: v.to(device) for k, v in inputs.items()}

        with torch.no_grad():
            vision_outputs = model.vision_model(**inputs)
            pooled = vision_outputs.pooler_output
            projected = model.visual_projection(pooled)
            # L2 normalize
            embeddings = projected / projected.norm(dim=-1, keepdim=True)
            embeddings = embeddings.cpu().numpy().astype(np.float32)

        all_ids.extend(ids)
        all_embeddings.append(embeddings)

        done = batch_start + len(batch)
        elapsed = time.time() - t0
        rate = done / elapsed
        eta = (len(entries) - done) / rate if rate > 0 else 0
        print(f"  [{done}/{len(entries)}] {rate:.1f} fig/s  ETA {eta:.0f}s")

    # Stack all embeddings
    matrix = np.vstack(all_embeddings)  # (N, 512)
    assert matrix.shape == (len(all_ids), EMBEDDING_DIM), \
        f"Shape mismatch: {matrix.shape} vs ({len(all_ids)}, {EMBEDDING_DIM})"

    # Convert to Float16 for compact storage (matches DINOv2 format)
    matrix_f16 = matrix.astype(np.float16)

    # Write binary matrix
    bin_path = out_dir / "clip_embeddings.bin"
    matrix_f16.tofile(str(bin_path))
    print(f"\nWrote {bin_path} ({bin_path.stat().st_size / 1024 / 1024:.1f} MB)")

    # Write index JSON
    index = {
        "model": MODEL_NAME,
        "dim": EMBEDDING_DIM,
        "count": len(all_ids),
        "dtype": "float16",
        "ids": all_ids,
        "sources": source_counts,
        "duplicate_ids_are_additional_views": True,
    }
    json_path = out_dir / "clip_embeddings_index.json"
    with open(json_path, "w") as f:
        json.dump(index, f)
    print(f"Wrote {json_path}")

    elapsed = time.time() - t0
    print(f"\nDone: {len(all_ids)} embeddings × {EMBEDDING_DIM}D in {elapsed:.1f}s")

    # Quick validation: check the saved Float16 matrix and a few cosine similarities.
    validation_matrix = matrix_f16.astype(np.float32)
    if not np.isfinite(validation_matrix).all():
        raise RuntimeError("Generated CLIP matrix contains NaN or Inf values")
    norms = np.linalg.norm(validation_matrix, axis=1)
    bad_norms = int(((norms < 0.98) | (norms > 1.02)).sum())
    if bad_norms:
        raise RuntimeError(f"Generated CLIP matrix has {bad_norms} non-normalized row(s)")

    print("\nValidation — top-3 nearest neighbors for first 3 figures:")
    for i in range(min(3, len(all_ids))):
        query = validation_matrix[i]
        # Cosine similarity (already L2-normalized, so dot product)
        sims = validation_matrix @ query
        top_indices = np.argsort(-sims)[1:4]  # skip self
        print(f"  {all_ids[i]}:")
        for j in top_indices:
            print(f"    {all_ids[j]}: cosine={sims[j]:.4f}")


if __name__ == "__main__":
    main()
