# LDraw Parts Library

This folder is **populated by a download script** — it is intentionally empty in the repo.

## What is this?

[LDraw](https://www.ldraw.org/) is the open-standard 3D LEGO part library, with **~17,000 official parts** maintained by the LEGO community since 1995. BrickVision uses these `.dat` files to render accurate 3D previews of identified pieces, instead of the old procedural approximations.

## Setup

From the repo root, run:

```sh
./scripts/download-ldraw-parts.sh
```

The script will:
1. Download the official `complete.zip` from ldraw.org (~80 MB)
2. Extract a curated subset of parts that match BrickVision's catalog (~5–15 MB on disk)
3. Place them into this folder in the standard LDraw layout:

```
LDraw/
  parts/        ← top-level part files (e.g. 3001.dat for a 2×4 brick)
    s/          ← sub-parts referenced by parts
  p/            ← primitives (cylinders, discs, edges)
    48/         ← high-resolution primitives
```

After running the script, regenerate the Xcode project and rebuild:

```sh
xcodegen generate
xcodebuild build -project BrickVision.xcodeproj -scheme BrickVision \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## License

LDraw parts are distributed under the [Creative Commons Attribution License 4.0 (CC BY 4.0)](https://creativecommons.org/licenses/by/4.0/) by the LDraw Parts Library Project. If you ship the app, include attribution in the in-app credits.

## Without this folder

If `LDraw/` is missing or empty, BrickVision falls back to procedural geometry (the old behavior). The build will still succeed — LDraw parts are an optional enhancement.
