# Scanner Engineering Lessons (Claude Opus 4.7 research notes)

External research on minifigure identification systems (BrickScan,
Brickset Minifig Finder, Rebrickable / BrickLink catalog structure)
converges on a set of engineering patterns this app should follow.
This document records the source material verbatim plus the concrete
code adjustments we've made (or should make) in response.

The companion document [MINIFIGURE_ANATOMY.md](MINIFIGURE_ANATOMY.md)
covers the *design-intent* reasoning behind why each part carries the
amount of identity information it does. This document is the
*engineering* counterpart.

---

## 1. Discriminative power per part — research breakdown

### Torso — by far the strongest single signal

The torso is the highest-information surface and the one LEGO varies
most aggressively. BrickLink's *Torso Assembly Decorated* category
contains tens of thousands of distinct prints — the single largest
minifigure part category by a wide margin. Rebrickable's inventorying
standard indexes torsos by **arm and hand color combinations** on top
of the print, multiplying the variant count further. BrickScan's
identification flow is literally "scan the torso, then locate the
corresponding head, hair, legs, and accessory that came with it" — the
torso is treated as the **anchor**.

**For our scanner:**
- Torso is the **primary classifier** — effectively the figure's primary key. The pipeline runs torso identification first, then uses other parts only as a consistency check (see §3).
- The **front of the torso** is where almost all of the signal lives.
- Back printing exists on ~30–40% of modern torsos and is worth
  capturing as a secondary feature, but don't make the pipeline depend
  on it.

### Head (face print) — strong for licensed, weak for generics

Head prints are high-variance in utility:
- For **licensed IP** (specific Star Wars, Harry Potter, Marvel
  characters), the face is often unique to that one character and can
  single-handedly identify them.
- For **generic City/Castle figures**, LEGO reuses a small pool of
  stock expressions across hundreds of unrelated torsos — the same
  "smirk with stubble" head shows up on a pirate, a mechanic, and a
  cowboy.

Rebrickable distinguishes **dual-sided heads** as a separate tagged
category, with both faces described in the part name, so the scanner
needs to handle the fact that the same physical head has two valid
prints depending on rotation.

**For our scanner:**
- Treat the head as a strong **disambiguator** given a torso
  hypothesis, rather than a primary classifier.
- Head + torso together is near-deterministic for most figures.
- A **non-yellow head color** is a meaningful signal (likely licensed
  character) — match it strongly when present.
- Generic yellow heads contribute zero identity signal.

### Hair / headgear — strong silhouette, moderate identity

Headgear is the most useful feature for **coarse-grained** classification
(knight? pirate? businessperson?) because silhouette dominates the
signal and is robust to lighting, angle, and low resolution.

But it's a weaker **fine-grained** identifier because LEGO aggressively
reuses hair molds — the same "tousled side-part" hair piece ships with
dozens of unrelated figures in different colors. **Color of the hair
piece adds meaningful entropy**; the same mold in black vs. dark brown
vs. red often indicates different characters.

**For our scanner:**
- Treat hair as two separate features: **mold ID (silhouette/shape)
  and color**.
- Mold is mid-tier discriminative; mold + color together is stronger.
- Headgear that's **character-specific** (a stormtrooper helmet, a
  specific wizard hat) jumps up to near-torso-level discriminative
  power because those molds aren't reused.

### Legs — low signal on average, occasional spikes

Most legs are solid-color unprinted pieces from a small palette
(black, blue, brown, dark tan), so they add little information.
When legs **are** printed or dual-molded (boots, armor, a tuxedo),
they jump sharply in discriminative power because printed legs are
relatively rare and usually character-specific.

Rebrickable has separate part codes for plain matching legs,
dual-colored legs, and multi-color injected "boots pattern" legs —
those latter two categories are where the signal is.

**For our scanner:**
- Run a quick **"printed vs. plain"** classifier first.
- Plain legs → downweight the leg feature heavily.
- Printed / dual-molded → upweight to roughly torso-tier.

### Accessories — contextual, not identifying

Accessories are highly reusable and frequently missing, swapped, or
lost when figures are resold. A lightsaber tells you "Jedi or Sith"
but not which one. Capes and neck-bracket accessories are slightly more
discriminative but still secondary.

**For our scanner:**
- Use accessories as a **weak prior**, not a classifier input.
- Gracefully handle missing accessories since loose minifigures in the
  wild are often incomplete.

---

## 2. Feature weighting (fallback / debug only)

The scanner is **not** a flat weighted ensemble — see §3 for the
torso-first cascade. These priors only apply when the cascade falls back
to joint inference (low torso confidence) or for scoring-debug views.

