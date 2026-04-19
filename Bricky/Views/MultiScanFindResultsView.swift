import SwiftUI

/// Sprint 2 / B3 — Grid of pile photos from multiple saved scans, each
/// thumbnail showing the matching piece bounding box(es) overlaid in the
/// piece color. Tap a thumbnail to open the full `PileResultsSheetView`
/// for that scan, filtered to the target piece.
struct MultiScanFindResultsView: View {
    let sessions: [ScanSession]
    let targetPiece: LegoPiece

    @Environment(\.dismiss) private var dismiss
    @State private var openSession: ScanSession?

    private let columns = [
        GridItem(.adaptive(minimum: 150), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    headerSummary
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(sessions) { session in
                            tile(for: session)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Found in \(sessions.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $openSession) { session in
                PileResultsSheetView(session: session,
                                     highlightPartNumber: targetPiece.partNumber)
            }
        }
    }

    // MARK: - Header

    private var headerSummary: some View {
        let totalMatches = sessions.reduce(0) { sum, session in
            sum + session.pieces
                .filter { $0.partNumber == targetPiece.partNumber }
                .reduce(0) { $0 + $1.quantity }
        }
        return HStack(spacing: 8) {
            Circle()
                .fill(Color.legoColor(targetPiece.color))
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(targetPiece.name)
                    .font(.subheadline.weight(.semibold))
                Text("\(totalMatches) total occurrence\(totalMatches == 1 ? "" : "s") across \(sessions.count) scan\(sessions.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }

    // MARK: - Tile

    private func tile(for session: ScanSession) -> some View {
        let matches = session.pieces.filter { $0.partNumber == targetPiece.partNumber }
        let quantity = matches.reduce(0) { $0 + $1.quantity }
        let captureIndex = matches.first?.captureIndex ?? 0
        let image = session.sourceImages[captureIndex]
        let entryDate = session.startedAt
        let label = session.placeName ?? entryDate.formatted(date: .abbreviated, time: .omitted)

        return Button {
            openSession = session
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    if let img = image {
                        GeometryReader { proxy in
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: proxy.size.width, height: proxy.size.height)
                                .clipped()
                            ForEach(matches) { piece in
                                if let box = piece.boundingBox {
                                    let rect = denormalize(box: box,
                                                           imageSize: img.size,
                                                           in: proxy.size)
                                    Rectangle()
                                        .stroke(Color.legoColor(piece.color), lineWidth: 2.5)
                                        .frame(width: rect.width, height: rect.height)
                                        .position(x: rect.midX, y: rect.midY)
                                        .shadow(color: .black.opacity(0.6), radius: 1.5)
                                }
                            }
                        }
                        .aspectRatio(1, contentMode: .fit)
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.gray.opacity(0.2))
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundStyle(.secondary)
                            )
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                Text(label)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Text("×\(quantity) match\(quantity == 1 ? "" : "es")")
                    .font(.caption2)
                    .foregroundStyle(Color.legoGreen)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Layout helper (aspect-fill version)

    /// Convert a normalized bbox (origin top-left) to screen-space inside
    /// an aspect-fill container. The image is scaled to cover `bounds` and
    /// centered, so we crop from both axes proportionally.
    private func denormalize(box: CGRect, imageSize: CGSize, in bounds: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              bounds.width > 0, bounds.height > 0 else { return .zero }
        let scale = max(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let scaledSize = CGSize(width: imageSize.width * scale,
                                height: imageSize.height * scale)
        let offsetX = (bounds.width - scaledSize.width) / 2
        let offsetY = (bounds.height - scaledSize.height) / 2
        return CGRect(
            x: offsetX + box.minX * scaledSize.width,
            y: offsetY + box.minY * scaledSize.height,
            width: box.width * scaledSize.width,
            height: box.height * scaledSize.height
        )
    }
}
