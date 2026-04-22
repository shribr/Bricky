import SwiftUI
import PhotosUI

/// Sprint 2 / B4 — "Find a Brick" hub: searchable list across the full
/// `LegoPartsCatalog` (~17K parts via merged catalogs). Each row shows
/// whether the user has the piece in any saved scan, and tapping opens
/// an action sheet with Find Live / Find in Saved Scan options.
struct FindABrickHubView: View {
    @State private var query: String = ""
    @State private var selectedCategory: PieceCategory? = nil

    @State private var selectedPiece: SearchablePiece?
    @State private var pieceToFindLive: LegoPiece?
    @State private var showSavedScanPicker = false
    @State private var showPhotoFinder = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var uploadedImage: UIImage?

    @ObservedObject private var history = ScanHistoryStore.shared

    /// A flattened, searchable representation. Pieces from saved scans take
    /// precedence so we can preserve color info; otherwise fall back to a
    /// neutral default color from the catalog entry.
    struct SearchablePiece: Identifiable, Hashable {
        let id: String  // partNumber
        let partNumber: String
        let name: String
        let category: PieceCategory
        let dimensions: PieceDimensions
        let displayColor: LegoColor
        let scanMatchCount: Int
        let totalQuantityAcrossScans: Int

        /// Convert to a transient `LegoPiece` suitable for `FindPieceView` /
        /// `FindInSavedScanPickerView`.
        func asLegoPiece() -> LegoPiece {
            LegoPiece(
                partNumber: partNumber,
                name: name,
                category: category,
                color: displayColor,
                dimensions: dimensions,
                confidence: 1.0,
                quantity: 1
            )
        }
    }

    /// Build the search index once per query change.
    private var results: [SearchablePiece] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Map of partNumber -> aggregated stats across all saved scans.
        var scanStats: [String: (matchCount: Int, totalQty: Int, color: LegoColor)] = [:]
        for entry in history.entries {
            var seenInThisScan = Set<String>()
            for piece in entry.pieces {
                let prev = scanStats[piece.partNumber]
                let firstHitInScan = !seenInThisScan.contains(piece.partNumber)
                seenInThisScan.insert(piece.partNumber)
                scanStats[piece.partNumber] = (
                    matchCount: (prev?.matchCount ?? 0) + (firstHitInScan ? 1 : 0),
                    totalQty: (prev?.totalQty ?? 0) + piece.quantity,
                    color: prev?.color ?? piece.color
                )
            }
        }

        let catalog = LegoPartsCatalog.shared
        let candidates: [LegoPartsCatalog.CatalogPiece]
        if q.isEmpty {
            // Default view: show pieces the user actually owns first
            candidates = catalog.pieces.filter { scanStats[$0.partNumber] != nil }
        } else {
            candidates = catalog.search(query: q)
        }

        let filtered = candidates.filter { piece in
            selectedCategory == nil || piece.category == selectedCategory
        }

