# Architecture

This document describes how the Bricky iOS app is structured and the patterns it
follows. It complements the high-level overview in the [root README](../README.md).

## Platform

- **Language:** Swift (async/await, actors, structured concurrency)
- **UI:** SwiftUI with `NavigationStack` on iPhone and an adaptive split layout on iPad
- **Minimum OS:** iOS 17.0
- **Tooling:** Xcode 16+

## Pattern: MVVM

Bricky uses Model–View–ViewModel with clear boundaries:

- **Models** (`Bricky/Models`) — plain data types (`LegoPiece`, `Minifigure`,
  `LegoProject`, `LegoSet`, `ScanSession`, `CommunityPost`, `MosaicJob`, …). Codable
  and `Sendable` where they cross concurrency boundaries.
- **ViewModels** (`Bricky/ViewModels`) — `@MainActor` `ObservableObject`s that own
  view state via `@Published` and call into services. They contain no view code and
  no direct persistence.
- **Views** (`Bricky/Views`) — SwiftUI views. They observe a view model and render
  state. Views never contain business logic.
- **Services** (`Bricky/Services`) — own data, algorithms, persistence, and network
  access. The classification and identification pipelines live here.

```
View  ──observes──▶  ViewModel  ──calls──▶  Service  ──owns──▶  Data / ML / Network
 ▲                                                                     │
 └──────────────────── @Published state ◀─────────────────────────────┘
```

## Key conventions

### Singletons for shared services

Long-lived services expose a shared instance: `InventoryStore.shared`,
`MinifigureIdentificationService.shared`, `BuildSuggestionEngine.shared`,
`CloudSyncManager.shared`, `SubscriptionManager.shared`,
`MosaicGenerationService.shared`. View models depend on these and accept injected
overrides where useful for testing.

### Concurrency

- View models and UI-publishing services are annotated `@MainActor`.
- Heavy Vision/CoreML work runs off the main actor (`Task.detached`, dedicated
  queues, or `actor` types).
- Networking clients are implemented as `actor`s with an injectable `URLSession`
  so tests can supply a stubbed `URLProtocol`.

### Phase state machines

Scan lifecycles use explicit phase enums rather than scattered booleans. For
example `ContinuousScanCoordinator` drives the scan lifecycle, and
`MosaicGeneratorViewModel.Phase` models `idle → submitting → processing → completed
/ failed`.

### Cascade pipelines

Recognition is staged from cheap to expensive:

- **Minifigure ID:** fast color filter → torso embedding (CoreML/DINOv2) → head/face
  refinement.
- **Brick classification:** rectangle detection → shape analysis → stud detection →
  color → piece matching.

### Configuration

`AppConfig` centralizes bundle identifiers, URL schemes, queue labels, IAP product
IDs, and service endpoints (including `mosaicApiBaseURL`). Avoid scattering literals
through the codebase.

### Localization

User-facing strings go through `LocalizedStrings` (`L10n`). No hardcoded display
strings in views.

## Data and persistence

- **Read-only catalogs** — bundled JSON catalogs (pieces, sets, the gzipped 16K+
  minifigure catalog) are never mutated at runtime.
- **User data** — inventories, favorites, and settings are written to app documents
  and synced through iCloud (key-value store and documents).
- **Community** — backed by CloudKit; degrades gracefully offline.
- **ML assets** — torso/face embeddings are precomputed offline (see `Tools/`) and
  bundled as binary index files loaded at runtime.

## Offline-first

All core features — scanning, identification, inventory, and build suggestions —
work without a network connection. Cloud and backend-dependent features (community,
sync, Mosaic Studio) degrade gracefully and surface honest error/empty states rather
than fabricated data.

## Subscriptions

`SubscriptionManager` (StoreKit 2) gates premium capability. The free tier remains
fully usable (e.g., a limited number of scans per day and a capped number of visible
build suggestions); premium surfaces such as Mosaic Studio present an honest upsell
when the user is not subscribed.

## Backend service

The optional [LEGO Model Generation backend](../services/lego-model-gen/README.md)
is a deterministic FastAPI service that powers Mosaic Studio. The app talks to it
through `MosaicGenerationService`; the base URL is configurable via `AppConfig`.

## Testing

- **Unit/integration:** `BrickyTests` — `XCTestCase` suites per feature area;
  `@MainActor` on view-model tests; network clients tested against a stubbed
  `URLProtocol`.
- **UI:** `BrickyUITests` — `XCUIApplication` launch and navigation flows.
- **Backend:** golden-file and cross-artifact invariant tests in
  `services/lego-model-gen`.

## File-size discipline

No source file should exceed ~2,500 lines. Files approaching the limit are
refactored into focused extensions or separate types.
