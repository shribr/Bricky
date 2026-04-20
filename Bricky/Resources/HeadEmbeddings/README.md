# Head Embeddings

This folder will contain the head-region embedding artifacts produced
by the offline training pipeline (`Tools/torso-embeddings/`):

- `head_embeddings.bin` — Float16 row-major matrix (N × 512)
- `head_embeddings_index.json` — `{ dim, count, ids[] }`
- `HeadEncoder.mlmodel` — CoreML model for on-device head encoding

## To populate

Run the head-encoder pipeline in Colab (after the torso pipeline):

```bash
python3 Tools/torso-embeddings/build-head-dataset.py --sleep 0.02
python3 Tools/torso-embeddings/train-head-encoder.py --epochs 20
python3 Tools/torso-embeddings/embed-head-catalog.py
python3 Tools/torso-embeddings/convert-head-encoder-coreml.py
```

Then copy the artifacts from `Bricky/Resources/HeadEmbeddings/` into
this folder, regenerate the Xcode project, and rebuild.

The app auto-detects these files at launch via
`HeadEmbeddingIndex.shared.isAvailable`.
