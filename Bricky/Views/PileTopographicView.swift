import SwiftUI
import simd

/// LiDAR-driven topographic wireframe overlay.
///
/// On AR-mode + LiDAR-capable devices, this renders a perspective-correct
/// 3D wireframe of the pile surface — the surface visibly "drapes" over the
/// real bricks in the camera feed. On devices without LiDAR or scene-depth,
/// nothing is rendered (the existing 2D coverage heatmap covers that case).
///
/// Performance budget: rebuilds are throttled to a maximum of 3 Hz and
/// skipped entirely when the pile contour hasn't moved more than ~1.5% of
/// the viewport since the last build. The wireframe path is the single
/// heaviest contributor to AR-mode lag, so these guards keep it well below
/// 5 ms per frame on iPhone 14 Pro.
struct PileTopographicView: View {
    @ObservedObject var geometry: PileGeometryService
    let cameraManager: ARCameraManager
    @ObservedObject private var settings = ScanSettings.shared

    @State private var lastWireframe: LiDARTopographicRenderer.Wireframe?
    @State private var lastBuildTime: Date = .distantPast
    @State private var lastBuildContourHash: Int = 0

    /// Minimum interval between wireframe rebuilds (3 Hz cap).
    private static let minRebuildInterval: TimeInterval = 1.0 / 3.0

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                if let wf = lastWireframe {
                    wireframeCanvas(wireframe: wf, size: size)
                    legendBadge
                }
            }
            .onAppear { rebuild(viewportSize: size) }
            .onChange(of: geometry.snapshot.timestamp) { _, _ in rebuild(viewportSize: size) }
            .onChange(of: size) { _, _ in rebuild(viewportSize: size, force: true) }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Drawing

    private func wireframeCanvas(wireframe: LiDARTopographicRenderer.Wireframe,
                                 size: CGSize) -> some View {
        Canvas { ctx, _ in
            for seg in wireframe.segments {
                let s = CGPoint(x: max(0, min(1, seg.start.x)) * size.width,
                                y: max(0, min(1, seg.start.y)) * size.height)
                let e = CGPoint(x: max(0, min(1, seg.end.x)) * size.width,
                                y: max(0, min(1, seg.end.y)) * size.height)
                let color = TopographicMeshRenderer
                    .color(elevation: seg.elevation, ramp: ramp)
                    // Brighten with elevation so peaks "glow" against dark camera feed.
                    .opacity(0.6 + 0.4 * seg.elevation)
                var p = Path()
                p.move(to: s)
                p.addLine(to: e)
                ctx.stroke(p, with: .color(color), lineWidth: 1.0)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var legendBadge: some View {
        if let wf = lastWireframe, wf.maxHeight > 0.005 {
            VStack(alignment: .leading, spacing: 2) {
                Text("LiDAR Topography")
                    .font(.caption2.weight(.semibold))
                Text(String(format: "Peak: %.1f cm", wf.maxHeight * 100))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.black.opacity(0.45))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.leading, 16)
            .padding(.top, 60)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: - Rebuild

    private func rebuild(viewportSize: CGSize, force: Bool = false) {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }
        let contour = geometry.snapshot.contour
        guard contour.count >= 3 else {
            lastWireframe = nil
            return
        }

        // Throttle: at most 3 rebuilds per second. Forced rebuilds (size
        // changes) bypass the throttle.
        let now = Date()
        if !force, now.timeIntervalSince(lastBuildTime) < Self.minRebuildInterval {
            return
        }

        // Skip when contour hasn't moved meaningfully. Hash a downsampled
        // bbox + vertex count — cheap to compute, robust to micro-jitter.
        let bbox = GeometryUtils.boundingBox(of: contour)
        let contourHash = Self.coarseHash(bbox: bbox, count: contour.count)
        if !force, contourHash == lastBuildContourHash {
            return
        }

        let resolution = settings.meshResolution
        if let wf = LiDARTopographicRenderer.build(
            contour: contour,
            cameraManager: cameraManager,
            viewportSize: viewportSize,
            resolution: resolution
        ) {
            lastWireframe = wf
            lastBuildTime = now
            lastBuildContourHash = contourHash
        }
    }

    /// Hash the contour bbox quantized to ~1.5% of viewport. Two contours
    /// that differ by less than that produce the same hash → no rebuild.
    private static func coarseHash(bbox: CGRect, count: Int) -> Int {
        let q: CGFloat = 0.015
        var hasher = Hasher()
        hasher.combine(Int((bbox.minX / q).rounded()))
        hasher.combine(Int((bbox.minY / q).rounded()))
        hasher.combine(Int((bbox.width / q).rounded()))
        hasher.combine(Int((bbox.height / q).rounded()))
        hasher.combine(count / 4) // bucket vertex count too
        return hasher.finalize()
    }

    private var ramp: TopographicMeshRenderer.ColorRamp {
        switch settings.meshColorRamp {
        case .viridis:   return .viridis
        case .grayscale: return .grayscale
        }
    }
}
