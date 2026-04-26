# Scanner Accuracy DEVLOG

<!-- markdownlint-disable MD022 MD032 MD036 MD040 -->

> **Goal:** Near 100% minifigure identification accuracy under every major condition.
> **Baseline:** Real-photo recall@1 = 0.040 (4%). Synthetic recall@1 = 0.239.

---

## 2026-04-26 Failure Handoff

The most recent scanner rescue work did not solve the actual live-photo
accuracy problem. The code builds and the focused scanner tests pass,
but the user continued to see bad real scans and explicitly reported
that the changes made the scanner worse. Treat the latest scanner
changes as an unvalidated experiment, not as a completed fix.

### What Was Attempted

| Area | Change | Outcome |
| --- | --- | --- |
| Default scanner core | Added a new CLIP + foreground color evidence path in `MinifigureIdentificationService.identifyWithEvidenceCore(...)`; legacy path remains behind `Bricky.UseLegacyMinifigureScannerCore`. | Did not produce acceptable live-photo results. |
| CLIP index | Rebuilt `Bricky/Resources/ClipEmbeddings/` from catalog renders, HuggingFace gap-fill images, and a small reviewed real-photo set. | Helped tiny local eval metrics but did not validate newly taken live photos. |
| Visual refinement | Reattached `refineWithLocalReferenceImages(...)` after the replacement core skipped it. | Corrected an implementation omission, but user still reported failed scans. |
| Candidate pool | Increased CLIP/candidate pool size so refinement could see more candidates. | More candidates did not solve ranking correctness. |
| Color gating | Added a dominant primary-color gate after green subjects returned red-heavy results. | A reactive rule that passed synthetic tests; not proven in live use. |
| Tests | Added synthetic evidence-core tests, including a green-dominant regression. | Tests verify the patched ranking rules, not real-world scanner accuracy. |
| Image enhancement/UI | Made straightening conservative, showed enhanced image before identification, refreshed scan history immediately. | Useful UX changes, but separate from recognition accuracy. |

### Current Assessment

- Do not assume the scanner is fixed because `xcodebuild` and the
  focused scanner tests passed.
- Do not assume the latest dominant-color gate is the right architecture.
  It was added because the scanner produced obviously wrong colors, but
  it is still another rule layered onto an unvalidated pipeline.
- Do not keep tuning confidence numbers, thresholds, and color-family
  exceptions without a real live-photo dataset.
- The code in `MinifigureIdentificationService.swift` is now carrying a
  large amount of patch logic around the underlying problem: the app
  still lacks a reliable, measured end-to-end path for newly captured
  photos.

### Recommended Next Step

Stop patching the ranker first. Build a ground-truth harness from actual
failed live scans, run the exact app pipeline against it, and measure
recall@1 and recall@5. Only then decide whether to keep any of the CLIP
evidence core, restore the legacy cascade, or rewrite around proper
segmentation and torso-first retrieval.

---

## Pipeline Architecture (as-is, post Session 2)

```
Camera Frame
  │
  ├─ Phase 1: Fast Color Cascade (~1s, on-device)
  │    ├─ Saliency crop → bestSubjectCrop()
  │    ├─ Vertical band extraction (head 0-30%, torso 30-70%, legs 65-100%)
  │    ├─ Dominant color extraction (24×24 downsample, k-means buckets)
  │    ├─ Generic yellow head detection (distance < 90 from #F2CD37)
  │    ├─ Torso pattern analysis (printPixelRatio, bandColors)
  │    ├─ Scoring: two modes —
  │    │    Standard: torso(0.72) + head(0.10) + hair(0.10) + legs(0.04)
  │    │    Adaptive (common torso colors): torso(0.40) + head(0.22) + hair(0.22) + legs(0.10)
  │    ├─ Cascade mode when torso >= 0.80 AND (patterned OR rare color)
  │    ├─ Candidate gate: composite > 0 AND torso > 0
  │    └─ Adaptive pool: cascade=60, lowQuality=100, joint=150
  │
  ├─ Phase 1.5: *** DISABLED *** (models are untrained)
  │    ├─ TorsoEncoder.mlmodel = vanilla ImageNet ResNet18 (no LEGO training)
  │    ├─ FaceEncoder.mlmodel = identical backbone with different label
  │    └─ Passthrough: mergedFastResults = fastResults
  │
  ├─ Phase 2: Visual Refinement (~6s cap)
  │    ├─ VNFeaturePrintObservation on full figure + torso band
  │    ├─ TorsoVisualSignature (quadrant + vertical-slice + edge-grid)
  │    ├─ Three-signal blend: 0.40 * torso_print + 0.35 * sig(×1.5) + 0.25 * full
  │    ├─ On-demand reference fetch (up to 24, diversity-aware, 4s timeout)
  │    │    └─ maxPerTheme = max(4, 24/4) = 6, backfills remaining budget
  │    └─ Returns top 6-8 by blended distance
  │
  └─ Post: UserCorrectionReranker
       ├─ Feature-print matching against past corrections
       ├─ Injection DISABLED (over-fired on unrelated scans)
       └─ Boost-only for figures already in candidate list
```

