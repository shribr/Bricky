import SwiftUI

/// Comprehensive help center with categorized guides, FAQs, and quick links.
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var showScanGuide = false
    @State private var showOnboarding = false

    private var filteredSections: [HelpSection] {
        if searchText.isEmpty { return helpSections }
        return helpSections.compactMap { section in
            let matchingItems = section.items.filter {
                $0.question.localizedCaseInsensitiveContains(searchText) ||
                $0.answer.localizedCaseInsensitiveContains(searchText)
            }
            if matchingItems.isEmpty { return nil }
            return HelpSection(title: section.title, icon: section.icon, color: section.color, items: matchingItems)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // Quick Actions
                Section {
                    Button {
                        showOnboarding = true
                    } label: {
                        Label("Replay Welcome Tour", systemImage: "arrow.counterclockwise")
                    }

                    Button {
                        showScanGuide = true
                    } label: {
                        Label("Scanning Tutorial", systemImage: "camera.viewfinder")
                    }

                    NavigationLink {
                        TipsListView()
                    } label: {
                        Label("Feature Tips", systemImage: "lightbulb.fill")
                    }
                } header: {
                    Text("Quick Start")
                }

                // FAQ sections
                ForEach(filteredSections) { section in
                    Section {
                        ForEach(section.items) { item in
                            DisclosureGroup {
                                Text(item.answer)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 4)
                            } label: {
                                Label(item.question, systemImage: item.icon)
                                    .font(.subheadline)
                            }
                        }
                    } header: {
                        Label(section.title, systemImage: section.icon)
                    }
                }

                // About section
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                } header: {
                    Text("About")
                }
            }
            .searchable(text: $searchText, prompt: "Search help topics")
            .navigationTitle("Help & Support")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showScanGuide) {
                ScanGuideView()
            }
            .fullScreenCover(isPresented: $showOnboarding) {
                ReplayOnboardingView()
            }
        }
    }
}

// MARK: - Replay Onboarding (no completion binding needed)

