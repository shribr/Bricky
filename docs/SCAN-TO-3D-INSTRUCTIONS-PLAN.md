# SCAN A REAL OBJECT → 3D MODEL → 3D INSTRUCTIONS — PLAN

Goal: let a user **scan a real-life object** and get back a **buildable LEGO
replica** with **step-by-step 3D instructions** rendered in the same polished
viewer used for authored projects and imported LDraw sets.

This is "§10" from `3D-BUILD-FEATURE-FIX-PLAN.md`, now written up as a standalone
plan because the surrounding pieces (the unified 3D instruction viewer, the
`AssemblyModel` bridge, the Set Forge capture/voxelize/generate stack) already
exist — so the remaining work is mostly **wiring + a device-only capture UI**,
not new algorithms.

## 1. What already exists (reuse, don't rebuild)

| Capability | Where | Status |
|---|---|---|
| Mesh → colored voxels (texture-aware, gravity-settled) | `Services/SetForge/MeshVoxelizer.swift` `voxelize(assetURL:)` | ✅ shipped |
| Voxels → brick set (bricks, parts, layer steps, LDR) | `Services/SetForge/SetForgeEngine.swift` | ✅ shipped |
| Import a `.usdz`/`.obj` 3D model → set | `ForgeVisionViewModel.generateFromMesh(url:)` + `ScanToSetView` fileImporter | ✅ shipped |
| Photo / 4-view / video-sweep → hosted mesh (Tripo) | Set Forge cloud paths (global spend cap) | ✅ shipped |
| **Bricks → `AssemblyModel`** | `Services/SetForge/GeneratedLegoSetAssembly.swift` `asAssemblyModel()` | ✅ shipped |
| Step-by-step 3D instruction viewer | `Views/BuildStepViewer.swift` (`init(assembly:)`) — entity focus, see-through, fly-in, completion page | ✅ shipped |
| Buildability validation (gapless steps, no floating bricks) | `Services/AssemblyValidator.swift` | ✅ shipped |
| Persist generated sets + source images | `Services/GeneratedSetStore.swift` | ✅ shipped |

**Implication:** the "3D model" and "instructions" halves are effectively done.
The gaps are the **capture front-end** and **routing a scanned set into the new
viewer**.

## 2. End-to-end flow

```
Real object
  │  (capture — §3)
  ▼
Digital mesh (.usdz)
  │  MeshVoxelizer.voxelize(assetURL:)
  ▼
VoxelModel (colored, gravity-settled)
  │  SetForgeEngine.generate(from:size:name:)
  ▼
GeneratedLegoSet (bricks + layer steps + parts)
  │  .asAssemblyModel()            ← existing bridge
  ▼
AssemblyModel
  │  BuildStepViewer(assembly:)     ← the unified 3D instruction viewer
  ▼
Step-by-step 3D instructions (+ completion page)
```

## 3. Capture (the genuinely new, device-only part)

A faithful replica needs the object observed **from all around** — a single view
can only ever produce a flat bas-relief. Modes trade user effort for fidelity:

| Mode | User effort | Coverage | Fidelity | Availability |
|---|---|---|---|---|
| Photogrammetry — RealityKit `ObjectCaptureSession` (LiDAR) | Orbit taking many overlapping photos at 2–3 heights; flip for the bottom | Full + top/bottom | Highest | **Device-only** (LiDAR) |
| Video walk-around | Slowly circle on video; app extracts frames | Full orbit | High | Device camera |
| AI multiview (Tripo) | ~4 photos (front/left/back/right) | Minimal — model hallucinates unseen faces | Medium | Any (cloud, capped) |
| Single photo | One tap | None | Bas-relief only | Any |

Guided capture should **default to the video sweep** (best coverage/effort) and
offer the **4-photo AI path** as the quick option. The video-sweep and
multi-photo flows are already shipped in Set Forge; the **Object Capture
photogrammetry UI is the new piece**.

> **Constraint:** `ObjectCaptureSession` is **not in the simulator SDK**. All
> guided-capture code must be guarded `#if !targetEnvironment(simulator)` and can
> only be verified on a real LiDAR device. Everything downstream of the produced
> `.usdz` (voxelize → set → assembly → viewer) is fully testable in the sim.

## 4. Work items

1. **Route scanned sets into the unified viewer (small, testable — do first).**
   Add a **"View 3D Instructions"** action on `GeneratedSetView` /
   `GeneratedSetsGalleryView` that presents `BuildStepViewer(assembly: set.asAssemblyModel(), title: set.name)`.
   This immediately gives every *existing* scanned/forged set real step-by-step
   3D instructions in the polished viewer — no capture work required.
2. **Guided Object Capture UI** — `Views/SetForge/ObjectCaptureView.swift`
   (device-only, `#if !targetEnvironment(simulator)`), producing a `.usdz` fed to
   the existing `MeshVoxelizer` path. Coaching overlay + progress, mirroring the
   existing sweep/guided-angle capture views.
