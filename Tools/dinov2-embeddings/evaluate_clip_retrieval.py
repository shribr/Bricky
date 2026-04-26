#!/usr/bin/env python3
"""Evaluate Bricky's shipped CLIP index against labeled image suites.

Supports three labeled layouts already present in the repo:

1. eval-dir:
   ground_truth.json + variants/<figure_id>/<filename>
2. flat-dir:
   files named <figure_id>.<ext>
3. huggingface-dir:
   metadata.json entries with fig_num + filename, images under images/

The script uses the same CLIP model that generated the shipped index and
reports recall plus top-k predictions for each query image.
"""

from __future__ import annotations

import argparse
import json
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import torch
import torch.nn.functional as F
from PIL import Image


BRICKY_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_INDEX_DIR = BRICKY_ROOT / "Bricky" / "Resources" / "ClipEmbeddings"
DEFAULT_REAL_PHOTOS_EVAL = BRICKY_ROOT / "Tools" / "dinov2-embeddings" / "real_photos" / "eval"
DEFAULT_BRICKLINK_EVAL = BRICKY_ROOT / "Tools" / "dinov2-embeddings" / "eval_bricklink"
DEFAULT_BRICKLINK_IMAGES = BRICKY_ROOT / "Tools" / "dinov2-embeddings" / "bricklink_images"
DEFAULT_HF_DATASET = BRICKY_ROOT / "Tools" / "datasets" / "huggingface-lego-captions"

K_RECALL = [1, 5, 10, 50]
IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp"}


@dataclass(frozen=True)
class QueryImage:
    suite: str
    figure_id: str
    image_path: Path
    variant: str


def detect_figure_bbox(img: Image.Image) -> tuple[int, int, int, int]:
    """Return (left, top, right, bottom) of the foreground figure."""
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


def load_clip_index(index_dir: Path) -> tuple[np.ndarray, list[str], dict]:
    meta = json.loads((index_dir / "clip_embeddings_index.json").read_text())
    dim = meta["dim"]
    count = meta["count"]
    dtype = meta.get("dtype", "float16")
    raw = (index_dir / "clip_embeddings.bin").read_bytes()
    np_dtype = {"float16": np.float16, "float32": np.float32}[dtype]
    matrix = np.frombuffer(raw, dtype=np_dtype).reshape(count, dim).astype(np.float32)
    return matrix, meta["ids"], meta


def iter_eval_dir_queries(eval_dir: Path, suite_name: str) -> list[QueryImage]:
    gt = json.loads((eval_dir / "ground_truth.json").read_text())
    queries: list[QueryImage] = []
    for entry in gt["ground_truth"]:
        figure_id = entry["figure_id"]
        for variant in entry["variants"]:
            queries.append(
                QueryImage(
                    suite=suite_name,
                    figure_id=figure_id,
                    image_path=eval_dir / "variants" / figure_id / variant,
                    variant=variant,
                )
            )
    return queries


def iter_flat_dir_queries(image_dir: Path, suite_name: str) -> list[QueryImage]:
    queries: list[QueryImage] = []
    for image_path in sorted(image_dir.iterdir()):
        if image_path.suffix.lower() not in IMAGE_EXTENSIONS:
            continue
        figure_id = image_path.stem
        queries.append(
            QueryImage(
                suite=suite_name,
                figure_id=figure_id,
                image_path=image_path,
                variant=image_path.name,
            )
        )
    return queries


def iter_huggingface_queries(dataset_dir: Path, suite_name: str) -> list[QueryImage]:
    metadata = json.loads((dataset_dir / "metadata.json").read_text())
    images_dir = dataset_dir / "images"
    queries: list[QueryImage] = []
    for entry in metadata:
        image_path = images_dir / entry["filename"]
        if not image_path.exists():
            continue
        queries.append(
            QueryImage(
                suite=suite_name,
                figure_id=entry["fig_num"],
                image_path=image_path,
                variant=entry["filename"],
            )
        )
    return queries


def default_suite_specs() -> dict[str, tuple[str, Path]]:
    return {
        "real_photos_eval": ("eval_dir", DEFAULT_REAL_PHOTOS_EVAL),
        "bricklink_eval": ("eval_dir", DEFAULT_BRICKLINK_EVAL),
        "bricklink_images": ("flat_dir", DEFAULT_BRICKLINK_IMAGES),
        "huggingface_captions": ("huggingface_dir", DEFAULT_HF_DATASET),
    }


