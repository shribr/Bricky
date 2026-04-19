import SwiftUI
import simd

/// Topographic wireframe overlay for the brick pile.
///
/// Renders a deformed grid (rows + columns) clipped to the pile contour, with
/// per-segment color taken from an elevation ramp (viridis or grayscale). The
/// effect mimics a scientific surface plot — gives the user a clear visual
/// "here's the shape of your pile" without obscuring the bricks underneath.
///
/// The wireframe rebuilds whenever the contour changes; rebuilds are cheap
/// (~28² grid synthesis, no GPU) but throttled by `PileGeometryService`'s own
/// 6 Hz snapshot cadence.
struct PileMeshOverlayView: View {
    @ObservedObject var geometry: PileGeometryService
    @ObservedObject var coordinator: ContinuousScanCoordinator
    @ObservedObject private var settings = ScanSettings.shared

    @State private var breathe: Bool = false
    @State private var legendOpacity: Double = 1
    @State private var hasShownLegend = false

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                if geometry.hasBoundary {
                    wireframeLayer(size: size)
                    badgeLayer(size: size)
                    legendLayer(size: size)
                } else if coordinator.phase == .detectingBoundary {
                    searchingHint(size: size)
                }
            }
            .onAppear { geometry.viewportSize = size }
            .onChange(of: size) { _, newSize in geometry.viewportSize = newSize }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
        .onChange(of: geometry.hasBoundary) { _, isVisible in
            guard isVisible, !hasShownLegend else { return }
            hasShownLegend = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation(.easeOut(duration: 0.8)) { legendOpacity = 0 }
            }
        }
    }

    // MARK: - Wireframe canvas

    private func wireframeLayer(size: CGSize) -> some View {
        let segments = TopographicMeshRenderer.buildWireframe(
            contour: geometry.snapshot.contour,
            resolution: 28
        )
        let ramp = currentRamp
        let isScanning = coordinator.phase == .scanning
        let alphaBoost = isScanning ? 1.0 : (breathe ? 0.95 : 0.75)

        return Canvas { ctx, _ in
            for seg in segments {
                // Defensive clamp: never draw outside the viewport even if
                // the contour pipeline emits a bad point.
                let s = CGPoint(x: max(0, min(1, seg.start.x)),
                                y: max(0, min(1, seg.start.y)))
                let e = CGPoint(x: max(0, min(1, seg.end.x)),
                                y: max(0, min(1, seg.end.y)))
                let color = TopographicMeshRenderer
                    .color(elevation: seg.elevation, ramp: ramp)
                    .opacity(0.55 + 0.4 * seg.elevation)
                    .opacity(alphaBoost)
                var path = Path()
                path.move(to: CGPoint(x: s.x * size.width, y: s.y * size.height))
                path.addLine(to: CGPoint(x: e.x * size.width, y: e.y * size.height))
                ctx.stroke(path, with: .color(color), lineWidth: 1.0)
            }
            // Note: the explicit contour stroke was removed — it amplified
            // noise from the upstream boundary tracker (jagged loops, off-
            // viewport excursions). The grid's outer edges already trace
            // the pile silhouette because off-pile segments are skipped.
        }
        .accessibilityHidden(true)
    }

    private var currentRamp: TopographicMeshRenderer.ColorRamp {
        switch settings.meshColorRamp {
        case .viridis:   return .viridis
        case .grayscale: return .grayscale
        }
    }

    // MARK: - Strategy badge

    private func badgeLayer(size: CGSize) -> some View {
        strategyBadge.position(badgePosition(in: size))
    }

    private func badgePosition(in size: CGSize) -> CGPoint {
        let bb = geometry.snapshot.boundingBox
        let x = bb.minX * size.width + 56
        let y = bb.minY * size.height + 22
        return CGPoint(x: max(60, min(size.width - 60, x)),
                       y: max(60, min(size.height - 60, y)))
    }

    private var strategyBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: strategyIcon)
                .font(.system(size: 11, weight: .semibold))
            Text(geometry.activeStrategy.description)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial.opacity(0.9))
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(
                TopographicMeshRenderer
                    .color(elevation: 1.0, ramp: currentRamp)
                    .opacity(0.7),
                lineWidth: 1
            )
        )
    }

    private var strategyIcon: String {
        switch geometry.activeStrategy {
        case .mesh:    return "cube.transparent.fill"
        case .depth:   return "perspective"
        case .density: return "circle.grid.3x3.fill"
        case .none:    return "viewfinder"
        }
    }

    // MARK: - Elevation legend

    private func legendLayer(size: CGSize) -> some View {
        let ramp = currentRamp
        return VStack(alignment: .leading, spacing: 4) {
            Text("Elevation")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            HStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { i in
                    let t = Double(i) / 23.0
                    Rectangle()
                        .fill(TopographicMeshRenderer.color(elevation: t, ramp: ramp))
                        .frame(width: 4, height: 8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .position(x: 64, y: size.height - 60)
        .opacity(legendOpacity)
    }

    // MARK: - Pre-boundary state

    private func searchingHint(size: CGSize) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "viewfinder.circle")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.white.opacity(breathe ? 0.95 : 0.55))
            Text("Looking for the brick pile…")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.white.opacity(0.85))
            Text("Slowly sweep across your pile")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .position(x: size.width / 2, y: size.height * 0.4)
    }
}
