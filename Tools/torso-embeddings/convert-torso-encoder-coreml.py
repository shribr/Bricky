"""Convert the trained PyTorch torso encoder to CoreML.

The runtime path on iOS uses CoreML to run the same encoder over the
captured torso band, then does cosine-NN against the bundled index.
The exported model takes a 224×224 RGB image (preprocessed with
ImageNet mean/std) and emits a 512-D L2-normalized embedding (the
backbone's features — same as `embed-torso-catalog.py` writes).

Output: Bricky/Resources/TorsoEmbeddings/TorsoEncoder.mlmodel
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
    "train_torso_encoder",
    str(Path(__file__).resolve().parent / "train-torso-encoder.py"),
).load_module()
TorsoEncoder = _TRAINER.TorsoEncoder


class InferenceWrapper(nn.Module):
    """Wrap the encoder so the exported graph returns *backbone*
    embeddings (512-D, L2-normalized) — matching what the bundled
    index stores. The projection head used during training is dropped
    because it isn't needed for retrieval and adds latency."""

    def __init__(self, encoder: TorsoEncoder):
        super().__init__()
        self.encoder = encoder

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.encoder.encode(x)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkpoint", type=Path,
                        default=Path(__file__).resolve().parent / "out" / "torso_encoder.pt")
    parser.add_argument("--output", type=Path,
                        default=Path(__file__).resolve().parents[2] / "Bricky" / "Resources" / "TorsoEmbeddings" / "TorsoEncoder.mlmodel")
    args = parser.parse_args()

    ckpt = torch.load(args.checkpoint, map_location="cpu")
    model = TorsoEncoder(embed_dim=ckpt.get("embed_dim", 256))
    model.load_state_dict(ckpt["state_dict"])
    model.eval()
    wrapped = InferenceWrapper(model).eval()

    example = torch.randn(1, 3, 224, 224)
    traced = torch.jit.trace(wrapped, example)

    # Image input: lets CoreML feed a CVPixelBuffer / CIImage directly
    # without the Swift caller building a tensor manually.
    image_input = ct.ImageType(
        name="image",
        shape=(1, 3, 224, 224),
        scale=1.0 / 255.0 / 0.226,  # approximate ImageNet std
        bias=[-0.485 / 0.229, -0.456 / 0.224, -0.406 / 0.225],
        color_layout=ct.colorlayout.RGB,
    )
    mlmodel = ct.convert(
        traced,
        inputs=[image_input],
        outputs=[ct.TensorType(name="embedding")],
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS17,
    )
    mlmodel.short_description = "Bricky torso-band encoder (ResNet18, 512-D, L2-normalized)"
    args.output.parent.mkdir(parents=True, exist_ok=True)
    mlmodel.save(str(args.output))
    print(f"Wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
