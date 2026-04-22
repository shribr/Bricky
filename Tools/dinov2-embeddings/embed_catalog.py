"""Embed every catalog render with a pretrained DINOv2 encoder.

Produces the same .bin + .json layout the iOS runtime already knows
how to load (see Bricky/Services/TorsoEmbeddingIndex.swift), so a
winner from this prototype can be swapped in at the resource level
without Swift changes.

Default model is `dinov2_vits14` (~22M params, 384-D embeddings) for
CPU-affordable smoke tests. Use `dinov2_vitb14` (768-D) or
`dinov2_vitl14` (1024-D) for the real run on GPU.

The torso crop strategy mirrors `Tools/torso-embeddings/build-torso-
dataset.py` (vertical band 0.30..0.70 of the centered render) so
we're measuring the encoder, not a crop change. A separate sweep can
replace this with a learned crop later.
"""

from __future__ import annotations

import argparse
import gzip
import json
import sys
import time
from pathlib import Path

import numpy as np
import torch
import torch.nn.functional as F
from PIL import Image
from torchvision import transforms


BRICKY_ROOT = Path(__file__).resolve().parents[2]
CATALOG_PATH = BRICKY_ROOT / "Bricky" / "Resources" / "MinifigureCatalog.json.gz"
IMAGES_ROOT = BRICKY_ROOT / "Bricky" / "Resources" / "MinifigImages"
DEFAULT_OUT = Path(__file__).resolve().parent / "index" / "dinov2_vits14"

TORSO_TOP = 0.30
TORSO_BOTTOM = 0.70
TARGET_SIZE = 224


def load_catalog_paths(exclude_ids: set[str]) -> list[tuple[str, Path]]:
    with gzip.open(CATALOG_PATH, "rb") as f:
        data = json.load(f)
    figs = data["figures"] if isinstance(data, dict) else data
    out: list[tuple[str, Path]] = []
    for f in figs:
        fid = f["id"]
        if fid in exclude_ids:
            continue
        p = IMAGES_ROOT / f"{fid}.jpg"
        if p.exists():
            out.append((fid, p))
    return out


