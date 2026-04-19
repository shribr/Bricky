import SwiftUI

/// Detailed view for a specific build project with instructions
struct BuildDetailView: View {
    let suggestion: BuildSuggestionEngine.BuildSuggestion
    let availablePieces: [LegoPiece]
    var scanImage: UIImage? = nil

    @StateObject private var favoritesStore = FavoritesStore.shared
    @State private var selectedTab: DetailTab = .overview
    @State private var completedSteps: Set<Int> = []
    @State private var showShareSheet = false
    @State private var showBuildStepViewer = false
    @State private var showShareToCommunity = false
    @State private var isTimerActive = false

    enum DetailTab: String, CaseIterable {
        case overview = "Overview"
        case pieces = "Pieces"
        case instructions = "Instructions"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("Tab", selection: $selectedTab) {
                ForEach(DetailTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            // Tab content
            switch selectedTab {
            case .overview:
                overviewTab
            case .pieces:
                piecesTab
            case .instructions:
                instructionsTab
            }
        }
        .navigationTitle(suggestion.project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    favoritesStore.toggle(suggestion.project.id)
                    HapticManager.selection()
                } label: {
                    Image(systemName: favoritesStore.isFavorited(suggestion.project.id) ? "heart.fill" : "heart")
                        .foregroundStyle(favoritesStore.isFavorited(suggestion.project.id) ? Color.legoRed : .secondary)
                }
                .accessibilityLabel(favoritesStore.isFavorited(suggestion.project.id) ? "Remove from favorites" : "Add to favorites")

                Button {
                    showShareSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share build")

                if AuthenticationService.shared.isSignedIn {
                    Button {
                        showShareToCommunity = true
                    } label: {
                        Image(systemName: "person.3.fill")
                    }
                    .accessibilityLabel("Share to community")
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [buildShareText])
        }
        .sheet(isPresented: $showShareToCommunity) {
            NavigationStack {
                ShareBuildSuggestionView(suggestion: suggestion)
            }
        }
        .sheet(isPresented: $showBuildStepViewer) {
            BuildStepViewer(project: suggestion.project)
        }
    }

    // MARK: - Overview Tab

