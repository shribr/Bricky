# Changelog

All notable changes to Bricky are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

App version reflects `MARKETING_VERSION` in the Xcode project; the build number
is `CURRENT_PROJECT_VERSION`.

## [Unreleased]

### Added

- **3D model preview on a project's Overview.** The Overview hero is now an
  auto-rotating (drag-to-rotate) 3D render of the finished model built from its
  actual pieces, instead of a flat icon. Falls back to the icon only when a
  project has no renderable pieces.
- **“See What You Can Build” on the Home screen.** A promo card explains how build
  suggestions work, points to where the feature lives (Scan Results), and
  launches it directly — from your last scan when available, otherwise into the
  Scanner.
- **Tappable scan location.** The captured-location chip on Scan Results now
  opens the pin on a map.
- **Set Collection thumbnails & tile view.** Settings now has a *Set Collection*
  section with an **Auto-Download Thumbnails** toggle (fetches the official
  Rebrickable photo whenever a set is identified/added) and a **Download Missing
  Thumbnails** button showing thumbnail coverage. The Set Collection list shows a
  green photo-checkmark on any set that has a thumbnail, and a new **Tile View**
  toolbar toggle shows each set with its thumbnail plus theme/category and year
  (one record per row, list or tile).

### Changed

- **3D step-by-step instructions now match the model.** The build viewer renders
  each project's real assembly at true stud-grid coordinates, revealing pieces
  cumulatively per step and highlighting the pieces added in the current step;
  step text and per-step piece lists are derived from the same placements, so the
  words always match what's on screen. Replaces the old layout that scattered
  pieces in floating rows unrelated to the described steps. (Introduces an
  `AssemblyModel` — an ordered, positioned, gravity-validated brick list — with an
  LDraw `.ldr`/`.mpd` importer and a deterministic fallback generator.)
- **Scan Results layout.** The detected-pieces list now scrolls independently
  while the primary actions stay pinned in a fixed footer (redesigned into a
  prominent “See What You Can Build” CTA plus a compact grid of secondary
  actions). Viewing a scan from history no longer shows the “Scan Complete”
  header/checkmark, and the location chip uses a purple/lavender scheme (not red)
  that adapts to light/dark.
- **Home quick actions.** *Find a Brick* now sits right after *Scanner* and uses
  the green/white styling so every card is consistent; the developer-only subject
  recognition card is hidden; and the Instructions tab is instructions-only (the
  Timed Build entry was removed).
- **Set details: tappable missing pieces & instructions link.** Tapping a
  missing piece now opens the shared 3D preview; the details screen links to the
  set's building instructions on Rebrickable; and the inventory match section
  notes completion is approximate (based on a representative sample, not the
  full bill of materials).

- **Exact set completion via full BOMs.** Completion %, missing pieces, and All
  Pieces are computed against each set's complete parts list, cached on-device,
  instead of the bundled sample; the "approximate" disclaimer disappears once a
  full list is fetched. The list is fetched by the proxy's `GET /api/setParts`
  using `rebrickable-api-key` from Key Vault, with a per-user iCloud-synced
  personal key as fallback. Thumbnails and parts lists are cached and flagged per
  set to avoid repeat API calls; the set details screen offers manual refresh of
  both. Set details also adds a clear "Add to My Collection" button above missing
  pieces (the toolbar +/✓ is just a shortcut for the same action).
- **Community "My Posts" reliability.** Selecting My Posts now also queries the
  signed-in user's posts directly from CloudKit and merges them into the feed,
  and switching filters re-fetches — so your builds show up even outside the
  general feed window.
- **Minifig lookup uses the shared key via Key Vault.** Minifig search now goes
  through the proxy's `GET /api/minifigSearch` (same `rebrickable-api-key` from
  Key Vault) and only falls back to the bundled key if the proxy is unavailable.




- **AI LEGO set identification (developer-only).** The Scanner can now identify
  which official LEGO set an *already-built model* is from a single photo. It
  proposes up to three candidate sets via cloud GPT-4o vision, then **grounds**
  each proposal against the bundled `LegoSetCatalog` so verified matches show
  authoritative name/theme/year/piece-count and unresolved guesses are clearly
  flagged "Unverified guess" — never presented as fact. Like cloud subject
  recognition, this is a hidden, developer-only feature: the **"Identify a Set"**
  entry only appears on the Scanner landing when the in-app developer Pro
  override is enabled, and it is gated on `developerProOverride` (sharing the
  same monthly Azure safety cap). It is reserved as the flagship of a future
  paid monthly tier.
  - `Models/IdentifiedSet.swift` — `IdentifiedSet` / `SetIdentificationResult`
    with lenient decoding and catalog grounding.
  - `Services/SetIdentificationService.swift` — `AzureOpenAISetClient` calling
    the recognition proxy; `LegoSetCatalog.resolve(setNumber:name:year:)`
    grounding helper.
  - `ViewModels/SetIdentificationViewModel.swift` — idle → identifying →
    results / empty / failed / upsell, with verified-first ranking.
  - `Views/SetIdentificationView.swift` + dev-gated Scanner entry point.
  - Proxy: `services/recognition-proxy/src/functions/identifySet.ts`
    (`POST /api/identifySet`) + `identifySetWithOpenAI` / `parseSets`.
  - Tests: `BrickyTests/SetIdentificationTests.swift` (16 tests) and
    `services/recognition-proxy/test/identifySet.test.ts` (10 tests).
