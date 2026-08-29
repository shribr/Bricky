import Foundation

/// Generates a coherent, gravity-valid `AssemblyModel` from a bag of
/// `RequiredPiece`s, for catalog projects that don't yet have an authored (or
/// LDraw-imported) assembly. Output is deterministic and always passes
/// `AssemblyValidator` (every non-ground brick rests flush on support).
///
/// Aesthetics are intentionally blocky — this is the fallback path from the
/// plan's §3.2; recognizable authored/LDraw models take precedence when present.
enum ProceduralAssemblyGenerator {

    static func generate(from required: [RequiredPiece], defaultColor: LegoColor = .gray) -> AssemblyModel {
        // Expand to individual bricks.
        var bricks: [(category: PieceCategory, dims: PieceDimensions, color: LegoColor)] = []
        for piece in required {
            let color = piece.colorPreference ?? defaultColor
            for _ in 0..<max(0, piece.quantity) {
                bricks.append((piece.category, piece.dimensions, color))
            }
        }
        guard !bricks.isEmpty else { return AssemblyModel(placements: []) }

        // Build order: larger footprint first (structural base), then taller,
        // then stable by colour — deterministic.
        bricks.sort { a, b in
            let fa = a.dims.studsWide * a.dims.studsLong
            let fb = b.dims.studsWide * b.dims.studsLong
            if fa != fb { return fa > fb }
            if a.dims.heightUnits != b.dims.heightUnits { return a.dims.heightUnits > b.dims.heightUnits }
            return a.color.rawValue < b.color.rawValue
        }

        // Roughly-cubic footprint so the build has some height, not a flat carpet.
        let totalArea = bricks.reduce(0) { $0 + max(1, $1.dims.studsWide) * max(1, $1.dims.studsLong) }
        let maxW = bricks.map { max(1, $0.dims.studsWide) }.max() ?? 1
        let maxL = bricks.map { max(1, $0.dims.studsLong) }.max() ?? 1
        let baseArea = max(maxW * maxL, Int(pow(Double(totalArea), 2.0 / 3.0).rounded(.up)))
        let width = max(maxW, Int(Double(baseArea).squareRoot().rounded(.up)))
        let depth = max(maxL, Int((Double(baseArea) / Double(width)).rounded(.up)))

        let piecesPerStep = max(1, min(4, Int((Double(bricks.count) / 20.0).rounded(.up))))

        var topAt: [BrickPlacement.Column: Int] = [:]   // current stacked height per column
        var placements: [BrickPlacement] = []
        var maxZUsed = 0

        for (index, brick) in bricks.enumerated() {
            let w = max(1, brick.dims.studsWide)
            let l = max(1, brick.dims.studsLong)
            let h = max(1, brick.dims.heightUnits)

            // Prefer the lowest flush slot inside the footprint (fills the base
            // layer before stacking); extend the footprint only if none exists.
            var best: (x: Int, z: Int, top: Int)?
            for z in 0...max(0, depth - l) {
                for x in 0...max(0, width - w) {
                    if let top = flushHeight(x: x, z: z, w: w, l: l, topAt: topAt) {
                        if best == nil || top < best!.top {
                            best = (x, z, top)
                        }
                    }
                }
            }
            let slot = best ?? (x: 0, z: maxZUsed, top: 0) // fresh ground row

            for dx in 0..<w {
                for dz in 0..<l {
                    topAt[BrickPlacement.Column(x: slot.x + dx, z: slot.z + dz)] = slot.top + h
                }
            }
            maxZUsed = max(maxZUsed, slot.z + l)

            placements.append(BrickPlacement(
                category: brick.category,
                dimensions: brick.dims,
                color: brick.color,
                position: GridPosition(x: slot.x, y: slot.top, z: slot.z),
                rotationDegrees: 0,
                step: index / piecesPerStep + 1
            ))
        }
        return AssemblyModel(placements: placements)
    }

    /// The support height for a `w×l` footprint at (x, z) if all covered columns
    /// share the same top (flush support / ground); otherwise `nil`.
    private static func flushHeight(
        x: Int, z: Int, w: Int, l: Int,
        topAt: [BrickPlacement.Column: Int]
    ) -> Int? {
        var height: Int?
        for dx in 0..<w {
            for dz in 0..<l {
                let top = topAt[BrickPlacement.Column(x: x + dx, z: z + dz)] ?? 0
                if let h = height {
                    if h != top { return nil }
                } else {
                    height = top
                }
            }
        }
        return height
    }
}

extension LegoProject {
    /// The assembly to render/step from: the authored/LDraw assembly when
    /// present, else a bundled LDraw model for this project, else a generated
    /// one from the required pieces.
    var resolvedAssembly: AssemblyModel {
        if let assembly, !assembly.placements.isEmpty { return assembly }
        if let bundled = LDrawModelLibrary.assembly(forProjectNamed: name) { return bundled }
        return ProceduralAssemblyGenerator.generate(from: requiredPieces)
    }

    /// Whether this project has authored geometry that renders as a recognizable
    /// shape (an inline assembly or a bundled LDraw model). Projects without one
    /// fall back to a blocky procedural build, so they're hidden from build
    /// suggestions until a real model is added.
    var hasRecognizableModel: Bool {
        if let assembly, !assembly.placements.isEmpty { return true }
        return LDrawModelLibrary.hasModel(forProjectNamed: name)
    }
}