---

## Root Cause Analysis

### Why real-photo recall@1 = 4%

1. **Domain gap in embeddings.** The DINOv2 index was built from white-background renders. Real photos have varied backgrounds, lighting, shadows, partial occlusion. The torso crop at 30-70% of a real photo may include table/hand/background that doesn't exist in renders.

2. **TorsoEncoder.mlmodelc likely not bundled.** The `TorsoEmbeddingService` gracefully falls back to `[]` when the CoreML model isn't in the bundle. If Phase 1.5 is a no-op, the pipeline relies entirely on color cascade + Vision feature prints — neither of which was designed for cross-domain matching.

3. **Color cascade is coarse.** Phase 1 maps captured colors to the nearest LEGO color from a fixed palette, then matches against catalog `torso.color` which is just the base plastic color. Hundreds of figures share "Black" torso. Without print evidence, cascade mode doesn't activate, and scoring degrades to joint inference with a 0.55 confidence ceiling.

4. **Vision VNFeaturePrint is a generic embedding.** It's trained on natural photos, not LEGO-specific. On minifigure crops it clusters tightly — unrelated figures land at distances 6-10 from each other. The distance scale makes it unreliable as a fine-grained discriminator.

5. **Reference image availability.** Phase 2 can only visually compare candidates whose reference images are locally cached (~3K bundled). For the other ~13K figures, it falls back to color-only.

6. **Single embedding per figure in the index.** Each figure has one vector from one render angle. Real photos vary in pose, lighting, crop. One vector can't capture this variance.

---

## Milestone Plan

### M0: Diagnostic Tooling ✅ (Session 1)
**Goal:** Understand exactly where the pipeline fails on real inputs.
- [x] Add structured diagnostic logging to `identify()`
- [x] Create `ScannerPipelineTests.swift` with 49 tests — all passing
- [x] Verify TorsoEncoder.mlmodelc bundling (runtime compilation fallback added)

### M1: Test Coverage for Core Pipeline ✅ (Sessions 1-2)
**Goal:** Catch regressions before they ship.
- [x] Test `fastColorBasedCandidates()` with known-color images
- [x] Test cascade vs joint-inference scoring paths
- [x] Test confidence calibration (boundary continuity verified)
- [x] Test Phase 2 blending (all signal combinations)
- [x] Test adaptive scoring for common colors
- [x] Test candidate gate (torso > 0 required)
- [x] Test color enum coverage (all 20 catalog colors + alias "Trans Red")
- [x] **57 ScannerPipelineTests, 650 total tests — all green**

### M2: Improve Phase 1 Color Cascade ✅ (Session 2)
**Goal:** Get the correct figure into the top-60+ candidate pool more reliably.
- [x] Adaptive scoring for common torso colors (Black=2404, White=2808 figures)
  - Standard weights: torso 0.72 / head 0.10 / hair 0.10 / legs 0.04
  - Adaptive weights: torso 0.40 / head 0.22 / hair 0.22 / legs 0.10
  - Activates for 11 common colors (>300 figures each)
- [x] Tighten candidate gate: `composite > 0 AND torso > 0`
- [x] Adaptive candidate pool size: cascade=60, lowQuality=100, joint=150
- [x] Fix "Transparent Red" enum rawValue (was "Trans Red", catalog uses "Transparent Red")
- [x] Add `LegoColor(fromString:)` initializer for alias support across both catalogs

### M3: Strengthen Phase 1.5 Embeddings — BLOCKED (models untrained)
**Goal:** Make embedding retriever the primary discriminator.
- [x] **CRITICAL FINDING: Both CoreML models are untrained ImageNet ResNet18 backbones**
  - TorsoEncoder.mlmodel (42.6 MB) and FaceEncoder.mlmodel (42.6 MB) are identical weights
  - Only difference: description string "torso-band" vs "face-region" (1-byte shift)
  - No training evidence: no checkpoints, no data directory, no training logs
  - Colab notebooks `Bricky-evaluate-dinov2.ipynb` / `dinov2_retrieval_prototype.ipynb` were never executed
  - **Phase 1.5 DISABLED** — passthrough until real models are trained
- [ ] Train actual DINOv2-based models (requires labeled dataset)
- [ ] Multi-vector support per figure (render + augmented variants)

