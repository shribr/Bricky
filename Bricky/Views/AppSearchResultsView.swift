import SwiftUI

/// Grouped, app-wide search results (features, settings, help, tutorials, ...).
/// Shown over the Settings form while the Settings search field has text.
struct AppSearchResultsView: View {
    let query: String
    /// Settings results are resolved by the host screen (expand + scroll).
    let onSelectSetting: (SettingsAnchor) -> Void

    @State private var groups: [AppSearchGroup] = []
    @State private var hasSearched = false
    @State private var presentedSheet: PresentedSheet?

    private var tokens: [String] { AppSearchText.tokens(query) }
    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private enum PresentedSheet: Identifiable {
        case help(question: String)
        case scanGuide(page: Int)
        case welcomeTour(page: Int)
        case buildExplainer
        case privacy
        case paywall

        var id: String {
            switch self {
            case .help(let question): return "help.\(question)"
            case .scanGuide(let page): return "scan.\(page)"
            case .welcomeTour(let page): return "tour.\(page)"
            case .buildExplainer: return "build"
            case .privacy: return "privacy"
            case .paywall: return "paywall"
            }
        }
    }

    var body: some View {
        Group {
            if trimmedQuery.count < AppSearchService.minimumQueryLength {
                ContentUnavailableView(
                    "Search \(AppConfig.appName)",
                    systemImage: "magnifyingglass",
                    description: Text("Type at least \(AppSearchService.minimumQueryLength) characters to search features, settings, help, tutorials and more.")
                )
            } else if hasSearched && groups.isEmpty {
                ContentUnavailableView.search(text: trimmedQuery)
            } else {
                resultsList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .task(id: query) {
            guard trimmedQuery.count >= AppSearchService.minimumQueryLength else {
                groups = []
                hasSearched = false
                return
            }
            // Debounce keystrokes; the task is cancelled when `query` changes.
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            groups = AppSearchService.shared.search(trimmedQuery)
            hasSearched = true
        }
        .sheet(item: $presentedSheet) { sheet in
            sheetContent(for: sheet)
        }
    }

    // MARK: - List

    private var resultsList: some View {
        List {
            ForEach(groups) { group in
                Section {
                    ForEach(group.results) { result in
                        row(for: result)
                    }
                } header: {
                    Label("\(group.category.title) (\(group.totalCount))", systemImage: group.category.icon)
                } footer: {
                    if group.isTruncated {
                        Text("Showing the first \(group.results.count) of \(group.totalCount). Add more words to narrow the results.")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private func row(for result: AppSearchResult) -> some View {
        let entry = result.entry
        switch entry.destination {
        case .feature, .tips, .buildIdea, .set, .minifigure:
            NavigationLink {
                pushedDestination(for: entry.destination)
            } label: {
                rowLabel(entry)
            }
        case .setting(let anchor):
            Button { onSelectSetting(anchor) } label: { rowLabel(entry, showsChevron: true) }
                .buttonStyle(.plain)
        case .helpArticle(let question):
            Button { presentedSheet = .help(question: question) } label: { rowLabel(entry, showsChevron: true) }
                .buttonStyle(.plain)
        case .tutorial(let tutorial):
            Button {
                switch tutorial {
                case .scanGuide(let page): presentedSheet = .scanGuide(page: page)
                case .welcomeTour(let page): presentedSheet = .welcomeTour(page: page)
                case .buildExplainer: presentedSheet = .buildExplainer
                }
            } label: { rowLabel(entry, showsChevron: true) }
                .buttonStyle(.plain)
        case .privacyPolicy:
            Button { presentedSheet = .privacy } label: { rowLabel(entry, showsChevron: true) }
                .buttonStyle(.plain)
        case .paywall:
            Button { presentedSheet = .paywall } label: { rowLabel(entry, showsChevron: true) }
                .buttonStyle(.plain)
        }
    }

    private func rowLabel(_ entry: AppSearchEntry, showsChevron: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.icon)
                .font(.callout)
                .foregroundStyle(Color.legoBlue)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(highlighted(entry.title))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                if let breadcrumb = entry.breadcrumb {
                    Text(breadcrumb)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if !entry.body.isEmpty {
                    Text(highlighted(AppSearchText.snippet(of: entry.body, tokens: tokens)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 0)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func highlighted(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        for range in AppSearchText.matchRanges(of: tokens, in: text) {
            if let attributedRange = Range(range, in: attributed) {
                attributed[attributedRange].inlinePresentationIntent = .stronglyEmphasized
                attributed[attributedRange].backgroundColor = Color.legoYellow.opacity(0.35)
            }
        }
        return attributed
    }

    // MARK: - Destinations

    @ViewBuilder
    private func pushedDestination(for destination: AppSearchDestination) -> some View {
        switch destination {
        case .feature(let feature):
            featureView(feature)
        case .tips:
            TipsListView()
        case .buildIdea(let id):
            if let project = BuildSuggestionEngine.shared.allProjects.first(where: { $0.id == id }) {
                BuildDetailView(
                    suggestion: BuildSuggestionEngine.BuildSuggestion(
                        project: project,
                        matchPercentage: 0,
                        missingPieces: project.requiredPieces
                    ),
                    availablePieces: []
                )
            } else {
                unavailable
            }
        case .set(let number):
            if let legoSet = LegoSetCatalog.shared.set(byNumber: number) {
                SetDetailView(legoSet: legoSet)
            } else {
                unavailable
            }
        case .minifigure(let id):
            if let figure = MinifigureCatalog.shared.allFigures.first(where: { $0.id == id }) {
                MinifigureDetailView(figure: figure)
            } else {
                unavailable
            }
        default:
            unavailable
        }
    }

    private var unavailable: some View {
        ContentUnavailableView("Not Available", systemImage: "questionmark.folder")
    }

    @ViewBuilder
    private func featureView(_ feature: AppFeature) -> some View {
        switch feature {
        case .scanner: PreScanAnalysisView()
        case .findABrick: FindABrickHubView()
        case .seeWhatYouCanBuild: BuildFeatureExplainerView(hasRecentPieces: false)
        case .mosaicStudio: MosaicGeneratorView()
        case .setCollection: SetCollectionView()
        case .setModels: SetModelsView()
        case .storageBins: StorageView()
        case .community: CommunityFeedView()
        case .puzzles: PuzzleView()
        case .minifigureCatalog: MinifigureCatalogView()
        case .scanToSet: ScanToSetView()
        case .describeSet: DescribeSetView()
        case .forgedSets: GeneratedSetsGalleryView()
        case .scanOneBrick: ScanBrickView()
        case .rebuildableSets: RebuildableSetsView()
        case .colorCalibration: ColorCalibrationWizardView()
        }
    }

    @ViewBuilder
    private func sheetContent(for sheet: PresentedSheet) -> some View {
        switch sheet {
        case .help(let question): HelpView(initialSearch: question)
        case .scanGuide(let page): ScanGuideView(startPage: page)
        case .welcomeTour(let page): ReplayOnboardingView(startPage: page)
        case .buildExplainer: BuildFeatureExplainerView(hasRecentPieces: false)
        case .privacy: PrivacyPolicyView()
        case .paywall: PaywallView()
        }
    }
}
