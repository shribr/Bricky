# How to run the DINOv2 prototype

You have three realistic environments. Pick one.

## Option A — Google Colab (recommended; matches your existing flow)

Mirrors the pattern you already use for `train-torso-encoder.ipynb`.
Free T4 tier is enough; DINOv2 ViT-L/14 on A100 takes ~3 minutes for
the full catalog.

1. Open a new Colab notebook, select **Runtime → Change runtime type → GPU**.
2. Clone the repo and pull LFS (if the catalog images are LFS-backed):
   ```python
   !git clone https://github.com/shribr/Bricky.git
   %cd Bricky
   ```
3. Install deps:
   ```python
   !pip install -q -r Tools/dinov2-embeddings/requirements.txt
   ```
4. Build the eval set (once — deterministic given the seed):
   ```python
   !python Tools/dinov2-embeddings/build_eval_set.py \
       --count 200 --variants-per-figure 8 --seed 42
   ```
5. Embed the catalog with DINOv2 ViT-S (fastest, smallest bundle):
   ```python
   !python Tools/dinov2-embeddings/embed_catalog.py \
       --model dinov2_vits14 \
       --out Tools/dinov2-embeddings/index/dinov2_vits14
   ```
   On a T4 this is ~2 minutes for the full 14K catalog.
6. Score:
   ```python
   !python Tools/dinov2-embeddings/evaluate_retrieval.py \
       --index Tools/dinov2-embeddings/index/dinov2_vits14 \
       --report Tools/dinov2-embeddings/reports/dinov2_vits14.json
   ```
7. Score the shipped SimCLR index on the same eval set (if
   `Tools/torso-embeddings/out/torso_encoder.pt` is reachable):
   ```python
   !python Tools/dinov2-embeddings/compare_existing.py \
       --report Tools/dinov2-embeddings/reports/simclr_shipped.json
   ```
8. Compare the two JSON reports — `recall@1`, `recall@5`, `recall@10`.

If DINOv2 ViT-S is close or below SimCLR, try `--model dinov2_vitb14`
or `--model dinov2_vitl14`. Bigger models take longer to embed and
produce larger bundles but should raise the ceiling.

## Option B — Local workstation with GPU

Exactly the same commands. Skip the `!` prefix. If you have less
than ~12 GB VRAM, stick with `dinov2_vits14` or `dinov2_vitb14`.

## Option C — Local CPU (slow but works for ViT-S)

```
cd Bricky
pip install -r Tools/dinov2-embeddings/requirements.txt
python Tools/dinov2-embeddings/build_eval_set.py --count 200 --variants-per-figure 8
python Tools/dinov2-embeddings/embed_catalog.py --model dinov2_vits14
python Tools/dinov2-embeddings/evaluate_retrieval.py
```

Expect ~15–25 minutes for the full catalog embed on a recent
laptop CPU. ViT-B is too slow to be worth it on CPU; ViT-L will
take hours.

## Reading the reports

```
{
  "encoder": "dinov2_vits14",
  "catalog_size": 14111,
  "variants_scored": 1600,
  "recall@1":  0.62,
  "recall@5":  0.84,
  "recall@10": 0.90,
  "recall@50": 0.96,
  "sample_failures": [ ... ]
}
```

**Rough interpretations** (order-of-magnitude, not guarantees):

| recall@5 | What it means |
|----------|---------------|
| < 0.20   | Encoder is effectively blind — probably a crop/preprocessing bug, not the model |
| 0.20–0.50 | Weak. Expected for your current SimCLR. Distinguishes "color bucket" better than "specific print" |
| 0.50–0.75 | Usable as a top-8 candidate list (matches your UX pattern of showing top 8) |
| > 0.75   | Ship it |

`sample_failures` is 20 worst cases. Skim them — if the top-5 for a
failed query is full of figures with the same torso color but
different prints, the encoder is confusing "color" for "identity"
and you need a stronger backbone or fine-tuning. If the top-5 looks
random, there's a preprocessing mismatch between index and query.

## Once you have a winner

Swap the bundled assets — nothing else changes:

```
cp Tools/dinov2-embeddings/index/dinov2_vits14/torso_embeddings.bin \
   Bricky/Resources/TorsoEmbeddings/torso_embeddings.bin
cp Tools/dinov2-embeddings/index/dinov2_vits14/torso_embeddings_index.json \
   Bricky/Resources/TorsoEmbeddings/torso_embeddings_index.json
```

You'll also need a matching `TorsoEncoder.mlmodel` — that's the
one genuinely new piece (DINOv2 → CoreML conversion). We can write
that once the offline numbers justify it.

Delete `torso_embeddings_mean.bin` — the mean-centering band-aid
isn't needed with DINOv2 embeddings, and the iOS loader treats its
absence as "skip centering" (see `TorsoEmbeddingIndex.swift` ll.
146-162).

## If you can't run it right now

The pipeline was smoke-tested end-to-end in a sandbox using a
random-init stub (`--random-init`) because outbound weight
downloads are blocked there. The plumbing is known-good. The first
real accuracy number you'll see is from Colab.
