"""Embed every catalog head crop using the trained head encoder and write
the bundled vector index that ships with the iOS app.

Output (under Bricky/Resources/HeadEmbeddings/):
    head_embeddings.bin         # raw Float16 row-major matrix (N × D)
    head_embeddings_index.json  # { "dim": D, "count": N, "ids": [...] }
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
_TRAINER = SourceFileLoader(
    "train_head_encoder",
    str(Path(__file__).resolve().parent / "train-head-encoder.py"),
).load_module()
HeadEncoder = _TRAINER.HeadEncoder


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
                        default=Path(__file__).resolve().parent / "data-head")
    parser.add_argument("--checkpoint", type=Path,
                        default=Path(__file__).resolve().parent / "out-head" / "head_encoder.pt")
    parser.add_argument("--output", type=Path,
                        default=Path(__file__).resolve().parents[2] / "Bricky" / "Resources" / "HeadEmbeddings")
    parser.add_argument("--batch-size", type=int, default=64)
    parser.add_argument("--device",
                        default="cuda" if torch.cuda.is_available() else "cpu")
    args = parser.parse_args()

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
        sys.exit("No head crops found — run build-head-dataset.py first.")

    ckpt = torch.load(args.checkpoint, map_location=args.device)
    model = HeadEncoder(embed_dim=ckpt.get("embed_dim", 256)).to(args.device)
    model.load_state_dict(ckpt["state_dict"])
    model.eval()

    loader = DataLoader(CropDataset(paths), batch_size=args.batch_size,
                        num_workers=4, shuffle=False)
    embeddings: list[np.ndarray] = []
    with torch.no_grad():
        for xb, _ in loader:
            xb = xb.to(args.device, non_blocking=True)
            z = model.encode(xb)
            embeddings.append(z.cpu().numpy().astype(np.float16))
    matrix = np.concatenate(embeddings, axis=0)
    print(f"Encoded {matrix.shape[0]} heads → embedding dim {matrix.shape[1]}")

    args.output.mkdir(parents=True, exist_ok=True)
    bin_path = args.output / "head_embeddings.bin"
    matrix.tofile(bin_path)
    index_path = args.output / "head_embeddings_index.json"
    index_path.write_text(json.dumps({
        "dim": int(matrix.shape[1]),
        "count": int(matrix.shape[0]),
        "dtype": "float16",
        "ids": ids,
    }, separators=(",", ":")))
    print(f"Wrote {bin_path} ({bin_path.stat().st_size / (1024*1024):.1f} MB)")
    print(f"Wrote {index_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
