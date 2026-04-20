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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let image = capturedImage {
                    capturedImageHeader(image)
                }

                selectionSummary

                tagsInput

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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveCorrections() }
                        .font(.body.weight(.semibold))
                        .disabled(selectedIds.isEmpty || isSaving)
                }
            }
            .searchable(text: $searchText, prompt: "Search 16,000+ figures by name, theme, or ID")
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

    private var tagsInput: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Training Tags (optional)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("e.g. island, warrior, tribal, yellow, green", text: $userTagsText)
                .textFieldStyle(.roundedBorder)
                .font(.subheadline)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Text("Comma-separated keywords to help improve future scans.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
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
    }

    @ViewBuilder
    private func figureRow(_ fig: Minifigure) -> some View {
        Button {
            toggleSelection(fig.id)
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
