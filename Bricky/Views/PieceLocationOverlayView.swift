import SwiftUI

/// Overlay view that highlights the locations of specific pieces in a captured pile image
struct PieceLocationOverlayView: View {
    let image: UIImage
    let locations: [PieceLocationService.PieceLocation]
    let pieceName: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack {
                    // Base image
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .overlay {
                            // Dim the image slightly
                            Color.black.opacity(0.3)
                        }
                        .overlay {
                            // Highlight located pieces
                            ForEach(Array(locations.enumerated()), id: \.offset) { index, location in
                                let frame = convertBoundingBox(
                                    location.boundingBox,
                                    imageSize: image.size,
                                    viewSize: imageFitSize(image: image, container: geo.size)
                                )

                                PieceHighlightView(
                                    frame: frame,
                                    color: location.color,
                                    confidence: location.matchConfidence,
                                    index: index + 1
                                )
                                .offset(
                                    x: frame.midX - geo.size.width / 2,
                                    y: frame.midY - geo.size.height / 2
                                )
                            }
                        }

                    // Info badge at bottom
                    VStack {
                        Spacer()
                        HStack {
                            Image(systemName: "sparkle.magnifyingglass")
                            Text("\(locations.count) possible location\(locations.count == 1 ? "" : "s") for \(pieceName)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("Find Piece")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// Convert normalized bounding box to view coordinates (accounting for aspect fit)
    private func convertBoundingBox(
        _ bbox: CGRect,
        imageSize: CGSize,
        viewSize: CGSize
    ) -> CGRect {
        let scaleX = viewSize.width
        let scaleY = viewSize.height

        // Vision uses bottom-left origin; flip Y
        let x = bbox.origin.x * scaleX
        let y = (1 - bbox.origin.y - bbox.height) * scaleY
        let w = bbox.width * scaleX
        let h = bbox.height * scaleY

        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Calculate the size of the image when displayed with aspect fit
    private func imageFitSize(image: UIImage, container: CGSize) -> CGSize {
        let imageAspect = image.size.width / image.size.height
        let containerAspect = container.width / container.height

        if imageAspect > containerAspect {
            // Image is wider — constrained by width
            let width = container.width
            let height = width / imageAspect
            return CGSize(width: width, height: height)
        } else {
            // Image is taller — constrained by height
            let height = container.height
            let width = height * imageAspect
            return CGSize(width: width, height: height)
        }
    }
}

/// Individual piece highlight with pulsing animation
struct PieceHighlightView: View {
    let frame: CGRect
    let color: LegoColor
    let confidence: Float
    let index: Int

    @State private var isPulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Highlight rectangle
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.legoColor(color), lineWidth: 3)
                .frame(width: frame.width, height: frame.height)
                .shadow(color: Color.legoColor(color).opacity(reduceMotion ? 0.6 : (isPulsing ? 0.8 : 0.4)), radius: reduceMotion ? 6 : (isPulsing ? 10 : 4))

            // Glow fill
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.legoColor(color).opacity(reduceMotion ? 0.2 : (isPulsing ? 0.3 : 0.15)))
                .frame(width: frame.width, height: frame.height)

            // Index badge
            Text("\(index)")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .padding(4)
                .background(Circle().fill(Color.legoColor(color)))
                .offset(x: -frame.width / 2 + 8, y: -frame.height / 2 + 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Piece location \(index), \(Int(confidence * 100)) percent match")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}
