"""Train a torso-band encoder via self-supervised contrastive learning.

This is a DINO/SimCLR-style trainer: each figure's torso crop is its
own "identity"; we generate two heavily-augmented views per crop and
push their embeddings together while pushing apart embeddings of
different figures' crops in the same batch.

Why self-supervised: there's no human-labeled "this image is figure
fig-000697" dataset for ~16K LEGO minifigures, but the figure ID
itself IS a perfect label — two crops sharing a fig-id are positives,
crops with different fig-ids are negatives. We don't even need a
real classifier; we just need an embedding space where same-torso
crops are close and different-torso crops are far. Cosine-NN over
that space is the runtime classifier.

Architecture: ResNet18 backbone (~11M params) + 2-layer MLP projection
head down to 256-D L2-normalized embeddings. NT-Xent loss with
temperature 0.1.

Outputs:
    {OUTPUT_DIR}/torso_encoder.pt          (state_dict)
    {OUTPUT_DIR}/training_metadata.json    (hparams + git info)

This script REQUIRES PyTorch + torchvision and is meant to run on a
GPU host (Colab T4 free tier is sufficient for a few epochs). It is
NOT invoked as part of the iOS build; only the artifacts it produces
get bundled.
"""

from __future__ import annotations

import argparse
import json
import os
import random
import sys
import time
from pathlib import Path

try:
    import torch
    import torch.nn as nn
    import torch.nn.functional as F
    from torch.utils.data import Dataset, DataLoader
    from torchvision import models, transforms
    from PIL import Image
except ImportError:  # pragma: no cover
    sys.exit("torch + torchvision + Pillow required. See README.md.")


EMBED_DIM = 256
TARGET_SIZE = 224
DEFAULT_DATA = Path(__file__).resolve().parent / "data"
DEFAULT_OUTPUT = Path(__file__).resolve().parent / "out"


class TorsoPairDataset(Dataset):
    """Returns (view1, view2, fig_idx) for every torso crop on disk.

    The two views come from independent applications of the
    augmentation pipeline below, simulating phone-camera variability
    (rotation, lighting, blur, partial occlusion, JPEG-style noise).
    """

    def __init__(self, root: Path):
        self.paths = sorted((root / "figures").glob("*.jpg"))
        if not self.paths:
            raise RuntimeError(f"No .jpg torso crops in {root / 'figures'}")
        self.augment = transforms.Compose([
            transforms.RandomResizedCrop(TARGET_SIZE, scale=(0.7, 1.0)),
            transforms.RandomHorizontalFlip(p=0.5),
            transforms.RandomApply([transforms.ColorJitter(
                brightness=0.4, contrast=0.4, saturation=0.3, hue=0.05)], p=0.8),
            transforms.RandomApply([transforms.GaussianBlur(
                kernel_size=5, sigma=(0.1, 2.0))], p=0.4),
            transforms.RandomApply([transforms.RandomRotation(degrees=12)], p=0.5),
            transforms.RandomGrayscale(p=0.05),
            transforms.ToTensor(),
            # ImageNet stats — backbone is initialized from ImageNet.
            transforms.Normalize(mean=[0.485, 0.456, 0.406],
                                 std=[0.229, 0.224, 0.225]),
        ])

    def __len__(self) -> int:
        return len(self.paths)

    def __getitem__(self, idx: int):
        img = Image.open(self.paths[idx]).convert("RGB")
        v1 = self.augment(img)
        v2 = self.augment(img)
        return v1, v2, idx


class TorsoEncoder(nn.Module):
    """ResNet18 backbone + 2-layer MLP projection head."""

    def __init__(self, embed_dim: int = EMBED_DIM):
        super().__init__()
        backbone = models.resnet18(weights=models.ResNet18_Weights.IMAGENET1K_V1)
        self.feature_dim = backbone.fc.in_features  # 512
        backbone.fc = nn.Identity()
        self.backbone = backbone
        self.projection = nn.Sequential(
            nn.Linear(self.feature_dim, 512),
            nn.BatchNorm1d(512),
            nn.ReLU(inplace=True),
            nn.Linear(512, embed_dim),
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        feat = self.backbone(x)
        z = self.projection(feat)
        return F.normalize(z, dim=-1)

    def encode(self, x: torch.Tensor) -> torch.Tensor:
        """Inference path: skip projection, return L2-normalized backbone
        features. Smaller (512 vs 256), no head needed at runtime."""
        feat = self.backbone(x)
        return F.normalize(feat, dim=-1)


def nt_xent_loss(z1: torch.Tensor, z2: torch.Tensor, temperature: float = 0.1) -> torch.Tensor:
    """Symmetric NT-Xent (SimCLR) loss."""
    batch = z1.size(0)
    z = torch.cat([z1, z2], dim=0)                     # 2B × D
    sim = torch.matmul(z, z.T) / temperature           # 2B × 2B
    # Mask out self-similarity.
    mask = torch.eye(2 * batch, dtype=torch.bool, device=z.device)
    sim = sim.masked_fill(mask, -1e9)
    # Positives: i ↔ i+B and i+B ↔ i.
    targets = torch.arange(batch, device=z.device)
    targets = torch.cat([targets + batch, targets], dim=0)
    return F.cross_entropy(sim, targets)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data", type=Path, default=DEFAULT_DATA)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--epochs", type=int, default=20)
    parser.add_argument("--batch-size", type=int, default=128)
    parser.add_argument("--lr", type=float, default=3e-4)
    parser.add_argument("--num-workers", type=int, default=4)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--device", default="cuda" if torch.cuda.is_available() else "cpu")
    args = parser.parse_args()

    random.seed(args.seed)
    torch.manual_seed(args.seed)

    args.output.mkdir(parents=True, exist_ok=True)
    dataset = TorsoPairDataset(args.data)
    loader = DataLoader(dataset, batch_size=args.batch_size, shuffle=True,
                        num_workers=args.num_workers, drop_last=True,
                        pin_memory=(args.device == "cuda"))

    model = TorsoEncoder().to(args.device)
    optim = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=1e-4)
    sched = torch.optim.lr_scheduler.CosineAnnealingLR(optim, T_max=args.epochs)

    print(f"Training on {len(dataset)} torso crops, {args.epochs} epochs, batch={args.batch_size}")

    history = []
    for epoch in range(args.epochs):
        model.train()
        t0 = time.time()
        running = 0.0
        n = 0
        for v1, v2, _ in loader:
            v1 = v1.to(args.device, non_blocking=True)
            v2 = v2.to(args.device, non_blocking=True)
            z1 = model(v1)
            z2 = model(v2)
            loss = nt_xent_loss(z1, z2)
            optim.zero_grad()
            loss.backward()
            optim.step()
            running += loss.item() * v1.size(0)
            n += v1.size(0)
        sched.step()
        avg_loss = running / max(n, 1)
        history.append({"epoch": epoch, "loss": avg_loss, "secs": time.time() - t0})
        print(f"  epoch {epoch + 1:>2}/{args.epochs}  loss={avg_loss:.4f}  ({history[-1]['secs']:.1f}s)")

    out_pt = args.output / "torso_encoder.pt"
    torch.save({"state_dict": model.state_dict(), "embed_dim": EMBED_DIM}, out_pt)
    meta = {
        "epochs": args.epochs,
        "batch_size": args.batch_size,
        "lr": args.lr,
        "embed_dim": EMBED_DIM,
        "history": history,
    }
    (args.output / "training_metadata.json").write_text(json.dumps(meta, indent=2))
    print(f"Wrote encoder to {out_pt}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
