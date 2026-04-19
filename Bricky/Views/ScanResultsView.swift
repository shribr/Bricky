import SwiftUI

/// Shows results after scanning, with piece summary and navigation to catalog/builds
struct ScanResultsView: View {
    @ObservedObject var session: ScanSession
    @State private var navigateToCatalog = false
    @State private var navigateToBuilds = false
    @State private var pieceToEdit: LegoPiece?
    @State private var pieceToPreview: LegoPiece?
    @State private var pieceToLocate: LegoPiece?
    /// Sprint 2 / B1 — launch live find for this piece.
    @State private var pieceToFindLive: LegoPiece?
    /// Sprint 2 / B2-B3 — open saved-scan picker for this piece.
    @State private var pieceToFindInSavedScan: LegoPiece?
    @State private var showShareSheet = false
    /// Sprint 6 / A3 — Brickit-style sheet showing pile photo with selectable
    /// piece overlays.
    @State private var showPileSheet = false
    /// Sprint 5 / F1 — pile diff (compare to a saved scan).
    @State private var showPileDiff = false
    /// Sprint 5 / F5 — storage bin sorting suggestions.
    @State private var showSortingSuggestions = false
    /// Search / sort / filter state for the detected pieces list.
    @StateObject private var filterState = PieceFilterSortState()

