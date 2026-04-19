import SwiftUI

/// View for browsing the LEGO set catalog and managing the user's set collection.
struct SetCollectionView: View {
    @StateObject private var collectionStore = SetCollectionStore.shared
    @StateObject private var inventoryStore = InventoryStore.shared
    @State private var searchText = ""
    @State private var selectedTheme: String?
    @State private var showOwnedOnly = false

    private let catalog = LegoSetCatalog.shared

    private var filteredSets: [LegoSet] {
        var result = catalog.sets

        if showOwnedOnly {
            let ownedNumbers = Set(collectionStore.collection.map(\.setNumber))
            result = result.filter { ownedNumbers.contains($0.setNumber) }
        }

        if let theme = selectedTheme {
            result = result.filter { $0.theme == theme }
        }

        if !searchText.isEmpty {
            result = catalog.search(searchText)
            if showOwnedOnly {
                let ownedNumbers = Set(collectionStore.collection.map(\.setNumber))
                result = result.filter { ownedNumbers.contains($0.setNumber) }
            }
        }

        return result
    }

    var body: some View {
        List {
            // Stats
            if !collectionStore.collection.isEmpty {
                statsSection
            }

            // Theme filter
            themeFilterSection

            // Sets
            setsSection
        }
        .searchable(text: $searchText, prompt: "Search sets by name or number")
        .navigationTitle("Set Collection")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Toggle(isOn: $showOwnedOnly) {
                    Label("Owned", systemImage: showOwnedOnly ? "checkmark.circle.fill" : "checkmark.circle")
                }
                .toggleStyle(.button)
            }
        }
    }

    // MARK: - Stats

    private var statsSection: some View {
        Section {
            HStack {
                Label("\(collectionStore.collection.count)", systemImage: "tray.full.fill")
                    .font(.subheadline)
                Spacer()
                Text("sets owned")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let inventory = inventoryStore.activeInventory {
                let avgCompletion = averageCompletion(inventory: inventory)
                HStack {
                    Label(String(format: "%.0f%%", avgCompletion), systemImage: "chart.pie.fill")
                        .font(.subheadline)
                    Spacer()
                    Text("avg. completion")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Collection")
        }
    }

    // MARK: - Theme Filter

    private var themeFilterSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    themeChip(nil, label: "All")
                    ForEach(catalog.allThemes, id: \.self) { theme in
                        themeChip(theme, label: theme)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }

    private func themeChip(_ theme: String?, label: String) -> some View {
        Button {
            withAnimation { selectedTheme = theme }
        } label: {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(selectedTheme == theme ? Color.blue : Color(.systemGray5))
                )
                .foregroundStyle(selectedTheme == theme ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sets List

    private var setsSection: some View {
        Section {
            if filteredSets.isEmpty {
                ContentUnavailableView("No Sets Found",
                                       systemImage: "magnifyingglass",
                                       description: Text("Try a different search or filter."))
            } else {
                ForEach(filteredSets) { legoSet in
                    NavigationLink(value: legoSet.setNumber) {
                        setRow(legoSet)
                    }
                }
            }
        } header: {
            Text("\(filteredSets.count) Sets")
        }
        .navigationDestination(for: String.self) { setNumber in
            if let legoSet = catalog.set(byNumber: setNumber) {
                SetDetailView(legoSet: legoSet)
            }
        }
    }

    private func setRow(_ legoSet: LegoSet) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(legoSet.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    if collectionStore.isInCollection(legoSet.setNumber) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.blue)
                    }
                }

                HStack(spacing: 8) {
                    Text("#\(legoSet.setNumber)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(legoSet.theme)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(legoSet.pieceCount) pcs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let inventory = inventoryStore.activeInventory {
                let pct = collectionStore.completionPercentage(for: legoSet, inventory: inventory)
                completionBadge(pct)
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            if collectionStore.isInCollection(legoSet.setNumber) {
                Button(role: .destructive) {
                    collectionStore.removeSet(legoSet.setNumber)
                } label: {
                    Label("Remove", systemImage: "minus.circle")
                }
            } else {
                Button {
                    collectionStore.addSet(legoSet.setNumber)
                } label: {
                    Label("Add", systemImage: "plus.circle")
                }
                .tint(Color.blue)
            }
        }
    }

    private func completionBadge(_ percentage: Double) -> some View {
        Text(String(format: "%.0f%%", percentage))
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(completionColor(percentage).opacity(0.15))
            )
            .foregroundStyle(completionColor(percentage))
    }

    private func completionColor(_ percentage: Double) -> Color {
        if percentage >= 100 { return .green }
        if percentage >= 50 { return .orange }
        return .red
    }

    private func averageCompletion(inventory: InventoryStore.Inventory) -> Double {
        let ownedNumbers = Set(collectionStore.collection.map(\.setNumber))
        let ownedSets = catalog.sets.filter { ownedNumbers.contains($0.setNumber) }
        guard !ownedSets.isEmpty else { return 0 }
        let total = ownedSets.reduce(0.0) {
            $0 + collectionStore.completionPercentage(for: $1, inventory: inventory)
        }
        return total / Double(ownedSets.count)
    }
}

// MARK: - Set Detail View

struct SetDetailView: View {
    let legoSet: LegoSet
    @StateObject private var collectionStore = SetCollectionStore.shared
    @StateObject private var inventoryStore = InventoryStore.shared

    var body: some View {
        List {
            // Set info
            infoSection

            // Completion
            if let inventory = inventoryStore.activeInventory {
                completionSection(inventory)
                missingPiecesSection(inventory)
            }

            // All pieces
            allPiecesSection
        }
        .navigationTitle(legoSet.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    if collectionStore.isInCollection(legoSet.setNumber) {
                        collectionStore.removeSet(legoSet.setNumber)
                    } else {
                        collectionStore.addSet(legoSet.setNumber)
                    }
                } label: {
                    Image(systemName: collectionStore.isInCollection(legoSet.setNumber) ? "checkmark.circle.fill" : "plus.circle")
                }
            }
        }
    }

    // MARK: - Info

    private var infoSection: some View {
        Section {
            LabeledContent("Set Number", value: "#\(legoSet.setNumber)")
            LabeledContent("Theme", value: legoSet.theme)
            LabeledContent("Year", value: "\(legoSet.year)")
            LabeledContent("Pieces", value: "\(legoSet.pieceCount)")
        } header: {
            Text("Details")
        }
    }

    // MARK: - Completion

    private func completionSection(_ inventory: InventoryStore.Inventory) -> some View {
        let pct = collectionStore.completionPercentage(for: legoSet, inventory: inventory)
        let missing = collectionStore.missingPieces(for: legoSet, inventory: inventory)
        return Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(String(format: "%.1f%% Complete", pct))
                        .font(.headline)
                    Spacer()
                    if pct >= 100 {
                        Label("Ready to Build!", systemImage: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                ProgressView(value: min(pct, 100), total: 100)
                    .tint(pct >= 100 ? .green : pct >= 50 ? .orange : .red)

                if !missing.isEmpty {
                    Text("\(missing.count) piece types missing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Inventory Match")
        }
    }

    private func missingPiecesSection(_ inventory: InventoryStore.Inventory) -> some View {
        let missing = collectionStore.missingPieces(for: legoSet, inventory: inventory)
        return Group {
            if !missing.isEmpty {
                Section {
                    ForEach(missing.prefix(20), id: \.partNumber) { item in
                        HStack {
                            if let color = LegoColor(rawValue: item.color) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.legoColor(color))
                                    .frame(width: 20, height: 20)
                            }
                            VStack(alignment: .leading) {
                                Text(item.partNumber)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Text(item.color)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("Need \(item.needed - item.have) more")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    if missing.count > 20 {
                        Text("+ \(missing.count - 20) more missing")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Missing Pieces")
                }
            }
        }
    }

    // MARK: - All Pieces

    private var allPiecesSection: some View {
        Section {
            ForEach(legoSet.pieces.indices, id: \.self) { idx in
                let piece = legoSet.pieces[idx]
                HStack {
                    if let color = LegoColor(rawValue: piece.color) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.legoColor(color))
                            .frame(width: 20, height: 20)
                    }
                    Text(piece.partNumber)
                        .font(.caption)
                        .fontWeight(.medium)
                    Text(piece.color)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("×\(piece.quantity)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("All Pieces (\(legoSet.pieces.count) types)")
        }
    }
}
