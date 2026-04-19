import Foundation

/// Central configuration for all app identity and branding.
///
/// **Every** string that references the app name, bundle ID, or any
/// app-specific identifier must read from this enum. This makes it
/// trivial to rebrand the app — change these values and rebuild.
///
/// Usage:
///   `AppConfig.appName`          → "Bricky"
///   `AppConfig.bundleId`         → "com.bricky.app"
///   `"\(AppConfig.queuePrefix).pipeline"` → "com.bricky.pipeline"
enum AppConfig {
    // MARK: - Identity

    /// User-visible app name (navigation titles, onboarding, share text, etc.)
    static let appName = "Bricky"

    /// Reverse-DNS bundle identifier for the main app target.
    static let bundleId = "com.bricky.app"

    /// Custom URL scheme for deep links and OAuth redirects.
    static let urlScheme = "bricky"

    /// Full OAuth redirect URL.
    static let authRedirectURL = "\(urlScheme)://auth"

    // MARK: - iCloud

    /// iCloud container identifier (must match entitlements).
    static let iCloudContainer = "iCloud.\(bundleId)"

    /// Ubiquity KV store identifier pattern.
    static let kvStoreId = "$(TeamIdentifierPrefix)\(bundleId)"

    // MARK: - Storage Prefixes

    /// Prefix for keychain service identifiers.
    static let keychainPrefix = "com.bricky"

    /// Prefix for GCD dispatch queue labels.
    static let queuePrefix = "com.bricky"

    /// Prefix for UserDefaults keys.
    static let defaultsPrefix = "bricky"

    /// URLCache on-disk directory name.
    static let urlCachePath = "AppURLCache"

    // MARK: - In-App Purchase

    /// Monthly subscription product ID.
    static let iapMonthlyProductId = "\(bundleId).pro.monthly"

    /// Annual subscription product ID.
    static let iapAnnualProductId = "\(bundleId).pro.annual"

    // MARK: - Keychain Keys (derived from prefix)

    static let keychainAccount = defaultsPrefix

    // MARK: - Dispatch Queues

    static let pipelineQueue = "\(queuePrefix).pipeline"
    static let environmentMonitorQueue = "\(queuePrefix).environmentmonitor"
    static let ldrawQueue = "\(queuePrefix).ldraw"
    static let pieceImageQueue = "\(queuePrefix).pieceimage"
    static let performanceQueue = "\(queuePrefix).performance"
    static let correctionLoggerQueue = "\(queuePrefix).correctionlogger"

    // MARK: - UserDefaults Keys

    static let dailyScanCountKey = "\(defaultsPrefix).daily.scanCount"
    static let dailyScanDateKey = "\(defaultsPrefix).daily.scanDate"
    static let analyticsEnabledKey = "\(defaultsPrefix).analytics.enabled"
    static let developerProOverrideKey = "\(defaultsPrefix).developer.proOverride"

    // MARK: - Notifications

    static let minifigureScanCompletedNotification = "\(appName).minifigureScanCompleted"

    // MARK: - Display

    /// Hashtag for sharing (no spaces, lowercase).
    static let hashtag = "#\(appName.lowercased())"

    /// Privacy policy URL (if hosted).
    static let privacyPolicyURL = "https://\(appName.lowercased()).app/privacy"

    /// Support email.
    static let supportEmail = "support@\(appName.lowercased()).app"
}