    var body: some View {
        Group {
            if session.pieces.isEmpty {
                ContentUnavailableView(
                    "No Pieces Found",
                    systemImage: "cube.transparent",
                    description: Text("Scan some LEGO bricks to see results here.")
                )
            } else {
                scrollContent
            }
        }
        .navigationTitle("Scan Results")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToCatalog) {
            PieceCatalogView(pieces: session.pieces)
        }
        .navigationDestination(isPresented: $navigateToBuilds) {
            BuildSuggestionsView(pieces: session.pieces)
        }
        .sheet(item: $pieceToEdit) { piece in
            EditPieceView(session: session, piece: piece)
        }
        .sheet(item: $pieceToPreview) { piece in
            ModelViewerView(piece: piece, scanSession: session)
        }
        .fullScreenCover(item: $pieceToLocate) { piece in
            PieceLocationView(piece: piece, scanSession: session)
        }
        .fullScreenCover(item: $pieceToFindLive) { piece in
            FindPieceView(piece: piece)
        }
        .sheet(item: $pieceToFindInSavedScan) { piece in
            FindInSavedScanPickerView(targetPiece: piece)
        }
        .toolbar {
            if !session.pieces.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [inventoryShareText])
        }
        .sheet(isPresented: $showPileSheet) {
            PileResultsSheetView(session: session)
        }
        .sheet(isPresented: $showPileDiff) {
            PileDiffView(currentSession: session)
        }
        .sheet(isPresented: $showSortingSuggestions) {
            SortingSuggestionsView(pieces: session.pieces)
        }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Summary header
                summaryCard

                // Detected pieces list (editable)
                if !session.pieces.isEmpty {
                    detectedPiecesList
                }

                // Category breakdown
                if !session.categorySummary.isEmpty {
                    categoryBreakdown
                }

                // Color breakdown
                if !session.colorSummary.isEmpty {
                    colorBreakdown
                }

                // Action buttons
                actionButtons
            }
            .padding()
        }
    }

    private var inventoryShareText: String {
        var text = "My LEGO Inventory (\(AppConfig.appName))\n\n"
        text += "\(session.totalPiecesFound) pieces, \(session.pieces.count) unique types\n\n"
        for piece in session.pieces.prefix(20) {
            text += "• \(piece.name) (\(piece.color.rawValue)) ×\(piece.quantity)\n"
        }
        if session.pieces.count > 20 {
            text += "...and \(session.pieces.count - 20) more types\n"
        }
        text += "\n#\(AppConfig.appName) #LEGO"
        return text
    }

    // MARK: - Filter / Sort helpers

    private var filteredPieces: [LegoPiece] {
        filterState.apply(to: session.pieces)
    }

    private var availableColors: [LegoColor] {
        Array(Set(session.pieces.map(\.color))).sorted { $0.rawValue < $1.rawValue }
    }

    private var availableCategories: [PieceCategory] {
        Array(Set(session.pieces.map(\.category))).sorted { $0.rawValue < $1.rawValue }
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 72, height: 72)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
            }

            Text("Scan Complete!")
                .font(.title2)
                .fontWeight(.bold)

            HStack(spacing: 32) {
                statItem(value: "\(session.totalPiecesFound)", label: "Total Pieces")
                statItem(value: "\(session.uniquePieceCount)", label: "Unique Types")
                statItem(value: "\(session.colorSummary.count)", label: "Colors")
            }

            // Confidence summary
            confidenceSummary

            // Sprint C — show captured location chip when available.
            if session.latitude != nil, session.longitude != nil {
                HStack(spacing: 6) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(.tint)
                    Text(session.placeName ?? "Location captured")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(Color.accentColor.opacity(0.12))
                )
                .accessibilityLabel("Scanned at \(session.placeName ?? "captured location")")
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Scan complete. \(session.totalPiecesFound) total pieces, \(session.uniquePieceCount) unique types, \(session.colorSummary.count) colors")
    }

    private var confidenceSummary: some View {
        let highConf = session.pieces.filter { $0.confidence >= 0.9 }.count
        let medConf = session.pieces.filter { $0.confidence >= 0.7 && $0.confidence < 0.9 }.count
        let lowConf = session.pieces.filter { $0.confidence < 0.7 }.count

        return HStack(spacing: 16) {
            if highConf > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text("\(highConf)")
                        .fontWeight(.semibold)
                }
                .font(.caption)
                .accessibilityLabel("\(highConf) high confidence")
            }
            if medConf > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("\(medConf)")
                        .fontWeight(.semibold)
                }
                .font(.caption)
                .accessibilityLabel("\(medConf) medium confidence")
            }
            if lowConf > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundStyle(.red)
                    Text("\(lowConf)")
                        .fontWeight(.semibold)
                }
                .font(.caption)
                .accessibilityLabel("\(lowConf) low confidence")
            }
        }
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(Color.legoBlue)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Category Breakdown

    private var categoryBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("By Category")
                .font(.headline)

            ForEach(session.categorySummary, id: \.category) { item in
                HStack {
                    Image(systemName: item.category.systemImage)
                        .frame(width: 24)
                        .foregroundStyle(Color.legoBlue)
                    Text(item.category.rawValue)
                    Spacer()
                    Text("\(item.count)")
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
        )
    }

    // MARK: - Color Breakdown

    private var colorBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("By Color")
                .font(.headline)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                ForEach(session.colorSummary, id: \.color) { item in
                    VStack(spacing: 6) {
                        Circle()
                            .fill(Color.legoColor(item.color))
                            .frame(width: 32, height: 32)
                            .shadow(radius: 1)
                        Text("\(item.count)")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text(item.color.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
        )
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            if !session.sourceImages.isEmpty {
                Button {
                    showPileSheet = true
                } label: {
                    Label("View Pile Photo", systemImage: "photo.on.rectangle.angled")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(.regularMaterial)
                                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                        )
                }
                .accessibilityHint("Tap pieces in the photo to highlight where they were detected")
            }

            Button {
                navigateToBuilds = true
            } label: {
                Label("See What You Can Build", systemImage: "hammer.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [Color.legoBlue, Color.legoBlue.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: Color.legoBlue.opacity(0.3), radius: 6, y: 3)
            }
            .accessibilityHint("Shows build suggestions based on your scanned pieces")

            Button {
                navigateToCatalog = true
            } label: {
                Label("View Full Catalog", systemImage: "list.bullet")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(.regularMaterial)
                            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                    )
            }
            .accessibilityHint("Browse all detected pieces with filters and sorting")

            // Sprint 5 / F5 — Storage suggestions
            Button {
                showSortingSuggestions = true
            } label: {
                Label("Sorting Suggestions", systemImage: "tray.2.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(.regularMaterial)
                            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                    )
            }
            .accessibilityHint("Recommended storage bin layouts for your pieces")

            // Sprint 5 / F1 — Compare to saved scan
            if ScanHistoryStore.shared.entries.contains(where: { $0.id != session.id }) {
                Button {
                    showPileDiff = true
                } label: {
                    Label("Compare to Saved Scan", systemImage: "arrow.left.arrow.right.circle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(.regularMaterial)
                                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                        )
                }
                .accessibilityHint("See added and removed pieces vs a previous scan")
            }
        }
    }

    // MARK: - Detected Pieces List

    private var detectedPiecesList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Detected Pieces")
                    .font(.headline)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "cube.fill")
                        .font(.caption2)
                    Text("Tap for 3D view")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }

            PieceFilterSortBar(
                state: filterState,
                availableColors: availableColors,
                availableCategories: availableCategories
            )

            if filteredPieces.isEmpty {
                Text("No pieces match the current search or filters.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            }

            ForEach(filteredPieces) { piece in
                Button {
                    pieceToPreview = piece
                } label: {
                    HStack(spacing: 12) {
                        // Color swatch with category icon overlay
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.legoColor(piece.color))
                            .frame(width: 40, height: 40)
                            .overlay(
                                Image(systemName: piece.category.systemImage)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(Color.bestForegroundOn(Color.legoColor(piece.color)))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                            )
                            .shadow(color: Color.legoColor(piece.color).opacity(0.4), radius: 3, y: 1)
                            .accessibilityLabel("\(piece.category.rawValue), \(piece.color.rawValue)")

                        // Info
                        VStack(alignment: .leading, spacing: 2) {
                            Text(piece.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                Text("\(piece.color.rawValue) · \(piece.dimensions.displayString)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)

                                // Confidence badge
                                HStack(spacing: 2) {
                                    Image(systemName: Color.confidenceIcon(piece.confidence))
                                        .font(.system(size: 9))
                                    Text("\(Int(piece.confidence * 100))%")
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                }
                                .foregroundStyle(Color.confidenceColor(piece.confidence))
                                .accessibilityLabel("\(Int(piece.confidence * 100)) percent confidence")
                            }
                        }

                        Spacer()

                        // Quantity
                        Text("×\(piece.quantity)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        pieceToPreview = piece
                    } label: {
                        Label("View 3D Model", systemImage: "rotate.3d")
                    }
                    Button {
                        pieceToFindLive = piece
                    } label: {
                        Label("Find in Live Pile", systemImage: "magnifyingglass")
                    }
                    Button {
                        pieceToFindInSavedScan = piece
                    } label: {
                        Label("Find in Saved Scans", systemImage: "tray.full")
                    }
                    if piece.locationSnapshot != nil ||
                        (piece.boundingBox != nil && piece.boundingBox != .zero && session.sourceImage(for: piece) != nil) {
                        Button {
                            pieceToLocate = piece
                        } label: {
                            Label("Find in Pile Photo", systemImage: "mappin.circle.fill")
                        }
                    }
                    Button {
                        pieceToEdit = piece
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        withAnimation { deletePiece(piece) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } preview: {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.legoColor(piece.color))
                            .frame(width: 44, height: 44)
                            .overlay(
                                Image(systemName: piece.category.systemImage)
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(Color.bestForegroundOn(Color.legoColor(piece.color)))
                            )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(piece.name)
                                .font(.headline)
                            Text("\(piece.dimensions.displayString) · \(piece.color.rawValue)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("×\(piece.quantity) · \(Int(piece.confidence * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(16)
                    .frame(width: 280)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(piece.name), \(piece.color.rawValue), quantity \(piece.quantity), \(Int(piece.confidence * 100)) percent confidence")
                .accessibilityHint("Tap to view 3D model. Long-press for more actions.")
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
        )
    }

    private func deletePiece(_ piece: LegoPiece) {
        if let index = session.pieces.firstIndex(where: { $0.id == piece.id }) {
            let qty = session.pieces[index].quantity
            session.pieces.remove(at: index)
            session.totalPiecesFound = max(0, session.totalPiecesFound - qty)
        }
    }
}

// MARK: - Edit Piece View

struct EditPieceView: View {
    @ObservedObject var session: ScanSession
    let piece: LegoPiece
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCategory: PieceCategory
    @State private var selectedColor: LegoColor
    @State private var studsWide: Int
    @State private var studsLong: Int
    @State private var quantity: Int
    @State private var name: String

    init(session: ScanSession, piece: LegoPiece) {
        self.session = session
        self.piece = piece
        _selectedCategory = State(initialValue: piece.category)
        _selectedColor = State(initialValue: piece.color)
        _studsWide = State(initialValue: piece.dimensions.studsWide)
        _studsLong = State(initialValue: piece.dimensions.studsLong)
        _quantity = State(initialValue: piece.quantity)
        _name = State(initialValue: piece.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Piece name", text: $name)
                }

                Section("Piece Type") {
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(PieceCategory.allCases, id: \.self) { cat in
                            Label(cat.rawValue, systemImage: cat.systemImage)
                                .tag(cat)
                        }
                    }
                }

                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(LegoColor.allCases, id: \.self) { color in
                            Button {
                                selectedColor = color
                            } label: {
                                Circle()
                                    .fill(Color.legoColor(color))
                                    .frame(width: 36, height: 36)
                                    .overlay {
                                        if selectedColor == color {
                                            Circle()
                                                .strokeBorder(.white, lineWidth: 3)
                                            Image(systemName: "checkmark")
                                                .font(.caption)
                                                .fontWeight(.bold)
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .shadow(radius: 2)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section("Dimensions") {
                    Stepper("Width: \(studsWide) studs", value: $studsWide, in: 1...12)
                    Stepper("Length: \(studsLong) studs", value: $studsLong, in: 1...16)
                }

                Section("Quantity") {
                    Stepper("\(quantity)", value: $quantity, in: 1...99)
                }
            }
            .navigationTitle("Edit Piece")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        applyEdits()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func applyEdits() {
        guard let index = session.pieces.firstIndex(where: { $0.id == piece.id }) else { return }

        // Log correction if anything changed (for model improvement)
        let original = session.pieces[index]
        let heightUnits = selectedCategory == .plate || selectedCategory == .tile ? 1 : 3
        if original.name != name || original.category != selectedCategory ||
           original.color != selectedColor || original.dimensions.studsWide != studsWide ||
           original.dimensions.studsLong != studsLong {
            CorrectionLogger.shared.logCorrection(
                original: original,
                correctedName: name,
                correctedCategory: selectedCategory,
                correctedColor: selectedColor,
                correctedStudsWide: studsWide,
                correctedStudsLong: studsLong
            )
        }

        let oldQty = session.pieces[index].quantity
        let updated = LegoPiece(
            id: piece.id,
            partNumber: piece.partNumber,
            name: name,
            category: selectedCategory,
            color: selectedColor,
            dimensions: PieceDimensions(studsWide: studsWide, studsLong: studsLong, heightUnits: heightUnits),
            confidence: piece.confidence,
            quantity: quantity
        )
        session.pieces[index] = updated
        session.totalPiecesFound += (quantity - oldQty)
    }
}
