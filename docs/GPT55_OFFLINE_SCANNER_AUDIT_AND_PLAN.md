# Bricky Offline Scanner Audit And Recovery Plan

Author: GPT-5.5 via GitHub Copilot
Date: 2026-04-25
Status: Upgraded GPT55 recovery plan for offline live-photo scanner reliability

## Accountability

This document began as the original GPT-5.4 High audit after repository inspection, scanner documentation review, bundled-resource validation, and recent commit review. GPT-5.5 has now taken over ownership, filled the remaining implementation and evaluation gaps, and upgraded the plan quality to GPT55 standards. It is not a restatement of prior Claude notes. Where prior documentation appears speculative, stale, or inconsistent with the shipped code, this document treats executable code, bundled assets, and verified test/evaluation results as the source of truth.

## Executive Summary

The core problem is not that Bricky lacks an offline model. The app already ships an offline CLIP-based retrieval path with a bundled model and a bundled embedding index. The real problem is that the scanner is currently described as fully offline while the runtime behavior is only offline-first:

1. Phase 1.5 uses a bundled CLIP model and bundled CLIP embeddings.
2. Phase 2 can opportunistically fetch missing reference images over the network.
3. Phase 3 can call Brickognize cloud fallback, and that setting defaults to enabled.
4. User-facing help and code comments overstate the offline guarantee.
5. Recent work has changed scoring, image enhancement, cloud UX, and embedding performance quickly, but without first freezing a strict offline contract and benchmark.

The recovery path is to stop treating this as a generic model-training problem and instead make offline behavior explicit, enforceable, measurable, and documented.

## Implementation Status Update

Status date: 2026-04-25

This section records what changed after the original audit above. The validated facts below are preserved as the audit snapshot at the time this plan was written; this status section is the current source of truth for work completed afterward.

### Completed

- Added explicit scanner operating modes: `Strict Offline`, `Offline First`, and `Assisted`.
- Migrated the old cloud fallback toggle into the new mode model. New installs now default to `Offline First`; existing users with cloud fallback enabled migrate to `Assisted`.
- Updated `MinifigureIdentificationService` to enforce mode boundaries:
  - `Strict Offline` uses bundled and user-owned local references only.
  - `Offline First` also allows already cached reference images, but no new reference downloads or Brickognize calls.
  - `Assisted` allows on-demand reference fetches and Brickognize fallback.
- Added scan provenance fields for reference source counts and cloud usage, and surfaced provenance-aware status text in the scan UI.
- Updated Settings and Help copy so the app no longer presents all scanner behavior as fully offline.
- Added `ScanSettingsModeTests` and verified the three mode policies with Xcode.
- Added a CLIP-first image evaluation harness at `Tools/dinov2-embeddings/evaluate_clip_retrieval.py` and tests at `Tools/dinov2-embeddings/test_evaluate_clip_retrieval.py`.
- Ran the shipped CLIP model against populated image suites and wrote reports under `Tools/dinov2-embeddings/reports/`.
- Upgraded the live-photo offline path so identification normalizes the scan image internally and CLIP retrieval merges results across several deterministic camera-photo crop variants. This reduces dependence on one brittle saliency crop and better matches the verified evaluator behavior for newly captured photos without using the network.

### Current CLIP Retrieval Results

These numbers measure Phase 1.5 CLIP retrieval only. They do not yet measure the full scanner pipeline with color cascade, Phase 2 visual reranking, correction reranking, or cloud assistance.

| Suite | Images scored | recall@1 | recall@5 | recall@10 | recall@50 |
| --- | ---: | ---: | ---: | ---: | ---: |
| Real scanned photos | 25 | 0.160 | 0.280 | 0.360 | 0.720 |
| BrickLink eval renders | 198 | 0.646 | 0.934 | 0.970 | 0.995 |
| BrickLink image folder | 198 | 0.652 | 0.934 | 0.975 | 0.995 |
| Hugging Face caption images | 12,379 | 0.848 | 0.965 | 0.982 | 0.997 |

### Current Interpretation

The CLIP local retrieval path is strong on catalog-like and render-domain images, but still weak on real scanned photos. The next quality work should focus on the real-photo domain gap and on measuring Phase 2 reranking separately from CLIP candidate generation.

### Still Open

- Build a verified real-photo benchmark split with ambiguous or uncertain labels separated from trusted labels.
- Add full scanner-pipeline evaluation that compares Phase 1, Phase 1.5 CLIP retrieval, Phase 2 reranking, and final strict-offline results.
- Decide whether DINOv2 fallback still provides measurable incremental value after CLIP and Phase 2 are evaluated independently.
- Reclassify Claude-era research docs into an archive or annotate them clearly as superseded.
- Fix stale references in `docs/README.md`.

## Original Validated Facts At Handoff

The following facts describe the audit snapshot before GPT-5.5 completed the mode enforcement, provenance, evaluator, and live-photo offline retrieval upgrades above.

### Runtime facts