3. **Entry point** — a **"Brickify a Real Object"** card on the Scanner landing
   (`PreScanAnalysisView`) and/or a Home promo, Pro-gated like the rest of Set
   Forge. Leads to the capture-mode chooser (Object Capture / video sweep / 4
   photos), reusing `ScanToSetView`'s existing chooser where possible.
4. **Instruction quality pass** — confirm SetForge's layer-by-layer stepping
   yields a sensible sequence through `BuildStepViewer` (it already sub-splits
   large layers into ~20+ steps). Tune step grouping only if needed.

## 5. Testing

- **Bridge/adapter:** `PlacedBrick` → `BrickPlacement` mapping, step alignment
  with `SetForgeInstructions.stepGroups`, and
  `asAssemblyModel().derivedRequiredPieces` == the set's aggregated parts.
  (Some of this is already covered; extend for the viewer wiring.)
- **Viewer wiring:** building `BuildStepViewer(assembly:)` from a generated set
  yields `stepCount > 0` and one node group per step.
- **Voxelizer / gravity / stepping:** already covered
  (`MeshVoxelizerTests`, `SetForgeEngineTests`).
- **Capture UI:** compile-guarded; runtime-verified on device only.

## 6. Risks

- **Object Capture device-only** — guard + validate on hardware; keep the
  cloud/photo fallbacks for non-LiDAR devices and the simulator.
- **Likeness vs. resolution** — small voxel sizes look blocky; default to
  Medium/Large for recognizable replicas (compute/thermal trade-off).
- **Capture quality** — lighting, texture, and full coverage strongly affect the
  reconstruction; the guided UI must coach the user to cover all sides.
- **Cost** — the hosted (Tripo) mesh path has a global monthly spend cap; on-device
  Object Capture and voxelization are free.

## 7. Recommended order

1. **Item 1** (route scanned sets into the unified viewer) — highest value,
   fully testable in the sim, unlocks 3D instructions for all existing generated
   sets immediately.
2. **Item 3** (entry point) — make the flow discoverable.
3. **Item 2** (Object Capture UI) — device-only; build + verify on hardware.
4. **Item 4** (quality pass).

## 8. Cloud AI providers & deployment

The "Cloud AI" reconstruction mode (Settings → 3D Reconstruction) routes the
scan to a hosted mesh provider via `services/recognition-proxy`. Two ways to run
it:

| Provider | `MESH_PROVIDER` | Per-scan cost | Setup |
|---|---|---|---|
| Tripo (default) | `tripo` | paid (global monthly cap) | set `TRIPO_API_KEY` |
| Self-hosted TripoSR/InstantMesh | `selfhosted` | ~$0 (your GPU/Replicate) | set `SELFHOSTED_MESH_URL` (+ optional `SELFHOSTED_MESH_KEY`) |

**Who can use it**
- **Developer override** (7-tap) → dev-bypass token; honored only where
  `DEV_BYPASS_TOKEN` is set (the developer's own deployment).
- **Real Bricky Pro** → the app sends the Apple-signed StoreKit JWS; the proxy
  validates it (`verifyEntitlement`) and accepts it for the mesh endpoints,
  behind the same global spend cap. GPT-4o recognition/set-ID stay
  developer-only.

**Self-hosted endpoint contract** — POST JSON `{ mode: 'text'|'image'|'multiview',
prompt?, imageBase64?, imagesBase64?, mime?, size }` → `{ modelUrl, format? }`
(defaults to `usdz`). Deploy any TripoSR/InstantMesh-compatible service
(MIT/Apache) on Replicate or a GPU host and point `SELFHOSTED_MESH_URL` at it.

**Function app settings**
```
MESH_PROVIDER=selfhosted            # or "tripo"
SELFHOSTED_MESH_URL=https://…       # required for selfhosted
SELFHOSTED_MESH_KEY=…               # optional bearer
APPSTORE_BUNDLE_ID=com.bricky.app   # default
APPSTORE_ENVIRONMENT=Production     # default
APPSTORE_VERIFY_CHAIN=true          # verify Apple signature chain in prod
```

Verify the Pro path in the StoreKit sandbox/TestFlight — a real receipt can't be
exercised in the simulator or unit tests.

## Changelog
- 2026-09-01 · Added §8 Cloud AI providers & deployment: Pro users can opt into
  Cloud AI (StoreKit JWS validated server-side, behind the spend cap) and a
  `selfhosted` mesh provider for ~$0-per-scan; documented env vars + endpoint
  contract.
- 2026-08-30 · Initial standalone plan. Confirmed the mesh→voxel→set→assembly→viewer
  chain and `asAssemblyModel()` bridge already exist; scoped remaining work to
  viewer-wiring (Item 1), entry point (Item 3), device-only Object Capture UI
  (Item 2), and a stepping quality pass (Item 4).
