"""Build a held-out evaluation set for minifigure retrieval.

For each held-out figure we generate K synthetic "noisy scan" variants.
The goal is NOT to be photo-realistic — it is to simulate the same
distribution shift a real camera scan introduces relative to a clean
catalog render, so that a retrieval encoder that only separates clean
renders (our current SimCLR weakness) gets honestly penalized.

Output:
    {OUT_DIR}/
        ground_truth.json    # [{ "figure_id": "fig-012345", "variants": ["v0.jpg", ...] }, ...]
        variants/
            fig-012345/
                v0.jpg
                v1.jpg
                ...

The held-out list is deterministic given --seed. Re-running with the
same seed reproduces the exact same eval set, so A/B comparisons
across encoders are directly comparable.
"""

from __future__ import annotations

import argparse
import gzip
import json
import math
import random
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageOps


BRICKY_ROOT = Path(__file__).resolve().parents[2]
CATALOG_PATH = BRICKY_ROOT / "Bricky" / "Resources" / "MinifigureCatalog.json.gz"
IMAGES_ROOT = BRICKY_ROOT / "Bricky" / "Resources" / "MinifigImages"
DEFAULT_OUT = Path(__file__).resolve().parent / "eval"

# A few distinct colored backgrounds give the eval variety without
# needing a natural-image dataset. Each is a solid color or a simple
# gradient that forces the encoder to ignore background.
BACKGROUND_PALETTE = [
    (220, 220, 220),   # neutral gray (table)
    (190, 170, 140),   # beige (carpet)
    (120, 130, 110),   # muted green (felt)
    (235, 230, 215),   # cream (paper)
    (90,  95,  105),   # dark slate
    (180, 140, 100),   # wood
    (50,  55,  60),    # near-black tabletop
]


def load_catalog() -> list[dict]:
    with gzip.open(CATALOG_PATH, "rb") as f:
        data = json.load(f)
    figs = data["figures"] if isinstance(data, dict) else data
    # Only keep figures whose render is bundled on-disk so we can
    # read the source image without hitting the network.
    out = []
    for f in figs:
        p = IMAGES_ROOT / f"{f['id']}.jpg"
        if p.exists():
            out.append({"id": f["id"], "path": p})
    return out


def paste_on_background(fig_img: Image.Image, rng: random.Random) -> Image.Image:
    """Composite the figure onto a solid/gradient background sized
    ~1.5x the figure, so the figure doesn't fill the frame (real
    phone photos rarely frame the figure edge-to-edge)."""
    import numpy as np
    bg_color = rng.choice(BACKGROUND_PALETTE)
    fw, fh = fig_img.size
    # Background size: 1.3x–1.8x the figure bbox.
    pad_w = int(fw * rng.uniform(1.3, 1.8))
    pad_h = int(fh * rng.uniform(1.3, 1.8))
    # Simple vertical gradient so the background isn't perfectly flat.
    bg = Image.new("RGB", (pad_w, pad_h), bg_color)
    grad_strength = rng.randint(15, 40)
    top_color = tuple(max(0, min(255, c - grad_strength)) for c in bg_color)
    overlay = Image.new("RGB", (pad_w, pad_h), top_color)
    mask = Image.linear_gradient("L").resize((pad_w, pad_h))
    bg = Image.composite(bg, overlay, mask)
    # Place figure at a random offset within the background.
    ox = rng.randint(0, pad_w - fw)
    oy = rng.randint(0, pad_h - fh)
    # Key the Rebrickable background out. Those renders are NOT on
    # pure white — they sit on a soft cream (~RGB 221,208,200 at
    # the corners) with JPEG-softened edges, so "distance from
    # pure white" doesn't catch them. Instead, sample the 4 corners
    # to learn the actual background color, then treat pixels close
    # to that color (in L2 RGB distance) as background.
    arr = np.asarray(fig_img.convert("RGB"), dtype=np.float32)
    corners = np.concatenate([
        arr[0:3, :].reshape(-1, 3),
        arr[-3:, :].reshape(-1, 3),
        arr[:, 0:3].reshape(-1, 3),
        arr[:, -3:].reshape(-1, 3),
    ], axis=0)
    bg_ref = corners.mean(axis=0)  # average corner color
    # L2 distance in RGB — cheap, works because renders have a flat
    # non-textured background. Threshold 42 keeps JPEG haze out
    # while leaving saturated figure parts intact (a red hat at
    # ~(200,40,40) is ~270 away; skin at (242,205,55) is ~260 away).
    dist = np.sqrt(((arr - bg_ref) ** 2).sum(axis=2))
    alpha = np.where(dist < 42, 0, 255).astype(np.uint8)
    # Feather the edge one pixel so pasted figures don't look like
    # perfect cutouts (which would give the encoder a too-easy
    # "locate the figure" shortcut).
    alpha_img = Image.fromarray(alpha, "L").filter(ImageFilter.GaussianBlur(radius=0.8))
    rgba = np.dstack([arr.astype(np.uint8), np.asarray(alpha_img, dtype=np.uint8)])
    fig_rgba = Image.fromarray(rgba, "RGBA")
    bg.paste(fig_rgba, (ox, oy), fig_rgba)
    return bg


