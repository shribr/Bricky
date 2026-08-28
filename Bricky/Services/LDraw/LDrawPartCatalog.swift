import Foundation

/// Maps LDraw part numbers to our `PieceCategory` + `PieceDimensions`.
///
/// Covers the common bricks/plates/tiles/slopes/round parts that make up simple
/// builds. Unknown parts resolve to `nil`; the model parser falls back to a 1×1
/// brick while preserving the real part number so LDraw geometry still renders.
enum LDrawPartCatalog {

    struct PartSpec {
        let category: PieceCategory
        let dimensions: PieceDimensions
    }

    private static func brick(_ w: Int, _ l: Int) -> PartSpec {
        PartSpec(category: .brick, dimensions: PieceDimensions(studsWide: w, studsLong: l, heightUnits: 3))
    }
    private static func plate(_ w: Int, _ l: Int) -> PartSpec {
        PartSpec(category: .plate, dimensions: PieceDimensions(studsWide: w, studsLong: l, heightUnits: 1))
    }
    private static func tile(_ w: Int, _ l: Int) -> PartSpec {
        PartSpec(category: .tile, dimensions: PieceDimensions(studsWide: w, studsLong: l, heightUnits: 1))
    }
    private static func slope(_ w: Int, _ l: Int) -> PartSpec {
        PartSpec(category: .slope, dimensions: PieceDimensions(studsWide: w, studsLong: l, heightUnits: 3))
    }
    private static func round(_ w: Int, _ l: Int, height: Int) -> PartSpec {
        PartSpec(category: .round, dimensions: PieceDimensions(studsWide: w, studsLong: l, heightUnits: height))
    }

    /// Part number (no extension, lowercased) → spec.
    static let specs: [String: PartSpec] = [
        // Bricks
        "3005": brick(1, 1), "3004": brick(1, 2), "3622": brick(1, 3),
        "3010": brick(1, 4), "3009": brick(1, 6), "3008": brick(1, 8),
        "3003": brick(2, 2), "3002": brick(2, 3), "3001": brick(2, 4),
        "2456": brick(2, 6), "3007": brick(2, 8), "3006": brick(2, 10),
        // Plates
        "3024": plate(1, 1), "3023": plate(1, 2), "3623": plate(1, 3),
        "3710": plate(1, 4), "3666": plate(1, 6), "3460": plate(1, 8),
        "3022": plate(2, 2), "3021": plate(2, 3), "3020": plate(2, 4),
        "3795": plate(2, 6), "3034": plate(2, 8), "3832": plate(2, 10),
        // Tiles
        "3070": tile(1, 1), "3069": tile(1, 2), "63864": tile(1, 3),
        "2431": tile(1, 4), "6636": tile(1, 6), "3068": tile(2, 2),
        // Slopes
        "3040": slope(1, 2), "4286": slope(1, 3), "3039": slope(2, 2),
        "3038": slope(2, 3), "3298": slope(2, 3),
        // Round
        "3062": round(1, 1, height: 3), "4073": round(1, 1, height: 1),
        "6141": round(1, 1, height: 1), "98138": round(1, 1, height: 1),
    ]

    static func spec(forPartNumber partNumber: String) -> PartSpec? {
        specs[normalize(partNumber)]
    }

    /// Strip a directory prefix + `.dat`/`.ldr` extension and lowercase.
    static func normalize(_ fileName: String) -> String {
        var name = fileName.lowercased().replacingOccurrences(of: "\\", with: "/")
        if let slash = name.lastIndex(of: "/") {
            name = String(name[name.index(after: slash)...])
        }
        for ext in [".dat", ".ldr", ".mpd"] where name.hasSuffix(ext) {
            name = String(name.dropLast(ext.count))
        }
        return name
    }
}
