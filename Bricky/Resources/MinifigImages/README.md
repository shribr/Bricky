# Bundled Reference Image Set

This folder contains curated reference images for the offline minifigure
identification feature. Each image is keyed by figure ID (`<id>.jpg`)
and the `index.json` file maps figure IDs to filenames.

## Building / refreshing this set

The set is built by `Tools/build-reference-set.py`. Run it once with
internet access to fetch ~2000 popular minifigure images from the
rebrickable CDN, resize them, and populate this folder.

```sh
pip install Pillow requests
python3 Tools/build-reference-set.py
```

After running, the folder will contain ~2000 JPEG files (~40 MB total)
plus an updated `index.json`. Commit both to source control so the
images ship with the app.

## How it's used at runtime

`MinifigureReferenceImageStore` loads `index.json` at startup and serves
images by figure ID. The minifigure identification service consults this
store first (offline, fast) before falling back to the disk URL cache or
network.
