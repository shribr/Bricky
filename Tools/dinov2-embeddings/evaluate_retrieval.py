"""Measure retrieval accuracy of a catalog embedding index against
the held-out eval set.

For each held-out figure's K variants we:
  1. Crop the same vertical band used at index time.
  2. Embed with the same encoder that built the index (name is
     recorded in the index JSON — we re-load it from torch hub).
  3. Rank all catalog figures by cosine similarity.
  4. Record whether the ground-truth figure appears in top-{1,5,10,50}.

Outputs a small JSON report with the headline numbers plus per-figure
failure cases so you can eyeball WHY it missed (e.g. "every miss had
a near-identical-torso distractor" vs. "losses to unrelated figures
→ encoder is actually blind to print").
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

import numpy as np
import torch
import torch.nn.functional as F
from PIL import Image
from torchvision import transforms

from embed_catalog import torso_crop, load_dinov2


DEFAULT_EVAL = Path(__file__).resolve().parent / "eval"
DEFAULT_INDEX = Path(__file__).resolve().parent / "index" / "dinov2_vits14"

K_RECALL = [1, 5, 10, 50]


def load_index(index_dir: Path) -> tuple[np.ndarray, list[str], dict]:
    meta = json.loads((index_dir / "torso_embeddings_index.json").read_text())
    dim = meta["dim"]
    count = meta["count"]
    dtype = meta.get("dtype", "float16")
    raw = (index_dir / "torso_embeddings.bin").read_bytes()
    np_dtype = {"float16": np.float16, "float32": np.float32}[dtype]
    matrix = np.frombuffer(raw, dtype=np_dtype).reshape(count, dim).astype(np.float32)
    return matrix, meta["ids"], meta


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
    parser.add_argument("--index", type=Path, default=DEFAULT_INDEX)
    parser.add_argument("--eval", type=Path, default=DEFAULT_EVAL)
    parser.add_argument("--report", type=Path, default=None,
                        help="Optional path to write the JSON report.")
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--device", default="cuda" if torch.cuda.is_available() else "cpu")
    parser.add_argument("--random-init", action="store_true",
                        help="Use the random-init stub to match an index built with "
                             "--random-init (smoke-test plumbing only).")
    args = parser.parse_args()

    matrix, ids, meta = load_index(args.index)
    encoder_name = meta.get("encoder")
    if not encoder_name:
        sys.exit("Index JSON has no 'encoder' field — can't reproduce the query encoder.")
    id_to_row = {fid: i for i, fid in enumerate(ids)}

    variants = eval_variant_paths(args.eval)
    if not variants:
        sys.exit("Empty eval set.")
    print(f"Evaluating {len(variants)} variants against {len(ids)}-figure index ({encoder_name})")

    model = load_dinov2(encoder_name, args.device, random_init=args.random_init)
    tx = transforms.Compose([
        transforms.ToTensor(),
        transforms.Normalize(mean=[0.485, 0.456, 0.406],
                             std=[0.229, 0.224, 0.225]),
    ])

    matrix_t = torch.from_numpy(matrix).to(args.device)

    hits = {k: 0 for k in K_RECALL}
    total = 0
    failures: list[dict] = []
    in_index: list[tuple[str, Path]] = []
    skipped_missing = 0
    for fid, p in variants:
        if fid in id_to_row:
            in_index.append((fid, p))
        else:
            skipped_missing += 1
    if skipped_missing:
        print(f"  NOTE: {skipped_missing} variants had ground-truth ids not in this index "
              "(eval set overlaps excluded figures). They are excluded from scoring.")

    t0 = time.time()
    batch_imgs: list[torch.Tensor] = []
    batch_meta: list[tuple[str, Path]] = []
    for i, (fid, p) in enumerate(in_index):
        img = Image.open(p).convert("RGB")
        crop = torso_crop(img)
        batch_imgs.append(tx(crop))
        batch_meta.append((fid, p))
        if len(batch_imgs) >= args.batch_size or i == len(in_index) - 1:
            batch = torch.stack(batch_imgs).to(args.device)
            with torch.no_grad():
                q = F.normalize(model(batch), dim=-1)
            # Cosine = dot product (both sides unit-length).
            scores = q @ matrix_t.T  # B × N
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
        "encoder": encoder_name,
        "index_dir": str(args.index),
        "eval_dir": str(args.eval),
        "catalog_size": len(ids),
        "variants_scored": total,
        "variants_skipped_missing_id": skipped_missing,
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
