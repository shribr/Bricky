import Foundation

/// Converts a packed mosaic (a flat grid of 1×N plate runs) into an
/// `AssemblyModel` so it can reuse the unified 3D step viewer. Each plate run
/// becomes a placement on the XZ plane (mosaic row → Z, one plate layer tall),
/// grouped into build steps by row (top → bottom).
enum MosaicAssemblyBridge {

    static func assembly(bricks: [MosaicBrick], palette: MosaicPalette) -> AssemblyModel {
        guard !bricks.isEmpty else { return AssemblyModel(placements: []) }

        // One step per mosaic row that actually has bricks (gapless).
        let rows = Set(bricks.map(\.y)).sorted()
        var stepForRow: [Int: Int] = [:]
        for (index, row) in rows.enumerated() { stepForRow[row] = index + 1 }

        let placements = bricks.map { brick -> BrickPlacement in
            BrickPlacement(
                category: .plate,
                dimensions: PieceDimensions(studsWide: brick.length, studsLong: 1, heightUnits: 1),
                color: legoColor(forName: brick.color, palette: palette),
                partNumber: brick.part,
                position: GridPosition(x: brick.x, y: 0, z: brick.y),
                rotationDegrees: 0,
                step: stepForRow[brick.y] ?? 1
            )
        }
        return AssemblyModel(placements: placements)
    }

    /// Map a mosaic palette color name to the nearest `LegoColor` (mosaic palette
    /// names don't always match `LegoColor` cases, so match by RGB).
    static func legoColor(forName name: String, palette: MosaicPalette) -> LegoColor {
        guard let color = palette.color(named: name) else { return .gray }
        return LegoColor.closest(
            r: UInt8(clamping: color.red),
            g: UInt8(clamping: color.green),
            b: UInt8(clamping: color.blue),
            excludeTransparent: true
        )?.color ?? .gray
    }
}
