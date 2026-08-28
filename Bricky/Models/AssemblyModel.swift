import Foundation

/// A single brick placed at an integer position on the LEGO stud grid, in build
/// order. An ordered list of these is the ground truth for a build — the final
/// 3D preview, the per-step renderings, the instruction text, and the derived
/// required-piece totals all come from placements (see the 3D build feature
/// plan in `docs/3d-build-feature-fix-plan.md`).
struct BrickPlacement: Codable, Identifiable, Hashable {
    let id: UUID
    let category: PieceCategory
    let dimensions: PieceDimensions
    let color: LegoColor
    /// Optional LDraw part number for an accurate mesh; falls back to procedural
    /// geometry when absent.
    let partNumber: String?
    /// Stud-grid position. `y` is the vertical layer measured in plate heights.
    let position: GridPosition
    /// Rotation about the vertical axis, in degrees (0 / 90 / 180 / 270).
    let rotationDegrees: Int
    /// 1-based build step this placement belongs to.
    let step: Int

    init(
        id: UUID = UUID(),
        category: PieceCategory,
        dimensions: PieceDimensions,
        color: LegoColor,
        partNumber: String? = nil,
        position: GridPosition,
        rotationDegrees: Int = 0,
        step: Int
    ) {
        self.id = id
        self.category = category
        self.dimensions = dimensions
        self.color = color
        self.partNumber = partNumber
        self.position = position
        self.rotationDegrees = rotationDegrees
        self.step = step
    }
}

/// Integer position on the stud grid. `x`/`z` are stud columns/rows; `y` is the
/// vertical layer in plate-height units (1 brick = 3 plates).
struct GridPosition: Codable, Hashable {
    let x: Int
    let y: Int
    let z: Int

    init(x: Int, y: Int, z: Int) {
        self.x = x
        self.y = y
        self.z = z
    }
}

/// Axis-aligned bounds of an assembly in stud-grid units.
struct GridBounds: Equatable {
    let min: GridPosition
    let max: GridPosition

    var isEmpty: Bool { min == max }
}

/// An ordered, positioned set of brick placements that composes a build.
struct AssemblyModel: Codable, Hashable {
    /// Placements in build order. `step` groups them into instruction steps.
    let placements: [BrickPlacement]

    init(placements: [BrickPlacement]) {
        self.placements = placements
    }

    // MARK: - Derived

    /// Highest step index present (0 when empty).
    var stepCount: Int {
        placements.map(\.step).max() ?? 0
    }

    /// Placements introduced at a specific 1-based step.
    func placements(inStep step: Int) -> [BrickPlacement] {
        placements.filter { $0.step == step }
    }

    /// All placements up to and including a step (what's on the table so far).
    func cumulativePlacements(throughStep step: Int) -> [BrickPlacement] {
        placements.filter { $0.step <= step }
    }

    /// Axis-aligned bounds across all placements (origin when empty).
    var bounds: GridBounds {
        guard let first = placements.first?.position else {
            return GridBounds(min: GridPosition(x: 0, y: 0, z: 0),
                              max: GridPosition(x: 0, y: 0, z: 0))
        }
        var minX = first.x, minY = first.y, minZ = first.z
        var maxX = first.x, maxY = first.y, maxZ = first.z
        for p in placements.map(\.position) {
            minX = Swift.min(minX, p.x); maxX = Swift.max(maxX, p.x)
            minY = Swift.min(minY, p.y); maxY = Swift.max(maxY, p.y)
            minZ = Swift.min(minZ, p.z); maxZ = Swift.max(maxZ, p.z)
        }
        return GridBounds(min: GridPosition(x: minX, y: minY, z: minZ),
                          max: GridPosition(x: maxX, y: maxY, z: maxZ))
    }

    /// Required-piece totals derived from the placements, so match-percentage
    /// logic stays consistent with what is actually built.
    var derivedRequiredPieces: [RequiredPiece] {
        struct Key: Hashable {
            let category: PieceCategory
            let dimensions: PieceDimensions
            let color: LegoColor
        }
        var counts: [Key: Int] = [:]
        var order: [Key] = []
        for placement in placements {
            let key = Key(category: placement.category,
                          dimensions: placement.dimensions,
                          color: placement.color)
            if counts[key] == nil { order.append(key) }
            counts[key, default: 0] += 1
        }
        return order.map { key in
            RequiredPiece(
                category: key.category,
                dimensions: key.dimensions,
                colorPreference: key.color,
                quantity: counts[key] ?? 0,
                flexible: false
            )
        }
    }
}
