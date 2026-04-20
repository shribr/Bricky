"""Embed every catalog torso crop using the trained encoder and write
the bundled vector index that ships with the iOS app.

Output (under Bricky/Resources/TorsoEmbeddings/):
    torso_embeddings.bin        # raw Float16 row-major matrix (N × D)
    torso_embeddings_index.json # { "dim": D, "count": N, "ids": [...] }

The .bin format is intentionally trivial — no headers, just contiguous
Float16 values — so the iOS loader can mmap it and read it as a flat
buffer without parsing. The accompanying JSON provides the figure-ID
ordering plus the dimensionality the runtime needs to interpret the
buffer.

Float16 is fine here: cosine-NN uses dot products on L2-normalized
vectors and Float16 has more than enough precision for that, while
halving the bundle size (~16 K × 256 × 2 bytes ≈ 8 MB).
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

try:
    import numpy as np
    import torch
    from torch.utils.data import DataLoader, Dataset
    from torchvision import transforms
    from PIL import Image
except ImportError:  # pragma: no cover
    sys.exit("torch + torchvision + Pillow + numpy required.")


from importlib.machinery import SourceFileLoader  # noqa: E402

# Re-use the encoder definition from the trainer without making it a
# package — keeps these scripts standalone-runnable.
_TRAINER = SourceFileLoader(
    "train_torso_encoder",
    str(Path(__file__).resolve().parent / "train-torso-encoder.py"),
).load_module()
TorsoEncoder = _TRAINER.TorsoEncoder


class CropDataset(Dataset):
    def __init__(self, paths: list[Path]):
        self.paths = paths
        self.tx = transforms.Compose([
            transforms.Resize((224, 224)),
            transforms.ToTensor(),
            transforms.Normalize(mean=[0.485, 0.456, 0.406],
                                 std=[0.229, 0.224, 0.225]),
        ])

    def __len__(self) -> int:
        return len(self.paths)

    def __getitem__(self, i: int):
        img = Image.open(self.paths[i]).convert("RGB")
        return self.tx(img), i


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data", type=Path,
                        default=Path(__file__).resolve().parent / "data")
    parser.add_argument("--checkpoint", type=Path,
                        default=Path(__file__).resolve().parent / "out" / "torso_encoder.pt")
    parser.add_argument("--output", type=Path,
                        default=Path(__file__).resolve().parents[2] / "Bricky" / "Resources" / "TorsoEmbeddings")
    parser.add_argument("--batch-size", type=int, default=64)
    parser.add_argument("--device",
                        default="cuda" if torch.cuda.is_available() else "cpu")
    args = parser.parse_args()

    # Resolve fig_id ↔ file path ordering by reading the manifest the
    # dataset builder wrote. This guarantees row N in the .bin
    # corresponds to ids[N] in the JSON.
    manifest = json.loads((args.data / "manifest.json").read_text())
    figs = manifest["figures"]
    paths: list[Path] = []
    ids: list[str] = []
    for f in figs:
        p = args.data / "figures" / f"{f['id']}.jpg"
        if p.exists():
            paths.append(p)
            ids.append(f["id"])
    if not paths:
        sys.exit("No torso crops found — run build-torso-dataset.py first.")

    ckpt = torch.load(args.checkpoint, map_location=args.device)
    model = TorsoEncoder(embed_dim=ckpt.get("embed_dim", 256)).to(args.device)
    model.load_state_dict(ckpt["state_dict"])
    model.eval()

    loader = DataLoader(CropDataset(paths), batch_size=args.batch_size,
                        num_workers=4, shuffle=False)
    embeddings: list[np.ndarray] = []
    with torch.no_grad():
        for xb, _ in loader:
            xb = xb.to(args.device, non_blocking=True)
            # Use the BACKBONE encoder (no projection head) for the
            # bundled index — backbone features are what the runtime
            # CoreML model exports and what cosine-NN runs against.
            z = model.encode(xb)
            embeddings.append(z.cpu().numpy().astype(np.float16))
    matrix = np.concatenate(embeddings, axis=0)  # N × D
    print(f"Encoded {matrix.shape[0]} torsos → embedding dim {matrix.shape[1]}")

    args.output.mkdir(parents=True, exist_ok=True)
    bin_path = args.output / "torso_embeddings.bin"
    matrix.tofile(bin_path)
    index_path = args.output / "torso_embeddings_index.json"
    index_path.write_text(json.dumps({
        "dim": int(matrix.shape[1]),
        "count": int(matrix.shape[0]),
        "dtype": "float16",
        "ids": ids,
    }, separators=(",", ":")))
    print(f"Wrote {bin_path} ({bin_path.stat().st_size:,} bytes)")
    print(f"Wrote {index_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
