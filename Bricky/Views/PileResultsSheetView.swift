import SwiftUI

/// Sprint 6 / A3 — Brickit-style results sheet.
///
/// Shows the original pile photo with detected piece bounding boxes
/// overlaid, plus a horizontally-scrolling thumbnail strip at the bottom.
/// Tap a thumbnail to highlight that piece's box; multi-select highlights
/// multiple boxes at once.
///
/// This view *coexists* with the existing `ScanResultsView` — it's reachable
/// via a "Pile View" button on results, not a replacement.
struct PileResultsSheetView: View {
    @ObservedObject var session: ScanSession
    /// Sprint 2 / B2 — when set, only pieces matching this part number
    /// are displayed in the thumbnail strip and pre-highlighted in the photo.
    /// `nil` (default) preserves the original “show all” behavior.
    let highlightPartNumber: String?
    @State private var selectedPieceIDs: Set<UUID> = []
    @State private var multiSelect = false
    @Environment(\.dismiss) private var dismiss

    init(session: ScanSession, highlightPartNumber: String? = nil) {
        self.session = session
        self.highlightPartNumber = highlightPartNumber
    }

    /// Pieces grouped by their capture (most scans = one capture).
    private var captureIndices: [Int] {
        let indices = Set(session.pieces.compactMap { $0.captureIndex })
        return indices.sorted()
    }

    @State private var currentCapture: Int = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                pileImageArea
                Divider()
                thumbnailStrip
            }
            .navigationTitle("Page \(currentCapture + 1) of \(max(captureIndices.count, 1))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        multiSelect.toggle()
                        if !multiSelect { selectedPieceIDs.removeAll() }
                    } label: {
                        Image(systemName: multiSelect ? "checkmark.circle.fill" : "checkmark.circle")
                    }
                    .accessibilityLabel(multiSelect ? "Exit multi-select" : "Multi-select")
                }
            }
        }
    }

    // MARK: - Pile image with overlays

    private var pileImageArea: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                if let img = session.sourceImages[currentCapture] {
                    let displaySize = aspectFit(image: img.size, in: proxy.size)
                    let originX = (proxy.size.width - displaySize.width) / 2
                    let originY = (proxy.size.height - displaySize.height) / 2
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(width: displaySize.width, height: displaySize.height)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    // Bounding boxes for highlighted pieces.
                    ForEach(visiblePieces) { piece in
                        if let box = piece.boundingBox, isHighlighted(piece) {
                            let rect = denormalize(box: box,
                                                   inSize: displaySize,
                                                   origin: CGPoint(x: originX, y: originY))
                            Rectangle()
                                .stroke(Color.legoColor(piece.color), lineWidth: 3)
                                .frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                                .shadow(color: .black.opacity(0.6), radius: 2)
                        }
                    }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.system(size: 48))
                            .foregroundStyle(.white.opacity(0.4))
                        Text("Pile photo not available")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
        }
    }

    private var visiblePieces: [LegoPiece] {
        let inCapture = session.pieces.filter { ($0.captureIndex ?? 0) == currentCapture }
        guard let target = highlightPartNumber else { return inCapture }
        return inCapture.filter { $0.partNumber == target }
    }

    private func isHighlighted(_ piece: LegoPiece) -> Bool {
        // When in find-mode, every visible piece is highlighted by default
        // (since they're all matches).
        if highlightPartNumber != nil { return true }
        if selectedPieceIDs.isEmpty { return true }
        return selectedPieceIDs.contains(piece.id)
    }

    // MARK: - Thumbnail strip

    private var thumbnailStrip: some View {
        VStack(spacing: 6) {
            HStack {
                Text(thumbnailSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !selectedPieceIDs.isEmpty {
                    Button("Clear") {
                        selectedPieceIDs.removeAll()
                    }
                    .font(.caption)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(visiblePieces) { piece in
                        thumbnail(for: piece)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .background(.ultraThinMaterial)
        .frame(height: 130)
    }

    private var thumbnailSubtitle: String {
        if selectedPieceIDs.isEmpty {
            return "\(visiblePieces.count) detected · tap a tile to highlight"
        }
        return "\(selectedPieceIDs.count) selected"
    }

    private func thumbnail(for piece: LegoPiece) -> some View {
        let selected = selectedPieceIDs.contains(piece.id)
        return Button {
            toggle(piece)
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Circle()
                        .fill(Color.legoColor(piece.color))
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: piece.category.systemImage)
                                .foregroundStyle(.white)
                                .font(.title3)
                        )
                        .overlay(
                            Circle()
                                .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 3)
                        )
                    if piece.quantity > 1 {
                        Text("×\(piece.quantity)")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.black.opacity(0.7)))
                            .foregroundStyle(.white)
                            .offset(x: 4, y: -4)
                    }
                }
                Text(piece.name)
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(maxWidth: 70)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(piece.name), \(piece.color.rawValue), quantity \(piece.quantity)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func toggle(_ piece: LegoPiece) {
        if multiSelect {
            if selectedPieceIDs.contains(piece.id) {
                selectedPieceIDs.remove(piece.id)
            } else {
                selectedPieceIDs.insert(piece.id)
            }
        } else {
            // Single-select: tapping a selected tile clears; tapping a new
            // one replaces.
            if selectedPieceIDs == [piece.id] {
                selectedPieceIDs.removeAll()
            } else {
                selectedPieceIDs = [piece.id]
            }
        }
    }

    // MARK: - Layout helpers

    /// Compute the on-screen rect occupied by an aspect-fit image of
    /// `image` size inside `bounds`.
    private func aspectFit(image: CGSize, in bounds: CGSize) -> CGSize {
        guard image.width > 0, image.height > 0,
              bounds.width > 0, bounds.height > 0 else { return .zero }
        let scale = min(bounds.width / image.width, bounds.height / image.height)
        return CGSize(width: image.width * scale, height: image.height * scale)
    }

    /// Convert a normalized bounding box (0–1, top-left origin) into a
    /// screen-space rect inside the displayed image area.
    private func denormalize(box: CGRect, inSize size: CGSize, origin: CGPoint) -> CGRect {
        CGRect(x: origin.x + box.minX * size.width,
               y: origin.y + box.minY * size.height,
               width: box.width * size.width,
               height: box.height * size.height)
    }
}
