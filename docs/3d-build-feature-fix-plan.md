# Plan: Fix the 3D "What You Can Build" Feature

**Status:** Proposed
**Created:** 2026-08-28
**Owner:** Bricky lead dev
**Related screens:** `BuildDetailView`, `BuildStepViewer`, `BuildSuggestionsView`
**Related data:** `Resources/BuildProjects.json`, `Models/LegoProject.swift`

---

## 1. Problem Statement

Two user-reported defects:

1. **Step-by-step instructions and per-step 3D renderings look nothing like the
   final product.** The steps feel random — pieces float in arbitrary rows and
   stack in ways that never resemble the object named by the project (a "chair,"
   a "race car," etc.).
2. **Step counts are unrealistically small.** Projects ship with ~6 steps. Even
   the simplest real LEGO set has ~20+ steps. Six steps reads as a toy, not a
   real instruction booklet.

Plus two adjacent asks already partially handled elsewhere:

3. The **Overview page** should show a real 3D render of the finished model, not
   an SF Symbol icon.

---

## 2. Root Cause

The data model has **no spatial/geometry ground truth** for a build. A
`LegoProject` today is:

- `requiredPieces: [RequiredPiece]` — an unordered *bag of parts* (category,
  dimensions, color, quantity). No positions.
- `instructions: [BuildStep]` — hand-authored **prose** (`instruction` +
  free-text `piecesUsed` string). Written independently of any model; nothing
  ties a step to specific pieces or positions.
- `imageSystemName` — an SF Symbol used as the hero "image."

Because there are no brick positions, `BuildStepViewer` **fabricates** geometry
at runtime (`buildAllStepNodes` / `distributePiecesAcrossSteps`):

- It splits `requiredPieces` **evenly** across `instructions.count` steps
  (arbitrary — unrelated to the prose), then
- lays each step's bricks out in naive left-to-right rows, bumping `yStack` up a
  layer per step.

The result cannot resemble the target object, and the number of steps is capped
by however many prose sentences an author happened to write (≈6).

**Conclusion:** you cannot derive a faithful 3D build or realistic step sequence
from a bag of parts + prose. We need an ordered, positioned **assembly model**
as the single source of truth, and everything (preview, steps, instruction text,
required-piece totals) must derive from it.

---

## 3. Target Design

### 3.1 Single source of truth: an ordered assembly model

Add positioned placements on a LEGO stud grid (integer coordinates), in build
order:

```swift
struct BrickPlacement: Codable, Identifiable {
    let id: UUID
    let category: PieceCategory
    let dimensions: PieceDimensions
    let color: LegoColor
    let partNumber: String?      // optional LDraw part for accurate mesh
    let position: GridPosition   // x, y (layer, in plate units), z — stud grid
    let rotationDegrees: Int     // 0 / 90 / 180 / 270 about vertical axis
    let step: Int                // 1-based build step this placement belongs to
}

struct GridPosition: Codable { let x: Int; let y: Int; let z: Int }

struct AssemblyModel: Codable {
    let placements: [BrickPlacement]   // authored/generated in build order
    // Derived at runtime: boundingBox, stepCount, per-step groups.
}
```

Extend `LegoProject` with an **optional** field for backward compatibility:

```swift
let assembly: AssemblyModel?   // nil => legacy fallback (old renderer)
```

Everything derives from `assembly`:

- **Final 3D preview** = render *all* placements at their real coordinates.
- **Steps** = placements grouped by `step`, revealed cumulatively.
- **Instruction text** = generated from the pieces added in each step (counts by
  part+color) plus a positional hint derived from coordinates
  ("Add 2× Red 2×4 Brick on the left, flush with the front edge").
- **`requiredPieces`** = *derived* by aggregating placements, so the match %
  logic stays consistent with what's actually built.

### 3.2 Where do assemblies come from?

Three sourcing strategies; recommend a **hybrid**:

| Strategy | Fidelity | Effort | Notes |
|---|---|---|---|
| **A. LDraw model import** | Highest | Med | LDraw `.ldr`/`.mpd` files *natively encode build steps* via `0 STEP` meta-commands and place whole parts via type-1 references. The app already has `LDrawParser`, `LDrawLibrary`, `LDrawGeometryBuilder`, `LDrawColorMap` (part-level). We extend to a **model-level** parser. Real models ⇒ real ~20-40 step sequences that look like the product. |
| **B. Parametric templates** | Medium (blocky but coherent) | Med | Category generators (car, chair, house, tree…) emit symmetric, connected, studded placements with sensible bottom-up step grouping. Scales to fill the library where no LDraw model exists. |
| **C. Hand-authored JSON** | High | Very high | Only for a few hero builds; too costly at library scale. |

**Recommendation:** Build the **LDraw model importer (A)** first — it directly
solves *both* defects (realistic geometry *and* real step counts) and reuses
existing LDraw code. Use **parametric templates (B)** to backfill projects that
have no bundled model. Keep the legacy renderer only as a fallback when
`assembly == nil`.

