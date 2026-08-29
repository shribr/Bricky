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

## 9. Future Feature — "Generate 3D Instructions" from a Set and from a Mosaic

Once the assembly-model pipeline (Phases 0–4) is in place, reuse it to generate
step-by-step 3D instructions for content the user already has in the app:

- **From a Set** — take an identified/collected set and produce an `AssemblyModel`
  (ideally from its LDraw model, else a template approximation) so the user can
  replay the build as interactive 3D instructions, independent of the paper
  booklet.
- **From a Mosaic** — convert a generated mosaic (`MosaicGenerator` /
  `MosaicInstructionsRenderer`) into an `AssemblyModel`: each mosaic cell becomes
  a positioned plate/tile placement, grouped into steps (e.g. by row or region),
  driving the same 3D step viewer used for builds.

Both entry points funnel into the shared `AssemblyModel` → `BuildStepPlanner` →
`BuildStepViewer` path, so no new rendering/step machinery is needed — only
adapters that emit placements from a set or a mosaic. Deferred until the core
build-instruction rework ships and is validated.

---

## 10. Future Feature — Scan a Real-Life Object → 3D Model → 3D Step-by-Step Instructions

Let a user point the phone at a real object (a mug, a toy, a shoe) and have the
app reconstruct it, "brickify" it, and hand back interactive 3D build
instructions for a LEGO replica.

**Most of this pipeline already exists** as the *Set Forge / Scan-to-Set*
feature (`ScanToSetView` → `ForgeVisionViewModel` → `MeshVoxelizer` →
`SetForgeEngine` → `GeneratedLegoSet`). This future feature is mainly (a) adding
a true on-device 3D **capture** front-end and (b) **bridging** the existing
generated-set output into the unified `AssemblyModel` path from Phases 0–5 so it
reuses the same 3D step viewer and overview preview.

### 10.1 Pipeline (capture → replica → instructions)

1. **Capture (real object → digital mesh).**
   - *Primary (new):* RealityKit `ObjectCaptureSession` (LiDAR-guided
     photogrammetry) → `.usdz`. **Device-only** — not in the simulator SDK, so it
     must be guarded `#if !targetEnvironment(simulator)` and verified on a LiDAR
     device.
   - *Existing fallbacks:* multiview 4-angle capture / video walk-around →
     hosted Tripo image→3D → `.usdz`; single photo → bas-relief. (All already
     shipped in Set Forge, with a global spend cap on the hosted path.)

   **Capture-coverage requirement (important UX constraint).** A faithful 3D
   model requires observing the object *from all around* — a single view can only
   ever yield a flat bas-relief. The capture modes trade user effort for
   fidelity:

   | Mode | What the user does | Coverage needed | Fidelity |
   |---|---|---|---|
   | Photogrammetry (Object Capture, LiDAR) | Orbit the object taking **many overlapping photos** (~20-200+, ~70% overlap, at 2-3 heights); flip the object to get the **bottom** | Full all-around + top/bottom | Highest |
   | Video walk-around | Slowly circle the object on video; app extracts frames | Full orbit (a 2nd higher/lower pass helps) | High |
   | AI multiview (Tripo) | Take **~4 photos** (front/left/back/right) | Minimal — model *hallucinates* unseen parts | Medium |
   | Single photo | One tap | None | Bas-relief only (flat/guessed back) |

   So the answer to "does the user record a video or take pictures of all
   sides?" is: **yes for genuine geometry** (video sweep or many-angle orbit),
   while the **4-view AI path** is the low-effort shortcut. "Exactly 6
   orthographic sides" isn't how either path works — photogrammetry wants *many
   overlapping* views; the AI path needs only ~4. The guided-capture UI should
   default to the video sweep (best coverage/effort balance) and offer the
   4-photo AI path as the quick option.

2. **Mesh → voxels.** `MeshVoxelizer.voxelize(assetURL:)` → `VoxelModel`
   (texture-aware colors; `gravitySettled()` guarantees nothing floats).
3. **Voxels → brick set.** `SetForgeEngine.generate(from:size:name:)` →
   `GeneratedLegoSet` (bricks, parts, layer-by-layer steps, LDR text).
4. **Bridge to `AssemblyModel` (new adapter).** Add
   `GeneratedLegoSet.asAssemblyModel()` mapping each `PlacedBrick` → a
   `BrickPlacement`: LDU coords (stud = 20, layer = 24) → `GridPosition`, LEGO
   color carried through, and `step` taken from
   `SetForgeInstructions.stepGroups(for:)`. This funnels real-object builds
   through the **same** `BuildStepViewer` + overview 3D preview as authored
   projects.
5. **Instructions.** Reuse the assembly-derived step planner. The existing
   layer-by-layer SetForge stepping already yields ~20+ steps for any non-trivial
   object (large layers auto-split into sub-steps), satisfying the realistic
   step-count requirement.

### 10.2 New work required
- `Views/ObjectCaptureView.swift` — guided LiDAR capture UI (device-only,
  `#if !targetEnvironment(simulator)`), producing a `.usdz` fed to the existing
  `MeshVoxelizer` import path.
