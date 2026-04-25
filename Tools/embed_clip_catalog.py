#!/usr/bin/env python3
"""Embed every catalog minifigure image with the LEGO-specific CLIP encoder.

Model: Armaggheddon/clip-vit-base-patch32_lego-minifigure
  - Fine-tuned CLIP ViT-B/32 on 12,966 LEGO minifigure images
  - 512-D L2-normalized embeddings
  - MIT license

Produces the same .bin + .json layout that the iOS runtime expects
(see Bricky/Services/TorsoEmbeddingIndex.swift), so the CLIP embeddings
can be loaded by the same index class with minimal Swift changes.

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
import struct
import sys
import time
from pathlib import Path

import numpy as np
import torch
from PIL import Image

BRICKY_ROOT = Path(__file__).resolve().parents[1]
CATALOG_PATH = BRICKY_ROOT / "Bricky" / "Resources" / "MinifigureCatalog.json.gz"
IMAGES_ROOT = BRICKY_ROOT / "Bricky" / "Resources" / "MinifigImages"
DEFAULT_OUT = BRICKY_ROOT / "Bricky" / "Resources" / "ClipEmbeddings"

MODEL_NAME = "Armaggheddon/clip-vit-base-patch32_lego-minifigure"
EMBEDDING_DIM = 512
INPUT_SIZE = 224


def load_catalog_ids() -> list[tuple[str, Path]]:
    """Return (fig_id, image_path) for every figure with a bundled image."""
    with gzip.open(CATALOG_PATH, "rb") as f:
        data = json.load(f)
    figs = data["figures"] if isinstance(data, dict) else data
    out: list[tuple[str, Path]] = []
    for fig in figs:
        fid = fig["id"]
        p = IMAGES_ROOT / f"{fid}.jpg"
        if p.exists():
            out.append((fid, p))
    return out


def main():
    parser = argparse.ArgumentParser(description="Generate CLIP embeddings for minifigure catalog")
    parser.add_argument("--batch-size", type=int, default=64)
    parser.add_argument("--device", type=str, default="auto",
                        choices=["auto", "cpu", "cuda", "mps"])
    parser.add_argument("--output", type=str, default=str(DEFAULT_OUT))
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

    # Load catalog
    entries = load_catalog_ids()
    print(f"Found {len(entries)} figures with images")

    # Process in batches
    all_ids: list[str] = []
    all_embeddings: list[np.ndarray] = []
    batch_size = args.batch_size
    t0 = time.time()

    for batch_start in range(0, len(entries), batch_size):
        batch = entries[batch_start:batch_start + batch_size]
        images = []
        ids = []
        for fid, img_path in batch:
            try:
                img = Image.open(img_path).convert("RGB")
                images.append(img)
                ids.append(fid)
            except Exception as e:
                print(f"  SKIP {fid}: {e}")
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
    }
    json_path = out_dir / "clip_embeddings_index.json"
    with open(json_path, "w") as f:
        json.dump(index, f)
    print(f"Wrote {json_path}")

    elapsed = time.time() - t0
    print(f"\nDone: {len(all_ids)} embeddings × {EMBEDDING_DIM}D in {elapsed:.1f}s")

    # Quick validation: check a few cosine similarities
    print("\nValidation — top-3 nearest neighbors for first 3 figures:")
    for i in range(min(3, len(all_ids))):
        query = matrix[i]
        # Cosine similarity (already L2-normalized, so dot product)
        sims = matrix @ query
        top_indices = np.argsort(-sims)[1:4]  # skip self
        print(f"  {all_ids[i]}:")
        for j in top_indices:
            print(f"    {all_ids[j]}: cosine={sims[j]:.4f}")


if __name__ == "__main__":
    main()
