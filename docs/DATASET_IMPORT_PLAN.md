# External Dataset Import Plan — DINOv2 Minifigure Embeddings

> **Status:** Draft → **Under critical review**  
> **Created:** 2026-04-23  
> **Updated:** 2026-04-23 — Critical review: cut scope, eliminated redundancy, focused on what actually moves the needle  
> **Scope:** Import external LEGO minifigure image datasets to improve real-photo retrieval accuracy  
> **Current real-photo recall@1:** 0.040 (baseline to beat)

---

## CRITICAL ISSUES FOUND IN REVIEW

### Issue 1: HuggingFace Armaggheddon is almost entirely redundant

The HuggingFace dataset sources from the **same Rebrickable CDN** as our existing 14,113 renders. The plan estimated ~1K–3K "gap-fills" but this is speculative — the actual overlap hasn't been measured. Even the gap-fills are just **more renders**, which don't help the core problem (real-photo recall = 0.040). Adding more renders from the same domain to the index does nothing for the domain gap.

**Decision: DROP from active plan.** If we later discover we're missing renders for specific figures, a simple `wget` from Rebrickable CDN is trivial. We don't need a 558 MB dataset download, overlap analysis pipeline, and dedicated scripts for this.

### Issue 2: Datasciencedonut has no ID labels — mapping cost is prohibitive

The 241 datasciencedonut photos have **zero figure identification labels**. The plan proposed "map to figure IDs using embedding nearest-neighbor against catalog" — but our current embeddings have 0.040 real-photo recall@1. Using a broken matcher to auto-label training data is circular reasoning; the mappings would be garbage. Every single one of the 241 photos would need manual identification against the 15,789-figure catalog.

**Decision: DEMOTE to "nice-to-have."** Only revisit after ihelon real photos are integrated and we have a working real-photo pipeline. At that point we can use the *improved* embeddings to auto-map these.

### Issue 3: Stable Diffusion synthetic generation doesn't produce specific figures

The `nerijs/lego-minifig-xl` model generates **generic LEGO-style minifigures** from text prompts. It cannot produce a specific catalog variant (e.g., "Harry Potter in Gryffindor robes from set 75978" vs. "Harry Potter in Quidditch robes from set 75956"). The torso print — which is exactly what our torso crop is trying to match — would be wrong on nearly every generation. The cosine similarity gate would either filter everything out or let through misleading embeddings.

**Decision: DROP entirely.** This is a solution looking for a problem. Real photos and cross-source renders address the domain gap directly.

### Issue 4: Plan proposes 6 new scripts that duplicate existing tools

The plan lists new scripts: `download_huggingface.py`, `download_kaggle.py`, `map_kaggle_ids.py`, `analyze_overlap.py`, `build_unified_mapping.py`, `ingest_external.py`. But `ingest_real_photos.py` **already handles** fuzzy name matching (`score_match()`), index augmentation (`cmd_augment()`), and eval set building (`cmd_eval()`). The Kaggle ihelon dataset just needs its folder structure adapted to what `ingest_real_photos.py` already expects — not a parallel pipeline.

**Decision: Extend `ingest_real_photos.py` to accept folder-organized datasets (one small code change), not build new infrastructure.**

### Issue 5: Over-engineered augmentation strategy

The plan proposes 5× augmentation on real photos (~2,500 augmented images from 498 originals), custom augmentation budgets, and new augmentation transforms. But `build_eval_set.py` already has rotation, perspective, shadow, and background augmentation. And augmenting 498 real photos 5× produces embeddings that are slight variants of each other — diminishing returns. Better to get the 498 raw embeddings right first.

**Decision: Skip augmentation in Phase 1.** Use raw embeddings only. Augment later ONLY if eval shows it helps.

### Issue 6: Torso crop may be the actual bottleneck, not dataset size

MinifigFinder uses Mask R-CNN to detect torso region precisely. Our pipeline uses a fixed heuristic (30%–70% vertical band) which works on clean renders but likely fails on real photos where the figure is tilted, partially occluded, or off-center. Adding more data won't fix a bad crop. We should validate the crop quality on real photos before investing in more data.

**Decision: Add a "torso crop audit" step before Phase 1. Visually inspect the torso crops from our existing 27 real iPhone photos to verify the crop is actually capturing torsos, not background.**

---

## Revised Scope: What Actually Matters

---

## Table of Contents