def random_perspective(img: Image.Image, rng: random.Random) -> Image.Image:
    """Small perspective warp simulating handheld phone angle."""
    w, h = img.size
    # Jitter each corner by up to 6% of the image side.
    def jitter(pt):
        jx = rng.uniform(-0.06, 0.06) * w
        jy = rng.uniform(-0.06, 0.06) * h
        return (pt[0] + jx, pt[1] + jy)
    src = [(0, 0), (w, 0), (w, h), (0, h)]
    dst = [jitter(p) for p in src]
    # Build the 8-coefficient perspective transform. PIL needs the
    # transform from OUTPUT → INPUT, so we solve the linear system.
    coeffs = _perspective_coeffs(dst, src)
    return img.transform((w, h), Image.Transform.PERSPECTIVE, coeffs,
                         resample=Image.BILINEAR, fillcolor=(0, 0, 0))


def _perspective_coeffs(src, dst):
    """Standard 8-param solver for PIL's perspective transform."""
    matrix = []
    for (x, y), (X, Y) in zip(dst, src):
        matrix.append([x, y, 1, 0, 0, 0, -X * x, -X * y])
        matrix.append([0, 0, 0, x, y, 1, -Y * x, -Y * y])
    import numpy as np
    A = np.array(matrix, dtype=np.float64)
    B = np.array([c for pt in src for c in pt], dtype=np.float64)
    res = np.linalg.solve(A, B)
    return tuple(float(v) for v in res)


def random_rotation(img: Image.Image, rng: random.Random) -> Image.Image:
    angle = rng.uniform(-25, 25)
    return img.rotate(angle, resample=Image.BILINEAR, fillcolor=(0, 0, 0), expand=False)


