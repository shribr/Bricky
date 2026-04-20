# Torso Embedding Training & Index Pipeline

This directory contains the offline training pipeline for the
**torso-embedding** and **head-embedding** identification models
(Option A from the identification-strategy ladder) and the runtime
artifacts they produce that get bundled into the iOS app.

## Why

The runtime cascade in `Bricky/Services/MinifigureIdentificationService.swift`
combines:
1. Color-cascade scoring (Phase 1).
2. Generic `VNFeaturePrintObservation` similarity over the torso band
   plus the new structural `TorsoVisualSignature` (Phase 2 — Option D).

Even with Option D, generic embeddings struggle when many figures share
a palette but differ in *print content* (e.g. an astronaut vs. a Star
Wars officer with the same white/orange torso). A torso-specific
embedding trained with self-supervision on the actual catalog images
fixes that — same-torso crops cluster together; different torsos do not.

This pipeline:
1. **Downloads** all torso reference renders from Rebrickable (or a
   curated subset), one image per figure.
2. **Trains** a small ResNet18-sized contrastive encoder (DINO/SimCLR
   style) where each figure's torso crop is a class. Heavy
   augmentation simulates phone-camera reality (lighting, blur,
   rotation, occlusion, JPEG noise).
3. **Embeds** every catalog torso once and writes
   `torso_embeddings.bin` (`Float16` matrix, ~16K × 256) and an
   accompanying `torso_embeddings_index.json` mapping row → figureId.
4. **Converts** the encoder to CoreML and writes `TorsoEncoder.mlmodel`
   so the device runs the same encoder over the captured torso band
   at scan time.

At runtime the iOS app loads the bundle (~10–15 MB encoder + ~16 MB
index), encodes the captured torso once per scan, and does cosine-
nearest-neighbor against the index — sub-millisecond on N3 silicon.

## Status

Scripts here are **scaffolding** — they encode the architecture choices
and produce the correct artifact layout, but training itself is intended
to be run on a workstation/Colab with a GPU, not on the developer's
laptop. Set `BRICKY_TRAINING_DATA_DIR` / `BRICKY_TRAINING_OUTPUT_DIR`
before invoking the scripts; outputs land in
`Bricky/Resources/TorsoEmbeddings/` for bundling.

## Pipeline

```
build-torso-dataset.py           # download / cache torso renders (one per figure)
        │
        ▼
train-torso-encoder.py           # DINO-style self-supervised training
        │
        ▼
embed-torso-catalog.py           # apply trained encoder → bin + index json
        │
        ▼
convert-torso-encoder-coreml.py  # PyTorch → CoreML for on-device inference
```

### Head Encoder Pipeline

Identical architecture, trained on the head/helmet region (top 5–35%
of the figure image). Catches distinctive headgear that the torso
pass misses (e.g. Darth Vader's helmet, Boba Fett's T-visor).

```
build-head-dataset.py            # download / cache head-band crops
        │
        ▼
train-head-encoder.py            # SimCLR contrastive training on head crops
        │
        ▼
embed-head-catalog.py            # apply trained encoder → bin + index json
        │
        ▼
convert-head-encoder-coreml.py   # PyTorch → CoreML for on-device inference
```

Head artifacts land in `Bricky/Resources/HeadEmbeddings/`.

After running either pipeline, regenerate the Xcode project (`xcodegen
generate`) and rebuild — the runtime paths in
`TorsoEmbeddingIndex.swift` and `HeadEmbeddingIndex.swift` will pick
up the new artifacts automatically.
