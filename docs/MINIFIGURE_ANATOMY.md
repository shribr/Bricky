# Minifigure Anatomy & Identification Heuristics

This document captures the design-intent reasoning behind why each part of
a LEGO minifigure carries a different amount of identity information. It
informs how the Bricky scanner weights signals when matching a captured
photo against the catalog.

## The torso is the primary key

The torso isn't just the highest-information part — it's effectively the
**primary key** of the minifigure. Three facts drive this:

1. **Torsos are nearly in 1:1 correspondence with figures.** LEGO almost
   never ships two distinct figures with the same torso print. Heads,
   hair, legs, and accessories get reused constantly across unrelated
   figures, but the torso is the slot LEGO uses to guarantee uniqueness.
   That's why BrickScan built its entire flow around scanning the torso
   first and looking up everything else from there — not because it's
   the most visually prominent, but because knowing the torso collapses
   the hypothesis space to basically one figure.
2. **Other parts are conditional lookups, not independent classifiers.**
   Given the torso, we usually know which 1–3 hair pieces, which 1–2
   heads, and which legs were shipped with it. The marginal information
   added by the other parts, *given the torso*, is small. Treating the
   parts as independent features contributing to a joint classification
   is the wrong model — the right model is **"identify torso, then
   verify with other parts."**
3. **Torso resilience to part swapping.** Loose secondary-market figures
   get reassembled with mismatched parts constantly. The torso is the
   most reliable signal because it's the part most likely to be original
   to the character — people swap hair and accessories casually, but a
   figure "is" its torso in a way it isn't its hair.

## Weighting (when a weighted view is needed)

The scanner now uses a **torso-first cascade** (see §6 below), but when a
flat weighted ensemble is needed for fallback or scoring debug views, the
priors are:

| Layer | Weight | Why |
| --- | --- | --- |
| Torso (front print + arm/hand colors) | **0.70–0.75** | Primary classifier — effectively the figure's primary key. |
| Head | **0.10** | Tiebreaker / confidence boost, especially for licensed characters. |
| Hair / headgear | **0.10** | Silhouette verification + color. |
| Legs | **0.03–0.05** | Only meaningful when printed/dual-molded. |
| Accessories | **0.02** | Context only; don't change identity. |

---

## 1. Hair / Headgear — the silhouette layer

This is the first thing the human eye registers because it breaks the
uniform cylinder-on-a-brick shape every minifigure shares. A cowboy hat,
a bouffant, a knight's helm, a wizard's pointed cap — these read
instantly at distance and at thumbnail size on a box.

LEGO invests heavily in new hair molds for flagship characters: changing
the silhouette is the single highest-leverage move for making a figure
feel distinct. It's also the **most expensive slot to customize** because
every new shape requires a new injection mold, so LEGO **reuses hair
pieces aggressively** across unrelated characters when the silhouette is
generic enough.

**Implication for the scanner:**
- **Presence/absence** of hair is informative ("the figure is bald" vs.
  "the figure has a tall hat" narrows the set significantly).
- **Specific hair attribution** ("this hair looks like X's hair") is
  almost always wrong — hair pieces are too widely shared.
- Treat hair color/silhouette as a **secondary signal**, never primary.

## 2. Torso — the identity layer

Once you're close enough to see printing, the torso tells you **who this
person is in the world** — their job, faction, era, allegiance. It's
the densest information channel on the figure because:

- It's the **largest flat printable surface**, and
- It includes the **arms**, which carry color blocking that extends
  the design.

Torsos are **cheap to make unique** (printing, not molding), so LEGO
treats them as nearly disposable — most licensed figures get bespoke
torso prints even when everything else is reused.

**Implication for the scanner:**
- The torso does **most of the character-differentiation work** in any
  given set, and should drive identification.
- A torso color/print match is the strongest single signal we have.
- Cross-attribute torso mismatches confidently ("torso looks like X");
  do NOT cross-attribute hair, face, or legs.

## 3. Face — the personality layer

Faces are the smallest printable surface and least visible from a
distance, so they don't carry identity — they carry **mood**. The same
"determined smirk" or "worried frown" gets reused across hundreds of
unrelated figures.

