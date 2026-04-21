"""Convert the trained PyTorch head encoder to CoreML.

Output: Bricky/Resources/HeadEmbeddings/HeadEncoder.mlmodel
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    import torch
    import torch.nn as nn
    import coremltools as ct
except ImportError:  # pragma: no cover
    sys.exit("torch + coremltools required. See README.md.")


from importlib.machinery import SourceFileLoader  # noqa: E402
_TRAINER = SourceFileLoader(
    "train_head_encoder",
    str(Path(__file__).resolve().parent / "train-head-encoder.py"),
).load_module()
HeadEncoder = _TRAINER.HeadEncoder


class InferenceWrapper(nn.Module):
    """Backbone embeddings only (512-D, L2-normalized)."""

    def __init__(self, encoder: HeadEncoder):
        super().__init__()
        self.encoder = encoder

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.encoder.encode(x)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkpoint", type=Path,
                        default=Path(__file__).resolve().parent / "out-head" / "head_encoder.pt")
    parser.add_argument("--output", type=Path,
                        default=Path(__file__).resolve().parents[2] / "Bricky" / "Resources" / "HeadEmbeddings" / "HeadEncoder.mlmodel")
    args = parser.parse_args()

    ckpt = torch.load(args.checkpoint, map_location="cpu")
    model = HeadEncoder(embed_dim=ckpt.get("embed_dim", 256))
    model.load_state_dict(ckpt["state_dict"])
    model.eval()
    wrapped = InferenceWrapper(model).eval()

    example = torch.randn(1, 3, 224, 224)
    traced = torch.jit.trace(wrapped, example)

    image_input = ct.ImageType(
        name="image",
        shape=(1, 3, 224, 224),
        scale=1.0 / 255.0 / 0.226,
        bias=[-0.485 / 0.229, -0.456 / 0.224, -0.406 / 0.225],
        color_layout=ct.colorlayout.RGB,
    )
    mlmodel = ct.convert(
        traced,
        inputs=[image_input],
        outputs=[ct.TensorType(name="embedding")],
        convert_to="neuralnetwork",
    )
    mlmodel.short_description = "Bricky head-region encoder (ResNet18, 512-D, L2-normalized)"
    args.output.parent.mkdir(parents=True, exist_ok=True)
    mlmodel.save(str(args.output))
    print(f"Wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
