import Foundation
import UIKit

/// Manages scan-related preferences including piece location screenshot settings
final class ScanSettings: ObservableObject {
    static let shared = ScanSettings()

    // MARK: - Scan Mode

    enum ScanMode: String, CaseIterable, Identifiable {
        case regular = "Regular"
        case detailed = "Detailed"

        var id: String { rawValue }

        var description: String {
            switch self {
            case .regular: return "Automatic real-time scanning with continuous detection"
            case .detailed: return "Guided segment-by-segment scan for thorough identification"
            }
        }

        var iconName: String {
            switch self {
            case .regular: return "bolt.circle.fill"
            case .detailed: return "square.grid.3x3.fill"
            }
        }
    }

    // MARK: - Tracking Mode

    enum TrackingMode: String, CaseIterable, Identifiable {
        case screenSpace = "2D Screen-Space"
        case arWorldTracking = "AR World Tracking"

        var id: String { rawValue }

        var description: String {
            switch self {
            case .screenSpace: return "Classic 2D tracking — hold camera steady over bricks"
            case .arWorldTracking: return "ARKit spatial tracking — move freely around bricks"
            }
        }

        var iconName: String {
            switch self {
            case .screenSpace: return "rectangle.on.rectangle"
            case .arWorldTracking: return "arkit"
            }
        }
    }

    /// Scan workflow mode: regular (auto-capture) or detailed (guided segments)
    @Published var scanMode: ScanMode {
        didSet { UserDefaults.standard.set(scanMode.rawValue, forKey: "ScanSettings.scanMode") }
    }

    /// Spatial tracking approach: 2D screen-space (current) or AR world tracking (future)
    @Published var trackingMode: TrackingMode {
        didSet { UserDefaults.standard.set(trackingMode.rawValue, forKey: "ScanSettings.trackingMode") }
    }

    // MARK: - Published Settings

    /// Whether to generate per-piece location snapshots during scanning
    @Published var locationSnapshotsEnabled: Bool {
        didSet { UserDefaults.standard.set(locationSnapshotsEnabled, forKey: "ScanSettings.locationSnapshotsEnabled") }
    }

    /// Whether to use the composite approach (one source image, on-demand highlights)
    /// vs the legacy approach (pre-rendered per-piece snapshots)
    @Published var useCompositeMode: Bool {
        didSet { UserDefaults.standard.set(useCompositeMode, forKey: "ScanSettings.useCompositeMode") }
    }

    /// Whether to pre-render all highlights when scanning stops (composite mode only)
    @Published var preRenderOnComplete: Bool {
        didSet { UserDefaults.standard.set(preRenderOnComplete, forKey: "ScanSettings.preRenderOnComplete") }
    }

    /// Segment grid size for detailed scan (3–10, NxN grid)
    @Published var segmentGridSize: Int {
        didSet { UserDefaults.standard.set(segmentGridSize, forKey: "ScanSettings.segmentGridSize") }
    }

    /// Whether to auto-detect grid size based on scanned area
    @Published var autoDetectGridSize: Bool {
        didSet { UserDefaults.standard.set(autoDetectGridSize, forKey: "ScanSettings.autoDetectGridSize") }
    }

    // MARK: - Geolocation (Sprint C)

    /// Whether scans tag themselves with the device's current location.
    /// Strict opt-in: even when this is `true`, no location is requested
    /// until OS-level `WhenInUse` permission has also been granted.
    @Published var locationCaptureEnabled: Bool {
        didSet { UserDefaults.standard.set(locationCaptureEnabled, forKey: "ScanSettings.locationCaptureEnabled") }
    }

    /// Whether the user has already seen the one-time consent modal at scan
    /// start. Once true, we never auto-prompt again — the user manages the
    /// setting from Settings.
    @Published var locationConsentPrompted: Bool {
        didSet { UserDefaults.standard.set(locationConsentPrompted, forKey: "ScanSettings.locationConsentPrompted") }
    }

    /// Radius (km) used by the "near me" inventory filter. 0.5 km default.
    @Published var locationFilterRadiusKm: Double {
        didSet { UserDefaults.standard.set(locationFilterRadiusKm, forKey: "ScanSettings.locationFilterRadiusKm") }
    }

    // MARK: - Pile Mesh Overlay

    enum MeshColorRamp: String, CaseIterable, Identifiable {
        case viridis = "Viridis"
        case grayscale = "Grayscale"

        var id: String { rawValue }

        var description: String {
            switch self {
            case .viridis:   return "Color elevation (purple → yellow)"
            case .grayscale: return "Mono wireframe (low contrast scenes)"
            }
        }
    }

    /// Color ramp used by `PileMeshOverlayView` for the topographic wireframe.
    @Published var meshColorRamp: MeshColorRamp {
        didSet { UserDefaults.standard.set(meshColorRamp.rawValue, forKey: "ScanSettings.meshColorRamp") }
    }