- `GeneratedLegoSet.asAssemblyModel()` adapter + LDU→stud-grid coordinate/step
  mapping (the single genuinely new, testable unit).
- Entry point: a "Brickify a Real Object" card (Scanner landing / Scan Results),
  Pro-gated like the rest of Set Forge.
- Persist results via the existing `GeneratedSetStore`; surface the 3D
  instructions through the unified viewer instead of the SetForge-specific one.

### 10.3 Risks
- **Object Capture is device-only** — cannot be compiled/tested against the
  simulator; guard it and validate on hardware.
- **Likeness vs. resolution** — blocky at small voxel sizes; default to
  Medium/Large for recognizable replicas (thermals/compute cost trade-off).
- **Capture quality** — lighting, texture, and full coverage strongly affect the
  reconstruction; keep the multiview/photo fallbacks for non-LiDAR devices.

### 10.4 Testing
- Adapter unit tests: `PlacedBrick` → `BrickPlacement` mapping, step alignment
  with `stepGroups`, and `asAssemblyModel().derivedRequiredPieces` == the set's
  aggregated parts.
- Voxelizer, gravity invariant, and SetForge stepping are already covered by
  existing suites (`MeshVoxelizerTests`, `SetForgeEngineTests`,
  `SetForgeInstructions`).

> Relationship to §9: §9 (set/mosaic) and §10 (real object) both converge on the
> same `AssemblyModel` bridge. Build the adapter layer once (`asAssemblyModel()`
> from `GeneratedLegoSet`) and all three sources — set, mosaic, real object —
> reuse the unified step viewer.

---

## Changelog
- 2026-08-28 · initial plan drafted (root cause, assembly-model design,
  LDraw-first sourcing, 6-phase rollout, model recommendation).
- 2026-08-28 · added §9 future feature (generate 3D instructions from a set and
  from a mosaic); Phase 0 (assembly data model + tests) implemented.
- 2026-08-28 · added §10 future feature (scan a real-life object → 3D model → 3D
  step-by-step instructions), reusing the Set Forge capture/voxelize/generate
  pipeline via a shared `GeneratedLegoSet.asAssemblyModel()` bridge.
- 2026-08-28 · clarified §10.1 capture-coverage requirement (video sweep or
  many-angle orbit for true geometry; ~4-view AI path as the low-effort
  shortcut; single photo = bas-relief only).
- 2026-08-28 · Phase 1 implemented: `LDrawModelParser` (`.ldr`/`.mpd` → ordered
  `AssemblyModel` with real `0 STEP` boundaries, MPD sub-model inlining,
  LDU→stud-grid coord/rotation mapping, colour-code mapping) + `LDrawPartCatalog`
  + 7 fixture tests. Sub-model-internal step boundaries flattened for now (noted
  limitation).
- 2026-08-28 · Phase 2 (part 1) implemented: the shared
  `GeneratedLegoSet.asAssemblyModel()` bridge (Set Forge bricks + step groups →
  `AssemblyModel`; the §9/§10 enabler) + `AssemblyValidator` harness (gapless
  steps, all-placements-stepped, no-floating-bricks via footprint support) +
  `BrickPlacement` footprint/support helpers + 8 tests. No bundled LDraw *models*
  exist yet, so the LDraw-import ingestion path (Phase 1 parser) awaits source
  models; wiring catalog projects to generated/template assemblies is folded into
  Phase 3.
- 2026-08-28 · Phase 3 implemented: `BuildStepPlanner` (assembly → `BuildStep`s
  with piece summaries + positional hints, derived from the same placements the
  viewer renders) + `ProceduralAssemblyGenerator` (deterministic, always-valid
  layered fill from a bag of `RequiredPiece`s) + `LegoProject.resolvedAssembly`
  wiring (authored/LDraw assembly preferred, else generated) + 7 tests. Generator
  aesthetics are blocky (support-guaranteed flush packing); recognizable
  LDraw/authored models still take precedence. Also removed the Timed Build entry
  from the Instructions tab (instructions-only screen).
- 2026-08-28 · Phase 4 implemented: `BuildStepViewer` rewritten to render the
  project's real `resolvedAssembly` placements at true grid coordinates
  (center-based container placement so rotations spin about the footprint
  centre), cumulative per-step reveal with the current step's new pieces
  highlighted (emission glow), bounding-sphere camera framing, and step text
  driven by `BuildStepPlanner` so words match the render. Removed the old
  even-distribution / floating-row layout.
- 2026-08-28 · Phase 5 implemented: the project Overview hero is now a rotating
  3D render of the finished model (`AssemblyPreviewView` + shared
  `AssemblySceneBuilder`, reused by the step viewer) with a graceful icon
  fallback when there are no placements; 3 placement-math tests.
- 2026-08-28 · Phase 6 implemented: golden/regression suite
  (`BuildProjectsGoldenTests`) asserts every catalog project resolves to a valid
  assembly with gapless, non-empty steps that cover all placements, and that
  generation is deterministic; CHANGELOG updated. Phases 0–6 of the "What Can I
  Build?" fix are complete (LDraw import path awaits bundled source models).