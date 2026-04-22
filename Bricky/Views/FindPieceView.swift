import SwiftUI

/// Camera view for finding a specific piece in a pile of bricks.
/// Shows the live camera feed, dims everything except the target piece when found.
struct FindPieceView: View {
    let piece: LegoPiece
    @StateObject private var viewModel = CameraViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // Camera feed
            CameraPreview(session: viewModel.cameraManager.session)
                .ignoresSafeArea()

            // Dimming overlay when target is found — dim everything except matched detections
            if viewModel.targetPieceFound {
                FindPieceOverlayView(detections: viewModel.liveDetections)
                    .ignoresSafeArea()
                    .transition(.opacity)
            } else if !viewModel.liveDetections.isEmpty {
                // Show normal overlay for non-target detections dimmed
                LiveDetectionOverlayView(detections: viewModel.liveDetections)
                    .ignoresSafeArea()
            }

            // Top bar
            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.statusMessage)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("\(piece.color.rawValue) \(piece.dimensions.displayString)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    Spacer()

                    Button {
                        viewModel.stopFindPiece()
                        dismiss()
                    } label: {
                        Text("Done")
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.legoBlue)
                            .clipShape(Capsule())
                    }
                }
                .padding()
                .background(
                    LinearGradient(
                        colors: [.black.opacity(0.85), .black.opacity(0.6), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea(edges: .top)
                )

                Spacer()

                // Found indicator
                if viewModel.targetPieceFound {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Piece found! Look for the highlighted area.")
                            .fontWeight(.medium)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.bottom, 40)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(.white)
                        Text("Point camera at your pile of bricks...")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.black.opacity(0.6))
                    .clipShape(Capsule())
                    .padding(.bottom, 40)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: viewModel.targetPieceFound)
        }
        .onAppear {
            viewModel.cameraManager.configureAndStart { [weak viewModel] in
                Task { @MainActor in
                    viewModel?.startFindPiece(piece)
                }
            }
        }
        .onDisappear {
            viewModel.stopFindPiece()
            viewModel.cameraManager.stopSession()
        }
        .statusBarHidden()
    }
}

// MARK: - Placeholder (uncomment to use instead of camera)
/*
struct FindPieceViewPlaceholder: View {
    let piece: LegoPiece
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.legoYellow.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "eye.trianglebadge.exclamationmark")
                    .font(.system(size: 56))
                    .foregroundStyle(.black.opacity(0.6))
                VStack(spacing: 12) {
                    Text("Live Pile Search")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.black)
                    Text("You are attempting to search for the **\(piece.name)** piece in a pile of bricks using your camera.")
                        .font(.body)
                        .foregroundStyle(.black.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Text("This feature is coming soon.")
                        .font(.subheadline)
                        .foregroundStyle(.black.opacity(0.5))
                }
                Spacer()
            }
            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.black.opacity(0.7))
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(.black.opacity(0.1)))
                    }
                    .padding()
                }
                Spacer()
            }
        }
        .statusBarHidden()
    }
}
*/

/// Overlay that dims everything except matched pieces.
/// When contour points are available, traces the actual brick perimeter.
/// Falls back to rounded rectangles when no contour data exists.
struct FindPieceOverlayView: View {
    let detections: [ObjectRecognitionService.DetectedObject]

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                // Draw full-screen dim
                context.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .color(.black.opacity(0.55))
                )

                for detection in detections {
                    let borderColor = Color.legoColor(detection.dominantColor)

                    if let contourPoints = detection.contourPoints, contourPoints.count >= 3 {
                        // --- Contour-based highlight ---
                        let screenPoints = contourPoints.map { pt in
                            CGPoint(
                                x: CGFloat(pt.x) * size.width,
                                y: (1 - CGFloat(pt.y)) * size.height
                            )
                        }

                        // Build closed contour path
                        var contourPath = Path()
                        contourPath.move(to: screenPoints[0])
                        for pt in screenPoints.dropFirst() {
                            contourPath.addLine(to: pt)
                        }
                        contourPath.closeSubpath()

                        // Cut out the piece area from the dim layer
                        context.blendMode = .destinationOut
                        // Slightly expanded for padding
                        context.fill(contourPath, with: .color(.white))

                        // Draw highlight contour
                        context.blendMode = .normal

                        // Outer glow
                        context.stroke(
                            contourPath,
                            with: .color(borderColor.opacity(0.4)),
                            lineWidth: 5
                        )

                        // Main contour border
                        context.stroke(
                            contourPath,
                            with: .color(borderColor),
                            lineWidth: 3
                        )

                        // Inner white edge
                        context.stroke(
                            contourPath,
                            with: .color(.white.opacity(0.7)),
                            lineWidth: 1.5
                        )
                    } else {
                        // --- Fallback: rounded rectangle ---
                        let rect = CGRect(
                            x: detection.boundingBox.origin.x * size.width,
                            y: (1 - detection.boundingBox.origin.y - detection.boundingBox.height) * size.height,
                            width: detection.boundingBox.width * size.width,
                            height: detection.boundingBox.height * size.height
                        )

                        context.blendMode = .destinationOut
                        let clearRect = Path(roundedRect: rect.insetBy(dx: -4, dy: -4), cornerRadius: 6)
                        context.fill(clearRect, with: .color(.white))

                        context.blendMode = .normal
                        context.stroke(
                            Path(roundedRect: rect.insetBy(dx: -6, dy: -6), cornerRadius: 8),
                            with: .color(borderColor.opacity(0.4)),
                            lineWidth: 4
                        )
                        context.stroke(
                            Path(roundedRect: rect.insetBy(dx: -2, dy: -2), cornerRadius: 5),
                            with: .color(borderColor),
                            lineWidth: 3
                        )
                        context.stroke(
                            Path(roundedRect: rect, cornerRadius: 4),
                            with: .color(.white.opacity(0.8)),
                            lineWidth: 1.5
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}