        return filtered.map { catalogPiece in
            let stats = scanStats[catalogPiece.partNumber]
            return SearchablePiece(
                id: catalogPiece.partNumber,
                partNumber: catalogPiece.partNumber,
                name: catalogPiece.name,
                category: catalogPiece.category,
                dimensions: catalogPiece.dimensions,
                displayColor: stats?.color ?? catalogPiece.commonColors.first ?? .gray,
                scanMatchCount: stats?.matchCount ?? 0,
                totalQuantityAcrossScans: stats?.totalQty ?? 0
            )
        }
        .sorted { lhs, rhs in
            // In your scans first, then by name
            if (lhs.scanMatchCount > 0) != (rhs.scanMatchCount > 0) {
                return lhs.scanMatchCount > 0
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            categoryFilterBar
            if results.isEmpty {
                emptyState
            } else {
                resultsList
            }
        }
        .navigationTitle("Find a Brick")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search 17,000+ pieces…")
        .confirmationDialog(
            selectedPiece?.name ?? "Find piece",
            isPresented: Binding(
                get: { selectedPiece != nil && pieceToFindLive == nil && !showSavedScanPicker },
                set: { if !$0 { selectedPiece = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let piece = selectedPiece {
                Button("Find in Live Pile") {
                    pieceToFindLive = piece.asLegoPiece()
                    selectedPiece = nil
                }
                if piece.scanMatchCount > 0 {
                    Button("Find in Saved Scans (\(piece.scanMatchCount))") {
                        showSavedScanPicker = true
                    }
                }
                Button("Find in Photo") {
                    showPhotoFinder = true
                }
                Button("Cancel", role: .cancel) {
                    selectedPiece = nil
                }
            }
        } message: {
            if let piece = selectedPiece {
                Text(piece.scanMatchCount > 0
                     ? "Found in \(piece.scanMatchCount) of your saved scans."
                     : "Not found in any saved scan yet.")
            }
        }
        .fullScreenCover(item: $pieceToFindLive) { piece in
            FindPieceView(piece: piece)
        }
        .sheet(isPresented: $showSavedScanPicker, onDismiss: { selectedPiece = nil }) {
            if let piece = selectedPiece {
                FindInSavedScanPickerView(targetPiece: piece.asLegoPiece())
            }
        }
        .photosPicker(
            isPresented: $showPhotoFinder,
            selection: $photoPickerItem,
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: photoPickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    uploadedImage = image
                }
                photoPickerItem = nil
            }
        }
        .fullScreenCover(item: Binding<FindInPhotoContext?>(
            get: {
                guard let img = uploadedImage, let piece = selectedPiece else { return nil }
                return FindInPhotoContext(piece: piece.asLegoPiece(), image: img)
            },
            set: { newVal in
                if newVal == nil {
                    uploadedImage = nil
                    selectedPiece = nil
                }
            }
        )) { context in
            FindInPhotoView(piece: context.piece, image: context.image)
        }
    }

    // MARK: - Category filter

    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(label: "All", active: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(PieceCategory.allCases, id: \.self) { cat in
                    chip(label: cat.rawValue, active: selectedCategory == cat, icon: cat.systemImage) {
                        selectedCategory = (selectedCategory == cat) ? nil : cat
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    private func chip(label: String, active: Bool, icon: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon = icon { Image(systemName: icon).font(.caption2) }
                Text(label).font(.caption.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(active ? Color.legoBlue.opacity(0.18) : Color.gray.opacity(0.1))
            .foregroundStyle(active ? Color.legoBlue : Color.primary)
            .clipShape(Capsule())
        }
    }

    // MARK: - Results list

    private var resultsList: some View {
        List(results) { result in
            Button {
                selectedPiece = result
            } label: {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.legoColor(result.displayColor))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Image(systemName: result.category.systemImage)
                                .foregroundStyle(.white.opacity(0.85))
                                .font(.caption)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        HStack(spacing: 8) {
                            Text(result.dimensions.displayString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("·")
                                .foregroundStyle(.secondary)
                            Text(result.partNumber)
                                .font(.caption.monospaced())
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    if result.scanMatchCount > 0 {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(result.scanMatchCount) scan\(result.scanMatchCount == 1 ? "" : "s")")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.legoGreen)
                            Text("×\(result.totalQuantityAcrossScans) total")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Not yet found")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label(query.isEmpty ? "Search the Catalog" : "No Results",
                  systemImage: "magnifyingglass")
        } description: {
            Text(query.isEmpty
                 ? "Type a piece name (\u{201C}plate 2x4\u{201D}) or part number to search across thousands of LEGO elements."
                 : "Try a different keyword or part number.")
        }
    }
}

// MARK: - Find in Photo context

/// Used as an Identifiable item for fullScreenCover binding.
struct FindInPhotoContext: Identifiable, Equatable {
    let id = UUID()
    let piece: LegoPiece
    let image: UIImage

    static func == (lhs: FindInPhotoContext, rhs: FindInPhotoContext) -> Bool {
        lhs.id == rhs.id
    }
}