### M4: Improve Phase 2 Visual Refinement ✅ (Session 2)
**Goal:** Better re-ranking when reference images are available.
- [x] Fix sigDist scale mismatch: TorsoVisualSignature RMSE ~0-1 vs VNFeaturePrint ~0-2+
  - Added 1.5x scaling to signature distances
  - Adjusted weights: 0.40 torso / 0.35 sig(scaled) / 0.25 full (was 0.45/0.30/0.25)
- [x] Fix confidence calibration: `0.66` → `2.0/3.0` for exact continuity at boundaries
- [x] Increase fetch budget: 16 → 24 with diversity-aware theme distribution
  - maxPerTheme = max(4, budget/4) = 6, backfills remaining budget
- [ ] Expand bundled reference image set from ~3K to ~5K
- [ ] Add face-region comparison as a Phase 2 signal

### M5: End-to-End Evaluation
**Goal:** Measure real-photo recall@1 systematically.
- [ ] Port Python eval pipeline to run against iOS pipeline output
- [ ] Create a ground-truth test set of 50+ labeled real photos
- [ ] Track recall@1, recall@5, mean reciprocal rank per milestone

---

## Session Log

### Session 1 — Pipeline Audit (current)

**Files read:**
- `MinifigureIdentificationService.swift` (1535 lines) — Full pipeline
- `TorsoEmbeddingService.swift` — CoreML encoder runtime
- `TorsoEmbeddingIndex.swift` — Cosine-NN over Float16 matrix
- `FaceEmbeddingService.swift` / `FaceEmbeddingIndex.swift` — Face embedding
- `HybridFigureAnalyzer.swift` — Hybrid figure detection
- `UserCorrectionReranker.swift` — Past-correction boosting
- `ContinuousScanCoordinator.swift` — Scan lifecycle
- `MinifigurePartClassifier.swift` — Part slot classification
- `TorsoVisualSignature.swift` — Structural torso descriptor
- `VisionUtilities.swift` — Shared Vision helpers
- Python: `embed_catalog.py`, `evaluate_retrieval.py`, `ingest_real_photos.py`

**Key findings:**
1. Core identification pipeline has **ZERO test coverage**. Only `fuzzyScore()` (4 tests) and `MinifigurePartClassifier.slot()` (13 tests) are tested.
2. `TorsoEmbeddingService.isAvailable` requires both `TorsoEncoder.mlmodelc` AND the embedding index. If either is missing, Phase 1.5 is silently disabled.
3. Phase 2 downloads reference images on-demand (up to 8, 4s timeout) — network dependency in the identification path.
4. `UserCorrectionReranker` injection is DISABLED due to over-firing. Only boost-only mode works.
5. Python `detect_figure_bbox()` is duplicated in two files with identical code.
6. Torso crop coordinates match between Python (30-70%) and Swift code.
7. `TorsoVisualSignature` is a smart addition — spatial color layout + edge density without ML.

**Actions taken:**
- Created `ScannerPipelineTests.swift` — 49 tests covering color mapping, embedding index, Vision, torso signatures, scoring, confidence calibration, cascade vs joint inference
- Added runtime .mlmodel→.mlmodelc compilation fallback to TorsoEmbeddingService and FaceEmbeddingService
- Added diagnostic logging throughout identify()

---

### Session 2 — Skeptical Audit + Scoring Fixes

**Critical Discovery: Both CoreML Models Are Untrained**

Performed a skeptical audit of all ML artifacts. Key evidence:
- `TorsoEncoder.mlmodel` (42,646,556 bytes) and `FaceEncoder.mlmodel` (42,646,557 bytes) — 1-byte size difference
- Both contain identical ResNet18 ImageNet backbone weights
- Only difference is the description string: "torso-band" vs "face-region" (1 byte longer)
- Byte-for-byte comparison after header alignment: zero meaningful differences
- No training artifacts exist anywhere: no checkpoints, no training data, no loss curves
- Colab notebooks never executed (no cell outputs)
- **Conclusion: These models have never been fine-tuned on LEGO data**

**Catalog Color Analysis:**

Analyzed all 15,789 figures in `MinifigureCatalog.json.gz`:
- Exactly 20 unique color strings (19 in LegoColor enum + "Transparent Red" mismatch)
- Torso color distribution (top 5): White=2,808 | Black=2,404 | Red=1,334 | Blue=905 | Dark Blue=726
- 11 colors have >300 figures (common) — joint inference cannot discriminate between them using torso alone

**Changes Made (7 fixes + 1 safety fix):**