def collect_queries(requested_suites: list[str]) -> tuple[dict[str, list[QueryImage]], dict[str, str]]:
    suite_specs = default_suite_specs()
    selected = requested_suites or list(suite_specs.keys())
    queries_by_suite: dict[str, list[QueryImage]] = {}
    skipped: dict[str, str] = {}

    for suite_name in selected:
        if suite_name not in suite_specs:
            skipped[suite_name] = "unknown suite"
            continue

        suite_kind, suite_path = suite_specs[suite_name]
        if not suite_path.exists():
            skipped[suite_name] = f"missing path: {suite_path}"
            continue

        if suite_kind == "eval_dir":
            queries = iter_eval_dir_queries(suite_path, suite_name)
        elif suite_kind == "flat_dir":
            queries = iter_flat_dir_queries(suite_path, suite_name)
        elif suite_kind == "huggingface_dir":
            queries = iter_huggingface_queries(suite_path, suite_name)
        else:
            skipped[suite_name] = f"unsupported suite kind: {suite_kind}"
            continue

        if not queries:
            skipped[suite_name] = f"no query images found at {suite_path}"
            continue
        queries_by_suite[suite_name] = queries

    return queries_by_suite, skipped


def load_model(model_name: str, device: torch.device):
    from transformers import CLIPModel, CLIPProcessor

    model = CLIPModel.from_pretrained(model_name)
    processor = CLIPProcessor.from_pretrained(model_name)
    model.eval()
    model.to(device)
    return model, processor


def embed_query_batch(
    model,
    processor,
    device: torch.device,
    query_batch: list[QueryImage],
    detect_bbox: bool,
) -> torch.Tensor:
    images = []
    for query in query_batch:
        img = Image.open(query.image_path).convert("RGB")
        if detect_bbox:
            img = img.crop(detect_figure_bbox(img))
        images.append(img)

    inputs = processor(images=images, return_tensors="pt", padding=True)
    pixel_values = inputs["pixel_values"].to(device)
    with torch.no_grad():
        image_features = model.get_image_features(pixel_values=pixel_values)
        image_features = F.normalize(image_features, dim=-1)
    return image_features


def evaluate_suite(
    suite_name: str,
    queries: list[QueryImage],
    matrix_t: torch.Tensor,
    ids: list[str],
    model,
    processor,
    device: torch.device,
    batch_size: int,
    detect_bbox: bool,
) -> dict:
    id_to_row = {figure_id: idx for idx, figure_id in enumerate(ids)}
    max_k = max(K_RECALL)
    total = 0
    skipped_missing_id = 0
    hits = {k: 0 for k in K_RECALL}
    failures: list[dict] = []
    predictions: list[dict] = []
    valid_queries = [query for query in queries if query.figure_id in id_to_row]
    skipped_missing_id = len(queries) - len(valid_queries)

    print(f"Suite {suite_name}: evaluating {len(valid_queries)} queries", flush=True)
    t0 = time.time()
    for start in range(0, len(valid_queries), batch_size):
        batch = valid_queries[start:start + batch_size]
        embeddings = embed_query_batch(model, processor, device, batch, detect_bbox)
        scores = embeddings @ matrix_t.T
        topk = torch.topk(scores, max_k, dim=1)
        top_indices = topk.indices.cpu().numpy()
        top_values = topk.values.cpu().numpy()

        for query, ranked_rows, ranked_scores in zip(batch, top_indices, top_values):
            gt_row = id_to_row[query.figure_id]
            gt_rank = None
            for rank, row_index in enumerate(ranked_rows):
                if row_index == gt_row:
                    gt_rank = rank
                    break

            for k in K_RECALL:
                if gt_rank is not None and gt_rank < k:
                    hits[k] += 1
            total += 1

            top5 = [
                {
                    "figure_id": ids[row_index],
                    "score": float(score),
                }
                for row_index, score in zip(ranked_rows[:5], ranked_scores[:5])
            ]
            prediction = {
                "figure_id": query.figure_id,
                "variant": query.variant,
                "image_path": str(query.image_path),
                "gt_rank": gt_rank,
                "top5": top5,
            }
            predictions.append(prediction)

            if gt_rank is None or gt_rank >= 5:
                failures.append(prediction)

        done = min(start + batch_size, len(valid_queries))
        elapsed = time.time() - t0
        rate = done / max(elapsed, 1e-3)
        print(f"  {done}/{len(valid_queries)}  {rate:.1f} img/s", flush=True)

    recall = {f"recall@{k}": hits[k] / total if total else 0.0 for k in K_RECALL}
    return {
        "suite": suite_name,
        "queries_total": len(queries),
        "queries_scored": total,
        "queries_skipped_missing_id": skipped_missing_id,
        **recall,
        "sample_failures": failures[:20],
        "predictions": predictions,
    }