private struct ReplayOnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentPage = 0

    private let pages: [ReplayPage] = [
        ReplayPage(icon: "camera.viewfinder", title: "Scan Your Bricks",
                   description: "Spread out your LEGO pieces and take a photo. \(AppConfig.appName) identifies every piece using on-device AI.",
                   color: Color.legoRed),
        ReplayPage(icon: "cube.fill", title: "Know What You Have",
                   description: "See a full inventory organized by type, color, and size. Edit, add, or remove pieces anytime.",
                   color: Color.legoBlue),
        ReplayPage(icon: "hammer.fill", title: "Discover What to Build",
                   description: "Get build suggestions matched to your pieces with step-by-step instructions.",
                   color: Color.legoGreen),
        ReplayPage(icon: "person.3.fill", title: "Join the Community",
                   description: "Share your builds, follow other builders, take daily challenges, and compete on puzzles.",
                   color: Color.legoOrange),
        ReplayPage(icon: "sparkles", title: "Powered by AI",
                   description: "All scanning runs on-device using Core ML for instant, private results.",
                   color: Color.legoYellow),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .padding()
            }

            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    VStack(spacing: 24) {
                        Spacer()
                        Image(systemName: page.icon)
                            .font(.system(size: 72))
                            .foregroundStyle(page.color)
                        Text(page.title)
                            .font(.title)
                            .fontWeight(.bold)
                        Text(page.description)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Spacer()
                        Spacer()
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            Button {
                if currentPage < pages.count - 1 {
                    withAnimation { currentPage += 1 }
                } else {
                    dismiss()
                }
            } label: {
                Text(currentPage < pages.count - 1 ? "Next" : "Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
    }
}

private struct ReplayPage {
    let icon: String
    let title: String
    let description: String
    let color: Color
}

// MARK: - Feature Tips List

/// Shows all available feature tips — users can learn about features they might have missed.
struct TipsListView: View {
    private let tips: [FeatureTipInfo] = [
        FeatureTipInfo(icon: "camera.viewfinder", color: Color.legoRed, title: "Scanning Modes",
                       detail: "\(AppConfig.appName) offers two scanning modes. Regular mode continuously captures pieces as you move the camera. Detailed mode divides the view into a grid and guides you through each segment for thorough coverage. Switch between them in Settings."),
        FeatureTipInfo(icon: "cube.fill", color: Color.legoBlue, title: "Save Your Inventory",
                       detail: "After scanning, tap \"Save\" to keep your inventory. You can name it, add notes, and access it later from the Home screen. Merge multiple scans into one inventory for a complete collection view."),
        FeatureTipInfo(icon: "hammer.fill", color: Color.legoGreen, title: "Build Suggestions",
                       detail: "View Results shows builds matched to your scanned pieces. The match percentage tells you how many required pieces you already own. Tap any build for step-by-step instructions."),
        FeatureTipInfo(icon: "person.3.fill", color: Color.legoOrange, title: "Community Features",
                       detail: "Share your builds with the community, comment on others' creations, and follow builders whose work you enjoy. Sign in with Apple to participate."),
        FeatureTipInfo(icon: "puzzlepiece.fill", color: .purple, title: "Puzzles & Games",
                       detail: "Try Build Puzzles — guess a LEGO build from progressive clues. Check the daily challenge for a new build idea each day. Complete builds to maintain your streak!"),
        FeatureTipInfo(icon: "timer", color: .orange, title: "Timed Build Mode",
                       detail: "When viewing build instructions, tap \"Start Build Timer\" to race against the estimated time. The timer tracks your progress and celebrates when you finish."),
        FeatureTipInfo(icon: "flame.fill", color: Color.legoRed, title: "Build Streaks",
                       detail: "Complete a daily challenge or timed build each day to maintain your streak. Your streak count appears on the Home screen and your profile."),
        FeatureTipInfo(icon: "icloud.fill", color: .cyan, title: "iCloud Sync",
                       detail: "Enable iCloud Sync in Settings to keep your inventories, sets, and storage bins in sync across all your devices."),
        FeatureTipInfo(icon: "wand.and.stars", color: Color.legoYellow, title: "On-Device AI",
                       detail: "All scanning uses on-device Core ML for instant results with no internet needed. Your images never leave your device."),
        FeatureTipInfo(icon: "square.grid.3x3.fill", color: .teal, title: "Detailed Scan Mode",
                       detail: "For large collections, use Detailed mode. It divides your view into segments and guides you through each one, ensuring no piece is missed. Great for sorting trays and bins."),
    ]

    var body: some View {
        List(tips) { tip in
            DisclosureGroup {
                Text(tip.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } label: {
                Label(tip.title, systemImage: tip.icon)
                    .foregroundStyle(tip.color)
            }
        }
        .navigationTitle("Feature Tips")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FeatureTipInfo: Identifiable {
    let id = UUID()
    let icon: String
    let color: Color
    let title: String
    let detail: String
}

// MARK: - Help Data

private struct HelpSection: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let color: Color
    let items: [HelpItem]
}

private struct HelpItem: Identifiable {
    let id = UUID()
    let icon: String
    let question: String
    let answer: String
}

private let helpSections: [HelpSection] = [
    HelpSection(
        title: "Scanning",
        icon: "camera.viewfinder",
        color: Color.legoRed,
        items: [
            HelpItem(icon: "camera.fill",
                     question: "How do I scan my LEGO pieces?",
                     answer: "Go to the Scan tab and tap the video button to start the live preview. Point your camera at your LEGO pieces spread out on a flat surface. Once you see bounding boxes around pieces, tap the capture button (it turns red) to identify and catalog them."),
            HelpItem(icon: "questionmark.circle",
                     question: "Why aren't all my pieces detected?",
                     answer: "Ensure pieces are spread out with space between them on a contrasting surface. Good lighting helps significantly. Try Detailed mode for large collections — it guides you through segments to ensure full coverage. You can always add missed pieces manually."),
            HelpItem(icon: "bolt.fill",
                     question: "What's the difference between Regular and Detailed scan?",
                     answer: "Regular mode continuously captures pieces as you move the camera — fast and great for small to medium collections. Detailed mode divides the view into a grid and guides you through each segment, ensuring nothing is missed. Best for large or complex collections."),
            HelpItem(icon: "arkit",
                     question: "What is AR mode?",
                     answer: "AR mode uses augmented reality to track pieces in 3D space. It shows bounding boxes anchored to real-world positions. Works best on devices with LiDAR (iPad Pro, iPhone Pro). Falls back to standard camera if AR isn't available."),
            HelpItem(icon: "wifi.slash",
                     question: "Can I scan without internet?",
                     answer: "Yes, but there are now three scan modes. Strict Offline uses only bundled and user-owned local assets. Offline First can also use references that were already cached on your device, but it never downloads new ones during a scan. Assisted mode can download missing references and check Brickognize when local confidence is low."),
        ]
    ),
    HelpSection(
        title: "Inventory & Catalog",
        icon: "tray.full.fill",
        color: Color.legoBlue,
        items: [
            HelpItem(icon: "square.and.arrow.down",
                     question: "How do I save my scanned inventory?",
                     answer: "After scanning, tap the Save button in the toolbar. Give your inventory a name and optional notes. Saved inventories appear on the Home screen and can be opened anytime."),
            HelpItem(icon: "arrow.triangle.merge",
                     question: "Can I merge multiple scans?",
                     answer: "Yes! When saving, you can choose to merge with an existing inventory. This combines pieces from both scans, adding quantities for duplicates."),
            HelpItem(icon: "square.and.arrow.up",
                     question: "Can I export my inventory?",
                     answer: "Yes — from the inventory detail view, tap the share button to export as CSV or BrickLink XML format. CSV works with spreadsheets; XML can be imported into BrickLink for buying missing pieces."),
            HelpItem(icon: "pencil",
                     question: "How do I edit a piece after scanning?",
                     answer: "In the results or catalog view, tap any piece to see its details. You can adjust the quantity, change the color, or update the piece type if the AI got it wrong."),
        ]
    ),
    HelpSection(
        title: "Building",
        icon: "hammer.fill",
        color: Color.legoGreen,
        items: [
            HelpItem(icon: "lightbulb.fill",
                     question: "How do build suggestions work?",
                     answer: "After scanning, \(AppConfig.appName) matches your pieces against a library of builds. Each suggestion shows a match percentage — how many required pieces you already have. Tap a build for step-by-step instructions with your matching pieces highlighted."),
            HelpItem(icon: "timer",
                     question: "What is Timed Build mode?",
                     answer: "When viewing build instructions, tap \"Start Build Timer\" to race against the estimated time. You can pause, resume, or stop anytime. Completing a timed build counts toward your daily streak!"),
            HelpItem(icon: "cube.transparent.fill",
                     question: "What is the 3D model viewer?",
                     answer: "Some builds include a 3D model you can rotate and zoom. Tap the \"View 3D Model\" button in the instructions to explore the build from every angle."),
        ]
    ),
    HelpSection(
        title: "Community",
        icon: "person.3.fill",
        color: Color.legoOrange,
        items: [
            HelpItem(icon: "person.crop.circle",
                     question: "How do I join the community?",
                     answer: "Tap Community in the sidebar (iPad) or navigate to Community from Home. Sign in with your Apple ID to post builds, comment, and follow other builders. No separate account needed."),
            HelpItem(icon: "heart.fill",
                     question: "How do likes and comments work?",
                     answer: "Tap the heart icon to like a build. Tap the comment bubble to view and add comments. You can delete your own comments by swiping left."),
            HelpItem(icon: "person.badge.plus",
                     question: "How do I follow a builder?",
                     answer: "Visit a builder's profile and tap the Follow button. Their new posts will appear in your feed. You can see your follower and following counts on your profile."),
        ]
    ),
    HelpSection(
        title: "Puzzles & Games",
        icon: "puzzlepiece.fill",
        color: .purple,
        items: [
            HelpItem(icon: "puzzlepiece.fill",
                     question: "How do Build Puzzles work?",
                     answer: "Each puzzle gives you progressive clues about a LEGO build. Read the clues and choose your answer from multiple options. Fewer clues needed means a higher score! Check the Games tab to play."),
            HelpItem(icon: "calendar",
                     question: "What is the Daily Challenge?",
                     answer: "A new build challenge appears every day on the Home screen. Complete it by building the suggested project — it uses common pieces you likely have. Completing challenges maintains your build streak."),
            HelpItem(icon: "flame.fill",
                     question: "How do streaks work?",
                     answer: "Complete a daily challenge or timed build each day to maintain your streak. Your current streak count shows on the Home screen and your profile. Miss a day and it resets to zero!"),
        ]
    ),
    HelpSection(
        title: "Scan Locations",
        icon: "mappin.and.ellipse",
        color: Color.legoBlue,
        items: [
            HelpItem(icon: "mappin.circle.fill",
                     question: "How does location tagging work?",
                     answer: "When enabled, \(AppConfig.appName) tags each scan with where you found those pieces — like “at my friend’s house.” You’ll see a one-time prompt the first time you scan; you can change your choice anytime in Settings › Scan Locations."),
            HelpItem(icon: "lock.shield",
                     question: "Is my location private?",
                     answer: "Yes. Coordinates are stored only on your device and rounded to roughly 11 meters of precision — enough to remember a place, not enough to pinpoint a home. Place names show only the city/state, never the street address."),
            HelpItem(icon: "map",
                     question: "Where do I see my scans on a map?",
                     answer: "On the Home screen, tap the “Map” button in the Scan History header (it appears once at least one scan has a location). Each pin shows the piece count and date — tap to open that scan."),
            HelpItem(icon: "location.fill",
                     question: "What does the “Near Me” filter do?",
                     answer: "Tap “Near Me” in the Scan History header to filter to only the scans within your configured radius (default 0.5 km). Adjust the radius in Settings › Scan Locations."),
            HelpItem(icon: "mappin.slash",
                     question: "How do I forget all stored locations?",
                     answer: "In Settings › Scan Locations, tap “Forget Locations on Saved Scans.” This wipes coordinates from every saved scan in one tap. Future scans won’t be tagged unless you re-enable the toggle."),
        ]
    ),
    HelpSection(
        title: "Settings & Account",
        icon: "gearshape",
        color: .gray,
        items: [
            HelpItem(icon: "icloud",
                     question: "How does iCloud Sync work?",
                     answer: "Enable iCloud Sync in Settings to keep inventories, set collection, and storage bins synchronized across all your Apple devices signed into the same iCloud account."),
            HelpItem(icon: "crown.fill",
                     question: "What does \(AppConfig.appName) Pro include?",
                     answer: "Pro unlocks unlimited scans, all AI analysis modes, advanced export formats, 3D model viewing, and community features. You can also share Pro with your family via Family Sharing."),
            HelpItem(icon: "person.3.fill",
                     question: "How does Family Sharing work?",
                     answer: "If you subscribe to \(AppConfig.appName) Pro, your family members who are part of your Apple Family Sharing group automatically get Pro access too. Check Settings > Subscription to see Family Sharing status."),
        ]
    ),
]
