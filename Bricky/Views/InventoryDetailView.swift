import SwiftUI
import UniformTypeIdentifiers

/// Shows the contents of a saved inventory with piece list, summary stats, breakdowns,
/// and management actions. Visual parity with `ScanResultsView`, minus scan-only
/// features (pile photo, location capture, edit/correction logging, pile diff).
struct InventoryDetailView: View {
    @StateObject private var inventoryStore = InventoryStore.shared
    let inventoryId: UUID

    // Toolbar / management state
    @State private var isEditing = false
    @State private var editedName = ""
    @State private var showDeleteConfirmation = false
    @State private var exportFileURL: URL?
    @State private var showShareSheet = false
    @State private var showImportPicker = false
    @State private var importError: String?
    @State private var showImportError = false
    @State private var importedCount: Int = 0
    @State private var showImportSuccess = false

    // Piece interaction state — mirrors ScanResultsView
    @State private var pieceToPreview: LegoPiece?
    @State private var pieceToFindLive: LegoPiece?
    @State private var pieceToFindInSavedScan: LegoPiece?
    @State private var navigateToBuilds = false
    @State private var navigateToCatalog = false
    @State private var showSortingSuggestions = false
    @State private var pieceToDelete: InventoryStore.InventoryPiece?
    @State private var showDeletePieceConfirm = false

    @StateObject private var filterState = PieceFilterSortState()
    @Environment(\.dismiss) private var dismiss

    private var inventory: InventoryStore.Inventory? {
        inventoryStore.inventories.first(where: { $0.id == inventoryId })
    }

