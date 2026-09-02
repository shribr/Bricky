import Foundation
import simd

/// One physical brick tracked in world space across many frames.
struct TrackedBrick: Identifiable {
    let id: UUID
    var worldPosition: SIMD3<Float>   // meters, ARKit world space
    var partNumber: String
    var name: String
    var color: LegoColor
    var confidence: Float
    var sightings: Int
    let firstSeen: Date
    var lastSeen: Date
}

/// Tracks unique physical bricks by 3D world position so the same brick is not
/// re-counted as the camera orbits, and so a persistent "already counted"
/// overlay can be anchored to each one.
@MainActor
final class BrickInstanceTracker: ObservableObject {
    @Published private(set) var bricks: [TrackedBrick] = []

    /// Detections closer than this (meters) are treated as the SAME brick.
    /// 2 cm matches the pipeline's existing depth-separation threshold.
    static let defaultMergeRadius: Float = 0.02

    /// Exponential smoothing factor applied to a merged brick's world position.
    private static let smoothingFactor: Float = 0.25

    var count: Int { bricks.count }

    /// Record a detection at a world position. If an existing brick lies within
    /// `mergeRadius`, merge into the NEAREST one (increment `sightings`, update
    /// `lastSeen`, exponentially smooth `worldPosition`, and adopt the incoming
    /// label/color/confidence only when `confidence` is strictly higher).
    /// Otherwise append a new brick. `now` is injectable for deterministic tests.
    /// - Returns: true if a NEW brick was added; false if merged into an existing one.
    @discardableResult
    func record(
        worldPosition: SIMD3<Float>,
        partNumber: String,
        name: String,
        color: LegoColor,
        confidence: Float,
        mergeRadius: Float = BrickInstanceTracker.defaultMergeRadius,
        now: Date = Date()
    ) -> Bool {
        if let index = nearestBrickIndex(to: worldPosition, within: mergeRadius) {
            merge(
                into: index,
                worldPosition: worldPosition,
                partNumber: partNumber,
                name: name,
                color: color,
                confidence: confidence,
                now: now
            )
            return false
        }

        bricks.append(
            TrackedBrick(
                id: UUID(),
                worldPosition: worldPosition,
                partNumber: partNumber,
                name: name,
                color: color,
                confidence: confidence,
                sightings: 1,
                firstSeen: now,
                lastSeen: now
            )
        )
        return true
    }

    /// Clear all tracked bricks (call at the start of each scan).
    func reset() {
        bricks.removeAll()
    }

    // MARK: - Private

    /// Index of the existing brick nearest to `position` whose distance is within
    /// `mergeRadius` (inclusive), or nil if none qualify.
    private func nearestBrickIndex(to position: SIMD3<Float>, within mergeRadius: Float) -> Int? {
        var bestIndex: Int?
        var bestDistance = Float.greatestFiniteMagnitude
        for (index, brick) in bricks.enumerated() {
            let distance = simd_distance(brick.worldPosition, position)
            if distance <= mergeRadius && distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }

    /// Merge an incoming detection into the existing brick at `index`.
    private func merge(
        into index: Int,
        worldPosition: SIMD3<Float>,
        partNumber: String,
        name: String,
        color: LegoColor,
        confidence: Float,
        now: Date
    ) {
        var brick = bricks[index]
        brick.sightings += 1
        brick.lastSeen = now
        brick.worldPosition = simd_mix(brick.worldPosition, worldPosition, SIMD3<Float>(repeating: Self.smoothingFactor))
        if confidence > brick.confidence {
            brick.partNumber = partNumber
            brick.name = name
            brick.color = color
            brick.confidence = confidence
        }
        bricks[index] = brick
    }
}
