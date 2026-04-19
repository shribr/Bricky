import SwiftUI

/// Full-screen view showing where a piece was detected in the scanned image
struct PieceLocationView: View {
    let piece: LegoPiece
    var scanSession: ScanSession?
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var showFindPiece = false
    @State private var onDemandSnapshot: UIImage?
    @State private var isGenerating = false
    @State private var viewMode: ViewMode = .detail

    /// Two ways to look at where a piece is:
    /// - `.detail` — close-up cropped highlight (the original behavior)
    /// - `.pileMap` — full pile image with the boundary outlined and the
    ///   piece's location highlighted within
    enum ViewMode: String, CaseIterable, Identifiable {
        case detail = "Detail"
        case pileMap = "Pile Map"
        var id: String { rawValue }
        var systemImage: String {
            switch self {
            case .detail: return "rectangle.dashed"
            case .pileMap: return "map"
            }
        }
    }

    private var displaySnapshot: UIImage? {
        piece.locationSnapshot ?? onDemandSnapshot
    }

    private var sourceImage: UIImage? {
        scanSession?.sourceImage(for: piece)
    }

    private var pileBoundary: [CGPoint] {
        scanSession?.pileBoundary(for: piece) ?? []
    }

    /// Sprint C — geolocation. "Last seen at \(place) · \(date)" line shown
    /// in the top bar. Returns nil when the session has no captured location.
    private var locationLine: String? {
        guard let session = scanSession,
              session.latitude != nil, session.longitude != nil else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let when = session.locationCapturedAt ?? session.startedAt
        let dateText = formatter.string(from: when)
        if let place = session.placeName, !place.isEmpty {
            return "\(place) · \(dateText)"
        }
        return dateText
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Image area — Detail (cropped highlight) or Pile Map (full image
            // with boundary outlined and piece highlighted within).
            Group {
                switch viewMode {
                case .detail:
                    if let snapshot = displaySnapshot {
                        zoomableImage(snapshot)
                    }
                case .pileMap:
                    if let img = sourceImage {
                        PileBoundaryLocationView(
                            image: img,
                            pieceBoundingBox: piece.boundingBox,
                            pileBoundary: pileBoundary,
                            highlightColor: Color.legoColor(piece.color)
                        )
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(zoomAndPanGesture)
                        .onTapGesture(count: 2) { toggleZoom() }
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "photo")
                                .font(.system(size: 48))
                                .foregroundStyle(.white.opacity(0.4))
                            Text("Pile image not available for this piece")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
            }

            // Loading indicator for on-demand generation
            if isGenerating {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                    Text("Generating highlight...")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            // Top bar overlay
            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(piece.name)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("\(piece.color.rawValue) · \(piece.dimensions.displayString)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                        if let placeLine = locationLine {
                            HStack(spacing: 4) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.caption2)
                                Text(placeLine)
                                    .font(.caption2)
                            }
                            .foregroundStyle(.white.opacity(0.7))
                        }
                    }

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .accessibilityLabel("Close")
                }
                .padding()
                .background(
                    LinearGradient(
                        colors: [.black.opacity(0.7), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea(edges: .top)
                )

                Spacer()

                // Bottom controls
                VStack(spacing: 12) {
                    // Find in pile button
                    Button {
                        showFindPiece = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "camera.viewfinder")
                                .font(.headline)
                            Text("Find in Pile")
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.legoBlue)
                        .clipShape(Capsule())
                        .shadow(color: Color.legoBlue.opacity(0.4), radius: 6, y: 3)
                    }
                    .accessibilityLabel("Find \(piece.name) in pile")
                    .accessibilityHint("Opens camera to scan for this specific piece")

                    // View mode toggle: cropped highlight vs full pile map
                    Picker("View Mode", selection: $viewMode) {
                        ForEach(ViewMode.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.systemImage).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 32)
                    .onChange(of: viewMode) { _, _ in resetZoom() }

                    Text("Pinch to zoom · Double-tap to toggle zoom")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.bottom, 16)
            }
        }
        .statusBarHidden()
        .fullScreenCover(isPresented: $showFindPiece) {
            FindPieceView(piece: piece)
        }
        .task {
            // Generate snapshot on demand if not pre-rendered (composite mode)
            if piece.locationSnapshot == nil, onDemandSnapshot == nil,
               let box = piece.boundingBox,
               let sourceImage = scanSession?.sourceImage(for: piece) {
                isGenerating = true
                let snapshot = await Task.detached(priority: .userInitiated) {
                    SnapshotRenderer.renderHighlight(
                        sourceImage: sourceImage,
                        highlightBox: box,
                        highlightColor: UIColor(Color.legoColor(piece.color))
                    )
                }.value
                onDemandSnapshot = snapshot
                isGenerating = false
            }
        }
    }

    // MARK: - Zoom & pan helpers (shared by both view modes)

    @ViewBuilder
    private func zoomableImage(_ snapshot: UIImage) -> some View {
        Image(uiImage: snapshot)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .scaleEffect(scale)
            .offset(offset)
            .gesture(zoomAndPanGesture)
            .onTapGesture(count: 2) { toggleZoom() }
    }

    private var zoomAndPanGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = lastScale * value.magnification
            }
            .onEnded { _ in
                lastScale = max(1.0, scale)
                scale = lastScale
                if scale <= 1.0 {
                    withAnimation(.easeOut(duration: 0.2)) {
                        offset = .zero
                        lastOffset = .zero
                    }
                }
            }
            .simultaneously(with:
                DragGesture()
                    .onChanged { value in
                        guard scale > 1.0 else { return }
                        offset = CGSize(
                            width: lastOffset.width + value.translation.width,
                            height: lastOffset.height + value.translation.height
                        )
                    }
                    .onEnded { _ in
                        lastOffset = offset
                    }
            )
    }

    private func toggleZoom() {
        withAnimation(.easeOut(duration: 0.25)) {
            if scale > 1.0 {
                resetZoom()
            } else {
                scale = 2.5
                lastScale = 2.5
            }
        }
    }

    private func resetZoom() {
        scale = 1.0
        lastScale = 1.0
        offset = .zero
        lastOffset = .zero
    }
}