    private var overviewTab: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Hero image area
                Image(systemName: suggestion.project.imageSystemName)
                    .font(.system(size: 64))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .background(
                        LinearGradient(
                            colors: [.legoBlue, .legoBlue.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                // Info grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    infoCard(icon: "clock", title: "Time", value: "~\(suggestion.project.estimatedMinutes) min")
                    infoCard(icon: "star.fill", title: "Difficulty", value: suggestion.project.difficulty.rawValue)
                    infoCard(icon: "cube.fill", title: "Pieces", value: "\(suggestion.project.requiredPieces.reduce(0) { $0 + $1.quantity })")
                    infoCard(icon: "percent", title: "Match", value: suggestion.percentageText)
                }

                // Description
                VStack(alignment: .leading, spacing: 8) {
                    Text("About")
                        .font(.headline)
                    Text(suggestion.project.description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Fun fact
                if let funFact = suggestion.project.funFact {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(Color.legoYellow)
                        Text(funFact)
                            .font(.callout)
                            .italic()
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.legoYellow.opacity(0.1))
                    )
                }

                // Build status
                if suggestion.isCompleteBuild {
                    Label("You have all the pieces to build this!", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.green.opacity(0.1))
                        )
                } else {
                    VStack(spacing: 8) {
                        Label("Missing some pieces", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline)
                            .foregroundStyle(.orange)

                        Text("You have \(suggestion.percentageText) of the required pieces")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.orange.opacity(0.1))
                    )
                }
            }
            .padding()
        }
    }

    private func infoCard(icon: String, title: String, value: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.legoBlue)
            Text(value)
                .font(.headline)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
        )
    }

    // MARK: - Pieces Tab

    private var piecesTab: some View {
        List {
            Section("Required Pieces") {
                ForEach(suggestion.project.requiredPieces) { required in
                    HStack(spacing: 12) {
                        // Status indicator
                        let isAvailable = hasPiece(required)
                        Image(systemName: isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(isAvailable ? .green : .red)

                        // Color swatch
                        if let color = required.colorPreference {
                            Circle()
                                .fill(Color.legoColor(color))
                                .frame(width: 24, height: 24)
                        } else {
                            Circle()
                                .fill(.gray.opacity(0.3))
                                .frame(width: 24, height: 24)
                                .overlay {
                                    Text("?")
                                        .font(.caption2)
                                }
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(required.displayName)
                                .font(.subheadline)
                            if required.flexible {
                                Text("Any color works")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            }
                        }

                        Spacer()

                        Text("×\(required.quantity)")
                            .font(.headline)
                            .monospacedDigit()
                    }
                }
            }

            if !suggestion.missingPieces.isEmpty {
                Section("Missing Pieces") {
                    ForEach(suggestion.missingPieces) { missing in
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)

                            Text(missing.displayName)
                                .font(.subheadline)

                            Spacer()

                            Text("Need \(missing.quantity)")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func hasPiece(_ required: RequiredPiece) -> Bool {
        let available = availablePieces.filter { piece in
            piece.category == required.category &&
            piece.dimensions.studsWide == required.dimensions.studsWide &&
            piece.dimensions.studsLong == required.dimensions.studsLong &&
            (required.flexible || required.colorPreference == nil || piece.color == required.colorPreference)
        }.reduce(0) { $0 + $1.quantity }
        return available >= required.quantity
    }

    /// Find the most relevant required piece for a given build step by parsing piecesUsed text
    private func findRequiredPiece(for step: BuildStep) -> RequiredPiece? {
        let stepText = step.piecesUsed.lowercased()
        return suggestion.project.requiredPieces.first { piece in
            let categoryMatch = stepText.contains(piece.category.rawValue.lowercased())
            let colorMatch = piece.colorPreference.map { stepText.contains($0.rawValue.lowercased()) } ?? false
            return categoryMatch || colorMatch
        } ?? suggestion.project.requiredPieces.first
    }

    // MARK: - Instructions Tab

    private var instructionsTab: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Build Timer
                if isTimerActive {
                    BuildTimerView(
                        estimatedTime: suggestion.project.estimatedTime,
                        isTimerActive: $isTimerActive,
                        onComplete: {
                            // Timer completed
                        }
                    )
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                } else {
                    FeatureTipView(
                        tip: .timedBuild,
                        icon: "timer",
                        title: "Timed Build Mode",
                        message: "Race against the estimated time! Start the timer, build, and tap complete when done. Counts toward your daily streak.",
                        color: .orange
                    )
                    .padding(.horizontal)

                    Button {
                        isTimerActive = true
                        HapticManager.impact()
                    } label: {
                        HStack {
                            Image(systemName: "timer")
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Start Build Timer")
                                    .font(.headline)
                                Text("Track your build time (\(suggestion.project.estimatedTime) est.)")
                                    .font(.caption)
                            }
                            Spacer()
                            Image(systemName: "play.fill")
                        }
                        .padding()
                        .foregroundStyle(.white)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.legoRed)
                        )
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }

                // 3D Viewer button
                Button {
                    showBuildStepViewer = true
                } label: {
                    HStack {
                        Image(systemName: "cube.transparent")
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("3D Step-by-Step")
                                .font(.headline)
                            Text("View assembly in interactive 3D")
                                .font(.caption)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding()
                    .foregroundStyle(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.legoBlue)
                    )
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
                .accessibilityLabel("Open 3D step-by-step viewer")
                ForEach(suggestion.project.instructions) { step in
                    VStack(spacing: 0) {
                        HStack(alignment: .top, spacing: 16) {
                            // Step number circle
                            ZStack {
                                Circle()
                                    .fill(completedSteps.contains(step.stepNumber) ? Color.green : Color.legoBlue)
                                    .frame(width: 36, height: 36)

                                if completedSteps.contains(step.stepNumber) {
                                    Image(systemName: "checkmark")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.white)
                                } else {
                                    Text("\(step.stepNumber)")
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.white)
                                }
                            }
                            .onTapGesture {
                                withAnimation {
                                    if completedSteps.contains(step.stepNumber) {
                                        completedSteps.remove(step.stepNumber)
                                    } else {
                                        completedSteps.insert(step.stepNumber)
                                        HapticManager.impact(.light)
                                    }
                                }
                            }
                            .accessibilityLabel("Step \(step.stepNumber), \(completedSteps.contains(step.stepNumber) ? "completed" : "not completed")")
                            .accessibilityHint("Double tap to toggle completion")
                            .accessibilityAddTraits(.isButton)

                            VStack(alignment: .leading, spacing: 8) {
                                Text(step.instruction)
                                    .font(.body)
                                    .strikethrough(completedSteps.contains(step.stepNumber))
                                    .foregroundStyle(completedSteps.contains(step.stepNumber) ? .secondary : .primary)

                                Label(step.piecesUsed, systemImage: "cube.fill")
                                    .font(.caption)
                                    .foregroundStyle(Color.legoBlue)

                                if let tip = step.tip {
                                    HStack(spacing: 4) {
                                        Image(systemName: "lightbulb.fill")
                                            .font(.caption2)
                                        Text(tip)
                                            .font(.caption)
                                            .italic()
                                    }
                                    .foregroundStyle(Color.legoOrange)
                                }

                                // Piece finder — find needed pieces in scan photo
                                if scanImage != nil, let matchingPiece = findRequiredPiece(for: step) {
                                    PieceFinderButton(
                                        requiredPiece: matchingPiece,
                                        scanImage: scanImage
                                    )
                                }
                            }
                        }
                        .padding()

                        // Connecting line
                        if step.stepNumber < suggestion.project.instructions.count {
                            HStack {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 2, height: 20)
                                    .padding(.leading, 17)
                                Spacer()
                            }
                        }
                    }
                }

                // Completion message
                if completedSteps.count == suggestion.project.instructions.count {
                    VStack(spacing: 12) {
                        Image(systemName: "party.popper.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.legoYellow)
                        Text("Build Complete!")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("Great job! Your \(suggestion.project.name) is ready.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(32)
                    .frame(maxWidth: .infinity)
                    .onAppear { HapticManager.notification(.success) }
                }
            }
            .padding(.vertical)
        }
    }

    private var buildShareText: String {
        let project = suggestion.project
        let pieceCount = project.requiredPieces.reduce(0) { $0 + $1.quantity }
        return """
        Check out this LEGO build idea from BrickVision!

        \(project.name) - \(project.difficulty.rawValue)
        \(project.description)
        \(pieceCount) pieces • ~\(project.estimatedMinutes) min

        #BrickVision #LEGO
        """
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
