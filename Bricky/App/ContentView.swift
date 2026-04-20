import SwiftUI

struct ContentView: View {
    @State private var hasCompletedOnboarding = UserDefaults.standard.bool(forKey: UserDefaultsKey.hasCompletedOnboarding)

    /// Use device idiom instead of horizontalSizeClass — on Plus/Pro Max iPhones,
    /// landscape flips horizontalSizeClass to .regular which would otherwise tear
    /// down the NavigationStack and dump the user back on Home.
    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    var body: some View {
        if hasCompletedOnboarding {
            if isPad {
                iPadLayout
            } else {
                NavigationStack {
                    HomeView()
                }
            }
        } else {
            OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
        }
    }

    // MARK: - iPad Layout

    private var iPadLayout: some View {
        AdaptiveSplitView()
    }
}

// MARK: - iPad Adaptive Split View

/// Sidebar-based navigation for iPad with split view layout
struct AdaptiveSplitView: View {
    @State private var selectedTab: SidebarTab? = .home
    @StateObject private var cameraViewModel = CameraViewModel()

    enum SidebarTab: String, CaseIterable, Identifiable {
        case home = "Home"
        case scan = "Scan"
        case catalog = "Catalog"
        case builds = "Builds"
        case community = "Community"
        case games = "Games"
        case settings = "Settings"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .home: return "house.fill"
            case .scan: return "camera.viewfinder"
            case .catalog: return "tray.full.fill"
            case .builds: return "hammer.fill"
            case .community: return "person.3.fill"
            case .games: return "puzzlepiece.fill"
            case .settings: return "gearshape"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(SidebarTab.allCases, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
            .navigationTitle("\(AppConfig.appName)")
            .listStyle(.sidebar)
        } detail: {
            NavigationStack {
                switch selectedTab {
                case .home, .none:
                    HomeView()
                case .scan:
                    CameraScanView()
                case .catalog:
                    if !cameraViewModel.scanSession.pieces.isEmpty {
                        PieceCatalogView(pieces: cameraViewModel.scanSession.pieces)
                    } else {
                        ContentUnavailableView(
                            "No Pieces Yet",
                            systemImage: "tray",
                            description: Text("Scan some LEGO bricks to see your catalog")
                        )
                    }
                case .builds:
                    if !cameraViewModel.scanSession.pieces.isEmpty {
                        BuildSuggestionsView(pieces: cameraViewModel.scanSession.pieces)
                    } else {
                        ContentUnavailableView(
                            "No Pieces Yet",
                            systemImage: "hammer",
                            description: Text("Scan some LEGO bricks to see build suggestions")
                        )
                    }
                case .community:
                    CommunityFeedView()
                case .games:
                    PuzzleView()
                case .settings:
                    SettingsView()
                }
            }
        }
    }
}
