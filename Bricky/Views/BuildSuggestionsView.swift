import SwiftUI

/// Shows suggested builds based on available pieces
struct BuildSuggestionsView: View {
    @StateObject private var viewModel = BuildSuggestionsViewModel()
    @StateObject private var favoritesStore = FavoritesStore.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var subscription = SubscriptionManager.shared
    @State private var showOnlyFavorites = false
    @State private var showPaywall = false
    let pieces: [LegoPiece]

    var body: some View {
        VStack(spacing: 0) {
            // First-use tip
            FeatureTipView(
                tip: .firstBuildSuggestion,
                icon: "hammer.fill",
                title: "Build Ideas",
                message: "These builds are matched to your scanned pieces. The percentage shows how many required pieces you have. Tap any build for step-by-step instructions.",
                color: Color.legoGreen
            )
            .padding(.horizontal)
            .padding(.top, 8)

            // Stats header
            statsHeader

            // Filter bar
            filterBar

            // Content
            if viewModel.isLoading {
                loadingView
            } else if viewModel.filteredSuggestions.isEmpty {
                emptyState
            } else {
                suggestionsList
            }
        }
        .navigationTitle("Build Ideas")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.generateSuggestions(from: pieces)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    // MARK: - Stats Header

    private var statsHeader: some View {
        HStack(spacing: 20) {
            VStack(spacing: 2) {
                Text("\(viewModel.completeBuildCount)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.green)
                Text("Ready to Build")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()
                .frame(height: 32)

            VStack(spacing: 2) {
                Text("\(viewModel.partialBuildCount)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.legoOrange)
                Text("Almost There")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()
                .frame(height: 32)

            VStack(spacing: 2) {
                Text("\(viewModel.suggestions.count)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.legoBlue)
                Text("Total Ideas")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Completable toggle
                Button {
                    viewModel.showOnlyCompletable.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: viewModel.showOnlyCompletable ? "checkmark.circle.fill" : "circle")
                        Text("Ready to Build")
                    }
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(viewModel.showOnlyCompletable ? Color.green.opacity(0.15) : Color.gray.opacity(0.1))
                    .foregroundStyle(viewModel.showOnlyCompletable ? .green : .primary)
                    .clipShape(Capsule())
                }

                // Favorites toggle
                Button {
                    showOnlyFavorites.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showOnlyFavorites ? "heart.fill" : "heart")
                        Text("Favorites")
                    }
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(showOnlyFavorites ? themeManager.colorTheme.primary.opacity(0.15) : Color.gray.opacity(0.1))
                    .foregroundStyle(showOnlyFavorites ? themeManager.colorTheme.primary : .primary)
                    .clipShape(Capsule())
                }

                // Category filter
                Menu {
                    Button("All Categories") {
                        viewModel.selectedCategory = nil
                    }
                    Divider()
                    ForEach(ProjectCategory.allCases, id: \.self) { cat in
                        Button {
                            viewModel.selectedCategory = cat
                        } label: {
                            Label(cat.rawValue, systemImage: cat.systemImage)
                        }
                    }
                } label: {
                    filterChip(
                        label: viewModel.selectedCategory?.rawValue ?? "Category",
                        active: viewModel.selectedCategory != nil
                    )
                }

                // Difficulty filter
                Menu {
                    Button("All Difficulties") {
                        viewModel.selectedDifficulty = nil
                    }
                    Divider()
                    ForEach(Difficulty.allCases, id: \.self) { diff in
                        Button(diff.rawValue) {
                            viewModel.selectedDifficulty = diff
                        }
                    }
                } label: {
                    filterChip(
                        label: viewModel.selectedDifficulty?.rawValue ?? "Difficulty",
                        active: viewModel.selectedDifficulty != nil
                    )
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    private func filterChip(label: String, active: Bool) -> some View {
        Text(label)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(active ? Color.legoBlue.opacity(0.15) : Color.gray.opacity(0.1))
            .foregroundStyle(active ? Color.legoBlue : Color.primary)
            .clipShape(Capsule())
    }

    // MARK: - Suggestions List

    private var suggestionsList: some View {
        let displaySuggestions = showOnlyFavorites
            ? viewModel.filteredSuggestions.filter { favoritesStore.isFavorited($0.project.id) }
            : viewModel.filteredSuggestions

        return ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(Array(displaySuggestions.enumerated()), id: \.element.id) { index, suggestion in
                    if subscription.canViewBuild(at: index) {
                        NavigationLink(destination: BuildDetailView(suggestion: suggestion, availablePieces: pieces)) {
                            BuildSuggestionCard(
                                suggestion: suggestion,
                                isFavorited: favoritesStore.isFavorited(suggestion.project.id),
                                onToggleFavorite: {
                                    favoritesStore.toggle(suggestion.project.id)
                                    HapticManager.selection()
                                }
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(suggestion.project.name), \(suggestion.percentageText) match, \(suggestion.project.difficulty.rawValue) difficulty, \(suggestion.project.estimatedMinutes) minutes")
                        .accessibilityHint("Opens build details and instructions")
                    } else {
                        Button {
                            showPaywall = true
                        } label: {
                            BuildSuggestionCard(
                                suggestion: suggestion,
                                isFavorited: favoritesStore.isFavorited(suggestion.project.id),
                                onToggleFavorite: { }
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.ultraThinMaterial)
                                VStack(spacing: 4) {
                                    Image(systemName: "lock.fill")
                                        .font(.title3)
                                        .foregroundStyle(Color.legoBlue)
                                    Text("Pro")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Color.legoBlue)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text("Finding cool things to build...")
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Matching Builds", systemImage: "hammer.circle")
        } description: {
            Text("Try scanning more pieces or adjusting your filters.")
        } actions: {
            Button("Clear Filters") {
                viewModel.selectedCategory = nil
                viewModel.selectedDifficulty = nil
                viewModel.showOnlyCompletable = false
                showOnlyFavorites = false
            }
            .buttonStyle(.bordered)
        }
    }
}

// MARK: - Build Suggestion Card

struct BuildSuggestionCard: View {
    let suggestion: BuildSuggestionEngine.BuildSuggestion
    var isFavorited: Bool = false
    var onToggleFavorite: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                // Project icon
                Image(systemName: suggestion.project.imageSystemName)
                    .font(.title)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                suggestion.isCompleteBuild ?
                                LinearGradient(colors: [.green, .green.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing) :
                                LinearGradient(colors: [.legoBlue, .legoBlue.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                    )

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(suggestion.project.name)
                            .font(.headline)

                        Spacer()

                        // Favorite button
                        if let onToggleFavorite {
                            Button {
                                onToggleFavorite()
                            } label: {
                                Image(systemName: isFavorited ? "heart.fill" : "heart")
                                    .foregroundStyle(isFavorited ? Color.legoRed : .secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(isFavorited ? "Remove from favorites" : "Add to favorites")
                        }

                        // Match percentage badge
                        Text(suggestion.percentageText)
                            .font(.caption)
                            .fontWeight(.bold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(matchColor.opacity(0.15))
                            .foregroundStyle(matchColor)
                            .clipShape(Capsule())
                    }

                    Text(suggestion.project.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            // Bottom info row
            HStack {
                // Difficulty
                HStack(spacing: 2) {
                    ForEach(0..<suggestion.project.difficulty.stars, id: \.self) { _ in
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                    }
                }
                .foregroundStyle(difficultyColor)

                Text(suggestion.project.difficulty.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                Label("~\(suggestion.project.estimatedMinutes) min", systemImage: "clock")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                Label(suggestion.project.category.rawValue, systemImage: suggestion.project.category.systemImage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Missing pieces indicator
            if !suggestion.isCompleteBuild && !suggestion.missingPieces.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text("Missing \(suggestion.missingPieces.count) piece type(s)")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            // Match progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(matchColor)
                        .frame(width: geo.size.width * suggestion.matchPercentage, height: 4)
                }
            }
            .frame(height: 4)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
        )
    }

    private var matchColor: Color {
        if suggestion.matchPercentage >= 1.0 { return .green }
        if suggestion.matchPercentage >= 0.7 { return .legoOrange }
        return .legoBlue
    }

    private var difficultyColor: Color {
        switch suggestion.project.difficulty {
        case .beginner, .easy: return .green
        case .medium: return .yellow
        case .hard: return .orange
        case .expert: return .red
        }
    }
}