0. [CRITICAL ISSUES FOUND IN REVIEW](#critical-issues-found-in-review) — **Read this first**
1. [Current State Summary](#1-current-state-summary)
2. [Dataset Inventory & Analysis](#2-dataset-inventory--analysis)
3. [Download & Storage Plan (Revised)](#3-download--storage-plan-revised)
4. [ID Mapping Strategy (Revised)](#4-id-mapping-strategy-revised)
5. [Image Processing Pipeline](#5-image-processing-pipeline)
6. [Training & Indexing Strategy](#6-training--indexing-strategy)
7. [Pipeline Changes (Revised — Minimal)](#7-pipeline-changes-scripts--notebooks)
8. [Validation & Testing (Revised)](#8-validation--testing-revised--practical-only)
9. [Risk & Mitigations](#9-risk--mitigations)
10. [Implementation Order (Revised — Minimal)](#10-implementation-order-revised--minimal-viable-path)
11. [External Tools & Architectural Insights](#11-external-tools--architectural-insights)
12. [Datasets Reviewed & Excluded](#12-datasets-reviewed--excluded)

---

## 1. Current State Summary

### Catalog & Renders

| Metric | Value |
|---|---|
| Catalog figures | 15,789 (`Bricky/Resources/MinifigureCatalog.json.gz`) |
| Catalog renders on disk | 14,113 (`Bricky/Resources/MinifigImages/fig-NNNNNN.jpg`) |
| Render source | Rebrickable CDN |
| Render size on disk | 144 MB |
| ID format | `fig-NNNNNN` (zero-padded 6 digits) |
| Catalog fields | `id`, `name`, `theme`, `year`, `partCount`, `imgURL`, `parts[]` |

### Embedding Pipeline

| Component | Detail |
|---|---|
| Model | DINOv2 ViT-S/14 (`dinov2_vits14`) — 384-D embeddings |
| Torso crop | Vertical band rows 30%–70%, thumbnail to 224×224, pad to square with fill `(244,244,244)` |
| Normalization | ImageNet mean `[0.485, 0.456, 0.406]`, std `[0.229, 0.224, 0.225]` |
| Index format | `torso_embeddings.bin` (Float16 row-major) + `torso_embeddings_index.json` |
| Index size estimate | 14,113 × 384 × 2 bytes ≈ **10.8 MB** |
| Runtime | CoreML on-device (iOS) |

### Existing Cross-Source Data

| Source | Count | Type | On Disk |
|---|---|---|---|
| BrickLink renders | 199 | CG renders (different style) | 23 MB in `Tools/dinov2-embeddings/bricklink_images/` |
| Real iPhone photos | 27 | Real-world photos | 13 MB in `images/figurines/` |
| Real photo mapping | 27 entries | JSON mapping file | `Tools/dinov2-embeddings/real_photos/mapping.json` |

### Key Code Files

| File | Purpose |
|---|---|
| `embed_catalog.py` | Builds the embedding index from catalog renders |
| `evaluate_retrieval.py` | Measures recall@{1,5,10,50} with bbox detection |
| `ingest_real_photos.py` | Maps real photos by fuzzy filename matching, augments index, builds eval sets |
| `fetch_bricklink_images.py` | Scrapes Rebrickable→BrickLink ID mapping, downloads BrickLink renders |
| `build_eval_set.py` | Generates synthetic augmented eval variants (rotation, lighting, bg, occlusion) |
| `compare_existing.py` | Compares embedding approaches |

### Key Pipeline Functions

- **`torso_crop(img)`** — Crop vertical band [30%, 70%], thumbnail to 224×224, pad to square
- **`detect_figure_bbox(img)`** — Corner-sampling background detection, L2 distance > 50 threshold, 8px padding. Used for real photos and augmented images before torso crop.
- **`embed_batch(model, batch)`** — L2-normalized CLS-token embeddings
- **`load_dinov2(model_name, device)`** — Hub loader with random-init stub option for smoke tests

---

## 2. Dataset Inventory & Analysis

### 2.1 HuggingFace: Armaggheddon/lego_minifigure_captions

| Property | Value |
|---|---|
| Size | 558 MB (12,966 images) |
| Source | Rebrickable (same as our catalog renders!) |
| Format | Parquet dataset with JPEG images |
| Columns | `image`, `short_caption`, `caption`, `fig_num`, `num_parts`, `minifig_inventory_id`, `part_inventory_id`, `part_num` |
| License | MIT |
| ID field | `fig_num` — this is the Rebrickable figure number, should map directly to `fig-NNNNNN` |

**Critical question: overlap.** This dataset sources from Rebrickable, the same CDN as our existing 14,113 renders. The `fig_num` field should map directly to our `fig-NNNNNN` IDs. We must quantify:
- How many of the 12,966 images match our existing 14,113 renders (expected: high overlap)
- How many are net-new figures we don't have renders for (gap-fill opportunity)
- Whether the images are identical bytes or different crops/resolutions (if identical → zero value for diversity)

**Expected outcome:** Mostly duplicate renders (same CDN), but may fill ~1,000–3,000 gaps where we have catalog entries but no render image. **Net value: gap-filling, not diversity.**

### 2.2 Kaggle: ihelon/lego-minifigures-classification

| Property | Value |
|---|---|
| Size | 31 MB (~498 real photos) |
| Source | Real photographs |
| Themes | Harry Potter, Jurassic World, Marvel, Star Wars |
| Format | Organized by character folders with multiple poses per figure |
| License | CC BY 4.0 |
| ID field | Character folder names (e.g., `HARRY POTTER/`, `YODA/`) — NO fig-NNNNNN IDs |

**This is the highest-value dataset** because it contains actual photographs (not renders), which directly addresses the domain gap causing our 0.040 real-photo recall@1. Multiple angles per figure provides the diversity needed.

**Challenge:** ID mapping requires fuzzy matching character names → our catalog. Only covers 4 themes (~50-100 unique characters), so catalog coverage is narrow but the real-photo signal is invaluable.

### 2.3 Kaggle: datasciencedonut/lego-minifigures

| Property | Value |
|---|---|
| Size | 475 MB (~241 images + background/modified variants) |
| Source | Real photographs against black background |
| Format | `raw_images/`, `modified_images/`, `background_images/` + `features.csv` metadata |
| Columns | `Image_Id`, `Human?`, `Hair?`, `Hat?`, `Helmet?` |
| License | **CC0: Public Domain** |
| ID field | Filenames only — NO fig-NNNNNN IDs |

**Now verified.** This is a real-photo dataset of LEGO minifigures shot against a black background, with attribute annotations (human/hair/hat/helmet). The black background is ideal for bbox detection (our corner-sampling approach will work well).

**Value:** 241 additional real photos with clean backgrounds. Lower priority than ihelon (fewer images, no theme/character labels), but the **CC0 license** is the most permissive of all datasets. The attribute metadata (hat, helmet, hair) could potentially inform torso-crop quality checks.

**Challenge:** No character or figure ID labels — requires the same fuzzy-match or visual-embedding approach as ihelon to map to `fig-NNNNNN` IDs. Given the black background, consider using the embeddings themselves to find nearest catalog matches.

### 2.4 BrickLink Renders (existing pipeline)

| Property | Value |
|---|---|
| Count | 199 fetched (of 200 targeted) |
| Source | BrickLink CDN |
| Format | PNG renders |
| Pipeline | `fetch_bricklink_images.py` already handles download and eval set creation |

Already integrated. Can be scaled up (the script supports arbitrary `--figures` count), but rate-limited by web scraping for the Rebrickable→BrickLink ID mapping.

### Dataset Value Matrix (Revised)

| Dataset | Image Type | Est. Net-New | ID Mapping Difficulty | Value for Real-Photo Recall | Priority |
|---|---|---|---|---|---|
| Kaggle ihelon (real photos) | Photographs | ~498 | Medium (folder names + existing `score_match()`) | **Very High** — only real photos with labels | **P0 — DO THIS** |
| BrickLink (scale up) | Renders | Up to ~14K | Medium (scrape mapping) | Medium (cross-render diversity) | **P1 — existing pipeline, just scale** |
| Kaggle datasciencedonut | Real photos (black bg) | ~241 | **Very Hard** (no labels, need working embeddings first) | Medium (CC0 license) | **DEFERRED** — revisit after P0 |
| HuggingFace Armaggheddon | Renders | ~1K–3K gap-fill | Easy (fig_num) | **Near zero** (same source as existing renders) | **DROPPED** |
| Stable Diffusion synthetic | AI-generated | Unlimited | N/A | **Near zero** (can't produce specific torso prints) | **DROPPED** |

> **Rationale:** The only thing that directly addresses the 0.040 real-photo recall is feeding the pipeline **actual photos of identifiable minifigures**. Kaggle ihelon is the only dataset that provides both. Everything else is either the same domain we already have (more renders), unlabeled (prohibitive mapping cost), or can't produce figure-specific images (SD). BrickLink scale-up is kept because it uses the existing pipeline with zero new code.

### 2.5 HuggingFace: nerijs/lego-minifig-xl (Stable Diffusion Synthetic Generation)

| Property | Value |
|---|---|
| Type | Fine-tuned Stable Diffusion XL model (NOT a dataset) |
| Source | [awesome-lego-machine-learning](https://github.com/360er0/awesome-lego-machine-learning) survey |
| Purpose | Generate photorealistic synthetic images of specific LEGO minifigures |
| License | Model weights license — check HuggingFace card |
| Compute | Requires GPU; generates ~2 images/sec on T4 |

**Strategy: Targeted synthetic data generation.** Rather than downloading a static dataset, we can generate photorealistic images of specific minifigures on demand. This is uniquely valuable because:

1. **Per-figure control:** Generate images for the exact `fig-NNNNNN` IDs where we have catalog renders but no real photos
2. **Domain gap bridging:** SD-generated images sit stylistically between CG renders and real photos — they can act as intermediate anchors in embedding space
3. **Unlimited scale:** Generate as many variants as needed, with varied backgrounds, lighting, angles

**Workflow:**
```python
from diffusers import StableDiffusionXLPipeline
pipe = StableDiffusionXLPipeline.from_pretrained("nerijs/lego-minifig-xl")
# Prompt engineering: "a LEGO minifigure of [character], on a wooden table, natural lighting"
# Generate 5-10 images per prompt, embed, compute cosine to catalog render
# Keep only those with cosine > 0.25 to the correct catalog entry
```

**Risk:** Generated images may not look like the specific minifigure variant. Mitigation: cosine similarity gating against the catalog render embedding.

**Priority:** P2 — requires compute and prompt engineering. Best applied after P0/P1 data is integrated and we know which figures still have poor recall.

### 2.6 Nature Paper / Gdansk University Dataset (Brick Parts)

| Property | Value |
|---|---|
| Paper | Boiński (2023), "Photos and rendered images of LEGO bricks", *Scientific Data* |
| Size | ~155,000 real photos + ~1,500,000 renders |
| Coverage | 447 distinct LEGO parts (NOT minifigures) |
| Source | Gdańsk University of Technology "Most Wiedzy" repository |
| URL | `mostwiedzy.pl/en/open-research-data/lego-bricks-for-training-classification-network,618104539639776-0` |
| License | Open access via institutional repository |
| Related code | [github.com/tobiasbrx/LegoSorterServer](https://github.com/tobiasbrx/LegoSorterServer) |

**Assessment: NOT directly useful for minifigure identification.** This is the largest LEGO dataset available, but it covers individual brick/part classification for sorting machines, not assembled minifigures. The 447 parts are standard bricks, plates, slopes, technic elements, etc.

**Potential indirect value:**
- If the dataset includes minifigure *component* parts (torso pieces, leg assemblies, head pieces), these could supplement torso-crop training
- The rendering pipeline (Blender + LDraw) documented in the paper and related code could be adapted to render minifigure torso crops from 3D models
- The real-photo portion demonstrates effective camera/lighting setups for LEGO photography

**Decision: EXCLUDE from immediate import pipeline.** Revisit only if we pursue a part-level recognition approach (detect torso + match torso print) rather than whole-figure embedding matching.

### 2.7 Related Tools & Rendering Resources (from awesome-lego-ml)

These are not datasets but could generate synthetic training data:

| Tool | Source | Description | Relevance |
|---|---|---|---|
| **BrickRenderer** | [github.com/spencerhhubert/brick-renderer](https://github.com/spencerhhubert/brick-renderer) | Renders realistic training images from LDraw .dat files | Could render minifigure parts with varied backgrounds/lighting. Requires LDraw minifig models. |
| **LegoSorter** | [github.com/LegoSorter](https://github.com/LegoSorter) | Full sorting machine pipeline: mobile app, rendering scripts, training backend | Rendering scripts could be adapted for minifigure torso rendering. |
| **LegoBrickClassification** | [github.com/jtheiner/LegoBrickClassification](https://github.com/jtheiner/LegoBrickClassification) | Blender + LDraw pipeline for generating synthetic brick images (224×224) | Image generation pipeline matches our target resolution. Their eval showed significant domain gap between synthetic and real — confirms our challenge. |
| **B200C Dataset** | [kaggle.com/ronanpickell/b200c-lego-classification-dataset](https://www.kaggle.com/datasets/ronanpickell/b200c-lego-classification-dataset) | 800K renders for 200 parts | Brick-only, no minifigures. Excluded. |

---

## 3. Download & Storage Plan (Revised)

### 3.1 Directory Structure

```
datasets/                               # At repo root (gitignored raw images)
├── README.md                           # License attributions
└── kaggle_real_photos/                 # Kaggle ihelon real photos (P0)
    ├── raw/                            # Original folder structure from Kaggle
    │   ├── harry_potter/
    │   ├── jurassic_world/
    │   ├── marvel/
    │   └── star_wars/
    ├── mapping.json                    # Character name → fig-NNNNNN mapping (committed)
    └── prepare.py                      # Adapter: folder structure → mapping JSON (committed)

Tools/dinov2-embeddings/
├── bricklink_images/                   # EXISTING — 199+ BrickLink renders
├── real_photos/                        # EXISTING — 27 real iPhone photos
└── ...
```

**Dropped (not needed):**
- ~~`datasets/huggingface_rebrickable/`~~ — Same renders we already have
- ~~`datasets/kaggle_datasciencedonut/`~~ — No labels, deferred
- ~~`datasets/unified_mapping.json`~~ — One source, no unification needed

### 3.2 Download Commands

**Kaggle real photos (the only download we need):**
```bash
pip install kaggle
kaggle datasets download -d ihelon/lego-minifigures-classification \
    -p datasets/kaggle_real_photos/raw/ \
    --unzip
```

### 3.3 Size Estimates & Git Implications

| Dataset | Download Size | Extracted Size | Git Recommendation |
|---|---|---|---|
| Kaggle real photos (ihelon) | 31 MB | ~40 MB | `.gitignore` raw images, commit mapping.json + prepare.py |
| BrickLink (scaled up) | Variable | ~23 MB per 200 figs | Already in `.gitignore` per existing pattern |

### 3.4 .gitignore Updates

Add to root `.gitignore`:
```
datasets/kaggle_real_photos/raw/
```

Commit: `datasets/kaggle_real_photos/mapping.json`, `datasets/kaggle_real_photos/prepare.py`, `datasets/README.md`

---

## 4. ID Mapping Strategy (Revised)

### 4.1 Kaggle ihelon → fig-NNNNNN (The Only Mapping We Need)

The Kaggle ihelon dataset organizes images by character name in theme folders:
```
HARRY POTTER/    → contains photos of Harry Potter minifigs
YODA/            → contains photos of Yoda minifigs  
IRON MAN/        → contains photos of Iron Man minifigs
```

**This uses the existing `score_match()` function from `ingest_real_photos.py`.** No new matching code needed.

**Multi-stage mapping approach:**

**Stage 1 — Theme-aware catalog filtering:**
```
Folder "harry_potter" → filter catalog to theme ∈ {"Harry Potter"}
Folder "star_wars"    → filter catalog to theme ∈ {"Star Wars"}
Folder "marvel"       → filter catalog to theme ∈ {"Marvel", "Super Heroes"}
Folder "jurassic_world" → filter catalog to theme ∈ {"Jurassic World"}
```

**Stage 2 — Character name fuzzy matching (existing `score_match()`):**
For each character folder (e.g., `HARRY POTTER`), fuzzy-match against figure names within the filtered theme.

**Stage 3 — Manual review:**
~50 character→figure_id mappings to review (NOT 498 — all photos in a folder share one mapping).

**For characters with multiple variants** (e.g., "Harry Potter" has ~20+ minifigure variants): Map to the most common variant. All photos in the folder become queries that should return any HP variant — this is fine for training the index.

### 4.2 Mapping File Format

Same format as existing `ingest_real_photos.py` mapping. The `prepare.py` adapter outputs this directly:

```json
[
  {
    "filename": "star_wars/YODA/001.jpg",
    "figure_id": "fig-003456",
    "figure_name": "Yoda",
    "confident": true,
    "candidates": [...]
  }
]
```

**DROPPED sections:**
- ~~§4.1 HuggingFace → fig-NNNNNN~~ — Dataset dropped
- ~~§4.3 Unified Mapping File Format~~ — One source, no unification needed
- ~~§4.4 Handling Unmappable Images~~ — Over-engineered for 50 character folders

---

## 5. Image Processing Pipeline

### 5.1 Source Image Characteristics (Active Sources Only)

| Source | Resolution | Background | Framing | Preprocessing Needed |
|---|---|---|---|---|
| Rebrickable renders (existing) | ~200×400px | Cream/white | Tight, centered | Torso crop only |
| BrickLink renders (existing + scale-up) | Variable | White/transparent | Different angle | Convert PNG→RGB, torso crop |
| Kaggle real photos (NEW) | High-res | Variable (tables, floors) | Loose, variable | **Bbox detect → torso crop** |
| iPhone photos (existing) | 4032×3024 | Real-world | Very loose | **Bbox detect → torso crop** |

### 5.2 Processing Strategy by Source

**Renders (BrickLink):**
1. Convert to RGB (handle RGBA PNGs)
2. Apply `torso_crop()` directly
3. No bbox detection needed

**Real Photos (Kaggle, iPhone):**
1. Convert to RGB
2. Apply `detect_figure_bbox()` to locate the minifigure
3. Crop to bbox → apply `torso_crop()`
4. If bbox returns full image (no figure detected), flag for review

**Note:** The existing `ingest_real_photos.py` `augment` command already handles this exact pipeline. No new processing code needed.

### 5.3 Bbox Detection — Known Risk

The current `detect_figure_bbox()` uses corner-sampling for background estimation + L2 threshold. This is the **most likely failure point** on real photos (see Critical Issue §6). Phase 0 validates this before investing in data.

**If crop fails on real photos, possible fixes (in order of complexity):**
1. Tune L2 threshold (currently 50 — may need adjustment for non-uniform backgrounds)
2. Add minimum bbox size check (≥ 15% of image area)
3. Use `rembg` library for background removal as preprocessing
4. Train a lightweight detector (future, only if needed)

### 5.4 Augmentation Strategy

**Decision: Skip augmentation in Phase 1.** Use raw embeddings only. The 350 augmentation-split photos already provide ~350 new real-photo anchor points in the index. Augmentation adds slight variants of the same photos — diminishing returns until we know the raw approach works.

Augmentation (using existing `build_eval_set.py` transforms) can be added in a future iteration if raw embeddings prove insufficient.

### 5.5 Output Format

All processed images must produce:
- 224×224 RGB JPEG
- Torso-cropped (vertical band 30%–70%)
- Padded to square with fill `(244, 244, 244)`
- Normalized with ImageNet mean/std at embedding time

---

## 6. Training & Indexing Strategy

### 6.1 Approach: Index Augmentation (NOT Fine-Tuning)

**Decision: Augment the embedding index, do not fine-tune DINOv2.**

Rationale:
- Fine-tuning DINOv2 requires significant compute and risks catastrophic forgetting
- The model already produces good features — the problem is that the index only contains one view (render) per figure
- Adding real-photo and cross-source embeddings to the index gives the nearest-neighbor search multiple "anchor points" per figure, naturally bridging the domain gap
- This is exactly what `ingest_real_photos.py`'s `augment` command already does

### 6.2 Multi-Source Index Construction (Revised)

**Strategy: Add real-photo embeddings to the existing index.**

Current index: 14,113 entries (1 embedding per figure)

| Source | Entries to Add | Status |
|---|---|---|
| Kaggle ihelon real photos (P0) | ~350 (70% of 498) | **Active** |
| BrickLink renders (P1, scale up) | ~1,800 additional | **Active — zero new code** |
| ~~Kaggle datasciencedonut~~ | ~~~241~~ | **Deferred** — no labels |
| ~~HuggingFace gap-fills~~ | ~~~2,000~~ | **Dropped** — same domain |
| ~~Stable Diffusion~~ | ~~~500~~ | **Dropped** — can't produce specific figures |
| **Total new** | **~2,150** | |
| **Total index** | **~16,250** | |

### 6.3 Weighting Strategy

When a figure has multiple embeddings (render + real photo), nearest-neighbor search naturally returns the closest one. No explicit weighting needed.

However, for figures with real-photo embeddings, we want to ensure the real-photo vector doesn't pull too far from the render vector (which could cause false matches). **Sanity check:** Compute cosine similarity between the render embedding and each real-photo embedding for the same figure. If cosine < 0.3, flag for review (likely a bad mapping or bad crop).

### 6.4 Index Size Impact (Revised)

| Metric | Current | After Phase 1+2 | Delta |
|---|---|---|---|
| Entries | 14,113 | ~16,250 | +15% |
| `.bin` file | 10.8 MB | ~12.4 MB | +1.6 MB |
| JSON index | ~350 KB | ~400 KB | +50 KB |
| **iOS bundle impact** | | | **+1.7 MB** |

Well within the 10 MB budget. No compression or quantization needed.

### 6.5 Evaluation Methodology

**Before/after metrics to track:**

| Eval Set | Metric | Baseline | Target |
|---|---|---|---|
| Synthetic variants (existing) | recall@1 | (current value) | ≥ maintain |
| Synthetic variants (existing) | recall@5 | (current value) | ≥ maintain |
| BrickLink cross-source | recall@1 | (current value) | ≥ maintain |
| Real iPhone photos (27) | recall@1 | **0.040** | **≥ 0.200** |
| Real iPhone photos (27) | recall@5 | (current value) | (track) |
| Kaggle real photos (held-out) | recall@1 | N/A (new) | ≥ 0.150 |
| Kaggle real photos (held-out) | recall@5 | N/A (new) | ≥ 0.350 |

**Eval split for Kaggle real photos:**
- 70% for index augmentation (~350 images)
- 30% for held-out evaluation (~150 images)
- Split stratified by character/theme to avoid information leakage

**Key principle:** The existing eval sets must NOT regress. New data should only improve real-photo recall without hurting synthetic recall.

---

## 7. Pipeline Changes (Scripts & Notebooks)

### 7.1 New Scripts (Revised — Minimal)

| Script | Purpose | Location |
|---|---|---|
| `prepare.py` | Convert Kaggle ihelon folder structure → flat mapping JSON for `ingest_real_photos.py` | `datasets/kaggle_real_photos/` |

That's it. One script, ~50 lines. The existing pipeline handles everything else.

**DROPPED scripts (redundant with existing tools):**
- ~~`download_huggingface.py`~~ — HuggingFace dataset dropped entirely (see Critical Issues §1)
- ~~`download_kaggle.py`~~ — Kaggle CLI one-liner, doesn't need a script
- ~~`map_kaggle_ids.py`~~ — Absorbed into `prepare.py` using existing `score_match()`
- ~~`analyze_overlap.py`~~ — HuggingFace dropped, no overlap analysis needed
- ~~`build_unified_mapping.py`~~ — No unified mapping needed with one data source
- ~~`ingest_external.py`~~ — `ingest_real_photos.py` already does this

### 7.2 Changes to Existing Scripts (Revised — Minimal)

**`ingest_real_photos.py`:**
- **No changes needed.** The `map`, `augment`, and `eval` commands already handle the full pipeline.
- `prepare.py` adapts the Kaggle folder structure into the mapping JSON format that `ingest_real_photos.py` already expects.

**`embed_catalog.py`, `evaluate_retrieval.py`, `build_eval_set.py`, `fetch_bricklink_images.py`:**
- No changes needed.

### 7.3 Notebook Changes (Colab, Revised — Minimal)

Add **one** new cell block to `dinov2_retrieval_prototype.ipynb`:

**New Cell Block: Kaggle Real Photos (after existing BrickLink cells)**
```
## Kaggle Real Photos — Download, Map, Augment Index, Evaluate
```

Cells to add:
1. `pip install kaggle` + download ihelon dataset
2. Run `prepare.py` to generate mapping JSON
3. Run `ingest_real_photos.py augment` with the Kaggle mapping
4. Run `evaluate_retrieval.py` on real-photo eval set
5. Compare before/after metrics

### 7.4 Colab Execution Flow (Revised)

```
1. Setup & Dependencies (existing)
2. Build eval set + embed catalog (existing)
3. Evaluate baseline (existing)
4. BrickLink fetch + eval (existing)
5. ** NEW: Download Kaggle ihelon dataset
6. ** NEW: Run prepare.py → mapping JSON
7. ** NEW: Augment index with real photos
8. ** NEW: Evaluate real-photo recall
9. ** NEW: Compare before/after
10. Save to GitHub (existing)
```

---

## 8. Validation & Testing (Revised — Practical Only)

### 8.1 Mapping Validation

For the ~50 Kaggle character→figure_id mappings:
- Visually inspect 2–3 sample photos per character against the catalog render
- Fix mismatches in `mapping.json` directly (one-time manual task)

### 8.2 Embedding Sanity Checks

For newly-added embeddings:
1. Compute cosine similarity to the catalog render embedding for the same figure ID
2. Expected: cosine > 0.2 for real photos
3. Outliers (cosine < 0.15) → likely bad mapping or failed crop → fix or remove

### 8.3 Regression Testing

Run existing eval suite before and after:

```bash
# Before: baseline on current index
python evaluate_retrieval.py --index index/dinov2_vits14 --eval eval/ --report reports/baseline.json

# After: same evals on augmented index
python evaluate_retrieval.py --index index/dinov2_vits14_augmented --eval eval/ --report reports/augmented.json
```

**Acceptance criteria:**
- Synthetic recall@1: no decrease > 0.02
- Real-photo recall@1: increase from 0.040 (any measurable improvement is progress)

**DROPPED over-engineering:**
- ~~Perceptual hash overlap analysis~~ — HuggingFace dropped
- ~~Visual comparison grids~~ — Manual review is sufficient for 50 mappings
- ~~Cross-source confusion matrix~~ — Nice to have later, not needed for Phase 1
- ~~Unmapped report JSON~~ — Just fix the mapping file directly

---

## 9. Risk & Mitigations

### 9.1 Dataset Quality Issues (Revised)

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Kaggle real photos have poor quality (blurry, partial) | Medium | Bad embeddings pollute index | Quality filter: reject images where bbox < 15% of image area or cropped figure < 50×50px |
| Kaggle photos contain non-minifigure content | Low | False embeddings | Cosine sanity check against catalog render |
| Torso crop fails on real photos (wrong region) | Medium | **High** — more data won't help | Phase 0 crop audit; fix crop logic before adding data |
| BrickLink renders have transparent backgrounds | Known | Torso crop uses wrong fill | Convert RGBA→RGB with white background (already handled) |

### 9.2 ID Mapping Errors (Revised)

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Kaggle fuzzy match assigns wrong figure | Medium | Poisoned embeddings | Manual review of ~50 mappings; cosine sanity check |
| One character folder maps to multiple valid figures | High | Ambiguous ground truth | Accept any variant as correct match |

### 9.3 Index Size Growth (Revised)

| Scenario | Index Size | iOS Bundle Delta |
|---|---|---|
| Current | 10.8 MB | — |
| +350 ihelon real photos | 11.1 MB | +0.3 MB |
| +350 ihelon + 1,800 BrickLink | 12.4 MB | +1.6 MB |

Well under the 20 MB budget. Size is not a concern with the reduced scope.

### 9.4 Colab Compute Time

| Step | Estimated Time (T4 GPU) | Estimated Time (CPU) |
|---|---|---|
| Embed 14K catalog renders | ~15 min | ~3 hours |
| Embed 3K external real photos | ~3 min | ~40 min |
| Embed 2K BrickLink renders | ~2 min | ~25 min |
| Run full eval suite (5 eval sets) | ~5 min | ~1 hour |
| **Total** | **~25 min** | **~5 hours** |

### 9.5 License Compliance (Revised)

| Dataset | License | Commercial Use | Attribution Required |
|---|---|---|---|
| Kaggle ihelon | CC BY 4.0 | ✅ Yes | Credit original author |
| BrickLink renders | Web scraping | ⚠️ Fair use for eval | Do not redistribute |

**Action:** Add license attribution to `datasets/README.md`. Only embeddings (not images) ship in the iOS app.

---

## 10. Implementation Order (Revised — Minimal Viable Path)

### Phase 0: Validate the Crop (Pre-requisite, ~30 min)

**Goal:** Confirm the torso crop actually works on real photos before investing in data.

1. Take our existing 27 real iPhone photos
2. Run `detect_figure_bbox()` → `torso_crop()` on each
3. Save the intermediate crops to a debug folder
4. Visually inspect: Is the torso actually in the crop? Or is it background / legs / head?
5. **If crops are bad:** Fix the crop logic FIRST — more data won't help a broken crop.
6. **If crops are reasonable:** Proceed to Phase 1.

### Phase 1: Kaggle Real Photos (P0 — The Only Thing That Matters)

**Goal:** Get 498 real photos into the existing pipeline and measure improvement.

This uses the **existing `ingest_real_photos.py` pipeline** with ONE modification: a small adapter to convert the Kaggle folder structure to the flat-file + mapping format that `ingest_real_photos.py` already expects.

**Steps:**
1. Download Kaggle ihelon dataset (31 MB): `kaggle datasets download -d ihelon/lego-minifigures-classification -p datasets/kaggle_real_photos/raw/ --unzip`
2. Write a short adapter script (`datasets/kaggle_real_photos/prepare.py`, ~50 lines) that:
   - Walks the theme/character folder structure
   - Generates a mapping JSON in the format `ingest_real_photos.py` expects
   - Uses the existing `score_match()` function for character→figure_id matching
3. Hand-review the mapping JSON (~50 character→figure_id assignments, NOT 498 — all photos in a character folder share one mapping)
4. Split: 70% → augmentation (for index), 30% → held-out eval
5. Run existing pipeline: `ingest_real_photos.py augment` → `evaluate_retrieval.py`
6. **Gate check:** Real-photo recall@1 must improve from 0.040.

**New code needed:** One file, ~50 lines. Everything else uses existing tools.

### Phase 2: BrickLink Scale-Up (P1 — Zero New Code)

**Goal:** Scale BrickLink renders from 199 → ~2,000 using the existing pipeline.

**Steps:**
1. Run existing `fetch_bricklink_images.py` with a higher target count
2. Embed new BrickLink renders using existing `embed_catalog.py` patterns
3. Run eval suite to verify cross-source recall improves
4. Verify no regression on synthetic recall

**New code needed:** Zero. Just run existing scripts.

### Phase 3: Ship to iOS

**Goal:** Export the best-performing index to the app.

1. Select the index with best real-photo recall without synthetic regression
2. Replace `Bricky/Resources/torso_embeddings.bin` + `torso_embeddings_index.json`
3. Test on physical device

**That's it.** No HuggingFace pipeline. No SD generation. No unified mapping infrastructure. No 6 new scripts. The bottleneck is real labeled photos, and we have one good source (ihelon) with an existing pipeline to ingest them.

### Optional Future Work (Only If Phase 1 Results Are Insufficient)

- **Datasciencedonut photos:** Revisit after Phase 1 when we have better embeddings to auto-map the unlabeled photos
- **LDraw multi-angle renders:** If torso crop angle is the problem, render figures from 4–8 angles instead of just one
- **Better object detection:** If torso crop is the bottleneck, look into a lightweight detector (YOLOv8-nano or similar) to replace the heuristic bbox

---

## Appendix: Quick Reference

### Key File Paths

| Purpose | Path |
|---|---|
| Catalog | `Bricky/Resources/MinifigureCatalog.json.gz` |
| Catalog renders | `Bricky/Resources/MinifigImages/fig-NNNNNN.jpg` |
| Embedding scripts | `Tools/dinov2-embeddings/` |
| Current real photos | `images/figurines/` |
| Real photo mapping | `Tools/dinov2-embeddings/real_photos/mapping.json` |
| BrickLink renders | `Tools/dinov2-embeddings/bricklink_images/` |
| BrickLink mapping | `Tools/dinov2-embeddings/bricklink_mapping.json` |
| External datasets (new) | `datasets/` |
| Production index (iOS) | `Bricky/Resources/torso_embeddings.bin` + `torso_embeddings_index.json` |

### Key Functions

| Function | File | Purpose |
|---|---|---|
| `torso_crop(img)` | `embed_catalog.py` | Vertical band 30-70%, 224×224, padded |
| `detect_figure_bbox(img)` | `evaluate_retrieval.py`, `ingest_real_photos.py` | Corner-based background detection |
| `embed_batch(model, batch)` | `embed_catalog.py` | L2-normalized CLS embeddings |
| `load_dinov2(name, device)` | `embed_catalog.py` | Model loader with stub option |
| `score_match(fig, prefix, tokens)` | `ingest_real_photos.py` | Fuzzy name matching |
| `load_or_build_mapping(fig_ids)` | `fetch_bricklink_images.py` | Rebrickable→BrickLink ID scraper |

### Size Budget

| Component | Current | Budget Max |
|---|---|---|
| Embedding index (.bin) | 10.8 MB | 20 MB |
| Index metadata (.json) | ~350 KB | 1 MB |
| Total iOS bundle delta | — | ≤ 10 MB |

---

## 11. External Tools & Architectural Insights

### 11.1 Minifig Finder (minifigfinder.com)

**Architecture:** Uses **Mask R-CNN** for detecting individual minifigure components (head, torso, legs) + **metric learning** for identification. This is the closest existing system to Bricky's approach.

**Key insight:** Their part-detection step (separate head/torso/legs before matching) may outperform our whole-figure bbox approach. If our torso crop continues underperforming on real photos, consider:
1. Training a simple object detector to locate just the torso region (instead of heuristic 30%–70% vertical band)
2. Using separate embeddings for head, torso, and legs with a combined score

**Applicability:** Architectural reference only — no public dataset or model weights available.

### 11.2 Brickognize (brickognize.com)

Existing web app that recognizes any LEGO part, minifigure, or set from a photo. Can serve as a benchmark: photograph the same test minifigures with both Brickognize and Bricky to compare accuracy on identical inputs.

### 11.3 LDraw-Based Rendering Pipeline

Multiple projects (LegoBrickClassification, BrickRenderer, LegoSorter) use **Blender + LDraw** to generate synthetic training data at 224×224 with varied lighting, backgrounds, and rotations. Key parameters from their work:

- **38 official brick colors** for variation
- **Camera on upper hemisphere** for natural viewing angles
- **Indoor backgrounds** (IndoorCVPR09 dataset) or noise for generalization
- **Rotation augmentation:** 0°, 90°, 180°, 270° in X axis

Their shared finding: **significant domain gap between synthetic renders and real photos** (LegoBrickClassification reports "results not satisfactory" when eval'd on real-world test set). This confirms that our 0.040 real-photo recall@1 is a known challenge in the field, not a pipeline bug.

### 11.4 Rendering Minifigures from LDraw

If we can obtain LDraw (.dat) files for assembled minifigures (not just individual parts), we could render torso crops at 224×224 from multiple angles using the Blender pipelines above. This would provide:
- Controlled variation in camera angle (which our single-render catalog doesn't have)
- Background variation (our renders all have the same cream/white background)
- Lighting variation

**Feasibility check needed:** Do assembled minifigure LDraw models exist, or only individual part models? The Rebrickable parts list for each figure could theoretically be assembled programmatically, but this is non-trivial.

---

## 12. Datasets Reviewed & Excluded

The following datasets were identified during research (primarily from the [awesome-lego-machine-learning](https://github.com/360er0/awesome-lego-machine-learning) survey) but **excluded** from the import plan because they focus on individual brick/part classification rather than assembled minifigure identification:

| Dataset | Size | Reason for Exclusion |
|---|---|---|
| Gdańsk/Nature paper (Boiński 2023) | 155K photos + 1.5M renders | 447 individual parts, not minifigures |
| B200C (Kaggle ronanpickell) | 800K renders | 200 parts, not minifigures |
| Joost Hazelzet "Images of LEGO Bricks" | 46K images, 1 GB | Standard brick images |
| Lego Semantic Segmentation (Kaggle hbahruz) | 354 files | Semantic segmentation of bricks |
| Synthetic LEGO Images (Kaggle marwin1665) | 1.5K files, 1 GB | Synthetic brick images |
| LEGO Dataset (Kaggle abhisheksinghblr) | 6K files, 90 MB | Brick dataset |

**Key takeaway from the survey:** The LEGO ML community is heavily focused on **part/brick sorting** (driven by the physical sorting machine use case). **Minifigure identification** is a much smaller niche. Our best external data sources remain the ones in our import pipeline (ihelon, datasciencedonut, BrickLink, HuggingFace Armaggheddon) plus the synthetic generation approach (§2.5).
