"""Evaluate the shipped SimCLR torso embedding index on the SAME
held-out eval set, so DINOv2 vs. existing is a like-for-like
comparison.

The shipped index lives at:
    Bricky/Resources/TorsoEmbeddings/
        torso_embeddings.bin
        torso_embeddings_index.json
        torso_embeddings_mean.bin     # norm-capped mean for centering
        TorsoEncoder.mlmodel          # CoreML (we don't use this here)

We reproduce the PyTorch query encoder by re-importing
`Tools/torso-embeddings/train-torso-encoder.py`'s `TorsoEncoder` class
and loading the most recent .pt checkpoint if available. If no
checkpoint is available on this machine, we fall back to comparing
ONLY the bundled DINOv2 index against the existing SimCLR embeddings
stored catalog-side — which is not apples-to-apples. Prefer running
this on the machine that produced the checkpoint.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from importlib.machinery import SourceFileLoader
from pathlib import Path

import numpy as np
import torch
import torch.nn.functional as F
from PIL import Image
from torchvision import transforms

BRICKY_ROOT = Path(__file__).resolve().parents[2]
SIMCLR_INDEX = BRICKY_ROOT / "Bricky" / "Resources" / "TorsoEmbeddings"
SIMCLR_TRAINER = BRICKY_ROOT / "Tools" / "torso-embeddings" / "train-torso-encoder.py"
DEFAULT_CHECKPOINT = BRICKY_ROOT / "Tools" / "torso-embeddings" / "out" / "torso_encoder.pt"
DEFAULT_EVAL = Path(__file__).resolve().parent / "eval"

TORSO_TOP = 0.30
TORSO_BOTTOM = 0.70
TARGET_SIZE = 224

K_RECALL = [1, 5, 10, 50]


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


def load_shipped_index() -> tuple[np.ndarray, list[str], np.ndarray | None]:
    meta = json.loads((SIMCLR_INDEX / "torso_embeddings_index.json").read_text())
    dim, count = meta["dim"], meta["count"]
    raw = (SIMCLR_INDEX / "torso_embeddings.bin").read_bytes()
    matrix = (np.frombuffer(raw, dtype=np.float16)
                .reshape(count, dim).astype(np.float32))
    mean_path = SIMCLR_INDEX / "torso_embeddings_mean.bin"
    mean_vec = None
    if mean_path.exists():
        mean_vec = np.frombuffer(mean_path.read_bytes(),
                                 dtype=np.float32).reshape(1, dim)
    return matrix, meta["ids"], mean_vec


def load_trained_encoder(checkpoint: Path, device: str):
    trainer = SourceFileLoader(
        "train_torso_encoder", str(SIMCLR_TRAINER)
    ).load_module()
    ckpt = torch.load(checkpoint, map_location=device)
    model = trainer.TorsoEncoder(embed_dim=ckpt.get("embed_dim", 256)).to(device)
    model.load_state_dict(ckpt["state_dict"])
    model.eval()
    return model


def eval_variant_paths(eval_dir: Path) -> list[tuple[str, Path]]:
    gt = json.loads((eval_dir / "ground_truth.json").read_text())
    out: list[tuple[str, Path]] = []
    for entry in gt["ground_truth"]:
        fid = entry["figure_id"]
        for name in entry["variants"]:
            out.append((fid, eval_dir / "variants" / fid / name))
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkpoint", type=Path, default=DEFAULT_CHECKPOINT)
    parser.add_argument("--eval", type=Path, default=DEFAULT_EVAL)
    parser.add_argument("--report", type=Path, default=None)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--device", default="cuda" if torch.cuda.is_available() else "cpu")
    args = parser.parse_args()

    if not args.checkpoint.exists():
        sys.exit(
            f"Checkpoint not found at {args.checkpoint}.\n"
            "Run this script on the host that produced the SimCLR checkpoint, "
            "or copy torso_encoder.pt into Tools/torso-embeddings/out/."
        )

    matrix, ids, mean_vec = load_shipped_index()
    id_to_row = {fid: i for i, fid in enumerate(ids)}
    print(f"Shipped index: {len(ids)} figures × {matrix.shape[1]}D"
          f" (mean-centering: {'yes' if mean_vec is not None else 'no'})")

    model = load_trained_encoder(args.checkpoint, args.device)
    tx = transforms.Compose([
        transforms.ToTensor(),
        transforms.Normalize(mean=[0.485, 0.456, 0.406],
                             std=[0.229, 0.224, 0.225]),
    ])
    matrix_t = torch.from_numpy(matrix).to(args.device)
    mean_t = torch.from_numpy(mean_vec).to(args.device) if mean_vec is not None else None

    variants = eval_variant_paths(args.eval)
    in_index = [(fid, p) for fid, p in variants if fid in id_to_row]
    skipped = len(variants) - len(in_index)

    hits = {k: 0 for k in K_RECALL}
    total = 0
    failures = []
    t0 = time.time()
    batch_imgs, batch_meta = [], []
    for i, (fid, p) in enumerate(in_index):
        img = Image.open(p).convert("RGB")
        crop = torso_crop(img)
        batch_imgs.append(tx(crop))
        batch_meta.append((fid, p))
        if len(batch_imgs) >= args.batch_size or i == len(in_index) - 1:
            batch = torch.stack(batch_imgs).to(args.device)
            with torch.no_grad():
                q = model.encode(batch)  # L2-normalized 512-D backbone
            if mean_t is not None:
                q = q - mean_t
                q = F.normalize(q, dim=-1)
            scores = q @ matrix_t.T
            topk_idx = torch.topk(scores, max(K_RECALL), dim=1).indices.cpu().numpy()
            for (qf, qp), row in zip(batch_meta, topk_idx):
                gt_row = id_to_row[qf]
                gt_rank = None
                for rank, r in enumerate(row):
                    if r == gt_row:
                        gt_rank = rank
                        break
                for k in K_RECALL:
                    if gt_rank is not None and gt_rank < k:
                        hits[k] += 1
                total += 1
                if gt_rank is None or gt_rank >= 5:
                    failures.append({
                        "figure_id": qf,
                        "variant": str(qp.relative_to(args.eval)),
                        "gt_rank": gt_rank,
                        "top5": [ids[r] for r in row[:5]],
                    })
            batch_imgs.clear()
            batch_meta.clear()
            if (i + 1) % (args.batch_size * 5) == 0 or i == len(in_index) - 1:
                elapsed = time.time() - t0
                rate = (i + 1) / max(elapsed, 1e-3)
                print(f"  {i + 1}/{len(in_index)}  {rate:.1f} img/s", flush=True)

    recall = {f"recall@{k}": hits[k] / total for k in K_RECALL}
    report = {
        "encoder": "SimCLR ResNet18 (shipped)",
        "catalog_size": len(ids),
        "variants_scored": total,
        "variants_skipped_missing_id": skipped,
        **recall,
        "sample_failures": failures[:20],
    }
    print()
    print(f"Catalog size     : {len(ids)}")
    print(f"Variants scored  : {total}")
    for k in K_RECALL:
        print(f"recall@{k:<3}       : {recall[f'recall@{k}']:.3f}  ({hits[k]}/{total})")

    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2))
        print(f"Wrote {args.report}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
