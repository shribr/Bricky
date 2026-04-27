import Foundation

/// Centralized registry of every `UserDefaults` key the app reads or
/// writes. Define new keys here as static `let` constants instead of
/// inline string literals at call sites — that way:
///
///   1. There's a single place to discover what app state is persisted.
///   2. Typos can't silently produce stale-default bugs (a misspelled
///      string literal at a write site would be a different key from
///      the read site, and the bug would only surface when state
///      mysteriously failed to persist).
///   3. Refactors and renames are mechanical (rename the constant,
///      compiler finds every usage).
///
/// Keys grouped by domain. The `ScanSettings.*` family is namespaced
/// because those keys are owned by `ScanSettings` and could otherwise
/// collide with a future top-level key.
enum UserDefaultsKey {
    // MARK: App

    static let hasCompletedOnboarding = "hasCompletedOnboarding"
    static let hasSeenScanGuide = "hasSeenScanGuide"
    static let iCloudSyncEnabled = "iCloudSyncEnabled"
    static let lastCloudSync = "lastCloudSync"

    // MARK: Appearance

    static let appearanceMode = "appearanceMode"
    static let colorTheme = "colorTheme"

    // MARK: Sound & Feedback

    static let hapticFeedback = "hapticFeedback"
    static let soundEffects = "soundEffects"

    // MARK: Scan

    static let scanMode = "scanMode"
    static let scanCoverageDetail = "scanCoverageDetail"
    static let scanOverlayStyle = "scanOverlayStyle"
    static let trackingMode = "trackingMode"
    static let scanAutoEnhanceEnabled = "scanAutoEnhanceEnabled"
    static let scanShadowRemovalEnabled = "scanShadowRemovalEnabled"

    // MARK: ScanSettings (owned by `ScanSettings`)

    enum ScanSettings {
        static let autoDetectGridSize = "ScanSettings.autoDetectGridSize"
        static let locationCaptureEnabled = "ScanSettings.locationCaptureEnabled"
        static let locationConsentPrompted = "ScanSettings.locationConsentPrompted"
        static let locationFilterRadiusKm = "ScanSettings.locationFilterRadiusKm"
        static let identificationMode = "ScanSettings.identificationMode"
        static let locationSnapshotsEnabled = "ScanSettings.locationSnapshotsEnabled"
        static let meshColorRamp = "ScanSettings.meshColorRamp"
        static let meshResolution = "ScanSettings.meshResolution"
        static let preRenderOnComplete = "ScanSettings.preRenderOnComplete"
        static let scanMode = "ScanSettings.scanMode"
        static let segmentGridSize = "ScanSettings.segmentGridSize"
        static let trackingMode = "ScanSettings.trackingMode"
        static let trackingModeLiDARMigratedV1 = "ScanSettings.trackingModeLiDARMigratedV1"
        static let useCompositeMode = "ScanSettings.useCompositeMode"
        static let cloudFallbackEnabled = "ScanSettings.cloudFallbackEnabled"
    }
}
