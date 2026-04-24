"""Convert a pretrained DINOv2 ViT to CoreML for on-device inference.

Produces two CoreML models:
  - TorsoEncoder.mlpackage  (for torso-band embedding)
  - FaceEncoder.mlpackage   (identical model, different name)

Both are the same DINOv2 backbone — the iOS code crops different
regions before feeding the model, so the model itself is the same.

The exported model takes a 224×224 RGB image and emits a D-dimensional
L2-normalized embedding (384 for vits14, 768 for vitb14, etc.).
ImageNet mean/std normalization is baked into the graph so the CoreML
ImageType input only needs [0,255] → [0,1] scaling.

Strategy: DINOv2 uses bicubic interpolation to resize positional
embeddings when the input resolution differs from training (518×518).
Since our input is always 224×224, we pre-compute the interpolated
positional embeddings at that resolution and freeze them, eliminating
the dynamic bicubic op that coremltools can't convert.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    import torch
    import torch.nn as nn
    import torch.nn.functional as F
    import coremltools as ct
except ImportError:
    sys.exit("torch + coremltools required. pip install torch coremltools")


BRICKY_ROOT = Path(__file__).resolve().parents[2]

# ImageNet normalization constants
_MEAN = [0.485, 0.456, 0.406]
_STD = [0.229, 0.224, 0.225]


def freeze_pos_embed(model: nn.Module, img_size: int = 224, patch_size: int = 14):
    """Pre-compute and freeze positional embeddings for a fixed input size.

    DINOv2 interpolates pos_embed at runtime if the grid doesn't match
    training. We do the interpolation ONCE and store the result, so the
    traced graph has no dynamic bicubic upsample op.
    """
    num_patches = (img_size // patch_size) ** 2  # 16×16 = 256 for 224/14
    pos_embed = model.pos_embed  # (1, N_train + 1, D) with CLS token

    if pos_embed.shape[1] == num_patches + 1:
        return  # Already the right size, nothing to do.

    cls_token = pos_embed[:, :1, :]  # (1, 1, D)
    patch_tokens = pos_embed[:, 1:, :]  # (1, N_train, D)

    # Reshape to 2D grid, interpolate, flatten back.
    dim = patch_tokens.shape[-1]
    old_grid = int(patch_tokens.shape[1] ** 0.5)
    new_grid = img_size // patch_size

    patch_tokens = patch_tokens.reshape(1, old_grid, old_grid, dim).permute(0, 3, 1, 2)
    patch_tokens = F.interpolate(
        patch_tokens.float(), size=(new_grid, new_grid),
        mode="bicubic", align_corners=False
    )
    patch_tokens = patch_tokens.permute(0, 2, 3, 1).reshape(1, -1, dim)

    new_pos_embed = torch.cat([cls_token, patch_tokens], dim=1)
    model.pos_embed = nn.Parameter(new_pos_embed, requires_grad=False)

    # Also monkey-patch interpolate_pos_encoding to be a no-op,
    # preventing the runtime bicubic call during tracing.
    def _noop_interpolate(self_inner, x, w, h):
        return self_inner.pos_embed
    import types
    model.interpolate_pos_encoding = types.MethodType(_noop_interpolate, model)


class DINOv2Wrapper(nn.Module):
    """Wraps a DINOv2 backbone for CoreML export.

    Bakes in ImageNet normalization and L2-normalizes the output
    embedding, matching what embed_catalog.py does offline.
    """

    def __init__(self, backbone: nn.Module):
        super().__init__()
        self.backbone = backbone
        self.register_buffer("mean", torch.tensor(_MEAN).view(1, 3, 1, 1))
        self.register_buffer("std", torch.tensor(_STD).view(1, 3, 1, 1))

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        # x arrives as [0, 1] from CoreML's scale=1/255 preprocessing.
        x = (x - self.mean) / self.std
        feats = self.backbone(x)
        return F.normalize(feats, dim=-1)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", default="dinov2_vits14",
                        help="DINOv2 variant: dinov2_vits14, dinov2_vitb14, etc.")
    parser.add_argument("--torso-out", type=Path,
                        default=BRICKY_ROOT / "Bricky" / "Resources" / "TorsoEmbeddings" / "TorsoEncoder.mlpackage")
    parser.add_argument("--face-out", type=Path,
                        default=BRICKY_ROOT / "Bricky" / "Resources" / "FaceEmbeddings" / "FaceEncoder.mlpackage")
    args = parser.parse_args()

    print(f"Loading {args.model} from torch hub...")
    hub_model = torch.hub.load("facebookresearch/dinov2", args.model,
                               trust_repo=True, verbose=False)
    hub_model.eval()

    # Freeze positional embeddings to 224×224 to eliminate dynamic bicubic op.
    print("Freezing positional embeddings for 224×224 input...")
    freeze_pos_embed(hub_model, img_size=224, patch_size=14)

    wrapper = DINOv2Wrapper(hub_model).eval()
    example = torch.randn(1, 3, 224, 224)

    # Verify output before tracing
    with torch.no_grad():
        test_out = wrapper(example)
        dim = test_out.shape[1]
        norm = test_out.norm(dim=1).item()
        print(f"  Output dim: {dim}, L2 norm: {norm:.4f}")

    print("Tracing model...")
    traced = torch.jit.trace(wrapper, example)

    # Verify traced output matches
    with torch.no_grad():
        traced_out = traced(example)
        diff = (test_out - traced_out).abs().max().item()
        print(f"  Trace verification: max diff = {diff:.6f}")

    print("Converting to CoreML...")
    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.ImageType(
                name="image",
                shape=(1, 3, 224, 224),
                scale=1.0 / 255.0,
                bias=[0, 0, 0],
                color_layout="RGB",
            )
        ],
        outputs=[ct.TensorType(name="embedding")],
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS16,
    )

    # Save as TorsoEncoder
    print(f"Saving TorsoEncoder to {args.torso_out}...")
    args.torso_out.parent.mkdir(parents=True, exist_ok=True)
    mlmodel.author = "DINOv2 (Meta AI)"
    mlmodel.short_description = f"DINOv2 {args.model} torso encoder for minifigure identification"
    mlmodel.save(str(args.torso_out))

    # Save as FaceEncoder (same model, different name)
    print(f"Saving FaceEncoder to {args.face_out}...")
    args.face_out.parent.mkdir(parents=True, exist_ok=True)
    mlmodel.short_description = f"DINOv2 {args.model} face encoder for minifigure identification"
    mlmodel.save(str(args.face_out))

    print(f"Done. Model dim={dim}, format=mlpackage")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