def torso_crop(img: Image.Image) -> Image.Image:
    w, h = img.size
    top = int(h * TORSO_TOP)
    bottom = int(h * TORSO_BOTTOM)
    band = img.crop((0, top, w, bottom))
    band.thumbnail((TARGET_SIZE, TARGET_SIZE), Image.LANCZOS)
    sq = Image.new("RGB", (TARGET_SIZE, TARGET_SIZE), (244, 244, 244))
    bw, bh = band.size
    sq.paste(band, ((TARGET_SIZE - bw) // 2, (TARGET_SIZE - bh) // 2))
    return sq


DINOV2_DIMS = {
    "dinov2_vits14": 384,
    "dinov2_vitb14": 768,
    "dinov2_vitl14": 1024,
    "dinov2_vitg14": 1536,
}


class _RandomViTStub(torch.nn.Module):
    """Randomly-initialized stand-in for a DINOv2 variant.

    Same output dimensionality as the real model but with untrained
    weights. Lets the pipeline run end-to-end in environments without
    outbound network access (sandboxes, air-gapped builds). Retrieval
    numbers from this stub are a RANDOM BASELINE — useful for
    confirming the scripts have no bugs, not for measuring quality.
    """

    def __init__(self, name: str):
        super().__init__()
        dim = DINOV2_DIMS[name]
        # A tiny conv trunk into a global average pool, just so the
        # forward pass consumes the image pixels and produces a
        # vector of the right size. Deterministic seed → stable
        # outputs across runs on the same inputs.
        torch.manual_seed(0xB12C_F1)
        self.trunk = torch.nn.Sequential(
            torch.nn.Conv2d(3, 32, 3, stride=2, padding=1),
            torch.nn.ReLU(inplace=True),
            torch.nn.Conv2d(32, 64, 3, stride=2, padding=1),
            torch.nn.ReLU(inplace=True),
            torch.nn.AdaptiveAvgPool2d(1),
            torch.nn.Flatten(),
            torch.nn.Linear(64, dim),
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.trunk(x)


def load_dinov2(model_name: str, device: str, random_init: bool = False):
    """Load a DINOv2 variant from torch hub.

    `dinov2_vits14`  → 384-D
    `dinov2_vitb14`  → 768-D
    `dinov2_vitl14`  → 1024-D
    `dinov2_vitg14`  → 1536-D (very large — skip on CPU)

    Passing ``random_init=True`` swaps in ``_RandomViTStub`` so the
    pipeline can run without network access. Use only for smoke tests.
    """
    if random_init:
        return _RandomViTStub(model_name).eval().to(device)
    hub_model = torch.hub.load("facebookresearch/dinov2", model_name,
                               trust_repo=True, verbose=False)
    hub_model.eval().to(device)
    return hub_model


def embed_batch(model, batch: torch.Tensor) -> torch.Tensor:
    """Return L2-normalized CLS-token embeddings for a batch."""
    with torch.no_grad():
        feats = model(batch)
    return F.normalize(feats, dim=-1)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", default="dinov2_vits14")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--limit", type=int, default=0,
                        help="Cap to N figures for smoke tests. 0 = all.")
    parser.add_argument("--exclude-eval", type=Path, default=None,
                        help="Path to eval/ground_truth.json; listed ids are excluded.")
    parser.add_argument("--device", default="cuda" if torch.cuda.is_available() else "cpu")
    parser.add_argument("--random-init", action="store_true",
                        help="Skip torch.hub download and use an untrained stub "
                             "of the same output size (pipeline smoke test only).")
    args = parser.parse_args()

    exclude_ids: set[str] = set()
    if args.exclude_eval and args.exclude_eval.exists():
        gt = json.loads(args.exclude_eval.read_text())
        exclude_ids = set(gt.get("held_out", []))
        print(f"Excluding {len(exclude_ids)} held-out figures from the catalog index")

    paths = load_catalog_paths(exclude_ids)
    if args.limit:
        paths = paths[: args.limit]
    print(f"Embedding {len(paths)} catalog figures with {args.model} on {args.device}")

    model = load_dinov2(args.model, args.device, random_init=args.random_init)
    if args.random_init:
        print("  ⚠ random-init stub — accuracy numbers are a random baseline only")

    tx = transforms.Compose([
        transforms.ToTensor(),
        transforms.Normalize(mean=[0.485, 0.456, 0.406],
                             std=[0.229, 0.224, 0.225]),
    ])

    args.out.mkdir(parents=True, exist_ok=True)
    ids: list[str] = []
    rows: list[np.ndarray] = []

    t0 = time.time()
    batch_imgs: list[torch.Tensor] = []
    batch_ids: list[str] = []
    dim = None
    for i, (fid, path) in enumerate(paths):
        try:
            img = Image.open(path).convert("RGB")
        except Exception as e:
            print(f"  ! skip {fid}: {e}", file=sys.stderr)
            continue
        crop = torso_crop(img)
        batch_imgs.append(tx(crop))
        batch_ids.append(fid)
        if len(batch_imgs) >= args.batch_size or i == len(paths) - 1:
            batch = torch.stack(batch_imgs).to(args.device)
            emb = embed_batch(model, batch).cpu().numpy().astype(np.float32)
            rows.append(emb)
            ids.extend(batch_ids)
            batch_imgs.clear()
            batch_ids.clear()
            if (i + 1) % (args.batch_size * 10) == 0 or i == len(paths) - 1:
                elapsed = time.time() - t0
                rate = (i + 1) / max(elapsed, 1e-3)
                eta = (len(paths) - (i + 1)) / max(rate, 1e-3)
                print(f"  {i + 1}/{len(paths)}  {rate:.1f} img/s  eta {eta/60:.1f}m",
                      flush=True)

    matrix = np.concatenate(rows, axis=0)
    dim = int(matrix.shape[1])

    # Save float16 matrix + json index in the schema the iOS runtime
    # already consumes.
    matrix_f16 = matrix.astype(np.float16)
    (args.out / "torso_embeddings.bin").write_bytes(matrix_f16.tobytes())
    (args.out / "torso_embeddings_index.json").write_text(json.dumps({
        "dim": dim,
        "count": int(matrix.shape[0]),
        "dtype": "float16",
        "ids": ids,
        "encoder": args.model,
    }, separators=(",", ":")))
    # No mean-centering by default — DINOv2 embeddings are already well
    # spread; adding the "fix the broken space" patch from the SimCLR
    # pipeline here would actively hurt.
    print(f"Wrote {matrix.shape[0]} × {dim} embeddings to {args.out}")
    print(f"Total time: {(time.time() - t0)/60:.1f}m")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
