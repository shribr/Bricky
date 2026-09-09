import Foundation

/// Pure, offline engine that answers "how much of this set can I build with the
/// bricks I have, and what am I missing?" — the no-ML half of the pile-to-sets
/// vision. It takes a set's bill of materials (from `RebrickableSetService`) and
/// a scanned/owned inventory and computes color-aware coverage plus a shortfall
/// list. No network, no fabrication: it only reports what the inputs support.
enum SetCompletionEngine {

    /// One required part the inventory can't fully cover.
    struct MissingPiece: Hashable {
        let partNumber: String
        /// `LegoColor` raw value, matching `LegoSet.SetPiece.color`.
        let color: String
        let required: Int
        let owned: Int
        /// How many more of this part+color are needed (`required - owned`, ≥ 1).
        var shortBy: Int { max(0, required - owned) }
    }

    /// Completion of one set against an inventory.
    struct Completion {
        let setNumber: String?
        /// 0…1 fraction of required piece instances the inventory covers.
        let coverage: Double
        /// Total required piece instances (sum of BOM quantities).
        let requiredPieceCount: Int
        /// Required instances the inventory covers (Σ min(owned, required)).
        let ownedTowardSetCount: Int
        /// Parts the inventory can't fully cover, largest shortfall first.
        let missing: [MissingPiece]

        var isComplete: Bool { requiredPieceCount > 0 && coverage >= 1.0 }
        var percentText: String { "\(Int((coverage * 100).rounded()))%" }
        /// Distinct part+color lines still short.
        var missingLineCount: Int { missing.count }
        /// Total individual pieces still needed across all lines.
        var missingPieceCount: Int { missing.reduce(0) { $0 + $1.shortBy } }
    }

    /// Aggregate an owned inventory into part+color → quantity.
    /// Color is keyed by `LegoColor.rawValue` so it lines up with a set BOM.
    static func aggregateInventory(_ pieces: [LegoPiece]) -> [String: Int] {
        var owned: [String: Int] = [:]
        for piece in pieces {
            let key = inventoryKey(partNumber: piece.partNumber, color: piece.color.rawValue)
            owned[key, default: 0] += max(0, piece.quantity)
        }
        return owned
    }

    /// Evaluate a single set BOM against an owned inventory (color-aware).
    static func evaluate(
        setNumber: String? = nil,
        bom: [LegoSet.SetPiece],
        ownedInventory pieces: [LegoPiece]
    ) -> Completion {
        evaluate(setNumber: setNumber, bom: bom, ownedCounts: aggregateInventory(pieces))
    }

    /// Evaluate against a pre-aggregated owned map (part+color → qty). Useful
    /// when ranking many sets against one inventory without re-aggregating.
    static func evaluate(
        setNumber: String? = nil,
        bom: [LegoSet.SetPiece],
        ownedCounts: [String: Int]
    ) -> Completion {
        // Collapse duplicate BOM lines (same part+color) into a single requirement.
        var required: [String: Int] = [:]
        for piece in bom where piece.quantity > 0 {
            let key = inventoryKey(partNumber: piece.partNumber, color: piece.color)
            required[key, default: 0] += piece.quantity
        }

        var requiredTotal = 0
        var coveredTotal = 0
        var missing: [MissingPiece] = []

        for (key, requiredQty) in required {
            let ownedQty = ownedCounts[key] ?? 0
            requiredTotal += requiredQty
            coveredTotal += min(ownedQty, requiredQty)
            if ownedQty < requiredQty {
                let (partNumber, color) = splitKey(key)
                missing.append(MissingPiece(
                    partNumber: partNumber,
                    color: color,
                    required: requiredQty,
                    owned: ownedQty
                ))
            }
        }

        let coverage = requiredTotal > 0 ? Double(coveredTotal) / Double(requiredTotal) : 0
        missing.sort {
            $0.shortBy != $1.shortBy ? $0.shortBy > $1.shortBy : $0.partNumber < $1.partNumber
        }

        return Completion(
            setNumber: setNumber,
            coverage: coverage,
            requiredPieceCount: requiredTotal,
            ownedTowardSetCount: coveredTotal,
            missing: missing
        )
    }

    /// Rank multiple sets by how buildable they are with one inventory,
    /// most-complete first. Aggregates the inventory once for efficiency.
    static func rank(
        sets: [(setNumber: String, bom: [LegoSet.SetPiece])],
        ownedInventory pieces: [LegoPiece]
    ) -> [Completion] {
        let owned = aggregateInventory(pieces)
        return sets
            .map { evaluate(setNumber: $0.setNumber, bom: $0.bom, ownedCounts: owned) }
            .sorted { $0.coverage > $1.coverage }
    }

    // MARK: - Keying

    private static func inventoryKey(partNumber: String, color: String) -> String {
        "\(partNumber)|\(color)"
    }

    private static func splitKey(_ key: String) -> (partNumber: String, color: String) {
        guard let sep = key.firstIndex(of: "|") else { return (key, "") }
        return (String(key[..<sep]), String(key[key.index(after: sep)...]))
    }
}
