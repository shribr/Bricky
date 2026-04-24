import SwiftUI
import UIKit

/// Coverage heatmap overlay: cells inside the pile boundary are tinted on a
/// red → orange → yellow → green ramp based on detection density. Red means
/// "no detections yet, point the camera here", green means "you've already
/// collected lots of pieces from this region".
///
/// Cells outside the boundary are transparent so the user can see where the
/// pile actually is. The pile contour (smoothed) is drawn over the heatmap
/// in white so it traces the outline cleanly.
struct ScanCoverageOverlayView: View {
    @ObservedObject var tracker: ScanCoverageTracker
    /// Optional pile contour in normalized 0–1 coords. When provided, cells
    /// fully outside the contour are skipped and the smoothed outline is
    /// drawn on top. When `nil` (no boundary detected yet) the overlay
    /// renders nothing — there's no useful "where to point" information
    /// without a known pile region.
    var pileContour: [CGPoint] = []

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let cellW = size.width / CGFloat(tracker.columns)
            let cellH = size.height / CGFloat(tracker.rows)
            // Use the convex-hull–based clean contour so we never draw
            // self-intersecting / spiky outlines from the upstream tracker.
            let cleaned = pileContour.count >= 3
                ? TopographicMeshRenderer.cleanContour(pileContour, smoothingIterations: 3)
                : []
            let hasContour = cleaned.count >= 3

            Canvas { context, _ in
                // 1. Coverage heatmap fill (only if we know where the pile is).
                if hasContour {
                    for row in 0..<tracker.rows {
                        for col in 0..<tracker.columns {
                            let idx = row * tracker.columns + col
                            let intensity = tracker.intensity[idx]
                            // Centre of cell, normalized — used to test if
                            // this cell is inside the pile contour.
                            let cx = (CGFloat(col) + 0.5) / CGFloat(tracker.columns)
                            let cy = (CGFloat(row) + 0.5) / CGFloat(tracker.rows)
                            guard GeometryUtils.pointInPolygon(CGPoint(x: cx, y: cy), polygon: cleaned) else { continue }

                            let rect = CGRect(
                                x: CGFloat(col) * cellW + 1,
                                y: CGFloat(row) * cellH + 1,
                                width: max(0, cellW - 2),
                                height: max(0, cellH - 2)
                            )
                            drawShadedTile(in: rect, intensity: intensity, context: context)
                        }
                    }
                }

                // 2. Smoothed pile contour outline on top.
                if hasContour {
                    var outline = Path()
                    let first = CGPoint(x: cleaned[0].x * size.width,
                                        y: cleaned[0].y * size.height)
                    outline.move(to: first)
                    for p in cleaned.dropFirst() {
                        outline.addLine(to: CGPoint(x: p.x * size.width,
                                                     y: p.y * size.height))
                    }
                    outline.closeSubpath()
                    context.stroke(outline, with: .color(.white.opacity(0.9)), lineWidth: 2)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .ignoresSafeArea()
    }

    /// Draw a single heatmap tile with faux-3D shading: rounded rect filled
    /// with a top-light → bottom-shadow vertical gradient, plus a 1pt
    /// highlight on the top edge. This makes the heatmap look like a stack
    /// of brick tiles instead of a flat 2D grid — the user's "feels like 2D"
    /// feedback drove this.
    private func drawShadedTile(in rect: CGRect, intensity: Double, context: GraphicsContext) {
        let t = max(0, min(1, intensity))
        let base = baseColor(intensity: t)
        // Highlight = base lightened ~25%; shadow = darkened ~25%.
        let highlight = base.lighter(by: 0.25)
        let shadow = base.darker(by: 0.20)

        let path = Path(roundedRect: rect, cornerRadius: 3)
        // Vertical gradient.
        let gradient = Gradient(stops: [
            .init(color: highlight.opacity(alpha(intensity: t)), location: 0.0),
            .init(color: base.opacity(alpha(intensity: t)),       location: 0.55),
            .init(color: shadow.opacity(alpha(intensity: t)),     location: 1.0),
        ])
        context.fill(
            path,
            with: .linearGradient(
                gradient,
                startPoint: CGPoint(x: rect.midX, y: rect.minY),
                endPoint: CGPoint(x: rect.midX, y: rect.maxY)
            )
        )
        // Thin top highlight to suggest a lit edge.
        var topEdge = Path()
        topEdge.move(to: CGPoint(x: rect.minX + 2, y: rect.minY + 1))
        topEdge.addLine(to: CGPoint(x: rect.maxX - 2, y: rect.minY + 1))
        context.stroke(topEdge, with: .color(.white.opacity(0.35 * alpha(intensity: t))), lineWidth: 1)
    }

    private func baseColor(intensity: Double) -> Color {
        let stops: [(Double, (Double, Double, Double))] = [
            (0.00, (0.95, 0.20, 0.20)),  // red
            (0.33, (0.98, 0.55, 0.15)),  // orange
            (0.66, (0.98, 0.85, 0.20)),  // yellow
            (1.00, (0.20, 0.80, 0.30)),  // green
        ]
        var rgb = stops.last!.1
        for k in 0..<(stops.count - 1) {
            let (t0, c0) = stops[k]
            let (t1, c1) = stops[k + 1]
            if intensity <= t1 {
                let f = (intensity - t0) / (t1 - t0)
                rgb = (
                    c0.0 + (c1.0 - c0.0) * f,
                    c0.1 + (c1.1 - c0.1) * f,
                    c0.2 + (c1.2 - c0.2) * f
                )
                break
            }
        }
        return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }

    private func alpha(intensity: Double) -> Double {
        // Untouched (red) cells stay readable but don't smother the bricks;
        // covered (green) cells fade so the user can see the bricks they've
        // already collected.
        0.55 - 0.20 * intensity
    }

}

/// Compact badge showing scan coverage percentage.
struct ScanCoverageBadge: View {
    @ObservedObject var tracker: ScanCoverageTracker

    var body: some View {
        HStack(spacing: 6) {
            // Mini grid icon
            Image(systemName: coverageIcon)
                .foregroundStyle(coverageColor)
            Text("\(Int(tracker.coveragePercent * 100))% covered")
                .fontWeight(.medium)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .foregroundStyle(.white)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        .accessibilityLabel("Scan coverage \(Int(tracker.coveragePercent * 100)) percent")
    }

    private var coverageColor: Color {
        switch tracker.coveragePercent {
        case 0..<0.3: return .red
        case 0.3..<0.6: return .orange
        case 0.6..<0.85: return .yellow
        default: return .green
        }
    }

    private var coverageIcon: String {
        switch tracker.coveragePercent {
        case 0..<0.3: return "square.grid.3x3"
        case 0.3..<0.6: return "square.grid.3x3.topleft.filled"
        case 0.6..<0.85: return "square.grid.3x3.middleleading.filled"
        default: return "square.grid.3x3.fill"
        }
    }
}

// MARK: - Color shading helpers (used to give heatmap tiles a 3D look)

private extension Color {
    /// Lighten this color toward white by `amount` (0…1). Operates in HSB.
    func lighter(by amount: Double) -> Color {
        adjustBrightness(by: amount)
    }

    /// Darken this color toward black by `amount` (0…1). Operates in HSB.
    func darker(by amount: Double) -> Color {
        adjustBrightness(by: -amount)
    }

    private func adjustBrightness(by delta: Double) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let nb = max(0, min(1, b + CGFloat(delta)))
        return Color(hue: Double(h), saturation: Double(s), brightness: Double(nb), opacity: Double(a))
    }
}