> Key insight on step counts: LDraw `0 STEP` boundaries give authentic step
> sequences directly. Where we synthesize steps (template path), target **1–4
> new parts per step**, producing ~20-40 steps for simple builds — matching the
> user's expectation.

---

## 4. Implementation Phases

### Phase 0 — Model + back-compat (small)
- Add `BrickPlacement`, `GridPosition`, `AssemblyModel`; add optional
  `assembly` to `LegoProject`.
- Derive `requiredPieces` from `assembly` when present (keep stored field for
  legacy rows).
- Tests: decode round-trip; derived required-pieces equals aggregated
  placements.

### Phase 1 — LDraw model (`.ldr`/`.mpd`) parser (medium, 3D-heavy)
- New `LDrawModelParser`: read type-1 sub-file references (part + transform +
  color), split into steps on `0 STEP`, resolve multi-model `.mpd` (`0 FILE`).
- Map LDraw units/orientation → our stud grid (`GridPosition` + rotation).
- Reuse `LDrawParser.Transform`, `LDrawColorMap`.
- Tests: parse a fixture model → expected placement count, step count, and
  per-step membership.

### Phase 2 — Assembly ingestion pipeline (medium, data)
- Offline tool in `Tools/` that converts bundled LDraw models → `AssemblyModel`
  JSON, and a parametric-template generator for category fallbacks.
- Rebuild `BuildProjects.json` to include `assembly` (or a sidecar per project).
- Data-validation harness: every placement connects to the model (no floating
  bricks), steps are contiguous and cover all placements.

### Phase 3 — Step planner / instruction generator (medium)
- `BuildStepPlanner`: group placements by `step`; for the template path,
  synthesize bottom-up steps (1–4 parts each, subassemblies first).
- Generate `BuildStep.instruction` + exact per-step piece list + positional
  hints from coordinates. Retire free-text `piecesUsed` in favor of derived
  data.
- Tests: step numbers monotonic & gapless; union of step pieces == full model;
  realistic step count (> ~15 for non-trivial builds).

### Phase 4 — `BuildStepViewer` rewrite (medium, 3D)
- Render **cumulative** placements at real grid coordinates (proper stud-up
  orientation, correct spacing via `BrickGeometryGenerator.studPitch` /
  `plateHeight`).
- Frame the camera on the model bounding box; **ghost/highlight** the current
  step's new pieces vs. already-placed pieces.
- Remove `distributePiecesAcrossSteps` / naive row layout.
- Tests: cumulative node count == sum of placements up to step N; camera framing
  non-degenerate for a known model.

### Phase 5 — Overview 3D preview (small–medium, 3D)
- Replace the SF Symbol hero in `BuildDetailView.overviewTab` with an
  interactive/auto-rotating SceneKit render of the full assembly; graceful
  fallback to the icon when `assembly == nil`.
- Reuse the Phase 4 scene builder (render all placements).

### Phase 6 — Docs, data audit, golden tests
- Golden tests for 2–3 reference builds (chair, race car, small house):
  placement + step snapshots so regressions are caught.
- Update CHANGELOG / FEATURE_LIST per project rules.

---

## 5. Backward Compatibility & Migration
- `assembly` is optional. Legacy projects with `assembly == nil` keep the
  current (imperfect) renderer, so nothing breaks while the library is
  converted.
- Convert the library incrementally; each converted project immediately gets the
  new preview + realistic steps.
- Persisted user data (favorites, completed steps by index) stays valid — steps
  remain an ordered list.

## 6. Risks
- **LDraw → stud-grid mapping** (orientation, sub-part transforms, mirrored
  determinants) is fiddly; isolate in Phase 1 with fixture tests before wiring
  UI.
- **Asset size:** bundling LDraw models/derived JSON grows the app. Mitigate by
  storing compact derived `AssemblyModel` JSON (not raw `.mpd`) and gzip like
  the minifigure catalog.
- **Template aesthetics:** parametric builds are blocky. Acceptable as a
  fallback; prioritize LDraw for hero projects.

## 7. Testing Summary
Per project rules, every phase ships tests: model round-trip, LDraw parse
fixtures, step-planner invariants (monotonic/gapless/complete), derived
required-pieces equality, cumulative render counts, camera framing, and golden
snapshots for reference builds. Run `-only-testing:BrickyTests/<Suite>` after
each phase and a full build before sign-off.

---

## 8. Model Recommendation (for implementation)

**Yes — a more capable model is warranted for Phases 1–4.** Those phases involve
3D coordinate-system math, LDraw transform composition / orientation mapping,
camera framing, and a multi-file data pipeline where subtle errors produce
"looks wrong" output that's hard to unit-test away. Phase 0, 5, and 6 are lighter
and fine on the current model.

Recommendation: switch the chat to the most capable available model before
starting **Phase 1**, and keep it through **Phase 4**. Phase 0 can begin now on
the current model to unblock the data types.

---

## Changelog
- 2026-08-28 · initial plan drafted (root cause, assembly-model design,
  LDraw-first sourcing, 6-phase rollout, model recommendation).
