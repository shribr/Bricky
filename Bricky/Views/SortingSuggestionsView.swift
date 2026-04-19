import SwiftUI

/// Sprint 5 / F5 — Show recommended storage-bin organization for the
/// user's pile, ranked by how balanced each strategy is.
struct SortingSuggestionsView: View {
    let pieces: [LegoPiece]
    @Environment(\.dismiss) private var dismiss

    private var suggestions: [SortingSuggestionService.Suggestion] {
        SortingSuggestionService.recommend(pieces: pieces)
    }

    @State private var selectedStrategy: SortingSuggestionService.GroupingStrategy?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerSummary
                    strategyPicker
                    if let chosen = chosenSuggestion {
                        binList(suggestion: chosen)
                    } else {
                        ContentUnavailableView(
                            "No Pieces",
                            systemImage: "tray",
                            description: Text("Scan some pieces first to get sorting suggestions.")
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("Storage Suggestions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                if selectedStrategy == nil {
                    selectedStrategy = suggestions.first?.strategy
                }
            }
        }
    }

    private var chosenSuggestion: SortingSuggestionService.Suggestion? {
        suggestions.first(where: { $0.strategy == selectedStrategy })
            ?? suggestions.first
    }

    // MARK: - Header

    private var headerSummary: some View {
        let total = pieces.reduce(0) { $0 + $1.quantity }
        let uniqueColors = Set(pieces.map { $0.color }).count
        let uniqueCategories = Set(pieces.map { $0.category }).count
        return VStack(alignment: .leading, spacing: 4) {
            Text("You have **\(total) pieces** across **\(uniqueColors) colors** and **\(uniqueCategories) categories**.")
                .font(.subheadline)
            Text("Recommended bin layouts (most balanced first):")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Strategy picker

    private var strategyPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(suggestions, id: \.strategy.rawValue) { suggestion in
                Button {
                    selectedStrategy = suggestion.strategy
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: selectedStrategy == suggestion.strategy
                              ? "checkmark.circle.fill"
                              : "circle")
                            .foregroundStyle(selectedStrategy == suggestion.strategy
                                             ? Color.legoBlue
                                             : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.strategy.rawValue)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            Text("\(suggestion.bins.count) bin\(suggestion.bins.count == 1 ? "" : "s") · balance score \(String(format: "%.1f", suggestion.balanceScore))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(selectedStrategy == suggestion.strategy
                                  ? Color.legoBlue.opacity(0.1)
                                  : Color.gray.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Bin list

    private func binList(suggestion: SortingSuggestionService.Suggestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Suggested Bins")
                .font(.subheadline.weight(.semibold))
                .padding(.top, 8)
            ForEach(suggestion.bins) { bin in
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.legoYellow.opacity(0.2))
                            .frame(width: 40, height: 40)
                        Image(systemName: "tray.fill")
                            .foregroundStyle(Color.legoYellow)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bin.label)
                            .font(.subheadline.weight(.semibold))
                        Text("\(bin.totalQuantity) pieces · \(bin.uniqueTypes) type\(bin.uniqueTypes == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !bin.exampleNames.isEmpty {
                            Text("e.g. " + bin.exampleNames.joined(separator: ", "))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.regularMaterial)
                )
            }
        }
    }
}
