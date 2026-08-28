import Foundation

/// Bridges a Set Forge `GeneratedLegoSet` (from a described set, a mosaic, or a
/// scanned real object) into the unified `AssemblyModel`, so all three sources
/// reuse the same 3D step viewer and overview preview (see §9/§10 of
/// `docs/3D-BUILD-FEATURE-FIX-PLAN.md`).
extension GeneratedLegoSet {
    /// Map the forged bricks + layer-by-layer step grouping into an ordered
    /// `AssemblyModel`.
    func asAssemblyModel() -> AssemblyModel {
        AssemblyModel(placements: Self.placements(from: bricks))
    }

    /// Core mapping, split out so it can be unit-tested without constructing a
    /// full `GeneratedLegoSet`. Step numbers come from
    /// `SetForgeInstructions.stepGroups` so they align with the generated steps.
    static func placements(from bricks: [PlacedBrick]) -> [BrickPlacement] {
        let groups = SetForgeInstructions.stepGroups(for: bricks)
        var result: [BrickPlacement] = []
        for (index, group) in groups.enumerated() {
            let step = index + 1
            for brick in group {
                result.append(brick.asBrickPlacement(step: step))
            }
        }
        return result
    }
}

extension PlacedBrick {
    /// A Set Forge brick is a 1×`length` brick running along +X, one build layer
    /// (24 LDU = 3 plate units) tall, at stud coordinates (x, z) and layer `y`.
    func asBrickPlacement(step: Int) -> BrickPlacement {
        BrickPlacement(
            category: .brick,
            dimensions: PieceDimensions(studsWide: length, studsLong: 1, heightUnits: 3),
            color: color,
            partNumber: part,
            position: GridPosition(x: x, y: y * 3, z: z), // layer → plate units
            rotationDegrees: 0,
            step: step
        )
    }
}
