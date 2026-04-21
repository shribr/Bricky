"""Convert the trained PyTorch face encoder to CoreML.

Output: Bricky/Resources/FaceEmbeddings/FaceEncoder.mlmodel
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
    "train_face_encoder",
    str(Path(__file__).resolve().parent / "train-face-encoder.py"),
).load_module()
FaceEncoder = _TRAINER.FaceEncoder


class InferenceWrapper(nn.Module):
    """Backbone embeddings only (512-D, L2-normalized).

    ImageNet normalization is baked into the graph so the CoreML
    ``ImageType`` input only needs [0, 255] → [0, 1] scaling."""

    _MEAN = [0.485, 0.456, 0.406]
    _STD  = [0.229, 0.224, 0.225]

    def __init__(self, encoder: FaceEncoder):
        super().__init__()
        self.encoder = encoder
        self.register_buffer("mean", torch.tensor(self._MEAN).view(1, 3, 1, 1))
        self.register_buffer("std",  torch.tensor(self._STD).view(1, 3, 1, 1))

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = (x - self.mean) / self.std
        return self.encoder.encode(x)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkpoint", type=Path,
                        default=Path(__file__).resolve().parent / "out-face" / "face_encoder.pt")
    parser.add_argument("--output", type=Path,
                        default=Path(__file__).resolve().parents[2] / "Bricky" / "Resources" / "FaceEmbeddings" / "FaceEncoder.mlmodel")
    args = parser.parse_args()

    ckpt = torch.load(args.checkpoint, map_location="cpu")
    model = FaceEncoder(embed_dim=ckpt.get("embed_dim", 256))
    model.load_state_dict(ckpt["state_dict"])
    model.eval()
    wrapped = InferenceWrapper(model).eval()

    example = torch.randn(1, 3, 224, 224)
    traced = torch.jit.trace(wrapped, example)

    image_input = ct.ImageType(
        name="image",
        shape=(1, 3, 224, 224),
        scale=1.0 / 255.0,
        bias=[0.0, 0.0, 0.0],
        color_layout=ct.colorlayout.RGB,
    )
    mlmodel = ct.convert(
        traced,
        inputs=[image_input],
        outputs=[ct.TensorType(name="embedding")],
        convert_to="neuralnetwork",
    )
    mlmodel.short_description = "Bricky face-region encoder (ResNet18, 512-D, L2-normalized)"
    args.output.parent.mkdir(parents=True, exist_ok=True)
    mlmodel.save(str(args.output))
    print(f"Wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