- Bricky ships a bundled CLIP model at `Bricky/Resources/LegoClipVision.mlpackage`.
- Bricky ships a bundled CLIP embedding index at `Bricky/Resources/ClipEmbeddings/clip_embeddings.bin` and `Bricky/Resources/ClipEmbeddings/clip_embeddings_index.json`.
- The CLIP embedding index metadata reports `count: 14175`, `dim: 512`, and model `Armaggheddon/clip-vit-base-patch32_lego-minifigure`.
- `ClipEmbeddingService` marks CLIP available when both the model and the bundled index are available.
- `MinifigureIdentificationService` uses CLIP as the primary Phase 1.5 retrieval path and DINOv2-style embeddings as fallback.
- `ScanSettings.cloudFallbackEnabled` exists and defaults to enabled.
- `MinifigureIdentificationService.refineWithLocalReferenceImages(...)` can fetch missing reference images over the network.

### Documentation and messaging facts

- `MinifigureIdentificationService` still contains a comment claiming: "No network downloads - the app works fully offline."
- `HelpView` tells users: "Offline mode uses on-device AI that works without any internet connection."
- `SettingsView` separately says Brickognize cloud fallback requires internet.
- `Bricky/Resources/MinifigImages/README.md` describes the bundled reference image set as roughly 2000 curated JPEGs, built from a script and consulted before disk cache or network.
- `docs/README.md` points to missing files, so the docs index is stale.

### What this means

The app ships real offline intelligence, but the shipped product contract is ambiguous. In practice, the user can be in one of three materially different states:

1. Strict local-only inference.
2. Local inference plus cached or opportunistically fetched reference images.
3. Local inference plus Brickognize cloud assistance.

Those modes are currently blurred together in code comments, settings language, and help content.

## Last 24 Hours Of Scanner Churn

Recent scanner-related commits show rapid changes across multiple layers of the pipeline:

- `825f8c6a`: refined candidate scoring and image enhancement workflow.
- `2c781737`: adjusted enhanced badge positioning and touched CLIP embedding index code.
- `0c53b3d5`: changed color discrimination in identification.
- `2107f149`: optimized embedding calculations using Accelerate across CLIP, face, torso, and identification code.
- `2fe0e736`: added cloud check messaging and camera-handling changes during identification.
- `d3581bc0`: added cloud validation banner and also updated scanner lessons documentation.
- `131934fe`: added debug logging to identification and scan history.
- `a8eeb207`: introduced bundled CLIP embeddings and CLIP retrieval into the pipeline.
- `c3ef9376`: updated the shipped CLIP model assets and related identification code.

This is useful context because it shows the scanner is still in a high-churn state. That is exactly when the team needs a frozen offline contract and benchmark, not more speculative training branches.

## Claude-Generated And Claude-Era Documents

### Positively identifiable as Claude-generated

- `docs/MINIFIGURE_SCANNER_LESSONS.md`
  - This file explicitly identifies itself as `Claude Opus 4.7 research notes`.

### Claude-era scanner documents that should not be treated as current source of truth without validation

- `docs/DATASET_IMPORT_PLAN.md`
- `docs/DEVLOG.md`
- `docs/MINIFIGURE_ANATOMY.md`
- `docs/README.md`

I cannot prove from repository metadata alone that each of those files was authored by Claude. What I can state confidently is that they belong to the same scanner experimentation phase and contain claims or assumptions that are now partly stale relative to the codebase.

## Flaws In The Prior Approach

### 1. The workstream optimized around training ideas before defining the shipped offline contract

The repo already ships a CLIP-based offline retrieval system. The highest-value question was not "how do we train more embeddings?" but "what exactly is allowed to happen when the user expects offline behavior?" That contract was never locked down first.

### 2. The approach over-indexed on DINOv2 and dataset import planning while the runtime path moved to CLIP

The documentation and planning spend a lot of energy on DINOv2 imports, torso embeddings, and model conversion. Meanwhile, the shipped scanner now depends heavily on CLIP retrieval with a 14,175-item bundled index. That is a mismatch between planning effort and actual runtime architecture.

### 3. Reference images and embedding retrieval were treated as one problem

They are different:

- The bundled CLIP index supports broad retrieval across a large figure set.
- The bundled reference image set is much smaller and is used later for reranking and visual refinement.

Trying to solve offline identification primarily by expanding ad hoc reference-image behavior is weaker than improving the canonical local retrieval path and evaluation loop.

### 4. Offline claims were allowed to drift away from the code

The current product copy says "works without any internet connection," but the code still permits opportunistic fetches and cloud fallback. That mismatch creates false negatives in debugging because the team cannot tell whether a result is genuinely offline, cached, or cloud-assisted.

### 5. Too much behavior changed before an offline benchmark was frozen

Scoring weights, image enhancement order, CLIP integration, cloud UX, and debug logging all changed in a short window. Without a locked offline benchmark set and evaluation matrix, it becomes difficult to tell whether a change improved local-only accuracy or just changed assisted behavior.

### 6. Historical notes, research notes, and current architecture were mixed together

The docs currently mix:

- design intuition,
- experimental training plans,
- devlog notes,
- and product-level claims.

That makes it easy to optimize the wrong layer because the documentation hierarchy is unclear.

## Correct Approach

### 1. Define explicit operating modes

Bricky needs three explicit, testable modes:

