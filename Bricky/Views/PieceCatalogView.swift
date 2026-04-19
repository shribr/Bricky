import SwiftUI

/// Displays all cataloged LEGO pieces with filtering and sorting
struct PieceCatalogView: View {
    @StateObject private var viewModel = PieceCatalogViewModel()
    let pieces: [LegoPiece]

    var body: some View {
        VStack(spacing: 0) {
            // Summary strip
            summaryStrip

            // Filter bar
            filterBar

            // Piece list
            if viewModel.filteredPieces.isEmpty {
                emptyState
            } else {
                pieceList
            }
        }
        .navigationTitle("Piece Catalog")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $viewModel.searchText, prompt: "Search pieces...")
        .onAppear {
            viewModel.pieces = pieces
        }
    }

    // MARK: - Summary Strip

    private var summaryStrip: some View {
        HStack(spacing: 24) {
            Label("\(viewModel.totalPieceCount) total", systemImage: "cube.fill")
            Label("\(viewModel.uniquePieceCount) unique", systemImage: "square.stack.3d.up.fill")
            Label("\(viewModel.colorCounts.count) colors", systemImage: "paintpalette.fill")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Sort picker
                Menu {
                    ForEach(PieceCatalogViewModel.SortOrder.allCases, id: \.self) { order in
                        Button {
                            viewModel.sortOrder = order
                        } label: {
                            if viewModel.sortOrder == order {
                                Label(order.rawValue, systemImage: "checkmark")
                            } else {
                                Text(order.rawValue)
                            }
                        }
                    }
                } label: {
                    filterChip(label: "Sort: \(viewModel.sortOrder.rawValue)", active: true)
                }

                // Category filter
                Menu {
                    Button("All Categories") {
                        viewModel.selectedCategory = nil
                    }
                    Divider()
                    ForEach(PieceCategory.allCases, id: \.self) { cat in
                        Button {
                            viewModel.selectedCategory = cat
                        } label: {
                            Label(cat.rawValue, systemImage: cat.systemImage)
                        }
                    }
                } label: {
                    filterChip(
                        label: viewModel.selectedCategory?.rawValue ?? "Category",
                        active: viewModel.selectedCategory != nil
                    )
                }

                // Color filter
                Menu {
                    Button("All Colors") {
                        viewModel.selectedColor = nil
                    }
                    Divider()
                    ForEach(LegoColor.allCases, id: \.self) { color in
                        Button(color.rawValue) {
                            viewModel.selectedColor = color
                        }
                    }
                } label: {
                    filterChip(
                        label: viewModel.selectedColor?.rawValue ?? "Color",
                        active: viewModel.selectedColor != nil
                    )
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    private func filterChip(label: String, active: Bool) -> some View {
        Text(label)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(active ? Color.legoBlue.opacity(0.15) : Color.gray.opacity(0.1))
            .foregroundStyle(active ? Color.legoBlue : Color.primary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(active ? Color.legoBlue.opacity(0.3) : Color.clear, lineWidth: 1)
            )
    }

    // MARK: - Piece List

    private var pieceList: some View {
        List {
            ForEach(viewModel.filteredPieces) { piece in
                PieceRowView(piece: piece) { amount in
                    viewModel.adjustQuantity(for: piece, by: amount)
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    let piece = viewModel.filteredPieces[index]
                    viewModel.removePiece(piece)
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Pieces Found", systemImage: "cube.transparent")
        } description: {
            Text("No pieces match your current filters.")
        } actions: {
            Button("Clear Filters") {
                viewModel.searchText = ""
                viewModel.selectedCategory = nil
                viewModel.selectedColor = nil
            }
            .buttonStyle(.bordered)
        }
    }
}

// MARK: - Piece Row View

struct PieceRowView: View {
    let piece: LegoPiece
    let onAdjustQuantity: (Int) -> Void
    /// Sprint 2 / B5 — fires when the user taps the explicit Find button.
    /// Optional so call-sites that don't care can ignore it.
    var onFindLive: (() -> Void)? = nil
    var onFindInSavedScans: (() -> Void)? = nil

    @State private var showFindLive = false
    @State private var showSavedPicker = false

    var body: some View {
        HStack(spacing: 12) {
            // Piece preview image
            Image(uiImage: PieceImageGenerator.shared.image(for: piece, size: 40))
                .resizable()
                .interpolation(.high)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .shadow(radius: 1)
                .accessibilityHidden(true)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(piece.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    Text(piece.color.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(piece.dimensions.displayString)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Confidence badge
                    HStack(spacing: 2) {
                        Image(systemName: Color.confidenceIcon(piece.confidence))
                            .font(.system(size: 9))
                        Text("\(Int(piece.confidence * 100))%")
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(Color.confidenceColor(piece.confidence))
                }
            }

            Spacer()

            // Quantity controls
            HStack(spacing: 8) {
                // Sprint 2 / B5 — explicit Find button
                Button {
                    if let onFindLive { onFindLive() } else { showFindLive = true }
                } label: {
                    Image(systemName: "magnifyingglass.circle.fill")
                        .foregroundStyle(Color.legoGreen)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Find \(piece.name) in live pile")

                Button {
                    onAdjustQuantity(-1)
                } label: {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Decrease quantity")

                Text("\(piece.quantity)")
                    .font(.headline)
                    .monospacedDigit()
                    .frame(minWidth: 24)
                    .accessibilityLabel("Quantity \(piece.quantity)")

                Button {
                    onAdjustQuantity(1)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.legoBlue)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Increase quantity")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(piece.name), \(piece.color.rawValue), \(piece.dimensions.displayString), quantity \(piece.quantity), \(Int(piece.confidence * 100)) percent confidence")
        .contextMenu {
            Button {
                if let onFindLive { onFindLive() } else { showFindLive = true }
            } label: {
                Label("Find in Live Pile", systemImage: "magnifyingglass")
            }
            Button {
                if let onFindInSavedScans { onFindInSavedScans() } else { showSavedPicker = true }
            } label: {
                Label("Find in Saved Scans", systemImage: "tray.full")
            }
        }
        .fullScreenCover(isPresented: $showFindLive) {
            FindPieceView(piece: piece)
        }
        .sheet(isPresented: $showSavedPicker) {
            FindInSavedScanPickerView(targetPiece: piece)
        }
    }
}