| Feature | Weight | Notes |
| --- | --- | --- |
| Torso (front print + arm/hand colors) | **0.70–0.75** | Primary classifier — effectively the figure's primary key |
| Head (face print, dual-side aware) | **0.10** | Tiebreaker / confidence boost (esp. licensed) |
| Hair / headgear (mold + color) | **0.10** | Silhouette verification + color |
| Legs (conditional: printed vs. plain) | **0.03–0.05** | Only meaningful when printed/dual-molded |
| Accessories | **0.02** | Context only; often missing |

Why so heavily torso-skewed: torsos are nearly in 1:1 correspondence with
figures (LEGO uses the torso slot to guarantee figure uniqueness), so
given the torso the marginal information from other parts is small. See
[MINIFIGURE_ANATOMY.md](MINIFIGURE_ANATOMY.md) for the design-intent
rationale.

---

## 3. Architectural pattern: torso-first cascade (NOT weighted ensemble)

This is the core architectural decision. The pipeline is a **cascade**,
not an ensemble of independent per-part votes:

1. **Torso classifier runs first** and returns a ranked list of
   candidate figures. Because the torso is effectively the figure's
   primary key, this collapses the hypothesis space to basically one
   figure when the torso read is clean.
2. **Other parts act as a consistency check** against each candidate —
   *"does the observed head/hair/legs match what this figure shipped
   with?"* — which **reranks or filters** the candidate list rather
   than contributing independent votes.
3. **Confidence is gated on torso classification quality.** If the
   torso classifier is confident, we're basically done; the other
   parts only confirm/reject. If torso confidence is low (occluded,
   faded, worn, ambiguous), the pipeline falls back to joint inference
   using the weighted priors in §2.

This matches what BrickScan does and what the Minifig Finder research
did. Implementation steps:

1. Segment the figure into canonical parts (head / torso / legs /
   headgear) with something like Mask R-CNN.
2. Run the torso classifier first → ranked candidate list.
3. For each candidate, consult a part-to-figure lookup table —
   *"does this exact torso + head + hair combination correspond to a
   released figure?"* — and rerank.

BrickLink and Rebrickable both expose which parts shipped with which
figures, which is directly usable as both a consistency-check source
and a training-label source.

### Training data implication

Because the torso carries ~70–75% of the identification signal, training
data collection should be **torso-heavy**. Clean, varied torso images —
different lighting, angles, wear levels, partial occlusion from hair or
accessories hanging down — will move accuracy more than anything else
we can do on the other parts.

---

## 4. Gotchas worth designing for

- **Dual-sided heads.** Same head ID has two valid faces. The head
  classifier needs to either recognize both sides as the same part, or
  capture rotation state.
- **Custom/third-party figures.** Custom prints exist for many
  characters; official employee/promotional figures exist outside the
  main catalog. The scanner needs an **"unknown/custom" bucket**.
- **Fading and wear.** Torso prints fade, especially on older figures.
  Train on worn examples or expose print-robustness as a known
  failure mode.
- **Reassembled figures.** Loose minifigures on the secondary market
  are frequently reassembled with mismatched parts. The combination
  consistency check should **score figures, not reject non-matches** —
  show the user the top-k hypotheses. (We already return top 8.)
- **Minidolls vs. minifigures.** Friends/Disney Princess minidolls are
  a different form factor entirely and need separate handling if in
  scope.

---

## 5. Lessons applied in code

| Lesson | Where it lives |
| --- | --- |
| Torso-first cascade (primary classifier → conditional rerank) | [Bricky/Services/MinifigureIdentificationService.swift](../Bricky/Services/MinifigureIdentificationService.swift) → `identify(...)` |
| Confidence-gated fallback to joint inference | same file → torso confidence gate |
| Patterned-torso recognition (additional unique-print bonus) | same file → `torsoIsPatterned` block |
| Generic yellow head ignored as identity signal | same file → `hasGenericHead` |
| Non-yellow head color match (licensed-character signal) used as consistency check | same file → head consistency block |
| Headgear presence + color used as consistency check (mold+color separation) | same file → `figureHasHeadgear` block |
| Printed-legs bonus only when legs band multi-colored AND fig has dual/printed legs | same file → printed-legs block |
| Plain solid-color legs are tiebreaker only | same file → reduced legs weight |
| Hair / face / legs not cross-attributed in hybrid analysis | [Bricky/Services/HybridFigureAnalyzer.swift](../Bricky/Services/HybridFigureAnalyzer.swift) — region gating |
| Top-K hypotheses returned (not single-answer rejection) | identify() returns up to 60 candidates → trimmed to 8 in UI |
| Show top-k always, never a hard "no match" reject | results sheet always shows what we have |

