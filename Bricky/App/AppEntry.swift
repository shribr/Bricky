import SwiftUI

@main
struct AppEntry: App {
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @StateObject private var analyticsService = AnalyticsService.shared
    @StateObject private var authService = AuthenticationService.shared

    init() {
        // UI Testing support: skip onboarding if launch argument is set
        if CommandLine.arguments.contains("--skip-onboarding") {
            UserDefaults.standard.set(true, forKey: UserDefaultsKey.hasCompletedOnboarding)
        }
        if CommandLine.arguments.contains("--reset-onboarding") {
            UserDefaults.standard.set(false, forKey: UserDefaultsKey.hasCompletedOnboarding)
        }

        // Boost URLCache so minifig thumbnails (and other CDN images) survive
        // scroll recycling instead of re-fetching from the network each time.
        let cache = URLCache(
            memoryCapacity: 64 * 1024 * 1024,
            diskCapacity: 512 * 1024 * 1024,
            diskPath: AppConfig.urlCachePath
        )
        URLCache.shared = cache
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(themeManager.colorTheme.primary)
                .preferredColorScheme(themeManager.appearanceMode.colorScheme)
                .environmentObject(themeManager)
                .task {
                    AnalyticsService.shared.track(.appLaunched)
                    Task.detached(priority: .utility) {
                        _ = LDrawLibrary.shared.isAvailable
                    }
                    Task { await MinifigureCatalog.shared.load() }
                    Task { await MinifigureClassificationService.shared.loadModel() }
                }
        }
    }
}
