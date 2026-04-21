import SwiftUI

/// After a scan, the user can open this sheet to search the full minifigure
/// catalog and tag which figures should have matched. This builds a labeled
/// training dataset for future Core ML model training.
struct MinifigureCorrectionPicker: View {
    let capturedImage: UIImage?
    let aiCandidateName: String
    let aiConfidence: Double
    let rejectedFigIds: [String]
    let onDone: () -> Void

    @State private var searchText = ""
    @State private var selectedIds = Set<String>()
    @State private var figures: [Minifigure] = []
    @State private var isSaving = false
    @State private var userTagsText = ""
    @State private var selectedTheme: String?
    @State private var showAddCustomFigure = false
    @State private var showTagsSheet = false
    @State private var profileFigure: Minifigure?
    @FocusState private var searchFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let image = capturedImage {
                    capturedImageHeader(image)
                }

                selectionSummary

                inlineSearchBar

                aiSuggestionChip

                themeFilterBar

                figureList

                addCustomFigureFooter
            }
            .navigationTitle("Correct Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Text("Correct Results")
                            .font(.headline)
                        Button {
                            showTagsSheet = true
                        } label: {
                            Image(systemName: userTagsText.isEmpty ? "tag" : "tag.fill")
                                .font(.body)
                                .foregroundStyle(userTagsText.isEmpty ? Color.accentColor : Color.green)
                        }
                        .accessibilityLabel("Add training tags")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveCorrections() }
                        .font(.body.weight(.semibold))
                        .disabled(selectedIds.isEmpty || isSaving)
                }
            }
            .onChange(of: searchText) { _, _ in updateResults() }
            .onChange(of: selectedTheme) { _, _ in updateResults() }
            .onAppear {
                // Start with the FULL catalog visible. The AI's guess is
                // surfaced as a one-tap chip in `aiSuggestionChip` so the
                // user can apply it if they want, but it doesn't lock them
                // into searching for a name that's almost certainly wrong.
                searchText = ""
                updateResults()
            }
            .sheet(isPresented: $showAddCustomFigure) {
                AddCustomFigureView(initialImage: capturedImage) { newFig in
                    // Auto-select the freshly-added figure so the user
                    // can hit Save and be done.
                    selectedIds.insert(newFig.id)
                    updateResults()
                }
            }
            .sheet(isPresented: $showTagsSheet) {
                trainingTagsSheet
            }
        }
    }

    /// Footer row offering the "add to catalog" escape hatch when none of
    /// the existing catalog figures match what the user scanned.
    private var addCustomFigureFooter: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                showAddCustomFigure = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Can't find it? Add to catalog")
                            .font(.subheadline.weight(.semibold))
                        Text("Save this figure locally with your own photo & details")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color(.secondarySystemBackground))
        }
    }

    // MARK: - Subviews

    private func capturedImageHeader(_ image: UIImage) -> some View {
        VStack(spacing: 6) {
            // Normalize orientation so a portrait scan always displays upright.
            Image(uiImage: image.normalizedOrientation())
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 160)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(radius: 3)

            Text("Select figures that match this scan")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    /// One-tap chip showing the AI's best guess. Tapping fills the search
    /// box; long-pressing clears it. Lets the user explore the AI's hint
    /// without being trapped by it.
    @ViewBuilder
    private var aiSuggestionChip: some View {
        let primaryGuess = aiCandidateName
            .components(separatedBy: ",").first?
            .trimmingCharacters(in: .whitespaces) ?? aiCandidateName

        if !primaryGuess.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.tint)
                Text("AI suggested:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    searchText = primaryGuess
                } label: {
                    Text(primaryGuess)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                Spacer()
                if !searchText.isEmpty || selectedTheme != nil {
                    Button("Reset filters") {
                        searchText = ""
                        selectedTheme = nil
                    }
                    .font(.caption.weight(.medium))
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }

    private var themeFilterBar: some View {
        let themes = MinifigureCatalog.shared.themes
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                themeChip(label: "All themes", isSelected: selectedTheme == nil) {
                    selectedTheme = nil
                }
                ForEach(themes, id: \.self) { theme in
                    themeChip(label: theme, isSelected: selectedTheme == theme) {
                        selectedTheme = (selectedTheme == theme ? nil : theme)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private func themeChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
                )
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private var selectionSummary: some View {
        Group {
            if !selectedIds.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("\(selectedIds.count) figure\(selectedIds.count == 1 ? "" : "s") selected")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Button("Clear") { selectedIds.removeAll() }
                        .font(.caption)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.green.opacity(0.1))
            }
        }
    }

    /// Inline search bar that lives in the same spot the (now-removed)
    /// training tags row used to occupy. Sits ABOVE the keyboard's reach
    /// because nothing below it gets auto-hidden when other inputs focus.
    private var inlineSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search 16,000+ figures by name, theme, or ID", text: $searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($searchFocused)
                .submitLabel(.search)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemBackground))
        )
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    /// Modal sheet for entering optional training tags. Triggered by the
    /// tag button in the toolbar; appears centered so the keyboard pops
    /// over a focused, full-screen input rather than competing with the
    /// figure list and search bar for vertical space.
    private var trainingTagsSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add keywords that describe this figure to help improve future scans. They're saved alongside your selection.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("e.g. island, warrior, tribal, yellow, green", text: $userTagsText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(3...6)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                Text("Comma-separated. Examples: \"red\", \"chef\", \"pirates 1994\".")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer()
            }
            .padding()
            .navigationTitle("Training Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") {
                        userTagsText = ""
                    }
                    .disabled(userTagsText.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showTagsSheet = false }
                        .font(.body.weight(.semibold))
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var figureList: some View {
        List {
            Section {
                ForEach(figures) { fig in
                    figureRow(fig)
                }
            } header: {
                HStack {
                    Text("\(figures.count) figure\(figures.count == 1 ? "" : "s")")
                    Spacer()
                    if figures.isEmpty {
                        Text("No matches — try clearing filters")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .textCase(nil)
            }
        }
        .listStyle(.plain)
        .navigationDestination(item: $profileFigure) { fig in
            CorrectionFigureProfileView(
                figure: fig,
                isSelected: selectedIds.contains(fig.id),
                onConfirm: {
                    selectedIds.insert(fig.id)
                    profileFigure = nil
                },
                onRemove: {
                    selectedIds.remove(fig.id)
                    profileFigure = nil
                }
            )
        }
    }

    @ViewBuilder
    private func figureRow(_ fig: Minifigure) -> some View {
        Button {
            profileFigure = fig
        } label: {
            HStack(spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    MinifigureImageView(url: fig.imageURL)
                        .frame(width: 50, height: 60)

                    if selectedIds.contains(fig.id) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.white, .green)
                            .offset(x: 4, y: 4)
                    }
                }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(fig.name)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(2)
                        Text("\(fig.theme) · \(fig.year > 0 ? String(fig.year) : "Unknown")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(fig.id)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    if selectedIds.contains(fig.id) {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.green)
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .listRowBackground(
                selectedIds.contains(fig.id)
                    ? Color.green.opacity(0.08)
                    : Color.clear
            )
    }

    // MARK: - Logic

    private func toggleSelection(_ id: String) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    private func updateResults() {
        let catalog = MinifigureCatalog.shared
        let themeFilter: Set<String> = selectedTheme.map { [$0] } ?? []
        figures = catalog.search(
            query: searchText,
            themes: themeFilter,
            yearRange: nil,
            sort: .nameAsc
        )
        // No cap — `List` is lazy so it can handle the full catalog.
    }

    private func saveCorrections() {
        guard let image = capturedImage else { return }
        isSaving = true

        let tags = userTagsText
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        MinifigureTrainingStore.shared.record(
            capturedImage: image,
            confirmedFigIds: Array(selectedIds),
            rejectedFigIds: rejectedFigIds,
            aiCandidateName: aiCandidateName,
            aiConfidence: aiConfidence,
            userTags: tags
        )

        isSaving = false
        onDone()
        dismiss()
    }
}

// MARK: - Figure Profile for Correction Flow

/// Full-screen profile shown when the user taps a figure in the correction
/// picker. Shows a large tappable image, figure details, and a Confirm /
/// Remove button so the user can inspect before committing.
struct CorrectionFigureProfileView: View {
    let figure: Minifigure
    let isSelected: Bool
    let onConfirm: () -> Void
    let onRemove: () -> Void

    @State private var showZoomImage = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Tappable image
                Button {
                    showZoomImage = true
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        MinifigureImageView(url: figure.imageURL)
                            .frame(maxHeight: 280)
                            .frame(maxWidth: .infinity)
                        Image(systemName: "magnifyingglass.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white, .black.opacity(0.55))
                            .padding(10)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View \(figure.name) full size")

                // Name + metadata
                VStack(spacing: 8) {
                    Text(figure.name)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)

                    HStack(spacing: 12) {
                        Label(figure.theme, systemImage: "tag.fill")
                        if figure.year > 0 {
                            Label("\(figure.year)", systemImage: "calendar")
                        }
                        Label("\(figure.partCount) parts", systemImage: "cube.fill")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Text(figure.id)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                // Parts list
                if !figure.requiredParts.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Parts")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(figure.requiredParts, id: \.self) { part in
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.legoColor(part.legoColor))
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Image(systemName: part.slot.systemImage)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(
                                                Color.bestForegroundOn(Color.legoColor(part.legoColor))
                                            )
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(part.displayName)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    Text("\(part.color) · \(part.partNumber)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.regularMaterial)
                    )
                }

                // External links
                VStack(spacing: 10) {
                    Button {
                        if let url = BrickLinkService.rebrickableMinifigureURL(figure.id) {
                            openURL(url)
                        }
                    } label: {
                        Label("View on Rebrickable", systemImage: "link")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(.regularMaterial)
                            )
                    }
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            // Confirm / Remove button pinned to bottom
            Button {
                if isSelected {
                    onRemove()
                } else {
                    onConfirm()
                }
            } label: {
                Label(
                    isSelected ? "Remove Match" : "Confirm Match",
                    systemImage: isSelected ? "xmark.circle.fill" : "checkmark.circle.fill"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(isSelected ? Color.red : Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            .background(.ultraThinMaterial)
        }
        .navigationTitle(figure.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showZoomImage) {
            ZoomableImageView(url: figure.imageURL, title: figure.name)
        }
    }
}