    /// Lattice resolution (cells per side) for the LiDAR topographic wireframe.
    /// Higher = denser mesh, more depth samples per frame. Range 16…64; default 36.
    @Published var meshResolution: Int {
        didSet { UserDefaults.standard.set(meshResolution, forKey: "ScanSettings.meshResolution") }
    }

    /// Last benchmark result in milliseconds per composite render
    @Published var lastBenchmarkMs: Double?

    /// Benchmark recommendation text
    @Published var benchmarkRecommendation: String?

    // MARK: - Init

    private init() {
        let defaults = UserDefaults.standard

        // Default: enabled with composite mode
        if defaults.object(forKey: "ScanSettings.locationSnapshotsEnabled") == nil {
            defaults.set(true, forKey: "ScanSettings.locationSnapshotsEnabled")
        }
        if defaults.object(forKey: "ScanSettings.useCompositeMode") == nil {
            defaults.set(true, forKey: "ScanSettings.useCompositeMode")
        }
        if defaults.object(forKey: "ScanSettings.preRenderOnComplete") == nil {
            defaults.set(true, forKey: "ScanSettings.preRenderOnComplete")
        }

        if defaults.object(forKey: "ScanSettings.segmentGridSize") == nil {
            defaults.set(3, forKey: "ScanSettings.segmentGridSize")
        }
        if defaults.object(forKey: "ScanSettings.autoDetectGridSize") == nil {
            defaults.set(true, forKey: "ScanSettings.autoDetectGridSize")
        }

        let modeStr = defaults.string(forKey: "ScanSettings.scanMode") ?? "Regular"
        self.scanMode = ScanMode(rawValue: modeStr) ?? .regular

        // Default tracking mode is 2D Screen-Space everywhere — it's
        // dramatically lighter than ARKit world tracking. AR World Tracking
        // (which enables the LiDAR topographic wireframe) is opt-in via the
        // top-bar pill or Settings.
        //
        // Reverse migration: a previous build briefly auto-flipped LiDAR
        // devices to AR World Tracking. Reset those installs back to 2D
        // (they can re-enable via the pill).
        let revertKey = "ScanSettings.trackingModeRevertedV2"
        if !defaults.bool(forKey: revertKey) {
            if defaults.bool(forKey: "ScanSettings.trackingModeLiDARMigratedV1") {
                defaults.set(TrackingMode.screenSpace.rawValue, forKey: "ScanSettings.trackingMode")
            }
            defaults.set(true, forKey: revertKey)
        }
        let trackStr = defaults.string(forKey: "ScanSettings.trackingMode") ?? TrackingMode.screenSpace.rawValue
        self.trackingMode = TrackingMode(rawValue: trackStr) ?? .screenSpace
        self.locationSnapshotsEnabled = defaults.bool(forKey: "ScanSettings.locationSnapshotsEnabled")
        self.useCompositeMode = defaults.bool(forKey: "ScanSettings.useCompositeMode")
        self.preRenderOnComplete = defaults.bool(forKey: "ScanSettings.preRenderOnComplete")
        self.segmentGridSize = max(3, min(10, defaults.integer(forKey: "ScanSettings.segmentGridSize")))
        self.autoDetectGridSize = defaults.bool(forKey: "ScanSettings.autoDetectGridSize")

        // Geolocation (Sprint C) — defaults: capture off, never prompted, 0.5 km radius.
        self.locationCaptureEnabled = defaults.bool(forKey: "ScanSettings.locationCaptureEnabled")
        self.locationConsentPrompted = defaults.bool(forKey: "ScanSettings.locationConsentPrompted")
        let storedRadius = defaults.double(forKey: "ScanSettings.locationFilterRadiusKm")
        self.locationFilterRadiusKm = storedRadius > 0 ? storedRadius : 0.5

        let rampStr = defaults.string(forKey: "ScanSettings.meshColorRamp") ?? MeshColorRamp.viridis.rawValue
        self.meshColorRamp = MeshColorRamp(rawValue: rampStr) ?? .viridis

        let storedRes = defaults.integer(forKey: "ScanSettings.meshResolution")
        self.meshResolution = storedRes > 0 ? max(16, min(64, storedRes)) : 24
    }

    // MARK: - Performance Benchmark

    /// Runs a benchmark simulating composite snapshot generation.
    /// Returns average time per render in milliseconds.
    func runBenchmark() async -> BenchmarkResult {
        // Generate a test image at typical camera resolution
        let testSize = CGSize(width: 3024, height: 4032) // iPhone camera resolution
        let iterations = 5

        // Create test image on background
        let testImage = await Task.detached(priority: .userInitiated) {
            let renderer = UIGraphicsImageRenderer(size: testSize)
            return renderer.image { ctx in
                // Fill with a gradient to simulate a real photo
                let colors = [UIColor.systemBlue.cgColor, UIColor.systemRed.cgColor]
                let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                          colors: colors as CFArray, locations: nil)!
                ctx.cgContext.drawLinearGradient(gradient,
                                                 start: .zero,
                                                 end: CGPoint(x: testSize.width, y: testSize.height),
                                                 options: [])
            }
        }.value

