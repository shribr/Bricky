## DINOv2 torso-retrieval prototype

A zero-shot baseline for minifigure identification that sidesteps the
training pitfalls of the `torso-embeddings/` pipeline (single image
per class + SimCLR = underseparated space, no domain-gap data).

The idea: a strong pretrained vision transformer already separates
fine-grained visual content well enough to retrieve the correct
catalog render for a messy real-world scan. We embed the catalog
once with DINOv2, store the matrix, and do cosine nearest-neighbor
at scan time — no custom training, no contrastive loss, no 14K-class
margin loss to tune.

If zero-shot DINOv2 beats the existing shipped `torso_embeddings.bin`
on a held-out eval set (it usually does for this kind of task), the
fix is "swap the encoder" not "re-train harder."

### Scripts

```
build-eval-set.py          # pick N held-out figures, synthesize noisy-scan variants
embed-catalog.py           # DINOv2 forward pass over all catalog renders → matrix + index
evaluate-retrieval.py      # recall@1/5/10 against the eval set for a given index
compare-existing.py        # run the same eval on Resources/TorsoEmbeddings/*.bin
```

### Intended workflow

```
# 1. Build a held-out eval set once (N figures × K noisy variants each)
python build-eval-set.py --count 200 --variants-per-figure 8 --seed 42

# 2. Embed the catalog with DINOv2 (GPU recommended; CPU works for smoke tests)
python embed-catalog.py --model dinov2_vits14 --out ./index/dinov2_vits14

# 3. Score DINOv2
python evaluate-retrieval.py --index ./index/dinov2_vits14 --eval ./eval

# 4. Score the shipped SimCLR index on the SAME eval set
python compare-existing.py --eval ./eval
```

### Why DINOv2 (not CLIP, not a custom encoder)

- **DINOv2** is self-supervised on 142M natural images, attends to
  dense visual structure (not text-alignment like CLIP), and has
  shown excellent zero-shot fine-grained retrieval in independent
  benchmarks. Three size tiers (S/B/L/g) let us trade accuracy
  for CoreML bundle size.
- **CLIP** is a valid alternative. It's tuned for image-text
  alignment, which sometimes hurts purely-visual retrieval of items
  without obvious captions (most LEGO torsos). Include as a
  secondary baseline if needed.
- **Custom fine-tuning** can come LATER once the zero-shot baseline
  is measured — then we know whether training effort is buying
  anything real vs. ~0 from the SimCLR pipeline.

### Eval set design

Catalog renders are clean and synthetic. Real scans aren't. The eval
generator applies a stack of transforms meant to simulate the
distribution shift at scan time:

- paste the figure onto a random natural background (hand, table,
  carpet, pile of other bricks)
- random perspective warp (±12°)
- random 3D-like rotation (±25° in-plane)
- random shadow + lighting jitter
- random partial occlusion (hand over part of the torso)
- JPEG compression + slight gaussian blur

Each held-out figure produces K variants. We record the figure_id
as ground truth and keep them OUT of the catalog embedding index so
retrieval is honestly held out.

### What this prototype does NOT do

- **No CoreML export.** Once we pick a winner we'll plug it into
  the existing `convert-*-encoder-coreml.py` pattern.
- **No runtime integration.** The iOS `TorsoEmbeddingService` can
  consume any `.bin` + `.json` with the same schema — no Swift
  changes needed to A/B swap.
- **No segmentation model.** Uses the existing fixed-band crop so
  results are comparable to the current pipeline. A learned
  segmenter is a separate optimization on top of whichever encoder
  wins.