    var body: some View {
        Group {
            if let inventory {
                scrollContent(inventory)
            } else {
                ContentUnavailableView("Inventory Not Found",
                                       systemImage: "tray",
                                       description: Text("This inventory may have been deleted."))
            }
        }
        .navigationTitle(inventory?.name ?? "Inventory")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToBuilds) {
            if let inventory {
                BuildSuggestionsView(pieces: legoPieces(from: inventory))
            }
        }
        .navigationDestination(isPresented: $navigateToCatalog) {
            if let inventory {
                PieceCatalogView(pieces: legoPieces(from: inventory))
            }
        }
        .sheet(item: $pieceToPreview) { piece in
            ModelViewerView(piece: piece)
        }
        .fullScreenCover(item: $pieceToFindLive) { piece in
            FindPieceView(piece: piece)
        }
        .sheet(item: $pieceToFindInSavedScan) { piece in
            FindInSavedScanPickerView(targetPiece: piece)
        }
        .sheet(isPresented: $showSortingSuggestions) {
            if let inventory {
                SortingSuggestionsView(pieces: legoPieces(from: inventory))
            }
        }
        .toolbar {
            if inventory != nil {
                ToolbarItem(placement: .navigationBarTrailing) {
                    inventoryMenu
                }
            }
        }
        .alert("Rename Inventory", isPresented: $isEditing) {
            TextField("Name", text: $editedName)
            Button("Save") {
                if !editedName.trimmingCharacters(in: .whitespaces).isEmpty {
                    inventoryStore.renameInventory(id: inventoryId, name: editedName)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete Inventory?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                inventoryStore.deleteInventory(id: inventoryId)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let inventory {
                Text("This will permanently delete \"\(inventory.name)\" and all \(inventory.totalPieces) pieces. This cannot be undone.")
            }
        }
        .confirmationDialog("Remove Piece?", isPresented: $showDeletePieceConfirm, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let piece = pieceToDelete {
                    inventoryStore.removePiece(id: piece.id, from: inventoryId)
                }
                pieceToDelete = nil
            }
            Button("Cancel", role: .cancel) { pieceToDelete = nil }
        } message: {
            if let piece = pieceToDelete {
                Text("Remove \(piece.name) (×\(piece.quantity)) from this inventory?")
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportFileURL {
                ShareSheet(items: [url])
            }
        }
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: [.commaSeparatedText, .xml],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let didAccess = url.startAccessingSecurityScopedResource()
                defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                do {
                    let pieces = try InventoryImporter.importFile(at: url)
                    inventoryStore.addPieces(pieces, to: inventoryId)
                    importedCount = pieces.count
                    showImportSuccess = true
                } catch {
                    importError = error.localizedDescription
                    showImportError = true
                }
            case .failure(let error):
                importError = error.localizedDescription
                showImportError = true
            }
        }
        .alert("Import Failed", isPresented: $showImportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "Unknown error")
        }
        .alert("Import Successful", isPresented: $showImportSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Imported \(importedCount) pieces into this inventory.")
        }
    }

    // MARK: - Scroll content

    private func scrollContent(_ inventory: InventoryStore.Inventory) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                summaryCard(inventory)

                if !inventory.pieces.isEmpty {
                    detectedPiecesList(inventory)
                }

                let categories = categorySummary(inventory)
                if !categories.isEmpty {
                    categoryBreakdown(categories)
                }

                let colors = colorSummary(inventory)
                if !colors.isEmpty {
                    colorBreakdown(colors)
                }

                actionButtons(inventory)
            }
            .padding()
        }
    }

    // MARK: - Toolbar Menu

    private var inventoryMenu: some View {
        Menu {
            Button {
                editedName = inventory?.name ?? ""
                isEditing = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Menu {
                Button {
                    if let inventory {
                        exportFileURL = InventoryExporter.csvFileURL(from: inventory)
                        if exportFileURL != nil { showShareSheet = true }
                    }
                } label: {
                    Label("Export as CSV", systemImage: "tablecells")
                }
                Button {
                    if let inventory {
                        exportFileURL = InventoryExporter.pdfFileURL(from: inventory)
                        if exportFileURL != nil { showShareSheet = true }
                    }
                } label: {
                    Label("Export as PDF", systemImage: "doc.richtext")
                }
                Button {
                    if let inventory {
                        exportFileURL = InventoryExporter.brickLinkXMLFileURL(from: inventory)
                        if exportFileURL != nil { showShareSheet = true }
                    }
                } label: {
                    Label("Export as BrickLink XML", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }

            Button {
                showImportPicker = true
            } label: {
                Label("Import Pieces", systemImage: "square.and.arrow.down")
            }

            Divider()

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete Inventory", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    // MARK: - Summary Card

    private func summaryCard(_ inventory: InventoryStore.Inventory) -> some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.legoBlue.opacity(0.15))
                    .frame(width: 72, height: 72)
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.legoBlue)
            }

            Text(inventory.name)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            HStack(spacing: 32) {
                statItem(value: "\(inventory.totalPieces)", label: "Total Pieces")
                statItem(value: "\(inventory.uniquePieces)", label: "Unique Types")
                statItem(value: "\(colorSummary(inventory).count)", label: "Colors")
            }

            HStack(spacing: 8) {
                Label(inventory.createdAt.formatted(date: .abbreviated, time: .omitted),
                      systemImage: "calendar")
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.secondary.opacity(0.12)))

                if inventory.updatedAt > inventory.createdAt.addingTimeInterval(60) {
                    Label("Updated \(inventory.updatedAt.formatted(.relative(presentation: .named)))",
                          systemImage: "clock.arrow.circlepath")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.secondary.opacity(0.12)))
                }
            }
            .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(inventory.name). \(inventory.totalPieces) total pieces, \(inventory.uniquePieces) unique types, \(colorSummary(inventory).count) colors")
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

    // MARK: - Detected Pieces List

    private func detectedPiecesList(_ inventory: InventoryStore.Inventory) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Pieces")
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
                availableColors: availableColors(in: inventory),
                availableCategories: availableCategories(in: inventory)
            )

            let visiblePieces = filterState.apply(to: inventory.pieces)

            if visiblePieces.isEmpty {
                Text("No pieces match the current search or filters.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            }

            ForEach(visiblePieces) { invPiece in
                let piece = legoPiece(from: invPiece)
                Button {
                    pieceToPreview = piece
                } label: {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.legoColor(invPiece.pieceColor))
                            .frame(width: 40, height: 40)
                            .overlay(
                                Image(systemName: invPiece.pieceCategory.systemImage)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(Color.bestForegroundOn(Color.legoColor(invPiece.pieceColor)))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                            )
                            .shadow(color: Color.legoColor(invPiece.pieceColor).opacity(0.4), radius: 3, y: 1)
                            .accessibilityLabel("\(invPiece.pieceCategory.rawValue), \(invPiece.color)")

                        VStack(alignment: .leading, spacing: 2) {
                            Text(invPiece.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text("\(invPiece.color) · \(invPiece.dimensions.displayString)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Text("×\(invPiece.quantity)")
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
                    Divider()
                    Button(role: .destructive) {
                        pieceToDelete = invPiece
                        showDeletePieceConfirm = true
                    } label: {
                        Label("Remove from Inventory", systemImage: "trash")
                    }
                } preview: {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.legoColor(invPiece.pieceColor))
                            .frame(width: 44, height: 44)
                            .overlay(
                                Image(systemName: invPiece.pieceCategory.systemImage)
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(Color.bestForegroundOn(Color.legoColor(invPiece.pieceColor)))
                            )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(invPiece.name)
                                .font(.headline)
                            Text("\(invPiece.dimensions.displayString) · \(invPiece.color)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("×\(invPiece.quantity)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(16)
                    .frame(width: 280)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(invPiece.name), \(invPiece.color), quantity \(invPiece.quantity)")
                .accessibilityHint("Tap to view 3D model. Long-press for more actions.")
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
        )
    }

    // MARK: - Category Breakdown

    private func categoryBreakdown(_ items: [(category: PieceCategory, count: Int)]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("By Category")
                .font(.headline)

            ForEach(items, id: \.category) { item in
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

    private func colorBreakdown(_ items: [(color: LegoColor, count: Int)]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("By Color")
                .font(.headline)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                ForEach(items, id: \.color) { item in
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

    private func actionButtons(_ inventory: InventoryStore.Inventory) -> some View {
        VStack(spacing: 12) {
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
            .accessibilityHint("Shows build suggestions based on this inventory")
            .disabled(inventory.pieces.isEmpty)

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
            .accessibilityHint("Browse all pieces in this inventory with filters and sorting")
            .disabled(inventory.pieces.isEmpty)

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
            .accessibilityHint("Recommended storage bin layouts for these pieces")
            .disabled(inventory.pieces.isEmpty)
        }
    }

    // MARK: - Helpers

    private func availableColors(in inventory: InventoryStore.Inventory) -> [LegoColor] {
        Array(Set(inventory.pieces.map(\.pieceColor))).sorted { $0.rawValue < $1.rawValue }
    }

    private func availableCategories(in inventory: InventoryStore.Inventory) -> [PieceCategory] {
        Array(Set(inventory.pieces.map(\.pieceCategory))).sorted { $0.rawValue < $1.rawValue }
    }

    private func categorySummary(_ inventory: InventoryStore.Inventory) -> [(category: PieceCategory, count: Int)] {
        var counts: [PieceCategory: Int] = [:]
        for p in inventory.pieces {
            counts[p.pieceCategory, default: 0] += p.quantity
        }
        return counts
            .map { (category: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    private func colorSummary(_ inventory: InventoryStore.Inventory) -> [(color: LegoColor, count: Int)] {
        var counts: [LegoColor: Int] = [:]
        for p in inventory.pieces {
            counts[p.pieceColor, default: 0] += p.quantity
        }
        return counts
            .map { (color: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    /// Build a transient `LegoPiece` from an `InventoryPiece` so the 3D viewer / Find / Builds can use it.
    private func legoPiece(from inv: InventoryStore.InventoryPiece) -> LegoPiece {
        LegoPiece(
            partNumber: inv.partNumber,
            name: inv.name,
            category: inv.pieceCategory,
            color: inv.pieceColor,
            dimensions: inv.dimensions,
            confidence: 1.0,
            quantity: inv.quantity
        )
    }

    private func legoPieces(from inventory: InventoryStore.Inventory) -> [LegoPiece] {
        inventory.pieces.map(legoPiece(from:))
    }
}