        // Benchmark composite renders
        let testBoxes: [CGRect] = (0..<5).map { i in
            CGRect(x: 0.1 + Double(i) * 0.15, y: 0.2, width: 0.12, height: 0.15)
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        await Task.detached(priority: .userInitiated) {
            for _ in 0..<iterations {
                for box in testBoxes {
                    _ = SnapshotRenderer.renderHighlight(
                        sourceImage: testImage,
                        highlightBox: box,
                        highlightColor: .systemRed
                    )
                }
            }
        }.value

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let totalRenders = iterations * testBoxes.count
        let avgMs = (elapsed / Double(totalRenders)) * 1000.0

        let result = BenchmarkResult(
            averageRenderMs: avgMs,
            totalRenders: totalRenders,
            totalTimeMs: elapsed * 1000.0,
            imageSize: testSize
        )

        await MainActor.run {
            self.lastBenchmarkMs = avgMs
            self.benchmarkRecommendation = result.recommendation
        }

        return result
    }

    struct BenchmarkResult {
        let averageRenderMs: Double
        let totalRenders: Int
        let totalTimeMs: Double
        let imageSize: CGSize

        var recommendation: String {
            if averageRenderMs < 15 {
                return "Excellent — your device handles snapshot rendering with ease. Keep location snapshots enabled for the best experience."
            } else if averageRenderMs < 40 {
                return "Good — rendering is fast enough for typical scans. Location snapshots are recommended. Consider disabling pre-rendering for scans with 20+ pieces."
            } else if averageRenderMs < 80 {
                return "Moderate — rendering may cause brief pauses during large scans. We recommend using Composite mode with pre-rendering disabled. Highlights will be generated on-demand when you view a piece's location."
            } else {
                return "Slow — snapshot rendering is resource-intensive on this device. We recommend disabling location snapshots to keep scanning smooth. You can still see piece locations via bounding box coordinates."
            }
        }

        var shouldEnableSnapshots: Bool { averageRenderMs < 80 }
        var shouldPreRender: Bool { averageRenderMs < 40 }
    }
}

// MARK: - Snapshot Renderer (Thread-Safe)

/// Renders piece location highlight overlays. All methods are thread-safe
/// and designed to run on background queues.
enum SnapshotRenderer {

    /// Render a single piece highlight on a source image.
    /// Safe to call from any thread.
    static func renderHighlight(
        sourceImage: UIImage,
        highlightBox: CGRect,
        highlightColor: UIColor
    ) -> UIImage {
        let size = sourceImage.size
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { ctx in
            sourceImage.draw(at: .zero)

            // Convert Vision coordinates (origin bottom-left) to UIKit (origin top-left)
            let rect = CGRect(
                x: highlightBox.origin.x * size.width,
                y: (1 - highlightBox.origin.y - highlightBox.height) * size.height,
                width: highlightBox.width * size.width,
                height: highlightBox.height * size.height
            )

            // Dim overlay with cutout
            ctx.cgContext.saveGState()
            let fullPath = UIBezierPath(rect: CGRect(origin: .zero, size: size))
            let cutout = UIBezierPath(roundedRect: rect, cornerRadius: 4)
            fullPath.append(cutout)
            fullPath.usesEvenOddFillRule = true
            ctx.cgContext.addPath(fullPath.cgPath)
            ctx.cgContext.setFillColor(UIColor.black.withAlphaComponent(0.45).cgColor)
            ctx.cgContext.fillPath(using: .evenOdd)

            // Highlight border
            ctx.cgContext.setStrokeColor(highlightColor.cgColor)
            ctx.cgContext.setLineWidth(max(3, size.width * 0.005))
            ctx.cgContext.stroke(rect.insetBy(dx: -1, dy: -1))

            // White outline for visibility
            ctx.cgContext.setStrokeColor(UIColor.white.cgColor)
            ctx.cgContext.setLineWidth(max(1.5, size.width * 0.002))
            ctx.cgContext.stroke(rect.insetBy(dx: -3, dy: -3))
            ctx.cgContext.restoreGState()
        }
    }

    /// Render highlights for multiple pieces on a single source image (batch).
    /// Returns a dictionary mapping piece ID to rendered snapshot.
    static func renderBatch(
        sourceImage: UIImage,
        pieces: [(id: UUID, boundingBox: CGRect, color: UIColor)]
    ) -> [UUID: UIImage] {
        var results: [UUID: UIImage] = [:]
        for piece in pieces {
            results[piece.id] = renderHighlight(
                sourceImage: sourceImage,
                highlightBox: piece.boundingBox,
                highlightColor: piece.color
            )
        }
        return results
    }
}