When you change weights or thresholds, update this table and the
companion [MINIFIGURE_ANATOMY.md](MINIFIGURE_ANATOMY.md).

---

## 5b. Source code audit findings (verified June 2025)

These findings were confirmed by reading every line of the identification
pipeline. Discrepancies between prior documentation and actual code are
noted.

### Full pipeline flow (verified)
```
identify(torsoImage:) → Phase 1 → Phase 1.5 → Phase 2 → UserCorrectionReranker
```

1. **Phase 1** (`fastColorBasedCandidates`): 24×24 downsample, coarse
   color bucketing, LEGO color mapping. Returns top **60** candidates.
   Cascade mode activates when torso score >= 0.80 AND (patterned OR
   rare color). Joint-inference weights: torso 0.72, head 0.10, hair
   0.10, legs 0.04, accessories 0.02 (placeholder).
2. **Phase 1.5** (`mergeWithEmbeddingHits`): CoreML `TorsoEncoder.mlmodelc`
   + `FaceEncoder.mlmodelc`. **Graceful no-op** when models aren't bundled
   (`isAvailable` checks both model + index). Injection threshold: cosine
   >= 0.50. **Never reorders** existing candidates — only adds new ones.
3. **Phase 2** (`refineWithLocalReferenceImages`): Three-signal blend:
   - `VNFeaturePrintObservation` on torso band (0.45 weight)
   - `TorsoVisualSignature` spatial descriptor (0.30 weight)
   - `VNFeaturePrintObservation` on full figure (0.25 weight)
   - Downloads up to 8 reference images on-demand (4s overall timeout)
   - Returns top 6-8 candidates
4. **UserCorrectionReranker**: Feature-print matching against past manual
   corrections. **Injection disabled** (over-fired). Boost-only: distance
   ≤ 3.5 = strong, ≤ 6 = moderate. Strict thresholds because VN feature
   prints cluster tightly on minifig photos.

### Embedding resources (verified in bundle)
- `Bricky/Resources/TorsoEmbeddings/`: `torso_embeddings.bin` (Float16),
  `torso_embeddings_index.json`, `torso_embeddings_mean.bin`
- `Bricky/Resources/FaceEmbeddings/`: `face_embeddings.bin` (Float16),
  `face_embeddings_index.json`, `face_embeddings_mean.bin`
- **Missing from bundle (unverified)**: `TorsoEncoder.mlmodelc`,
  `FaceEncoder.mlmodelc` — if absent, Phase 1.5 is entirely disabled

### Test coverage (as of audit)
- `fuzzyScore()`: 4 assertions
- `MinifigurePartClassifier.slot()`: 13 assertions
- **Core identification pipeline: ZERO test coverage**
- No tests for cascade scoring, embedding lookup, confidence calibration,
  or end-to-end identification

### Python pipeline alignment
- `embed_catalog.py` torso crop: 30-70% vertical band → 224×224 thumbnail
  → letterbox on (244,244,244) → ImageNet normalize. **Matches** Swift's
  Phase 1 crop coordinates but Swift uses `scaleFill` (not letterbox).
- `detect_figure_bbox()` duplicated identically in `evaluate_retrieval.py`
  and `ingest_real_photos.py`.
- DINOv2 `vits14` produces 384-D embeddings; index stores as Float16.

---

## 6. Future work (not yet implemented)

- **Trained CoreML torso-print classifier.** The biggest remaining
  gap: catalog `torso.color` is the base plastic color, not the print.
  A real torso-print classifier trained on BrickLink/Rebrickable
  *Torso Assembly Decorated* images would replace the
  `printPixelRatio` heuristic and let common-color solid scans
  (Black, White, Blue…) enter cascade mode safely. This is the
  BrickScan approach.
- **Mask R-CNN segmentation.** Right now we crop fixed vertical bands
  (hair 0–15%, head 12–28%, torso 28–65%, legs 65–100%). A learned
  segmenter would handle non-standard poses and cropping.
- **Part-to-figure consistency check.** We score figures by per-part
  color match, but don't yet verify "this exact torso + head + hair
  combination shipped together in any released set." Rebrickable
  inventories would enable this.
- **Dual-sided head awareness.** The head band check assumes one face.
  We should compare against both face prints when available.
- **Back-of-torso capture.** Currently single-photo. A guided two-shot
  flow (front then back) would unlock the ~30–40% of torsos with
  back-only printing.
- **Minidoll detection / branching.** Friends/Disney Princess figures
  use a different anatomy and currently mis-rank against minifigure
  catalog entries.
