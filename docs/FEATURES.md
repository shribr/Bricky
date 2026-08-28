# Features

Detailed feature descriptions and status for Bricky. For a short summary see the
[root README](../README.md); for how the app is built see
[architecture.md](architecture.md).

**Status legend:** ✅ Shipped · 🔒 Bricky Pro · 🧪 Requires a physical device

## Scanning & identification

| Feature | Status | Notes |
| --- | --- | --- |
| AR brick scanning | ✅ 🧪 | Real-time piece detection with confidence scoring and spatial tracking via ARKit + Vision. |
| Photo scanning | ✅ | Scan a picked or captured still image; trace the area to scan. Works without a live camera. |
| Minifigure identification | ✅ | Fast color cascade → CoreML torso embedding → head/face refinement against a 16K+ figure catalog. |
| AI subject recognition | 🛠️ dev-only | "Who or What Is This?" — identify famous people, cartoon/film characters, landmarks and famous places, and musicians in a photo via cloud GPT-4o vision. **Hidden, developer-only feature** unlocked solely by the in-app developer override; not exposed to users and not part of any paid tier. The Azure key stays server-side behind the recognition proxy, which accepts only the developer-bypass token. |
| AI set identification | 🛠️ dev-only | "Identify a Set" — scan an already-built model and find out which official LEGO set it is via cloud GPT-4o vision. Proposes up to three candidates, grounded against the bundled set catalog (verified matches vs. clearly-flagged unverified guesses). **Hidden, developer-only feature** that only appears on the Scanner landing when the in-app developer override is on; reserved as the flagship of a future paid monthly tier. Azure key stays server-side behind the recognition proxy. |
| Pre-scan analysis | ✅ | Auto-detects whether the frame is a brick pile or a minifigure before scanning. |
| Color calibration | ✅ | Camera color-calibration wizard for more accurate piece identification. |
| LiDAR topographic rendering | ✅ 🧪 | 3D mesh visualization and pile geometry analysis on compatible devices. |
| Scan history | ✅ | Geo-tagged scan sessions with reverse geocoding and a "near me" filter. |

## Inventory & catalog

| Feature | Status | Notes |
| --- | --- | --- |
| Inventory management | ✅ | Organize scanned pieces by color, category, and dimensions. |
| Storage bins | ✅ | Group pieces into bins with physical locations. |
| Import | ✅ | Import inventories from CSV/XML into a new inventory. |
| Piece & set catalog | ✅ | Browse the LEGO piece catalog and set information; track owned sets and completion. |

## Build & create

| Feature | Status | Notes |
| --- | --- | --- |
| Build suggestions | ✅ | Engine recommends buildable projects from your inventory with match percentages. Free tier shows a capped number of suggestions. |
| Daily challenges | ✅ | Daily build challenges with completion tracking and timing. |
| Mosaic Studio | ✅ 🔒 | Turn a photo into a buildable single-layer LEGO mosaic. Returns an LDraw model, instructions PDF, thumbnail, and full parts list to share. Launch from **Home → Mosaic Studio**. Powered by the LEGO Model Generation backend. |
| Demo mode | ✅ | Explore the app flow with sample pieces, no scan required. |

## Community & account

| Feature | Status | Notes |
| --- | --- | --- |
| Community sharing | ✅ | Post builds with photos, captions, and difficulty ratings; like and comment. CloudKit-backed, degrades gracefully offline. |
| User profile | ✅ | Sign in with Apple; profile surface from the Home avatar. |
| iCloud sync | ✅ | User data syncs via iCloud key-value store and documents. |
| Bricky Pro subscription | ✅ 🔒 | StoreKit 2 subscription that lifts scan limits and unlocks premium surfaces such as Mosaic Studio and AI subject recognition. |

## Mosaic Studio details

Mosaic Studio is a Bricky Pro feature backed by the
[LEGO Model Generation backend](../services/lego-model-gen/README.md).

**Flow:** pick a photo → choose a mosaic size → generate. The view renders exactly
one honest state at a time (idle / submitting / processing / completed / failed)
driven by the view model's phase. If the backend is unreachable, the user sees a
real error and a retry — never fabricated results.

**Outputs per job:**

| Artifact | File | Purpose |
| --- | --- | --- |
| LDraw model | `model.ldr` | Loads in LeoCAD / LDView. |
| Instructions | `instructions.pdf` | Row-by-row build steps. |
| Parts list | `parts.json` | Aggregated by part and color, with catalog IDs. |
| Thumbnail | `thumbnail.png` | Cover preview. |

**Configuration:** the backend base URL comes from `AppConfig.mosaicApiBaseURL`
(UserDefaults key `bricky.mosaic.apiBaseURL`, env `BRICKY_MOSAIC_API_URL`, default
`http://localhost:8000`).

## Free tier vs. Bricky Pro

Bricky is fully usable for free. Bricky Pro (🔒) lifts limits and unlocks premium
surfaces:

- **Free:** a limited number of scans per day and a capped number of visible build
  suggestions.
- **Pro:** unlimited scans, full build-suggestion visibility, and Mosaic Studio.

Premium surfaces always present an honest upsell rather than blocking the app.
