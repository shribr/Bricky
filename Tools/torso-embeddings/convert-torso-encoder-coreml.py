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
    because it isn't needed for retrieval and adds latency.

    ImageNet normalization is baked into the graph so the CoreML
    ``ImageType`` input only needs to do [0, 255] → [0, 1] scaling.
    This avoids the single-scale approximation that ``ct.ImageType``
    forces (one ``scale`` value for all three channels)."""

    # ImageNet channel stats
    _MEAN = [0.485, 0.456, 0.406]
    _STD  = [0.229, 0.224, 0.225]

    def __init__(self, encoder: TorsoEncoder):
        super().__init__()
        self.encoder = encoder
        self.register_buffer("mean", torch.tensor(self._MEAN).view(1, 3, 1, 1))
        self.register_buffer("std",  torch.tensor(self._STD).view(1, 3, 1, 1))

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        # x arrives as [0, 1] from CoreML's scale=1/255 preprocessing.
        x = (x - self.mean) / self.std
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
    # Only scale to [0, 1] here — per-channel ImageNet normalization
    # is baked into InferenceWrapper so we don't need the single-scale
    # approximation that ct.ImageType's bias/scale forces.
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
        # Use neuralnetwork format: avoids the BlobWriter bug on Colab
        # and works identically on iOS 17+.
        convert_to="neuralnetwork",
    )
    mlmodel.short_description = "Bricky torso-band encoder (ResNet18, 512-D, L2-normalized)"
    args.output.parent.mkdir(parents=True, exist_ok=True)
    mlmodel.save(str(args.output))
    print(f"Wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