Dual-sided heads doubled the expressive range without doubling the part
count, which was a clever economic move. Licensed characters (Harry
Potter, specific Star Wars characters) get unique faces because fans
notice; generic townspeople share a pool of maybe a few dozen stock
expressions.

**Implication for the scanner:**
- Skip generic LEGO yellow heads entirely from cross-attribution — they
  carry zero figure-specific signal.
- Even non-yellow heads are mostly indistinct; only treat as a hint
  when nothing else matches.

## 4. Legs — the afterthought layer

Mostly solid color because:
- You often can't see them clearly when the figure is posed in a set.
- They articulate as a single unit, so printing detail gets distorted
  in motion.
- The torso skirt covers the top portion anyway.

Printed legs are reserved for figures where the lower outfit genuinely
matters — a tuxedo, armored greaves, a specific uniform.

**Implication for the scanner:**
- Treat solid leg colors as a **tiebreaker only**.
- Never let a legs-color match outrank a torso match.
- Printed legs are slightly more informative (small bonus), but still
  secondary to torso.

## 5. Accessories — the context layer

A wand, a frying pan, a blaster, a briefcase — these don't change who
the figure is, they change **what the figure is doing**. LEGO uses
accessories to turn the same base character into multiple scene roles
without making new figures.

**Implication for the scanner:**
- Held accessories are NOT identity signals.
- Detection of "carrying X" is useful for surfacing related figures,
  but never as primary identification.

---

## 6. Architecture: torso-first cascade, not weighted ensemble

This pipeline is **not** a weighted ensemble. It is a cascade:

1. **Torso classifier runs first** and returns a ranked list of
   candidate figures.
2. **Other parts act as a consistency check** against each candidate —
   *"does the observed head/hair/legs match what this figure shipped
   with?"* — which **reranks or filters** the list rather than
   contributing independent votes.
3. **Confidence is gated on torso classification quality.** If the
   torso classifier is confident, you're basically done. If it's
   uncertain (occluded, faded, worn), the other parts start mattering
   more and the pipeline falls back to joint inference using the
   weighted priors above.

## Implication for training data

Training data collection should be **torso-heavy**. Clean, varied torso
images — different lighting, angles, wear levels, partial occlusion
from hair or accessories hanging down — will move accuracy more than
anything else we can do on the other parts.

## Where this is encoded in the codebase

| Concept | Location |
| --- | --- |
| Torso-first cascade (primary classifier → conditional rerank) | [Bricky/Services/MinifigureIdentificationService.swift](../Bricky/Services/MinifigureIdentificationService.swift) → `identify(...)` |
| Confidence-gated fallback to joint inference | same file → `torsoConfident` gate |
| Cascade gate requires print evidence OR rare base color | same file → `hasIdentifyingEvidence` (prevents "torso is black" from triggering cascade mode) |
| Torso-band print-pixel-ratio detection | same file → `analyzeTorsoSignature(...)` |
| Common vs. rare torso color partition | same file → `commonTorsoColors` |
| Torso-band feature print in Phase 2 (weighted 0.65 vs full 0.35) | same file → `refineWithLocalReferenceImages(...)` |
| Quality-aware confidence cap + retake advisory | same file → `lowQualityScan` block |
| Consistency-hits tiebreak before year-desc | same file → `matches.sort` block |
| Legs reduced to tiebreaker weight | same file → leg-slot loop |
| Hybrid analyzer skips hair/face/legs cross-attribution | [Bricky/Services/HybridFigureAnalyzer.swift](../Bricky/Services/HybridFigureAnalyzer.swift) → region-gating block |
| Generic yellow-head detection | both files |

Update those locations together when changing the weighting rule, and
keep this doc in sync with any reweight.

## Known limitation: catalog `torso.color` is not the primary key

`Minifigure.torsoPart.color` records only the *base plastic color*. The
torso's identity comes from its *print*. We approximate the print
without a trained classifier via `analyzeTorsoSignature`'s
`printPixelRatio`, but the long-term fix is a CoreML torso-print
classifier trained on `Torso Assembly Decorated` images (the BrickScan
approach). Until then, common-color solid torsos (Black, White, Blue…)
intentionally do NOT enter cascade mode and are ranked by joint
inference + Phase 2 visual similarity.