- **Pro puzzle packs** — Build Puzzles now ship as a free Starter Pack (10
  puzzles) and a Pro Pack (50 puzzles). Free players guess from a stable,
  deterministic 10-puzzle subset; Bricky Pro unlocks the full rotation. The
  puzzle screen shows pack progress ("X / N solved") and free players see an
  honest upsell to unlock the rest — no fake content, the starter pack is a
  strict subset of the Pro pack.
  - `SubscriptionManager.freePuzzleLimit` (10) / `proPuzzleLimit` (50) and
    `puzzlePoolLimit` gate the eligible puzzle pool by entitlement.
  - `PuzzleEngine.puzzlePool(limit:)` / `generatePuzzle(poolLimit:)` /
    `solvedCount(inPackOf:)` provide deterministic, name-ordered packs.
- **Shareable puzzle results** — Solving a puzzle offers a Wordle-style share
  card (filled/empty square grid for clues used, win streak, and score) via the
  standard share sheet. `PuzzleEngine.shareText(for:)`.

### Changed

- **Bricky Pro is a one-time $4.99 purchase.** Replaced the monthly/annual
  auto-renewing subscriptions with a single non-consumable unlock
  (`com.bricky.app.pro`). There is no subscription of any kind. The paywall
  shows one "Unlock Bricky Pro · one-time purchase" button with one-time-purchase
  legal copy.
- **Cloud AI subject scanning is now a hidden, developer-only feature.** It is
  unlocked solely by the in-app developer override (the 7-tap trick) — never by
  a normal Pro purchase — and involves no subscription or charge to users. The
  Home entry point is hidden unless the override is on, and the Pro paywall and
  upgrade banner no longer mention it. `SubscriptionManager` gates AI recognition
  on `developerProOverride`; the recognition proxy accepts only the developer-
  bypass token (`DEV_BYPASS_TOKEN`) and otherwise returns `not_entitled`. The
  monthly count is just a safety cap on the developer's own Azure spend, using
  GPT-4o vision. (StoreKit JWS verification is retained in the proxy as dormant
  infrastructure for a possible future paid tier.)

- **Scan Bricks renamed to "Scanner."** The Home quick-action button and its
  landing screen (title, navigation title, accessibility label) now read
  "Scanner" to reflect that it identifies bricks, minifigures, and — for the
  developer — built sets.
- **Scan Bricks now opens a landing screen.** Tapping "Scanner" from Home
  shows a titled intro screen ("Scanner") with a brief description and two
  clear entry points — **Pre-Scan Analysis** (live camera auto-detection) and
  **Scan a Photo** (pick/take an existing image). The standalone "Scan a Photo"
  button was removed from the Home screen since it now lives here. Content is
  width-capped and centered so the buttons don't stretch edge-to-edge on iPad.
- **Pre-Scan Analysis has a single exit.** Removed the redundant "X" button from
  the camera screen; a back chevron and the "Cancel" button both return to the
  Scanner landing screen (previously some exits dropped the user all the way
  back to Home).

### Fixed

- **Developer Pro override now works with AI recognition.** Using the developer
  Pro override (7-tap toggle in Settings → About) no longer fails the
  "Who or What Is This?" feature with a "couldn't verify your Bricky Pro
  subscription" error. The app sends a server-gated dev bypass token that the
  recognition proxy accepts only when `DEV_BYPASS_TOKEN` is configured (unset in
  production, so it is inert for real users). Real StoreKit entitlements are
  unchanged and still take precedence.

- **Upgrade to Pro is now front-and-center.** The Home screen shows a prominent
  "Upgrade to Bricky Pro" banner (crown, gradient, one-tap to the paywall) for
  free users; it disappears once Pro is active. Previously the paywall was only
  reachable from deeper feature screens.
- **Solved puzzles show a real "Built from these pieces" preview** — a strip of
  thumbnails rendered from the build's actual required pieces (true category,
  color, and dimensions via `PieceImageGenerator`), shown only after solving so
  it never leaks the answer. `PuzzleEngine.featuredPieces(for:limit:)`.

