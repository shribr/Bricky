# Face Embeddings

This folder will contain the face-region embedding artifacts produced
by the offline training pipeline (`Tools/torso-embeddings/`):

- `face_embeddings.bin` — Float16 row-major matrix (N × 512)
- `face_embeddings_index.json` — `{ dim, count, ids[] }`
- `FaceEncoder.mlmodel` — CoreML model for on-device face encoding

The face crop covers rows 17–35% of the figure image — below the
hairline, above the neck — capturing printed expressions, skin tone,
glasses, and facial hair while excluding hair/helmets/hats.

## To populate

Run the face-encoder pipeline in Colab:

```bash
python3 Tools/torso-embeddings/build-face-dataset.py --sleep 0.02
python3 Tools/torso-embeddings/train-face-encoder.py --epochs 20
python3 Tools/torso-embeddings/embed-face-catalog.py
python3 Tools/torso-embeddings/convert-face-encoder-coreml.py
```

Then copy the artifacts from `Bricky/Resources/FaceEmbeddings/` into
this folder, regenerate the Xcode project, and rebuild.

The app auto-detects these files at launch via
`FaceEmbeddingIndex.shared.isAvailable`.
