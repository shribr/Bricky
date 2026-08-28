# Contributing to Bricky

Thanks for working on Bricky. This guide captures the conventions that keep the
codebase consistent. For the bigger picture, read
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Getting started

1. Clone the repository.
2. Open `Bricky the Brick Scanner.xcodeproj` in Xcode 16+.
3. Select a simulator or device and build/run (⌘R).

> AR and LiDAR features require a physical device. Camera scanning requires a
> device with a camera.

### Backend (optional)

Mosaic Studio talks to the LEGO Model Generation backend in
`services/lego-model-gen`. To run it locally:

```bash
cd services/lego-model-gen
python3 -m venv .venv
.venv/bin/pip install -e ".[dev]"
.venv/bin/uvicorn app.api:app --reload
```

Point the app at it via `AppConfig.mosaicApiBaseURL` (UserDefaults key
`bricky.mosaic.apiBaseURL` or env `BRICKY_MOSAIC_API_URL`).

## Architecture rules

- Follow **MVVM**. Views render state; view models own state and call services;
  services own data and algorithms. No business logic in views.
- Use `@MainActor` on view models and UI-publishing services. Run heavy
  Vision/CoreML work off the main actor.
- Implement network clients as `actor`s with an injectable `URLSession`.
- Route all user-facing strings through `LocalizedStrings` (`L10n`). No hardcoded
  display strings.
- Centralize endpoints, IDs, and queue labels in `AppConfig`.
- Never mutate bundled read-only catalogs at runtime. User data goes to app
  documents or iCloud.
- Gate premium features through `SubscriptionManager` and always provide a usable
  free-tier experience.
- No file over ~2,500 lines — refactor into focused extensions or types.

## Adding a feature

Build in this order: **model → service → view model → view → tests**, then wire a
navigation entry point so the feature is reachable in the app.

## UI conventions

- Support both light and dark mode using semantic SwiftUI colors. Never hardcode
  `.white`/`.black` for surfaces or text.
- Action buttons (Generate, Save, Submit, …) are blue; destructive actions are red;
  green is reserved for status indicators.
- Cap form-control width and center it — inputs and primary buttons must not
  stretch edge-to-edge on iPad. Idiom: `.frame(maxWidth: <cap>).frame(maxWidth: .infinity)`.
- Use SF Symbols, not emoji, for icons. Use sans-serif type.
- Use Title Case for form labels.

## No stubs or fake data

Never ship mock, stub, placeholder, or hardcoded fake data in any surface a user
can see. If a list or scan has nothing real to show, render an honest empty state.
If an action can't be performed for real, guard the UI so it can't be taken.

## Tests

Tests ship with every feature and bug fix — this is non-negotiable.

- Add or update an `XCTestCase` suite in `BrickyTests` for new services, view
  models, and model logic. Use `@MainActor` on view-model tests and a stubbed
  `URLProtocol` for network clients.
- Add a `BrickyUITests` flow when you add a new navigation entry point.
- For bug fixes that change behavior, write a regression test that fails on the old
  code and passes on the new.
- Run the relevant suite and confirm it is green before considering work complete.

Run a focused suite from the command line:

```bash
xcodebuild test -project "Bricky the Brick Scanner.xcodeproj" -scheme Bricky \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:BrickyTests/<YourTestSuite>
```

## Adding files to the Xcode project

`Bricky the Brick Scanner.xcodeproj/project.pbxproj` is a classic (non-synchronized)
project. Each new `.swift` file must be registered in four places: `PBXBuildFile`,
`PBXFileReference`, its `PBXGroup` child list, and the appropriate
`PBXSourcesBuildPhase`. Use a unique 24-character uppercase hex identifier for each
new entry. The `xcodeproj` Ruby gem automates this reliably — prefer it over
hand-editing the `pbxproj`.

## Before you open a PR

- Build is clean with no new warnings.
- All relevant tests pass.
- Documentation is updated: `CHANGELOG.md`, and `docs/FEATURES.md` when a feature
  is added or its status changes.
- Bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` and the `VERSION` file for a
  release.
