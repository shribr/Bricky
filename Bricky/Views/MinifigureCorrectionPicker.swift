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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let image = capturedImage {
                    capturedImageHeader(image)
                }

                selectionSummary

                figureList
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
            .searchable(text: $searchText, prompt: "Search by name, theme, or ID")
            .onChange(of: searchText) { _, _ in updateResults() }
            .onAppear {
                // Pre-fill search with AI's guess to help the user find variants
                searchText = aiCandidateName
                    .components(separatedBy: ",").first?
                    .trimmingCharacters(in: .whitespaces) ?? aiCandidateName
                updateResults()
            }
        }
    }

    // MARK: - Subviews

    private func capturedImageHeader(_ image: UIImage) -> some View {
        VStack(spacing: 6) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(height: 100)
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

    private var figureList: some View {
        List(figures) { fig in
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
        .listStyle(.plain)
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
        figures = catalog.search(
            query: searchText,
            themes: [],
            yearRange: nil,
            sort: .nameAsc
        )
        // Cap at 200 results to keep the list performant
        if figures.count > 200 {
            figures = Array(figures.prefix(200))
        }
    }

    private func saveCorrections() {
        guard let image = capturedImage else { return }
        isSaving = true

        MinifigureTrainingStore.shared.record(
            capturedImage: image,
            confirmedFigIds: Array(selectedIds),
            rejectedFigIds: rejectedFigIds,
            aiCandidateName: aiCandidateName,
            aiConfidence: aiConfidence
        )

        isSaving = false
        onDone()
        dismiss()
    }
}
