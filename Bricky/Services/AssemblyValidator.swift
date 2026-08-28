import Foundation

/// Validates that an `AssemblyModel` is structurally sound before it drives the
/// 3D preview / step instructions: gapless build steps, every placement in a
/// step, and no floating bricks (each non-ground brick rests on support below).
enum AssemblyValidator {

    struct Result: Equatable {
        /// Distinct used steps form a gapless 1…N sequence.
        let stepsContiguous: Bool
        /// Every placement has a step ≥ 1.
        let allPlacementsStepped: Bool
        /// No brick floats — each non-ground brick has support directly below.
        let noFloatingBricks: Bool
        /// Human-readable problems, for diagnostics / test messages.
        let issues: [String]

        var isValid: Bool { stepsContiguous && allPlacementsStepped && noFloatingBricks }
    }

    static func validate(_ model: AssemblyModel) -> Result {
        let placements = model.placements
        var issues: [String] = []

        // Steps gapless 1…N.
        let usedSteps = Set(placements.map(\.step)).sorted()
        let stepsContiguous = usedSteps.isEmpty || usedSteps == Array(1...usedSteps.count)
        if !stepsContiguous {
            issues.append("Steps are not gapless 1…N: \(usedSteps)")
        }

        // Every placement stepped.
        let allPlacementsStepped = placements.allSatisfy { $0.step >= 1 }
        if !allPlacementsStepped {
            issues.append("Some placements have a step < 1")
        }

        // Floating-brick check.
        let (noFloating, floatingCount) = checkSupport(placements)
        if !noFloating {
            issues.append("\(floatingCount) brick(s) float with no support below")
        }

        return Result(
            stepsContiguous: stepsContiguous,
            allPlacementsStepped: allPlacementsStepped,
            noFloatingBricks: noFloating,
            issues: issues
        )
    }

    /// A brick is supported if it sits on the ground layer, or another brick's
    /// top surface (`topY`) meets its `bottomY` in a shared stud column.
    private static func checkSupport(_ placements: [BrickPlacement]) -> (ok: Bool, floating: Int) {
        guard let groundY = placements.map(\.bottomY).min() else { return (true, 0) }

        // Map each occupied column → the set of brick top-surface layers there.
        var topSurfaces: [BrickPlacement.Column: Set<Int>] = [:]
        for p in placements {
            for col in p.occupiedColumns {
                topSurfaces[col, default: []].insert(p.topY)
            }
        }

        var floating = 0
        for p in placements where p.bottomY != groundY {
            let supported = p.occupiedColumns.contains { col in
                topSurfaces[col]?.contains(p.bottomY) ?? false
            }
            if !supported { floating += 1 }
        }
        return (floating == 0, floating)
    }
}
