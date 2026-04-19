import SwiftUI

/// Shows the source image with the pile boundary contour outlined and the
/// piece's bounding box highlighted within. Gives the user a "you are here"
/// map of where a brick sits inside the entire scanned pile area.
///
/// Coordinate notes:
/// - `LegoPiece.boundingBox` uses Vision normalized coordinates (origin
///   bottom-left, 0–1).
/// - `pileBoundary` points use top-left normalized coordinates (origin
///   top-left, 0–1) — same space as `PileGeometry.Snapshot.contour`.
/// - Both are converted to view space (top-left origin) here.
struct PileBoundaryLocationView: View {
    let image: UIImage
    let pieceBoundingBox: CGRect?
    let pileBoundary: [CGPoint]
    let highlightColor: Color

    var body: some View {
        GeometryReader { geo in
            let imageSize = image.size
            let viewSize = geo.size
            let fit = aspectFit(content: imageSize, in: viewSize)

            ZStack(alignment: .topLeading) {
                // Background image
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: viewSize.width, height: viewSize.height)

                // Dim everything outside the pile boundary so the eye lands
                // on the relevant area first.
                if pileBoundary.count >= 3 {
                    Canvas { ctx, size in
                        var fullPath = Path()
                        fullPath.addRect(CGRect(origin: .zero, size: size))

                        var pilePath = Path()
                        let pts = pileBoundary.map {
                            CGPoint(x: fit.origin.x + $0.x * fit.size.width,
                                    y: fit.origin.y + $0.y * fit.size.height)
                        }
                        pilePath.move(to: pts[0])
                        for p in pts.dropFirst() { pilePath.addLine(to: p) }
                        pilePath.closeSubpath()

                        // Even-odd fill to punch a hole in the dim layer
                        let combined = fullPath
                            .union(pilePath, eoFill: true)
                            .subtracting(pilePath)
                        ctx.fill(combined, with: .color(.black.opacity(0.5)))

                        // Boundary outline
                        ctx.stroke(pilePath,
                                   with: .color(highlightColor.opacity(0.9)),
                                   style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    }
                    .allowsHitTesting(false)
                }

                // Piece bounding-box highlight (Vision coords → view coords)
                if let bbox = pieceBoundingBox {
                    let rect = visionBoxToViewRect(bbox, fit: fit)
                    ZStack {
                        // Glow ring
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(highlightColor, lineWidth: 4)
                            .blur(radius: 6)
                        // Crisp border
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(highlightColor, lineWidth: 2.5)
                        // Subtle fill
                        RoundedRectangle(cornerRadius: 4)
                            .fill(highlightColor.opacity(0.18))
                    }
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .allowsHitTesting(false)
                }
            }
            .frame(width: viewSize.width, height: viewSize.height)
        }
    }

    // MARK: - Geometry helpers

    /// Returns the rect (in view space) where the image is drawn under
    /// `aspectRatio(contentMode: .fit)`.
    private func aspectFit(content: CGSize, in container: CGSize) -> CGRect {
        guard content.width > 0 && content.height > 0 else { return .zero }
        let scale = min(container.width / content.width,
                        container.height / content.height)
        let w = content.width * scale
        let h = content.height * scale
        let x = (container.width - w) / 2
        let y = (container.height - h) / 2
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Converts a Vision normalized rect (origin bottom-left) to a view rect
    /// in the given fit area (origin top-left).
    private func visionBoxToViewRect(_ bbox: CGRect, fit: CGRect) -> CGRect {
        let w = bbox.width * fit.width
        let h = bbox.height * fit.height
        let x = fit.origin.x + bbox.origin.x * fit.width
        // Vision Y is bottom-up; view Y is top-down
        let y = fit.origin.y + (1 - bbox.origin.y - bbox.height) * fit.height
        return CGRect(x: x, y: y, width: w, height: h)
    }
}
