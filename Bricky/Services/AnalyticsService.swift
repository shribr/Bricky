import Foundation

/// Analytics event types tracked throughout the app.
enum AnalyticsEvent: String, CaseIterable {
    case appLaunched = "app_launched"
    case onboardingCompleted = "onboarding_completed"
    case scanStarted = "scan_started"
    case scanCompleted = "scan_completed"
    case buildViewed = "build_viewed"
    case aiIdeasGenerated = "ai_ideas_generated"
    case stlExported = "stl_exported"
    case subscriptionStarted = "subscription_started"
    case paywallViewed = "paywall_viewed"
    case paywallDismissed = "paywall_dismissed"
    case inventoryExported = "inventory_exported"
    case pieceSearched = "piece_searched"
}

/// Protocol for swappable analytics backends.
protocol AnalyticsProvider {
    func track(event: AnalyticsEvent, properties: [String: String])
}

/// Centralized analytics service with opt-in/out and swappable providers.
@MainActor
final class AnalyticsService: ObservableObject {
    static let shared = AnalyticsService()

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: enabledKey) }
    }

    private let enabledKey = AppConfig.analyticsEnabledKey
    private var providers: [AnalyticsProvider] = []

    private init() {
        // Default to opt-in for analytics
        let hasSetPref = UserDefaults.standard.object(forKey: enabledKey) != nil
        isEnabled = hasSetPref ? UserDefaults.standard.bool(forKey: enabledKey) : true
        providers.append(LocalAnalyticsProvider())
    }

    /// Add an analytics provider (e.g., Azure Application Insights, Firebase).
    func addProvider(_ provider: AnalyticsProvider) {
        providers.append(provider)
    }

    /// Track an analytics event with optional properties.
    func track(_ event: AnalyticsEvent, properties: [String: String] = [:]) {
        guard isEnabled else { return }
        for provider in providers {
            provider.track(event: event, properties: properties)
        }
    }

    /// URL of the local analytics log file.
    var localLogURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("analytics.jsonl")
    }

    /// Number of locally logged events.
    var localEventCount: Int {
        guard let data = try? Data(contentsOf: localLogURL),
              let content = String(data: data, encoding: .utf8) else { return 0 }
        return content.components(separatedBy: "\n").filter { !$0.isEmpty }.count
    }

    /// Clear local analytics log.
    func clearLocalLog() {
        try? FileManager.default.removeItem(at: localLogURL)
    }
}

/// Local analytics provider that appends events to a JSONL file for debugging.
struct LocalAnalyticsProvider: AnalyticsProvider {
    func track(event: AnalyticsEvent, properties: [String: String]) {
        let entry: [String: Any] = [
            "event": event.rawValue,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "properties": properties
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: entry),
              let line = String(data: data, encoding: .utf8) else { return }

        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("analytics.jsonl")

        let lineData = (line + "\n").data(using: .utf8) ?? Data()

        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(lineData)
                try? handle.close()
            }
        } else {
            try? lineData.write(to: url, options: .atomic)
        }
    }
}
