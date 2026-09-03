import SwiftUI
import MapKit

/// Shows results after scanning, with piece summary and navigation to catalog/builds
struct ScanResultsView: View {
    @ObservedObject var session: ScanSession
    /// When the results are opened from scan history (not a just-finished scan)
    /// we drop the celebratory "Scan Complete" header — it's obviously complete.
    var isFromHistory: Bool = false
    @State private var navigateToCatalog = false
    @State private var navigateToBuilds = false
    /// Sprint C — present the captured location on a map.
    @State private var showLocationMap = false
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
    /// Measured accuracy from the user's own verify actions (honest, unlike the
    /// heuristic per-piece confidence).
    @ObservedObject private var reliability = VerificationReliabilityStore.shared

    var body: some View {
        Group {
            if session.pieces.isEmpty {
                ContentUnavailableView(
                    "No Pieces Found",
                    systemImage: "cube.transparent",
                    description: Text("Scan some LEGO bricks to see results here.")
                )
            } else {
                resultsLayout
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
        .sheet(isPresented: $showLocationMap) {
            ScanLocationMapSheet(session: session)
        }
    }

    private var resultsLayout: some View {
        VStack(spacing: 0) {
            // Scrollable content — the pieces list scrolls independently of the
            // fixed action bar so the user never has to scroll to the bottom of
            // a long piece list to reach the primary actions.
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
                }
                .padding()
            }

            // Fixed action bar — always visible, scrolls independently of the list.
            actionBar
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
            // The celebratory checkmark + "Scan Complete!" only makes sense for
            // a just-finished scan. When browsing history it's redundant.
            if !isFromHistory {
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
            }

            HStack(spacing: 32) {
                statItem(value: "\(session.totalPiecesFound)", label: "Total Pieces")
                statItem(value: "\(session.uniquePieceCount)", label: "Unique Types")
                statItem(value: "\(session.colorSummary.count)", label: "Colors")
            }

            // Confidence summary
            confidenceSummary

            // Measured accuracy from the user's own verifications — an honest
            // number, unlike the heuristic per-piece confidence above.
            if let accuracy = reliability.observedAccuracy {
                Label("Verified accuracy: \(Int(accuracy * 100))% over \(reliability.totalSamples) checks",
                      systemImage: "checkmark.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Sprint C — captured location. Tappable chip that opens the pin on
            // a map. Purple/lavender (not red) so it never reads as an error.
            if session.latitude != nil, session.longitude != nil {
                Button {
                    showLocationMap = true
                    HapticManager.selection()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.circle.fill")
                        Text(session.placeName ?? "Location captured")
                            .font(.subheadline)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                    .foregroundStyle(Color.legoPurple)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(Color.legoLavender)
                    )
                }
                .accessibilityLabel("Scanned at \(session.placeName ?? "captured location")")
                .accessibilityHint("Opens the scan location on a map")
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

    // MARK: - Action Bar (fixed footer)

    private var actionBar: some View {
        VStack(spacing: 10) {
            // Primary CTA — always the most prominent action.
            Button {
                navigateToBuilds = true
            } label: {
                Label("See What You Can Build", systemImage: "hammer.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
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

            // Secondary actions — compact 2-column grid so they stay visible
            // without dominating the footer.
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                if !session.sourceImages.isEmpty {
                    secondaryActionButton("Pile Photo", systemImage: "photo.on.rectangle.angled") {
                        showPileSheet = true
                    }
                    .accessibilityHint("Tap pieces in the photo to highlight where they were detected")
                }

                secondaryActionButton("Full Catalog", systemImage: "list.bullet") {
                    navigateToCatalog = true
                }
                .accessibilityHint("Browse all detected pieces with filters and sorting")

                secondaryActionButton("Sorting", systemImage: "tray.2.fill") {
                    showSortingSuggestions = true
                }
                .accessibilityHint("Recommended storage bin layouts for your pieces")

                if ScanHistoryStore.shared.entries.contains(where: { $0.id != session.id }) {
                    secondaryActionButton("Compare", systemImage: "arrow.left.arrow.right.circle") {
                        showPileDiff = true
                    }
                    .accessibilityHint("See added and removed pieces vs a previous scan")
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func secondaryActionButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.legoBlue)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
            )
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
                        VerificationReliabilityStore.shared.record(predictedConfidence: piece.confidence, wasCorrect: true)
                        HapticManager.notification(.success)
                        if ContributionUploadQueue.shared.isSharingEnabled,
                           let box = piece.boundingBox,
                           let source = session.sourceImage(for: piece),
                           let crop = EditPieceView.cropImage(source, visionBox: box) {
                            ContributionUploadQueue.shared.enqueueCorrection(
                                crop: crop, action: "confirm", predicted: piece,
                                userPartNumber: piece.partNumber, userColor: piece.color,
                                userStudsWide: piece.dimensions.studsWide, userStudsLong: piece.dimensions.studsLong,
                                correctedShape: false, correctedColor: false)
                            Task { await ContributionUploadQueue.shared.flush() }
                        }
                    } label: {
                        Label("Mark Correct", systemImage: "checkmark.circle")
                    }
                    Button {
                        VerificationReliabilityStore.shared.record(predictedConfidence: piece.confidence, wasCorrect: false)
                        pieceToEdit = piece
                    } label: {
                        Label("Mark Wrong / Fix", systemImage: "xmark.circle")
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

// MARK: - Scan Location Map Sheet

/// Shows the single captured location for a scan as a pin on a map.
struct ScanLocationMapSheet: View {
    @ObservedObject var session: ScanSession
    @Environment(\.dismiss) private var dismiss

    private var coordinate: CLLocationCoordinate2D? {
        guard let lat = session.latitude, let lon = session.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let coordinate {
                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    ))) {
                        Annotation(session.placeName ?? "Scan location", coordinate: coordinate) {
                            ZStack {
                                Circle()
                                    .fill(Color.legoLavender)
                                    .frame(width: 40, height: 40)
                                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                                Image(systemName: "mappin.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(Color.legoPurple)
                            }
                        }
                    }
                    .ignoresSafeArea(edges: .bottom)
                } else {
                    ContentUnavailableView(
                        "No Location",
                        systemImage: "mappin.slash",
                        description: Text("This scan doesn't have a captured location.")
                    )
                }
            }
            .navigationTitle(session.placeName ?? "Scan Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
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
        let shapeChanged = original.category != selectedCategory ||
            original.dimensions.studsWide != studsWide ||
            original.dimensions.studsLong != studsLong ||
            original.name != name
        let colorChanged = original.color != selectedColor
        if shapeChanged || colorChanged {
            CorrectionLogger.shared.logCorrection(
                original: original,
                correctedName: name,
                correctedCategory: selectedCategory,
                correctedColor: selectedColor,
                correctedStudsWide: studsWide,
                correctedStudsLong: studsLong
            )

            // Persist the crop + confirmed answer so the scanner learns this
            // brick for future scans (needs the source image + a bounding box).
            if let box = piece.boundingBox,
               let source = session.sourceImage(for: piece),
               let crop = Self.cropImage(source, visionBox: box) {
                BrickCorrectionStore.shared.record(
                    crop: crop,
                    partNumber: piece.partNumber,
                    name: name,
                    category: selectedCategory,
                    color: selectedColor,
                    studsWide: studsWide,
                    studsLong: studsLong,
                    heightUnits: heightUnits,
                    correctedShape: shapeChanged,
                    correctedColor: colorChanged
                )

                // Also share it anonymously (embedding + labels, no photo) when opted in.
                ContributionUploadQueue.shared.enqueueCorrection(
                    crop: crop, action: "correct", predicted: original,
                    userPartNumber: piece.partNumber, userColor: selectedColor,
                    userStudsWide: studsWide, userStudsLong: studsLong,
                    correctedShape: shapeChanged, correctedColor: colorChanged
                )
                Task { await ContributionUploadQueue.shared.flush() }
            }
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

    /// Crop the source image to a piece's Vision bounding box (origin
    /// bottom-left, normalized) for storing as correction training data.
    fileprivate static func cropImage(_ image: UIImage, visionBox: CGRect) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let rect = CGRect(
            x: visionBox.origin.x * w,
            y: (1 - visionBox.origin.y - visionBox.height) * h,
            width: visionBox.width * w,
            height: visionBox.height * h
        ).intersection(CGRect(x: 0, y: 0, width: w, height: h))
        guard !rect.isEmpty, let cropped = cg.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cropped)
    }
}
