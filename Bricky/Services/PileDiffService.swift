import Foundation

/// Sprint 5 / F1 — Compare two scan sessions piece-by-piece (by part number
/// + color) and produce added/removed/unchanged buckets.
///
/// Pure value-type service so it's trivially testable without UI.
struct PileDiffService {

    struct PieceKey: Hashable {
        let partNumber: String
        let color: LegoColor
    }

    struct DiffEntry: Identifiable {
        var id: PieceKey { key }
        let key: PieceKey
        /// One representative piece from either side (used for display name,
        /// dimensions, category, etc.). Always non-nil.
        let representativePiece: LegoPiece
        let baselineQuantity: Int
        let currentQuantity: Int
        var delta: Int { currentQuantity - baselineQuantity }
    }

    struct DiffResult {
        let added: [DiffEntry]      // new in current
        let removed: [DiffEntry]    // missing in current
        let increased: [DiffEntry]  // present in both, larger in current
        let decreased: [DiffEntry]  // present in both, smaller in current
        let unchanged: [DiffEntry]  // present in both, same quantity

        var totalAdded: Int { added.reduce(0) { $0 + $1.currentQuantity } }
        var totalRemoved: Int { removed.reduce(0) { $0 + $1.baselineQuantity } }
        var netDelta: Int {
            (added + increased + decreased)
                .reduce(0) { $0 + $1.delta }
            - removed.reduce(0) { $0 + $1.baselineQuantity }
        }
    }

    /// Compare two piece arrays. Quantities for the same `(partNumber, color)`
    /// are summed within each side first.
    static func diff(baseline: [LegoPiece], current: [LegoPiece]) -> DiffResult {
        let baselineMap = aggregate(baseline)
        let currentMap = aggregate(current)

        var added: [DiffEntry] = []
        var removed: [DiffEntry] = []
        var increased: [DiffEntry] = []
        var decreased: [DiffEntry] = []
        var unchanged: [DiffEntry] = []

        // Walk current → bucket added/increased/unchanged
        for (key, currentBundle) in currentMap {
            if let baselineBundle = baselineMap[key] {
                let entry = DiffEntry(
                    key: key,
                    representativePiece: currentBundle.representative,
                    baselineQuantity: baselineBundle.quantity,
                    currentQuantity: currentBundle.quantity
                )
                if entry.delta > 0 {
                    increased.append(entry)
                } else if entry.delta < 0 {
                    decreased.append(entry)
                } else {
                    unchanged.append(entry)
                }
            } else {
                added.append(DiffEntry(
                    key: key,
                    representativePiece: currentBundle.representative,
                    baselineQuantity: 0,
                    currentQuantity: currentBundle.quantity
                ))
            }
        }
        // Walk baseline → bucket removed
        for (key, baselineBundle) in baselineMap where currentMap[key] == nil {
            removed.append(DiffEntry(
                key: key,
                representativePiece: baselineBundle.representative,
                baselineQuantity: baselineBundle.quantity,
                currentQuantity: 0
            ))
        }

        return DiffResult(
            added: added.sorted(by: pieceSort),
            removed: removed.sorted(by: pieceSort),
            increased: increased.sorted(by: pieceSort),
            decreased: decreased.sorted(by: pieceSort),
            unchanged: unchanged.sorted(by: pieceSort)
        )
    }

    private struct Bundle {
        var quantity: Int
        var representative: LegoPiece
    }

    private static func aggregate(_ pieces: [LegoPiece]) -> [PieceKey: Bundle] {
        var map: [PieceKey: Bundle] = [:]
        for piece in pieces {
            let key = PieceKey(partNumber: piece.partNumber, color: piece.color)
            if var existing = map[key] {
                existing.quantity += piece.quantity
                map[key] = existing
            } else {
                map[key] = Bundle(quantity: piece.quantity, representative: piece)
            }
        }
        return map
    }

    private static func pieceSort(_ a: DiffEntry, _ b: DiffEntry) -> Bool {
        a.representativePiece.name
            .localizedCaseInsensitiveCompare(b.representativePiece.name) == .orderedAscending
    }
}