1. `Strict Offline`: no network calls, no opportunistic reference fetches, no Brickognize.
2. `Offline First`: local inference allowed, cached assets allowed, but no new network fetches during a scan.
3. `Assisted`: local inference plus Brickognize fallback and any allowed online asset fetches.

The UI, settings, help text, logs, and tests should all use the same mode names.

### 2. Treat CLIP as the canonical local retrieval engine unless evidence proves otherwise

Right now CLIP is the actual shipped local retrieval backbone. That means:

- CLIP should be the primary benchmarked local model.
- DINOv2 fallback should be retained only if it provides measurable incremental value.
- If DINOv2 does not materially improve strict-offline accuracy or robustness, it should be demoted further or removed from the critical path.

### 3. Stop using broad dataset expansion as a proxy for product correctness

The next dataset should not be "more data because more data might help." It should be a failure-driven benchmark built from real scanner misses:

- same-torso wrong-color confusion,
- low-light captures,
- partial occlusion,
- tilted scans,
- similar prints across variants,
- cloud-only recoveries that local mode missed.

That benchmark should be labeled by operating mode and expected top-k behavior.

### 4. Make network boundaries enforceable in code

For strict offline mode:

- disable Brickognize fallback entirely,
- disable Phase 2 opportunistic fetches,
- emit debug metadata showing `local_only = true`,
- fail fast if a network-dependent branch is entered.

This removes ambiguity from debugging and from user reports.

### 5. Separate retrieval quality from reranking quality

Evaluation should report at least:

- Phase 1 top-k recall,
- Phase 1.5 CLIP top-k recall,
- Phase 2 reranked top-1 accuracy,
- strict-offline vs assisted deltas,
- confidence calibration,
- cloud rescue rate.

That will show whether the problem is candidate generation, reranking, or fallback policy.

### 6. Rebuild the documentation hierarchy

Create and maintain four clearly separated doc types:

1. `Architecture`: current runtime truth.
2. `Operations`: what each user-visible mode means.
3. `Evaluation`: benchmark definitions and current results.
4. `Research Archive`: old experiments, model notes, failed ideas.

Claude-era notes should move to archive status unless reaffirmed by current code and tests.

## Recovery Plan

### Phase 0: Freeze truth

Goal: make the current scanner explainable before changing behavior again.

- Document the exact current pipeline and operating modes.
- Add debug annotations that record whether a result used local-only, cached assets, opportunistic fetch, or Brickognize.
- Correct all user-facing and developer-facing offline claims that are false today.

Exit criteria:

- every scan result can be classified by operating mode,
- docs no longer claim "fully offline" unless that path is actually enforced,
- no unresolved ambiguity about whether the result was cloud-assisted.

### Phase 1: Ship a real strict offline mode

Goal: produce one mode that is honestly and completely offline.

- Add a strict local-only mode flag.
- Disable opportunistic fetches in that mode.
- Force Brickognize off in that mode.
- Add tests that fail if the strict mode enters any network-capable path.

Exit criteria:

- strict offline runs with no network dependencies,
- UI and help text accurately describe the difference between strict offline and assisted modes,
- regression tests cover the network boundary.

### Phase 2: Improve local quality using failure-driven evaluation

Goal: improve the local path using measured scanner failures, not broad speculation.

- Build a labeled failure corpus from recent misses and user corrections.
- Benchmark CLIP retrieval separately from Phase 2 reranking.
- Reassess whether DINOv2 fallback is still buying meaningful accuracy.
- Expand bundled reference assets only where they improve measured Phase 2 reranking.

Exit criteria:

- measurable improvement on strict-offline top-1 and top-k metrics,
- a clear decision on whether DINOv2 stays in the critical path,
- asset growth tied to benchmark wins.

### Phase 3: Reduce churn and protect gains

Goal: stop re-breaking the scanner with unmeasured pipeline edits.

- Add a stable offline benchmark suite.
- Gate scanner changes on benchmark deltas.
- Separate UI-only changes from pipeline changes in review.
- Move historical research docs into an archive section so active docs stay trustworthy.

Exit criteria:

- offline regressions are caught before merge,
- docs reflect current behavior,
- scanner tuning is benchmark-driven instead of guess-driven.

## Recommended Immediate Next Steps

1. Build a compact strict-offline benchmark set from recent known misses and live phone captures before making further model or scoring changes.
2. Add full scanner-pipeline evaluation that reports Phase 1 color recall, Phase 1.5 CLIP recall, Phase 2 reranked top-1, and final strict-offline results separately.
3. Run the new multi-crop live-photo CLIP path against the real-photo benchmark and compare it against the single-crop baseline.
4. Decide whether DINOv2 fallback still provides measurable value after CLIP and Phase 2 are evaluated independently.
5. Reclassify `docs/MINIFIGURE_SCANNER_LESSONS.md` and related experiment docs as research/archive material unless reaffirmed.

## Final Position

Bricky does not need a vague "better offline model strategy" first. It needs an honest offline contract, a frozen local benchmark, and a CLIP-centered evaluation loop grounded in the code that already ships. Once that foundation is in place, model and asset decisions can be made with evidence instead of churn.
