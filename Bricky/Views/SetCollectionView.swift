import SwiftUI

/// View for browsing the LEGO set catalog and managing the user's set collection.
struct SetCollectionView: View {
    @StateObject private var collectionStore = SetCollectionStore.shared
    @StateObject private var inventoryStore = InventoryStore.shared
    @State private var searchText = ""
    @State private var selectedTheme: String?
    @State private var showOwnedOnly = false
    @AppStorage("setCollection.tileView") private var tileView = false
    @State private var showSettings = false

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

    /// Prominent entry into the interactive 3D building-instruction models.
    private var buildInstructionsSection: some View {
        Section {
            NavigationLink {
                SetModelsView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "cube.transparent.fill")
                        .font(.title2)
                        .foregroundStyle(Color.legoBlue)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("3D Building Instructions")
                            .font(.headline)
                        Text("Step-by-step 3D models you can rotate and build")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if SetModelLibrary.entries().count > 0 {
                        Text("\(SetModelLibrary.entries().count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    var body: some View {
        List {
            // 3D building instructions entry (prominent, discoverable)
            buildInstructionsSection

            // Stats
            if !collectionStore.collection.isEmpty {
                statsSection
            }

            // Theme filter
            themeFilterSection

            // Sets
            setsSection
        }
        .navigationDestination(for: String.self) { setNumber in
            if let legoSet = catalog.set(byNumber: setNumber) {
                SetDetailView(legoSet: legoSet)
            }
        }
        .searchable(text: $searchText, prompt: "Search sets by name or number")
        .refreshable {
            await collectionStore.downloadMissingThumbnails()
        }
        .navigationTitle("Set Collection")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                NavigationLink {
                    SetModelsView()
                } label: {
                    Image(systemName: "cube.transparent")
                }
                .accessibilityLabel("3D Set Models")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView() }
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
                        if tileView {
                            tileRow(legoSet)
                        } else {
                            setRow(legoSet)
                        }
                    }
                }
            }
        } header: {
            HStack {
                Text("\(filteredSets.count) Sets")
                Spacer()
                Toggle(isOn: $tileView) {
                    Label("Tile View", systemImage: tileView ? "square.grid.2x2.fill" : "list.bullet")
                        .labelStyle(.iconOnly)
                }
                .toggleStyle(.button)
                .accessibilityLabel(tileView ? "Switch to list view" : "Switch to tile view")
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

            if collectionStore.hasImage(for: legoSet.setNumber) {
                Image(systemName: "photo.badge.checkmark")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .accessibilityLabel("Thumbnail available")
            }

            if let inventory = inventoryStore.activeInventory {
                let pct = collectionStore.completionPercentage(for: legoSet, inventory: inventory)
                completionBadge(pct)
            }
        }
        .padding(.vertical, 10)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
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

    private func tileRow(_ legoSet: LegoSet) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                if let thumb = collectionStore.image(for: legoSet.setNumber) {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "shippingbox")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8))

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

                Text("#\(legoSet.setNumber) · \(legoSet.pieceCount) pcs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(legoSet.theme) · \(String(legoSet.year))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                if let inventory = inventoryStore.activeInventory {
                    let pct = collectionStore.completionPercentage(for: legoSet, inventory: inventory)
                    completionBadge(pct)
                }
                if collectionStore.hasImage(for: legoSet.setNumber) {
                    Image(systemName: "photo.badge.checkmark")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .accessibilityLabel("Thumbnail available")
                }
            }
        }
        .padding(.vertical, 8)
        .frame(minHeight: 80)
        .contentShape(Rectangle())
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
    @State private var showRebrickableConfirm = false
    @State private var showInstructionsConfirm = false
    @Environment(\.openURL) private var openURL
    @State private var fetchingImage = false
    @State private var previewPiece: LegoPiece?
    @State private var fetchingBOM = false
    @State private var bomError: String?
    @State private var showSettings = false

    /// Public set page on Rebrickable (sets use a "-1" variant suffix).
    private var rebrickableURL: URL? {
        URL(string: "https://rebrickable.com/sets/\(legoSet.setNumber)-1/")
    }

    /// Building instructions for the set on Rebrickable.
    private var instructionsURL: URL? {
        URL(string: "https://rebrickable.com/instructions/\(legoSet.setNumber)-1/")
    }

    /// Build a renderable piece from a catalog part number + color string so a
    /// tapped row can open the shared 3D preview. Falls back to a basic brick.
    private func renderablePiece(partNumber: String, color: String, quantity: Int) -> LegoPiece {
        let legoColor = LegoColor(fromString: color) ?? .gray
        if let cat = LegoPartsCatalog.shared.piece(byPartNumber: partNumber) {
            return LegoPiece(partNumber: cat.partNumber, name: cat.name, category: cat.category,
                             color: legoColor, dimensions: cat.dimensions, quantity: quantity)
        }
        return LegoPiece(partNumber: partNumber, name: "Part \(partNumber)", category: .brick,
                         color: legoColor,
                         dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3),
                         quantity: quantity)
    }

    var body: some View {
        List {
            // Scanned/confirmed photo of the set, if saved
            if let image = collectionStore.image(for: legoSet.setNumber) {
                Section {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 220)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }

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
        .sheet(item: $previewPiece) { piece in
            ModelViewerView(piece: piece)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView() }
        }
    }

    // MARK: - Info

    private var infoSection: some View {
        Section {
            LabeledContent("Set Number", value: "#\(legoSet.setNumber)")
            LabeledContent("Theme", value: legoSet.theme)
            LabeledContent("Year", value: String(legoSet.year))
            LabeledContent("Pieces", value: "\(legoSet.pieceCount)")
            if rebrickableURL != nil {
                Button {
                    showRebrickableConfirm = true
                } label: {
                    HStack {
                        Text(legoSet.name)
                            .underline()
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                    }
                    .foregroundStyle(Color.legoBlue)
                }
                .accessibilityLabel("View \(legoSet.name) on Rebrickable")
            }
            if instructionsURL != nil {
                Button {
                    showInstructionsConfirm = true
                } label: {
                    HStack {
                        Label("Building Instructions", systemImage: "book.pages")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                    }
                    .foregroundStyle(Color.legoBlue)
                }
                .accessibilityLabel("View building instructions for \(legoSet.name) on Rebrickable")
            }
            Button {
                fetchingImage = true
                Task {
                    _ = await collectionStore.fetchRebrickableImage(for: legoSet.setNumber)
                    fetchingImage = false
                }
            } label: {
                HStack {
                    Label(collectionStore.hasImage(for: legoSet.setNumber) ? "Refresh Photo from Rebrickable" : "Get Photo from Rebrickable",
                          systemImage: "photo.badge.arrow.down")
                    Spacer()
                    if fetchingImage { ProgressView() }
                }
                .foregroundStyle(Color.legoBlue)
            }
            .disabled(fetchingImage)
            if RebrickableSetService().isConfigured {
                Button {
                    fetchingBOM = true
                    bomError = nil
                    Task {
                        do { _ = try await collectionStore.fetchFullBOM(for: legoSet.setNumber) }
                        catch { bomError = error.localizedDescription }
                        fetchingBOM = false
                    }
                } label: {
                    HStack {
                        Label(collectionStore.hasFullBOM(for: legoSet.setNumber) ? "Refresh Full Parts List" : "Fetch Full Parts List",
                              systemImage: "list.bullet.rectangle")
                        Spacer()
                        if fetchingBOM { ProgressView() }
                        else if collectionStore.hasFullBOM(for: legoSet.setNumber) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                    .foregroundStyle(Color.legoBlue)
                }
                .disabled(fetchingBOM)
                if let bomError {
                    Text(bomError).font(.caption).foregroundStyle(.red)
                }
            }
        } header: {
            Text("Details")
        }
        .confirmationDialog("Open on Rebrickable?", isPresented: $showRebrickableConfirm, titleVisibility: .visible) {
            Button("Open") { if let url = rebrickableURL { openURL(url) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This opens \(legoSet.name) in your browser.")
        }
        .confirmationDialog("Open Instructions on Rebrickable?", isPresented: $showInstructionsConfirm, titleVisibility: .visible) {
            Button("Open") { if let url = instructionsURL { openURL(url) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This opens the building instructions for \(legoSet.name) in your browser.")
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

                if !collectionStore.hasFullBOM(for: legoSet.setNumber) {
                    Text("Based on a representative sample of this set's pieces — completion is approximate. Fetch the full parts list for exact figures.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Button {
                    if collectionStore.isInCollection(legoSet.setNumber) {
                        collectionStore.removeSet(legoSet.setNumber)
                    } else {
                        collectionStore.addSet(legoSet.setNumber)
                    }
                } label: {
                    Label(collectionStore.isInCollection(legoSet.setNumber) ? "In My Collection" : "Add to My Collection",
                          systemImage: collectionStore.isInCollection(legoSet.setNumber) ? "checkmark.seal.fill" : "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.white)
                        .padding(.vertical, 8)
                        .background(collectionStore.isInCollection(legoSet.setNumber) ? Color.green : Color.blue, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))            }
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
                        Button {
                            previewPiece = renderablePiece(partNumber: item.partNumber, color: item.color, quantity: item.needed - item.have)
                        } label: {
                            HStack {
                                if let color = LegoColor(fromString: item.color) {
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
                                Image(systemName: "cube.transparent")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
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
        let pieces = collectionStore.effectivePieces(for: legoSet)
        return Section {
            ForEach(pieces.indices, id: \.self) { idx in
                let piece = pieces[idx]
                HStack {
                    if let color = LegoColor(fromString: piece.color) {
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
            Text("All Pieces (\(pieces.count) types)")
        }
    }
}
