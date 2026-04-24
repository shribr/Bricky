"""Embed catalog faces with DINOv2 for the face-embedding index.

Same as embed_catalog.py but uses the face crop region (17-35%)
instead of torso (30-70%). Output goes to FaceEmbeddings format.
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
DEFAULT_OUT = Path(__file__).resolve().parent / "index" / "dinov2_vits14_face"

FACE_TOP = 0.17
FACE_BOTTOM = 0.35
TARGET_SIZE = 224


def load_catalog_paths() -> list[tuple[str, Path]]:
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


def face_crop(img: Image.Image) -> Image.Image:
    w, h = img.size
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
    parser.add_argument("--model", default="dinov2_vits14")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--device", default="cuda" if torch.cuda.is_available() else "cpu")
    args = parser.parse_args()

    paths = load_catalog_paths()
    print(f"Embedding {len(paths)} catalog faces with {args.model} on {args.device}")

    hub_model = torch.hub.load("facebookresearch/dinov2", args.model,
                               trust_repo=True, verbose=False)
    hub_model.eval().to(args.device)

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
    for i, (fid, path) in enumerate(paths):
        try:
            img = Image.open(path).convert("RGB")
        except Exception as e:
            print(f"  ! skip {fid}: {e}", file=sys.stderr)
            continue
        crop = face_crop(img)
        batch_imgs.append(tx(crop))
        batch_ids.append(fid)
        if len(batch_imgs) >= args.batch_size or i == len(paths) - 1:
            batch = torch.stack(batch_imgs).to(args.device)
            with torch.no_grad():
                feats = hub_model(batch)
                emb = F.normalize(feats, dim=-1).cpu().numpy().astype(np.float32)
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

    matrix_f16 = matrix.astype(np.float16)
    (args.out / "face_embeddings.bin").write_bytes(matrix_f16.tobytes())
    (args.out / "face_embeddings_index.json").write_text(json.dumps({
        "dim": dim,
        "count": int(matrix.shape[0]),
        "dtype": "float16",
        "ids": ids,
        "encoder": args.model,
    }, separators=(",", ":")))
    print(f"Wrote {matrix.shape[0]} × {dim} face embeddings to {args.out}")
    print(f"Total time: {(time.time() - t0)/60:.1f}m")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
