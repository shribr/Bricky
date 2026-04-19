import Foundation
import ARKit
import Combine
import CoreGraphics
import simd

/// Auto-selects the best available pile-geometry strategy for the device and
/// publishes a unified `PileGeometry.Snapshot` for the rest of the scanning
/// pipeline to consume.
///
/// Tier order (best → fallback):
/// 1. **mesh**    — LiDAR scene reconstruction. iPhone 12 Pro+, iPad Pro 2020+.
/// 2. **depth**   — `sceneDepth` map. Newer non-LiDAR Pro devices.
/// 3. **density** — Vision detection density. Universal fallback. Slow but works everywhere.
///
/// The service is driven by frame updates (`onARFrameUpdated`) plus per-frame
/// detection feedback (`recordDetections`). It throttles snapshot rebuilds so
/// the heavy work happens at most ~6× per second.
@MainActor
final class PileGeometryService: ObservableObject {

    /// Latest pile snapshot. SwiftUI views observe this.
    @Published private(set) var snapshot: PileGeometry.Snapshot = .empty
    /// Strategy currently in use.
    @Published private(set) var activeStrategy: PileGeometry.Strategy = .none
    /// `true` once we have any usable contour.
    @Published private(set) var hasBoundary: Bool = false
    /// 0–1 stability — increases as the contour stops changing.
    @Published private(set) var stability: Double = 0

    // Strategies
    private let meshStrategy = MeshBoundaryStrategy()
    private let depthStrategy = DepthBoundaryStrategy()
    /// Density fallback uses the existing detection-driven tracker.
    let densityTracker = OrganicBoundaryTracker()

    // Throttling
    private var lastBuiltAt: Date = .distantPast
    private let minBuildInterval: TimeInterval = 1.0 / 6.0

    // Stability tracking
    private var previousArea: CGFloat = 0
    private var stableSamples: Int = 0
    private let stableSamplesNeeded: Int = 8

    weak var arCameraManager: ARCameraManager?
    var viewportSize: CGSize = CGSize(width: 390, height: 844)

    // MARK: - Public API

    /// Reset all geometry state. Call when starting a new scan.
    func reset() {
        snapshot = .empty
        activeStrategy = .none
        hasBoundary = false
        stability = 0
        previousArea = 0
        stableSamples = 0
        lastBuiltAt = .distantPast
        densityTracker.reset()
    }

    /// Feed Vision detection bounding boxes into the density-tier tracker.
    /// Always called regardless of which tier ends up being active so the
    /// fallback is always warm.
    func recordDetections(_ boxes: [CGRect]) {
        densityTracker.recordDetections(boxes)
        rebuildIfDue(forceDensity: true)
    }

    /// Called from the AR frame callback — opportunistic rebuild from mesh/depth.
    func onARFrameUpdated() {
        rebuildIfDue(forceDensity: false)
    }

    /// Force an immediate rebuild (e.g. when the user taps "confirm").
    func forceRebuild() {
        lastBuiltAt = .distantPast
        rebuildIfDue(forceDensity: false)
    }

    /// Whether the user has been holding still long enough that the contour
    /// is settled. Used by the coordinator to auto-advance from boundary
    /// detection to scanning without a manual confirm tap.
    var isStable: Bool { stability >= 0.85 }

    // MARK: - Build pipeline

    private func rebuildIfDue(forceDensity: Bool) {
        let now = Date()
        guard now.timeIntervalSince(lastBuiltAt) >= minBuildInterval else { return }
        lastBuiltAt = now

        // Try the best tier first.
        var newSnapshot: PileGeometry.Snapshot? = nil
        var strategy: PileGeometry.Strategy = .none

        if !forceDensity, let cam = arCameraManager, ARCameraManager.supportsLiDAR {
            // Mesh strategy
            newSnapshot = meshStrategy.snapshot(
                meshAnchors: cam.meshAnchors,
                planeAnchor: cam.scanPlaneAnchor,
                cameraTransform: cam.cameraTransform,
                cameraIntrinsics: cam.latestCameraIntrinsics,
                viewportSize: viewportSize,
                imageResolution: cam.latestImageResolution
            )
            if newSnapshot?.hasContour == true {
                strategy = .mesh
            }
        }

        if newSnapshot == nil || newSnapshot?.hasContour == false,
           !forceDensity,
           let cam = arCameraManager,
           ARCameraManager.supportsSceneDepth {
            newSnapshot = depthStrategy.snapshot(depthData: cam.latestSceneDepth, viewportSize: viewportSize)
            if newSnapshot?.hasContour == true {
                strategy = .depth
            }
        }

        if newSnapshot == nil || newSnapshot?.hasContour == false {
            // Density fallback: convert OrganicBoundaryTracker output.
            densityTracker.computeBoundary()
            if densityTracker.hasBoundary {
                let smoothed = PileGeometry.chaikinSmooth(densityTracker.boundaryPath, passes: 0)
                let conf = min(1.0, Double(densityTracker.boundaryPath.count) / 60.0)
                newSnapshot = PileGeometry.Snapshot(
                    contour: smoothed,
                    meshTriangles: [],
                    confidence: conf,
                    strategy: .density,
                    timestamp: Date()
                )
                strategy = .density
            }
        }

        guard let snap = newSnapshot, snap.hasContour else {
            // Keep the previous snapshot if we still don't have anything.
            return
        }

        snapshot = snap
        activeStrategy = strategy
        hasBoundary = true
        updateStability(snap.boundingBox)
    }

    private func updateStability(_ rect: CGRect) {
        let area = rect.width * rect.height
        if previousArea == 0 {
            previousArea = area
            return
        }
        let delta = abs(area - previousArea) / max(previousArea, 0.0001)
        if delta < 0.05 {
            stableSamples = min(stableSamplesNeeded, stableSamples + 1)
        } else {
            stableSamples = max(0, stableSamples - 2)
        }
        stability = Double(stableSamples) / Double(stableSamplesNeeded)
        previousArea = area
    }

    // MARK: - Test Hooks

    /// Inject a snapshot directly. Used by unit tests to bypass ARKit.
    func injectTestSnapshot(_ snap: PileGeometry.Snapshot, stable: Bool = true) {
        snapshot = snap
        hasBoundary = snap.hasContour
        activeStrategy = snap.strategy
        if stable {
            stableSamples = stableSamplesNeeded
            stability = 1
        }
    }
}