def random_shadow(img: Image.Image, rng: random.Random) -> Image.Image:
    """Darken a random half-plane to simulate directional lighting."""
    w, h = img.size
    overlay = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(overlay)
    # Random diagonal shadow edge.
    direction = rng.choice(["left", "right", "top", "bottom"])
    strength = rng.randint(30, 90)
    if direction == "left":
        draw.rectangle([0, 0, w // 2, h], fill=strength)
    elif direction == "right":
        draw.rectangle([w // 2, 0, w, h], fill=strength)
    elif direction == "top":
        draw.rectangle([0, 0, w, h // 2], fill=strength)
    else:
        draw.rectangle([0, h // 2, w, h], fill=strength)
    overlay = overlay.filter(ImageFilter.GaussianBlur(radius=max(w, h) // 8))
    dark = Image.new("RGB", (w, h), (0, 0, 0))
    return Image.composite(dark, img, overlay)


def random_occlusion(img: Image.Image, rng: random.Random) -> Image.Image:
    """Paint a 'finger/hand' blob over part of the figure."""
    w, h = img.size
    overlay = img.copy()
    draw = ImageDraw.Draw(overlay)
    # Ellipse about 15-30% of the image height, skin-tone color.
    blob_w = int(w * rng.uniform(0.15, 0.30))
    blob_h = int(h * rng.uniform(0.25, 0.45))
    cx = rng.randint(0, w)
    cy = rng.randint(h // 3, h)
    skin = rng.choice([(220, 180, 140), (200, 160, 120), (180, 140, 100), (150, 120, 90)])
    draw.ellipse([cx - blob_w // 2, cy - blob_h // 2,
                  cx + blob_w // 2, cy + blob_h // 2], fill=skin)
    return Image.blend(img, overlay, rng.uniform(0.6, 0.9))


def random_blur_and_jpeg(img: Image.Image, rng: random.Random) -> Image.Image:
    if rng.random() < 0.6:
        img = img.filter(ImageFilter.GaussianBlur(radius=rng.uniform(0.3, 1.2)))
    # Simulate JPEG compression by round-tripping through bytes.
    import io
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=rng.randint(55, 85))
    buf.seek(0)
    return Image.open(buf).convert("RGB")


def color_jitter(img: Image.Image, rng: random.Random) -> Image.Image:
    import numpy as np
    arr = np.asarray(img, dtype=np.float32)
    # Multiplicative per-channel gain.
    gain = np.array([rng.uniform(0.85, 1.15) for _ in range(3)], dtype=np.float32)
    arr = np.clip(arr * gain, 0, 255)
    # Additive brightness shift.
    arr = np.clip(arr + rng.uniform(-15, 15), 0, 255)
    return Image.fromarray(arr.astype("uint8"), "RGB")


def make_variant(source: Image.Image, rng: random.Random) -> Image.Image:
    out = paste_on_background(source, rng)
    out = random_rotation(out, rng)
    out = random_perspective(out, rng)
    out = random_shadow(out, rng)
    if rng.random() < 0.5:
        out = random_occlusion(out, rng)
    out = color_jitter(out, rng)
    out = random_blur_and_jpeg(out, rng)
    # Resize to a typical phone-capture resolution so the encoder
    # sees inputs roughly comparable to what the iOS pipeline would
    # hand it (a 224 square after the crop stage).
    out.thumbnail((512, 512), Image.LANCZOS)
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--count", type=int, default=200,
                        help="How many figures to hold out.")
    parser.add_argument("--variants-per-figure", type=int, default=8)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    args = parser.parse_args()

    rng = random.Random(args.seed)

    figures = load_catalog()
    if len(figures) < args.count:
        sys.exit(f"Only {len(figures)} catalog figures on disk; requested {args.count}")
    rng.shuffle(figures)
    held_out = figures[: args.count]

    variants_root = args.out / "variants"
    variants_root.mkdir(parents=True, exist_ok=True)
    ground_truth = []
    for fig in held_out:
        source = Image.open(fig["path"]).convert("RGB")
        fig_dir = variants_root / fig["id"]
        fig_dir.mkdir(parents=True, exist_ok=True)
        names = []
        for k in range(args.variants_per_figure):
            local_rng = random.Random(rng.randrange(1 << 31))
            v = make_variant(source, local_rng)
            name = f"v{k}.jpg"
            v.save(fig_dir / name, "JPEG", quality=88)
            names.append(name)
        ground_truth.append({"figure_id": fig["id"], "variants": names})

    (args.out / "ground_truth.json").write_text(
        json.dumps({"held_out": [g["figure_id"] for g in ground_truth],
                    "ground_truth": ground_truth}, indent=2)
    )
    (args.out / "config.json").write_text(json.dumps({
        "count": args.count,
        "variants_per_figure": args.variants_per_figure,
        "seed": args.seed,
    }, indent=2))
    total = sum(len(g["variants"]) for g in ground_truth)
    print(f"Wrote {total} variants for {len(ground_truth)} figures to {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