| # | File | Change | Rationale |
| --- | --- | --- | --- |
| 1 | MinifigureIdentificationService.swift | Disabled Phase 1.5 (passthrough) | Models are untrained — embedding noise hurts accuracy |
| 2 | MinifigureIdentificationService.swift | Adaptive candidate pool (60/100/150) | Larger pool for harder cases (low quality, joint inference) |
| 3 | MinifigureIdentificationService.swift | sigDist ×1.5 scaling, weights 0.40/0.35/0.25 | Signature RMSE ~0-1 was underweighted vs VNFeaturePrint ~0-2+ |
| 4 | MinifigureIdentificationService.swift | Confidence calibration: 0.66 → 2.0/3.0 | Eliminates ~0.002 discontinuities at d=0.7 and d=1.0 boundaries |
| 5 | MinifigureIdentificationService.swift | Fetch budget 16→24 with theme diversity | More visual comparisons, spread across themes not concentrated |
| 6 | MinifigureIdentificationService.swift | Adaptive scoring for common torso colors | Boosts head/hair/legs weights when torso matches 2000+ figures |
| 7 | MinifigureIdentificationService.swift | Candidate gate: require torso > 0 | Filters out figures with no torso match (zero-information candidates) |
| 8 | LegoPiece.swift | transparentRed rawValue "Trans Red" → "Transparent Red" | Matches minifigure catalog; added fromString alias for parts catalog |

**Additional safety fix:**
- Added `LegoColor(fromString:)` initializer with alias support
- Updated all 10 call sites across 5 files to use `fromString` instead of `rawValue`
- Both catalogs (minifigure: "Transparent Red", parts: "Trans Red") now parse correctly

**Test Results:**
- ScannerPipelineTests: 57 tests (up from 49), 0 failures
- Full suite: 650 tests, 0 failures

---

## Session 3: Cloud Fallback Integration & Dataset Research

### Key Discovery: Brickognize API

Researched public LEGO recognition datasets and models. Found:
- **ihelon dataset** (Hugging Face): 498 real photos of 28 unique figures across 4 themes. Too small for training but useful as eval set.
- **Brickognize API** (`api.brickognize.com`): Free public LEGO recognition service. `POST /predict/figs/` accepts multipart `query_image`, returns BrickLink IDs + names + confidence scores + bounding boxes. No auth required, ~1 req/sec rate limit.

**Validation results** (4/4 correct on rendered catalog images):
- sw0001 "Battle Droid" → correctly identified
- sh0001 "Batman" → correctly identified  
- cty0001 "Police Officer" → correctly identified
- hp0001 "Harry Potter" → correctly identified

**Strategic decision:** Use Brickognize as Phase 3 cloud fallback rather than building our own model. It already returns BrickLink IDs (eliminating the need for BrickLink mapping scrapers) and bridges the render-vs-photo domain gap.

### Pipeline Update: Phase 3 Cloud Fallback

```
  ├─ Phase 3: Cloud Fallback (NEW)
  │    ├─ Triggers when top Phase 2 confidence < 0.65
  │    ├─ Sends torso crop to Brickognize API (3s timeout)
  │    ├─ Name-similarity matching (Jaccard + theme bonus) maps
  │    │    BrickLink IDs → catalog Minifigure objects
  │    ├─ Merge strategy:
  │    │    ├─ Existing candidate boost: confidence += cloudScore × 0.3
  │    │    └─ New injection: requires cloudScore > 0.5 AND matchConfidence > 0.3
  │    │         confidence = cloudScore × matchConfidence × 0.8
  │    └─ Rate limited (1 req/sec), JPEG capped at 500KB
```

### New Files

| File | Lines | Purpose |
| --- | --- | --- |
| BrickognizeService.swift | ~240 | Actor-based cloud service: API call, response parsing, name matching |
| BrickognizeServiceTests.swift | ~310 | 27 tests: response parsing, tokenization, matching, thresholds, merging |
| Tools/brickognize_validate.py | ~220 | Validation: sample/map/eval-photos commands |
| Tools/enrich_catalog.py | ~200 | Catalog gap analysis: analyze/fill-images/report commands |

### Catalog Enrichment

Downloaded Rebrickable CSVs (minifigs.csv.gz, inventory_minifigs.csv.gz):
- 885 figures exist only in Rebrickable (not in our catalog) — mostly very old or obscure
- 1,678 figures missing images → downloaded 64, 1,614 are 404s on Rebrickable CDN (unrendered)
- Catalog coverage: 14,177 / 15,789 = ~90% have local images

### Code Changes

| # | File | Change |
| --- | --- | --- |
| 1 | Bricky/Services/BrickognizeService.swift | NEW: Cloud minifigure recognition service |
| 2 | MinifigureIdentificationService.swift | Added `cloudFallbackIfNeeded()` between Phase 2 and reranker |
| 3 | UserDefaultsKey.swift | Added `ScanSettings.cloudFallbackEnabled` key |
| 4 | ScanSettings.swift | Added `cloudFallbackEnabled` published property (default: true) |

### Test Results

- BrickognizeServiceTests: 27 tests, 0 failures
- ScannerPipelineTests: 57 tests, 0 failures
- Full suite: 677+ tests, 0 failures