- **Who or What Is This?** — AI subject recognition. Point Bricky at a photo and
  it identifies famous people, cartoon/film characters, landmarks and famous
  places, and musicians using cloud GPT-4o vision. Launches from the Home screen.
  Gated behind Bricky Pro with a fair-use monthly allowance
  (`AppConfig.proMonthlyAIRecognitionLimit`, default 100/month) so the Azure cost
  is covered by the subscription; free users see an honest upsell. The Azure
  OpenAI key never ships in the app — the app calls a server proxy that verifies
  the StoreKit entitlement (signed JWS), enforces the quota, and calls GPT-4o.
  - `Models/RecognizedSubject.swift` — subject, category, and result DTOs.
  - `Services/ImageRecognitionService.swift` — proxy client with honest,
    localized error mapping (offline, not-entitled, quota-exceeded, etc.).
  - `ViewModels/ImageRecognitionViewModel.swift` — idle → recognizing → results /
    empty / failed / upsell state machine.
  - `Views/ImageRecognitionView.swift` + Home entry point.
  - `Views/CameraImagePicker.swift` — shared camera/library picker (extracted from
    Mosaic Studio so both flows reuse it).
  - `SubscriptionManager` monthly AI-recognition quota with calendar-month reset
    and signed-entitlement (`currentEntitlementJWS()`) support.
  - `AppConfig.aiRecognitionEndpoint` configuration (UserDefaults/env override,
    default `https://bricky-recognition.azurewebsites.net/api/recognizeImage`).
- **Bricky recognition proxy** (`services/recognition-proxy`) — Azure Functions v4
  (TypeScript) service that holds the Azure OpenAI key, verifies the StoreKit
  entitlement server-side, enforces a per-user monthly quota in Azure Table
  Storage, and calls GPT-4o vision with a strict "famous subjects only, never
  guess private individuals" system prompt.
- **Mosaic Studio** — turn any photo into a buildable single-layer LEGO mosaic.
  Launches from the Home screen quick-actions (Home → Mosaic Studio). Submits a
  photo to the LEGO Model Generation backend, polls for progress, and returns an
  LDraw model, a step-by-step instructions PDF, a thumbnail, and a complete parts
  list that can be shared. Gated behind Bricky Pro with an honest free-tier upsell.
  - `Models/MosaicJob.swift` — job, progress, result, and parts DTOs.
  - `Services/MosaicGenerationService.swift` — `actor` API client (submit, poll,
    fetch result, download artifacts, resolve relative artifact URLs).
  - `ViewModels/MosaicGeneratorViewModel.swift` — submit → poll → load-result
    state machine with cancellation.
  - `Views/MosaicGeneratorView.swift` — photo picker, size presets, sortable parts
    list, and artifact share sheet.
  - `AppConfig.mosaicApiBaseURL` configuration (UserDefaults key
    `bricky.mosaic.apiBaseURL`, env `BRICKY_MOSAIC_API_URL`, default
    `http://localhost:8000`).
- **LEGO Model Generation backend** (`services/lego-model-gen`) — deterministic
  FastAPI service that converts a 2D photo into a LEGO mosaic (LDraw, instructions
  PDF, parts list, thumbnail, metadata). Validated by golden-file and
  cross-artifact brick-count consistency tests.

### Tests

- `BrickyTests/ImageRecognitionTests.swift` (8 tests) covers the proxy client
  response/error mapping and lenient subject decoding; `ImageRecognitionViewModelTests`
  (3 tests) and `SubscriptionManagerAIQuotaTests` (3 tests) cover the Pro-gating
  state machine and monthly quota accounting. `services/recognition-proxy`
  ships `test/openai.test.ts` and `test/entitlement.test.ts` (15 tests) covering
  GPT-4o response parsing and StoreKit entitlement verification.
- `BrickyTests/MosaicGenerationServiceTests.swift` (9 tests) and
  `BrickyTests/MosaicGeneratorViewModelTests.swift` (6 tests) cover the iOS client
  end to end with a stubbed `URLProtocol`.
- `BrickyUITests` adds `testNavigationToMosaicStudio`, a launch-flow smoke test for
  the new Home entry point.
- Backend golden-file and invariant suite in `services/lego-model-gen`.

### Documentation

- Added `docs/ARCHITECTURE.md`, `docs/FEATURES.md`, `CONTRIBUTING.md`, this
  changelog, and a `VERSION` file.

## [1.4.0]

Baseline release at the point changelog tracking began. Established the core
Bricky experience:

- AR and photo-based brick scanning with on-device Vision detection.
- Minifigure identification via a fast color cascade plus CoreML torso/face
  embeddings.
- Inventory management, storage bins, and CSV/XML import.
- Build suggestions driven by available inventory.
- Piece and set catalog browsing.
- Community sharing, daily challenges, scan history with geo-tagging, and LiDAR
  topographic rendering.
- Bricky Pro subscription (StoreKit 2) gating scan limits and premium surfaces.

[Unreleased]: https://github.com/shribr/Bricky/compare/v1.4.0...HEAD
[1.4.0]: https://github.com/shribr/Bricky/releases/tag/v1.4.0
