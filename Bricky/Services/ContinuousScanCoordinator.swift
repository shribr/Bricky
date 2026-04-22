import Foundation
import SwiftUI
import Combine
import CoreGraphics

/// New simplified scan coordinator that replaces the old segment-based
/// `DetailedScanCoordinator` and `ARDetailedScanCoordinator`.
///
/// Phases:
///   `.idle`              — not scanning
///   `.detectingBoundary` — pile contour is forming. Auto-advances when stable.
///   `.boundaryReady`     — contour stable; brief pulse before scanning begins
///   `.scanning`          — continuous coverage scan. User orbits pile slowly.
///   `.complete`          — user stopped or auto-completed
///
/// There are no segments, no manual drift detection, no per-segment animations.
/// The pile contour is provided by `PileGeometryService`, which transparently
/// chooses between LiDAR mesh, scene depth, or detection density.
@MainActor
final class ContinuousScanCoordinator: ObservableObject {

    // MARK: - Phase

    enum Phase: Equatable {
        case idle
        case detectingBoundary
        case boundaryReady
        case scanning
        case complete
    }

    // MARK: - Published State

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var runningTotalPieces: Int = 0
    @Published private(set) var runningUniquePieces: Int = 0
    /// 0–1 coverage estimate based on detection density inside the contour.
    @Published private(set) var coverage: Double = 0
    /// Auto-completion countdown (seconds remaining) once coverage plateaus.
    @Published private(set) var autoCompleteCountdown: Double? = nil

    // MARK: - Geometry

    let geometry: PileGeometryService

    // MARK: - Internals

    private var globalPartNumbers: Set<String> = []
    private var coverageCellsHit: Set<Int> = []
    /// Working coverage grid resolution.
    private let coverageGrid: Int = 24
    private var lastCoverageGrowthAt: Date = Date()
    /// How long coverage must plateau before auto-completion countdown begins.
    private let plateauTimeout: TimeInterval = 4.0
    private var autoCompleteTask: Task<Void, Never>?

    // MARK: - Init

    init(geometry: PileGeometryService? = nil) {
        self.geometry = geometry ?? PileGeometryService()
    }

    // MARK: - Phase Control

    /// Start a fresh scan: clear all state, enter boundary detection.
    func start() {
        cancelAutoComplete()
        runningTotalPieces = 0
        runningUniquePieces = 0
        coverage = 0
        coverageCellsHit = []
        globalPartNumbers = []
        lastCoverageGrowthAt = Date()
        geometry.reset()
        phase = .detectingBoundary
    }

    /// User taps "rescan boundary" — wipes geometry but keeps pieces.
    func restartBoundary() {
        cancelAutoComplete()
        coverage = 0
        coverageCellsHit = []
        geometry.reset()
        lastCoverageGrowthAt = Date()
        phase = .detectingBoundary
    }

    /// Manually finish boundary detection (user tapped "Confirm").
    /// Also called automatically once `geometry.isStable` becomes true.
    func confirmBoundary() {
        guard phase == .detectingBoundary, geometry.hasBoundary else { return }
        phase = .boundaryReady
        // Brief pulse, then begin scanning.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let self, self.phase == .boundaryReady else { return }
            self.phase = .scanning
        }
    }

    /// User taps "Done" — finish the scan now.
    func finish() {
        cancelAutoComplete()
        phase = .complete
    }

    /// Reset to idle.
    func reset() {
        cancelAutoComplete()
        phase = .idle
        runningTotalPieces = 0
        runningUniquePieces = 0
        coverage = 0
        coverageCellsHit = []
        globalPartNumbers = []
        geometry.reset()
    }

    // MARK: - Detection Feedback

    /// Feed Vision detection bounding boxes (Vision normalized, origin
    /// bottom-left, 0–1) every frame.
    func recordDetections(
        boxes: [CGRect],
        partNumbers: [String],
        totalSessionPieces: Int
    ) {
        // Always feed the geometry service (warms density fallback + signals
        // mesh/depth refresh).
        geometry.recordDetections(boxes)

        // Auto-advance from boundary detection when geometry is stable.
        if phase == .detectingBoundary, geometry.isStable {
            confirmBoundary()
        }

        // While scanning, update unique-piece set + coverage grid.
        guard phase == .scanning else { return }

        runningTotalPieces = totalSessionPieces

        var grew = false
        for (i, box) in boxes.enumerated() {
            if i < partNumbers.count {
                let key = partNumbers[i]
                if globalPartNumbers.insert(key).inserted {
                    grew = true
                }
            }
            // Convert Vision bbox center → coverage cell.
            let cx = box.midX
            let cy = 1 - box.midY        // flip to top-left origin
            let col = max(0, min(coverageGrid - 1, Int(cx * Double(coverageGrid))))
            let row = max(0, min(coverageGrid - 1, Int(cy * Double(coverageGrid))))
            let cellID = row * coverageGrid + col
            if coverageCellsHit.insert(cellID).inserted {
                grew = true
            }
        }
        runningUniquePieces = globalPartNumbers.count
        coverage = min(1.0, Double(coverageCellsHit.count) / Double(coverageGrid * coverageGrid / 4))

        if grew {
            lastCoverageGrowthAt = Date()
            cancelAutoComplete()
        } else {
            evaluateAutoComplete()
        }
    }

    // MARK: - Auto-Complete

    private func evaluateAutoComplete() {
        let idle = Date().timeIntervalSince(lastCoverageGrowthAt)
        guard idle >= plateauTimeout else { return }
        guard autoCompleteTask == nil else { return }
        guard coverage >= 0.35 else { return }   // require some progress before offering auto-finish

        let countdownSeconds: Double = 5.0
        autoCompleteCountdown = countdownSeconds
        autoCompleteTask = Task { [weak self] in
            var remaining = countdownSeconds
            while remaining > 0 {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                guard !Task.isCancelled else { return }
                remaining -= 0.1
                guard let self else { return }
                if remaining <= 0 {
                    self.autoCompleteCountdown = nil
                    self.autoCompleteTask = nil
                    self.finish()
                } else {
                    self.autoCompleteCountdown = remaining
                }
            }
        }
    }

    private func cancelAutoComplete() {
        autoCompleteTask?.cancel()
        autoCompleteTask = nil
        autoCompleteCountdown = nil
    }
}
