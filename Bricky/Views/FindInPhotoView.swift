import SwiftUI

/// Displays a user-uploaded photo with object detection overlaid,
/// highlighting any instances of the target brick piece.
struct FindInPhotoView: View {
    let piece: LegoPiece
    let image: UIImage

    @StateObject private var recognitionService = ObjectRecognitionService()
    @Environment(\.dismiss) private var dismiss
    @State private var detections: [ObjectRecognitionService.DetectedObject] = []
    @State private var matchingDetections: [ObjectRecognitionService.DetectedObject] = []

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                let displaySize = aspectFit(image: image.size, in: geo.size)
                let originX = (geo.size.width - displaySize.width) / 2
                let originY = (geo.size.height - displaySize.height) / 2

                ZStack {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: displaySize.width, height: displaySize.height)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)

                    // Highlight matching pieces
                    ForEach(matchingDetections) { detection in
                        let rect = denormalize(
                            box: detection.boundingBox,
                            inSize: displaySize,
                            origin: CGPoint(x: originX, y: originY)
                        )
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.green, lineWidth: 3)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                            .shadow(color: .green.opacity(0.5), radius: 4)
                    }

                    // Show non-matching detections dimmed
                    ForEach(detections.filter { det in
                        !matchingDetections.contains(where: { $0.id == det.id })
                    }) { detection in
                        let rect = denormalize(
                            box: detection.boundingBox,
                            inSize: displaySize,
                            origin: CGPoint(x: originX, y: originY)
                        )
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                    }
                }
            }

            // Top bar
            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        if recognitionService.isProcessing {
                            HStack(spacing: 6) {
                                ProgressView().tint(.white)
                                Text("Analyzing photo…")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                            }
                        } else if !matchingDetections.isEmpty {
                            Text("Found \(matchingDetections.count) match\(matchingDetections.count == 1 ? "" : "es")!")
                                .font(.headline)
                                .foregroundStyle(.green)
                        } else if !detections.isEmpty {
                            Text("Piece not found in this photo")
                                .font(.headline)
                                .foregroundStyle(.orange)
                        } else {
                            Text("No bricks detected")
                                .font(.headline)
                                .foregroundStyle(.white.opacity(0.7))
                        }

                        Text("\(piece.color.rawValue) \(piece.dimensions.displayString)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.blue)
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

                // Bottom info bar
                if !matchingDetections.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Matching pieces highlighted in green")
                            .fontWeight(.medium)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.bottom, 40)
                }
            }
        }
        .statusBarHidden()
        .task {
            analyzeImage()
        }
    }

    // MARK: - Analysis

    private func analyzeImage() {
        recognitionService.processImage(image) { objects in
            detections = objects
            matchingDetections = objects.filter { det in
                matchesPiece(det, target: piece)
            }
        }
    }

    /// Check if a detection matches the target piece by category, color, and dimensions.
    private func matchesPiece(
        _ detection: ObjectRecognitionService.DetectedObject,
        target: LegoPiece
    ) -> Bool {
        // Match by part number if available
        if !detection.partNumber.isEmpty && detection.partNumber == target.partNumber {
            return true
        }
        // Fall back to category + color + dimensions matching
        let categoryMatch = detection.estimatedCategory == target.category
        let colorMatch = detection.dominantColor == target.color
        let dimsMatch = detection.estimatedDimensions == target.dimensions
        return categoryMatch && colorMatch && dimsMatch
    }

    // MARK: - Geometry

    private func aspectFit(image imageSize: CGSize, in containerSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let wRatio = containerSize.width / imageSize.width
        let hRatio = containerSize.height / imageSize.height
        let scale = min(wRatio, hRatio)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    private func denormalize(box: CGRect, inSize size: CGSize, origin: CGPoint) -> CGRect {
        CGRect(
            x: origin.x + box.origin.x * size.width,
            y: origin.y + (1 - box.origin.y - box.height) * size.height,
            width: box.width * size.width,
            height: box.height * size.height
        )
    }
}
