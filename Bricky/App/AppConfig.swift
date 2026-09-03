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

    /// Bricky Pro product ID. A single one-time (non-consumable) unlock —
    /// there is no subscription.
    static let iapProProductId = "\(bundleId).pro"

    // MARK: - AI Subject Recognition (cloud, developer-only)

    /// Base URL of the server proxy that holds the Azure OpenAI key, verifies
    /// the developer-bypass token, enforces the monthly quota, and calls GPT-4o
    /// vision. The key is NEVER shipped in the app — the proxy is the only place
    /// that can reach Azure OpenAI. Cloud AI is a hidden, developer-only feature
    /// (unlocked by the in-app override); no normal user can reach it.
    /// Overridable at runtime via the `BRICKY_RECOGNITION_ENDPOINT` Info.plist
    /// value / environment.
    static var aiRecognitionEndpoint: URL? {
        if let raw = infoPlistString("BRICKY_RECOGNITION_ENDPOINT") ??
            ProcessInfo.processInfo.environment["BRICKY_RECOGNITION_ENDPOINT"],
           let url = URL(string: raw) {
            return url
        }
        return URL(string: "https://\(appName.lowercased())-recognition.azurewebsites.net/api/recognizeImage")
    }

    /// Server proxy endpoint that identifies a built LEGO set from a photo via
    /// GPT-4o vision. Same proxy deployment and key handling as
    /// `aiRecognitionEndpoint` — the Azure key is NEVER shipped in the app, and
    /// set identification is a hidden, developer-only feature (unlocked by the
    /// in-app override). Overridable via `BRICKY_SET_ID_ENDPOINT`.
    static var setIdentificationEndpoint: URL? {
        if let raw = infoPlistString("BRICKY_SET_ID_ENDPOINT") ??
            ProcessInfo.processInfo.environment["BRICKY_SET_ID_ENDPOINT"],
           let url = URL(string: raw) {
            return url
        }
        return URL(string: "https://\(appName.lowercased())-recognition.azurewebsites.net/api/identifySet")
    }

    /// Server proxy endpoint that forges a brick-compatible voxel model from a
    /// text description via GPT-4o (Set Forge Phase 2). Same proxy deployment and
    /// key handling as `aiRecognitionEndpoint` — the Azure key is NEVER shipped in
    /// the app, and cloud model generation is a hidden, developer-only feature
    /// (unlocked by the in-app override). Overridable via `BRICKY_FORGE_TEXT_ENDPOINT`.
    /// When unset/unreachable, the app falls back to the on-device shape library.
    static var forgeFromTextEndpoint: URL? {
        if let raw = infoPlistString("BRICKY_FORGE_TEXT_ENDPOINT") ??
            ProcessInfo.processInfo.environment["BRICKY_FORGE_TEXT_ENDPOINT"],
           let url = URL(string: raw) {
            return url
        }
        return URL(string: "https://\(appName.lowercased())-recognition.azurewebsites.net/api/forgeFromText")
    }

    /// Server proxy endpoint that forges a high-fidelity 3D **mesh** from a text
    /// description via a hosted vendor (Tripo), returning a model URL the app
    /// downloads and voxelizes. Premium Set Forge tier; same developer-only,
    /// key-on-server handling as the other cloud features. When unset/unreachable
    /// the app falls back to the GPT voxel path, then the on-device library.
    /// Overridable via `BRICKY_FORGE_MESH_ENDPOINT`.
    static var forgeMeshFromTextEndpoint: URL? {
        if let raw = infoPlistString("BRICKY_FORGE_MESH_ENDPOINT") ??
            ProcessInfo.processInfo.environment["BRICKY_FORGE_MESH_ENDPOINT"],
           let url = URL(string: raw) {
            return url
        }
        return URL(string: "https://\(appName.lowercased())-recognition.azurewebsites.net/api/forgeMeshFromText")
    }

    /// Server proxy endpoint that forges a high-fidelity 3D **mesh** from a
    /// photo via the configured hosted vendor, returning a model URL the app
    /// downloads and voxelizes. Premium Set Forge (Scan to Set) tier; same
    /// developer-only, key-on-server handling. Overridable via
    /// `BRICKY_FORGE_MESH_IMAGE_ENDPOINT`.
    static var forgeMeshFromImageEndpoint: URL? {
        if let raw = infoPlistString("BRICKY_FORGE_MESH_IMAGE_ENDPOINT") ??
            ProcessInfo.processInfo.environment["BRICKY_FORGE_MESH_IMAGE_ENDPOINT"],
           let url = URL(string: raw) {
            return url
        }
        return URL(string: "https://\(appName.lowercased())-recognition.azurewebsites.net/api/forgeMeshFromImage")
    }

    /// Server proxy endpoint that forges a genuinely 3D **mesh** from multiple
    /// angles (front/left/back/right) via the configured vendor's multiview
    /// model, returning a model URL the app downloads and voxelizes. Premium
    /// Set Forge (3D Scan) tier. Overridable via `BRICKY_FORGE_MESH_MV_ENDPOINT`.
    static var forgeMeshFromMultiviewEndpoint: URL? {
        if let raw = infoPlistString("BRICKY_FORGE_MESH_MV_ENDPOINT") ??
            ProcessInfo.processInfo.environment["BRICKY_FORGE_MESH_MV_ENDPOINT"],
           let url = URL(string: raw) {
            return url
        }
        return URL(string: "https://\(appName.lowercased())-recognition.azurewebsites.net/api/forgeMeshFromMultiview")
    }

    /// Server endpoint that ingests anonymized brick corrections/confirmations
    /// for crowdsourced scanner accuracy. Overridable via
    /// `BRICKY_CONTRIBUTE_FLAG_ENDPOINT`.
    static var contributeFlagEndpoint: URL? {
        if let raw = infoPlistString("BRICKY_CONTRIBUTE_FLAG_ENDPOINT") ??
            ProcessInfo.processInfo.environment["BRICKY_CONTRIBUTE_FLAG_ENDPOINT"],
           let url = URL(string: raw) {
            return url
        }
        return URL(string: "https://\(appName.lowercased())-recognition.azurewebsites.net/api/contributeFlag")
    }

    /// Server endpoint that serves the crowdsourced correction index (promoted
    /// consensus labels) to ALL users — reading improvements is open; only
    /// contributing is gated. Overridable via `BRICKY_CORRECTION_INDEX_ENDPOINT`.
    static var correctionIndexEndpoint: URL? {
        if let raw = infoPlistString("BRICKY_CORRECTION_INDEX_ENDPOINT") ??
            ProcessInfo.processInfo.environment["BRICKY_CORRECTION_INDEX_ENDPOINT"],
           let url = URL(string: raw) {
            return url
        }
        return URL(string: "https://\(appName.lowercased())-recognition.azurewebsites.net/api/correctionIndex")
    }

    /// Monthly AI recognition allowance. Cloud AI is developer-only, so this is
    /// just a safety cap on the developer's own Azure GPT-4o spend; it keeps
    /// total spend under the development cost cap while testing. Everyone without
    /// the developer override gets zero.
    static let proMonthlyAIRecognitionLimit = 100

    /// Developer-bypass entitlement token for AI recognition. When Pro is
    /// granted via the in-app developer override (the 7-tap toggle), there is
    /// no real StoreKit receipt to send the proxy, so the app instead sends
    /// this `dev-override:<secret>` token. The proxy ONLY honors it when its
    /// `DEV_BYPASS_TOKEN` app setting matches the `<secret>` portion — and that
    /// setting is left UNSET in production, so this path is inert there.
    ///
    /// Overridable at runtime via the `BRICKY_RECOGNITION_DEV_TOKEN` Info.plist
    /// value / environment. The baked secret must match the proxy's
    /// `DEV_BYPASS_TOKEN` app setting (see services/recognition-proxy/README).
    static var aiRecognitionDevBypassToken: String? {
        if let raw = infoPlistString("BRICKY_RECOGNITION_DEV_TOKEN") ??
            ProcessInfo.processInfo.environment["BRICKY_RECOGNITION_DEV_TOKEN"],
           !raw.isEmpty {
            return raw
        }
        return "dev-override:8f3c2a9e7b14d05f96a1c3e8d2b47f60"
    }

    private static func infoPlistString(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }

    // MARK: - Rebrickable API

    /// Server proxy that returns a set's full parts list using the team's
    /// Rebrickable key from Key Vault. Checked first; if it has no key the app
    /// falls back to a personal key. Overridable via `BRICKY_SET_PARTS_ENDPOINT`.
    static var setPartsEndpoint: URL? {
        if let raw = infoPlistString("BRICKY_SET_PARTS_ENDPOINT") ??
            ProcessInfo.processInfo.environment["BRICKY_SET_PARTS_ENDPOINT"],
           let url = URL(string: raw) {
            return url
        }
        return URL(string: "https://\(appName.lowercased())-recognition.azurewebsites.net/api/setParts")
    }

    /// Key for the user's personal Rebrickable key, stored on-device and synced
    /// via iCloud key-value store. Only used as a fallback when the proxy/Key
    /// Vault has none.
    static let rebrickableAPIKeyDefaultsKey = "\(defaultsPrefix).rebrickable.apiKey"

    /// Effective personal Rebrickable key (nil when unset). Reads the env/Info
    /// override, then UserDefaults, then the iCloud KV store. Server BOM lookups
    /// don't need this — it's the on-device fallback.
    static var rebrickableAPIKey: String? {
        if let raw = infoPlistString("BRICKY_REBRICKABLE_API_KEY") ??
            ProcessInfo.processInfo.environment["BRICKY_REBRICKABLE_API_KEY"],
           !raw.isEmpty {
            return raw
        }
        let local = UserDefaults.standard.string(forKey: rebrickableAPIKeyDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let local, !local.isEmpty { return local }
        let cloud = NSUbiquitousKeyValueStore.default.string(forKey: rebrickableAPIKeyDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (cloud?.isEmpty == false) ? cloud : nil
    }

    /// Shared minifig-lookup key (free tier), used by `BrickognizeService` only
    /// as a fallback when the proxy/Key Vault has none.
    static let rebrickableMinifigKey = "f80c762a9866cefa7111f5cabd5556dd"

    /// Proxy minifig search endpoint that uses the Key Vault Rebrickable key.
    /// Checked first; the bundled key is a fallback. Overridable via
    /// `BRICKY_MINIFIG_SEARCH_ENDPOINT`.
    static var minifigSearchEndpoint: URL? {
        if let raw = infoPlistString("BRICKY_MINIFIG_SEARCH_ENDPOINT") ??
            ProcessInfo.processInfo.environment["BRICKY_MINIFIG_SEARCH_ENDPOINT"],
           let url = URL(string: raw) {
            return url
        }
        return URL(string: "https://\(appName.lowercased())-recognition.azurewebsites.net/api/minifigSearch")
    }

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

    /// Count of AI subject recognitions used in the current calendar month.
    static let aiRecognitionCountKey = "\(defaultsPrefix).ai.recognitionCount"

    /// First-day-of-month marker (yyyy-MM) the count above belongs to, so it
    /// resets automatically when the month rolls over.
    static let aiRecognitionMonthKey = "\(defaultsPrefix).ai.recognitionMonth"

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