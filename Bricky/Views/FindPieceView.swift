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
            // FindPieceView always shows the regular AVCaptureSession
            // preview, so explicitly configure THAT camera regardless of the
            // user's current tracking-mode setting (otherwise, when the user
            // is in AR World Tracking mode, `viewModel.setupCamera()` would
            // configure the AR session and the regular preview would stay
            // black).
            viewModel.cameraManager.configureAndStart { [weak viewModel] in
                Task { @MainActor in
                    viewModel?.startFindPiece(piece)
                }
            }
        }
        .onDisappear {
            viewModel.stopFindPiece()
        }
        .statusBarHidden()
    }
}

/// Overlay that dims everything except matched piece bounding boxes
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
                    // Convert Vision coords to view coords
                    let rect = CGRect(
                        x: detection.boundingBox.origin.x * size.width,
                        y: (1 - detection.boundingBox.origin.y - detection.boundingBox.height) * size.height,
                        width: detection.boundingBox.width * size.width,
                        height: detection.boundingBox.height * size.height
                    )

                    // Cut out the piece area (clear the dim)
                    context.blendMode = .destinationOut
                    let clearRect = Path(roundedRect: rect.insetBy(dx: -4, dy: -4), cornerRadius: 6)
                    context.fill(clearRect, with: .color(.white))

                    // Draw highlight border
                    context.blendMode = .normal
                    let borderColor = Color.legoColor(detection.dominantColor)

                    // Outer glow
                    context.stroke(
                        Path(roundedRect: rect.insetBy(dx: -6, dy: -6), cornerRadius: 8),
                        with: .color(borderColor.opacity(0.4)),
                        lineWidth: 4
                    )

                    // Main border
                    context.stroke(
                        Path(roundedRect: rect.insetBy(dx: -2, dy: -2), cornerRadius: 5),
                        with: .color(borderColor),
                        lineWidth: 3
                    )

                    // White inner border
                    context.stroke(
                        Path(roundedRect: rect, cornerRadius: 4),
                        with: .color(.white.opacity(0.8)),
                        lineWidth: 1.5
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}
