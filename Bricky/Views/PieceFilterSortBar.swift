import SwiftUI

/// Reusable search/sort/filter state + bar for any `[LegoPiece]` list.
/// Used by ScanResultsView and InventoryDetailView.
@MainActor
final class PieceFilterSortState: ObservableObject {
    enum SortKey: String, CaseIterable, Identifiable {
        case nameAsc = "Name (A–Z)"
        case nameDesc = "Name (Z–A)"
        case quantityDesc = "Quantity (high → low)"
        case quantityAsc = "Quantity (low → high)"
        case confidenceDesc = "Confidence (high → low)"
        case color = "Color"
        case category = "Category"
        var id: String { rawValue }
    }

    @Published var searchText: String = ""
    @Published var sortKey: SortKey = .nameAsc
    @Published var selectedColors: Set<LegoColor> = []
    @Published var selectedCategories: Set<PieceCategory> = []

    var hasActiveFilters: Bool {
        !searchText.isEmpty || !selectedColors.isEmpty || !selectedCategories.isEmpty
    }

    func reset() {
        searchText = ""
        selectedColors.removeAll()
        selectedCategories.removeAll()
    }

    /// Apply current state to a piece list.
    func apply(to pieces: [LegoPiece]) -> [LegoPiece] {
        var result = pieces

        // Filter — color
        if !selectedColors.isEmpty {
            result = result.filter { selectedColors.contains($0.color) }
        }
        // Filter — category
        if !selectedCategories.isEmpty {
            result = result.filter { selectedCategories.contains($0.category) }
        }
        // Search — case-insensitive substring on name OR partNumber
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            let lower = q.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(lower) ||
                $0.partNumber.lowercased().contains(lower)
            }
        }
        // Sort
        switch sortKey {
        case .nameAsc:
            result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .nameDesc:
            result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        case .quantityDesc:
            result.sort { $0.quantity > $1.quantity }
        case .quantityAsc:
            result.sort { $0.quantity < $1.quantity }
        case .confidenceDesc:
            result.sort { $0.confidence > $1.confidence }
        case .color:
            result.sort { $0.color.rawValue < $1.color.rawValue }
        case .category:
            result.sort { $0.category.rawValue < $1.category.rawValue }
        }
        return result
    }

    /// Apply the same state to a list of `InventoryStore.InventoryPiece` values
    /// (which lack a `confidence` field). `.confidenceDesc` falls back to name sort.
    func apply(to pieces: [InventoryStore.InventoryPiece]) -> [InventoryStore.InventoryPiece] {
        var result = pieces

        if !selectedColors.isEmpty {
            result = result.filter { selectedColors.contains($0.pieceColor) }
        }
        if !selectedCategories.isEmpty {
            result = result.filter { selectedCategories.contains($0.pieceCategory) }
        }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            let lower = q.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(lower) ||
                $0.partNumber.lowercased().contains(lower)
            }
        }
        switch sortKey {
        case .nameAsc:
            result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .nameDesc:
            result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        case .quantityDesc:
            result.sort { $0.quantity > $1.quantity }
        case .quantityAsc:
            result.sort { $0.quantity < $1.quantity }
        case .color:
            result.sort { $0.color < $1.color }
        case .category:
            result.sort { $0.category < $1.category }
        case .confidenceDesc:
            // confidence isn't tracked on InventoryPiece — fall back to name asc
            result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return result
    }
}

/// Compact bar with a search field, sort menu, and filter menu.
struct PieceFilterSortBar: View {
    @ObservedObject var state: PieceFilterSortState
    /// Distinct colors present in the current piece set (used to scope the
    /// filter menu to relevant options only).
    let availableColors: [LegoColor]
    /// Distinct categories present in the current piece set.
    let availableCategories: [PieceCategory]

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                // Search field
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("Search name or part #", text: $state.searchText)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if !state.searchText.isEmpty {
                        Button {
                            state.searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.gray.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Sort menu
                Menu {
                    ForEach(PieceFilterSortState.SortKey.allCases) { key in
                        Button {
                            state.sortKey = key
                        } label: {
                            if state.sortKey == key {
                                Label(key.rawValue, systemImage: "checkmark")
                            } else {
                                Text(key.rawValue)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.legoBlue)
                }
                .accessibilityLabel("Sort options")

                // Filter menu
                Menu {
                    if !availableColors.isEmpty {
                        Section("Color") {
                            ForEach(availableColors, id: \.self) { color in
                                Button {
                                    if state.selectedColors.contains(color) {
                                        state.selectedColors.remove(color)
                                    } else {
                                        state.selectedColors.insert(color)
                                    }
                                } label: {
                                    if state.selectedColors.contains(color) {
                                        Label(color.rawValue, systemImage: "checkmark")
                                    } else {
                                        Text(color.rawValue)
                                    }
                                }
                            }
                        }
                    }
                    if !availableCategories.isEmpty {
                        Section("Category") {
                            ForEach(availableCategories, id: \.self) { cat in
                                Button {
                                    if state.selectedCategories.contains(cat) {
                                        state.selectedCategories.remove(cat)
                                    } else {
                                        state.selectedCategories.insert(cat)
                                    }
                                } label: {
                                    if state.selectedCategories.contains(cat) {
                                        Label(cat.rawValue, systemImage: "checkmark")
                                    } else {
                                        Text(cat.rawValue)
                                    }
                                }
                            }
                        }
                    }
                    if state.hasActiveFilters {
                        Section {
                            Button(role: .destructive) {
                                state.reset()
                            } label: {
                                Label("Clear All Filters", systemImage: "xmark.circle")
                            }
                        }
                    }
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "line.3.horizontal.decrease.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.legoBlue)
                        if state.hasActiveFilters {
                            Circle()
                                .fill(Color.legoRed)
                                .frame(width: 8, height: 8)
                                .offset(x: 2, y: -2)
                        }
                    }
                }
                .accessibilityLabel("Filter options")
            }

            // Active-filter chip strip
            if state.hasActiveFilters {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(state.selectedColors), id: \.self) { color in
                            chip("Color: \(color.rawValue)") {
                                state.selectedColors.remove(color)
                            }
                        }
                        ForEach(Array(state.selectedCategories), id: \.self) { cat in
                            chip("Category: \(cat.rawValue)") {
                                state.selectedCategories.remove(cat)
                            }
                        }
                    }
                }
            }
        }
    }

    private func chip(_ label: String, onClear: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption.weight(.medium))
            Button(action: onClear) {
                Image(systemName: "xmark.circle.fill").font(.caption)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.legoBlue.opacity(0.15))
        .foregroundStyle(Color.legoBlue)
        .clipShape(Capsule())
    }
}