def write_suite_outputs(report_dir: Path, suite_report: dict) -> None:
    report_dir.mkdir(parents=True, exist_ok=True)
    suite_name = suite_report["suite"]
    report_path = report_dir / f"clip_{suite_name}.json"
    predictions_path = report_dir / f"clip_{suite_name}_predictions.json"
    report_payload = dict(suite_report)
    report_payload.pop("predictions", None)
    report_path.write_text(json.dumps(report_payload, indent=2))
    predictions_path.write_text(json.dumps(suite_report["predictions"], indent=2))
    print(f"Wrote {report_path}")
    print(f"Wrote {predictions_path}")


def write_summary(report_dir: Path, run_summary: dict) -> Path:
    """Merge this run into the cumulative CLIP summary.

    Evaluations are often run suite-by-suite because the full image corpus is
    large. Merging prevents a later partial run from silently deleting earlier
    suite results.
    """
    report_dir.mkdir(parents=True, exist_ok=True)
    summary_path = report_dir / "clip_summary.json"
    if summary_path.exists():
        summary = json.loads(summary_path.read_text())
    else:
        summary = {"skipped": {}}

    summary.setdefault("skipped", {})
    summary["skipped"].update(run_summary.get("skipped", {}))
    for suite_name, suite_report in run_summary.items():
        if suite_name == "skipped":
            continue
        summary[suite_name] = suite_report

    summary["last_updated_utc"] = datetime.now(timezone.utc).isoformat()
    summary["last_run_suites"] = [
        suite_name for suite_name in run_summary.keys()
        if suite_name != "skipped"
    ]
    summary_path.write_text(json.dumps(summary, indent=2))
    return summary_path


def choose_device(device_name: str) -> torch.device:
    if device_name == "auto":
        if torch.cuda.is_available():
            return torch.device("cuda")
        if hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
            return torch.device("mps")
        return torch.device("cpu")
    return torch.device(device_name)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--index-dir", type=Path, default=DEFAULT_INDEX_DIR)
    parser.add_argument("--suite", action="append", default=[],
                        help="Named suite to run. Defaults to all discovered suites.")
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--device", default="auto", choices=["auto", "cpu", "cuda", "mps"])
    parser.add_argument("--report-dir", type=Path,
                        default=BRICKY_ROOT / "Tools" / "dinov2-embeddings" / "reports")
    parser.add_argument("--no-detect-bbox", action="store_true")
    args = parser.parse_args()

    matrix, ids, meta = load_clip_index(args.index_dir)
    queries_by_suite, skipped = collect_queries(args.suite)
    if not queries_by_suite:
        raise SystemExit(f"No runnable suites found. Skipped: {json.dumps(skipped, indent=2)}")

    device = choose_device(args.device)
    print(f"Device: {device}")
    print(f"Loading CLIP model: {meta['model']}")
    model, processor = load_model(meta["model"], device)
    matrix_t = torch.from_numpy(matrix).to(device)

    summary: dict[str, dict] = {"skipped": skipped}
    for suite_name, queries in queries_by_suite.items():
        suite_report = evaluate_suite(
            suite_name=suite_name,
            queries=queries,
            matrix_t=matrix_t,
            ids=ids,
            model=model,
            processor=processor,
            device=device,
            batch_size=args.batch_size,
            detect_bbox=not args.no_detect_bbox,
        )
        write_suite_outputs(args.report_dir, suite_report)
        summary[suite_name] = {
            key: value for key, value in suite_report.items()
            if key != "predictions"
        }

        print(f"\nSuite {suite_name} summary")
        print(f"  scored: {suite_report['queries_scored']}")
        for k in K_RECALL:
            print(f"  recall@{k:<3}: {suite_report[f'recall@{k}']:.3f}")

    summary_path = write_summary(args.report_dir, summary)
    print(f"\nWrote {summary_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())