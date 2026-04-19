import Foundation

/// Sprint 5 / F5 — Recommend storage-bin organization for a pile of pieces.
///
/// Heuristic only: groups pieces by color family OR by category, picks
/// whichever produces the most balanced bins for the user's pile size.
struct SortingSuggestionService {

    enum GroupingStrategy: String {
        case byColorFamily = "By Color Family"
        case byCategory = "By Category"
        case bySize = "By Size"
    }

    struct Bin: Identifiable {
        let id = UUID()
        let label: String
        /// Pieces (aggregated quantity) belonging to this bin.
        let totalQuantity: Int
        let uniqueTypes: Int
        /// Up to a few example piece names for the bin label preview.
        let exampleNames: [String]
    }

    struct Suggestion {
        let strategy: GroupingStrategy
        let bins: [Bin]
        /// Lower = more balanced (std deviation of bin sizes).
        let balanceScore: Double
    }

    static func recommend(pieces: [LegoPiece]) -> [Suggestion] {
        let totalCount = pieces.reduce(0) { $0 + $1.quantity }
        guard totalCount > 0 else { return [] }

        let strategies: [GroupingStrategy] = [.byColorFamily, .byCategory, .bySize]
        return strategies
            .map { strategy in
                let bins = makeBins(pieces: pieces, strategy: strategy)
                return Suggestion(
                    strategy: strategy,
                    bins: bins,
                    balanceScore: stdDev(of: bins.map { Double($0.totalQuantity) })
                )
            }
            .sorted { $0.balanceScore < $1.balanceScore }
    }

    // MARK: - Bin construction

    private static func makeBins(pieces: [LegoPiece], strategy: GroupingStrategy) -> [Bin] {
        var groups: [String: [LegoPiece]] = [:]
        for piece in pieces {
            let key: String
            switch strategy {
            case .byColorFamily:
                key = colorFamily(for: piece.color)
            case .byCategory:
                key = piece.category.rawValue
            case .bySize:
                key = sizeBucket(for: piece.dimensions)
            }
            groups[key, default: []].append(piece)
        }
        return groups
            .map { key, bucket in
                let total = bucket.reduce(0) { $0 + $1.quantity }
                let uniqueTypes = Set(bucket.map { $0.partNumber }).count
                let names = Array(Set(bucket.map { $0.name }))
                    .sorted()
                    .prefix(3)
                    .map { String($0) }
                return Bin(label: key,
                           totalQuantity: total,
                           uniqueTypes: uniqueTypes,
                           exampleNames: names)
            }
            .sorted { $0.totalQuantity > $1.totalQuantity }
    }

    // MARK: - Color family

    /// Group LEGO colors into bins typical of physical sorters.
    static func colorFamily(for color: LegoColor) -> String {
        switch color {
        case .red, .pink, .orange, .darkRed:                 return "Reds & Warm"
        case .yellow, .tan, .brown:                          return "Yellows & Earth"
        case .green, .lime, .darkGreen:                      return "Greens"
        case .blue, .lightBlue, .purple, .darkBlue:          return "Blues & Purple"
        case .white:                                         return "White"
        case .black, .darkGray, .gray:                       return "Black & Gray"
        case .transparent, .transparentBlue, .transparentRed: return "Transparent"
        }
    }

    // MARK: - Size bucket

    static func sizeBucket(for dim: PieceDimensions) -> String {
        let area = dim.studsWide * dim.studsLong
        switch area {
        case ...2:  return "Tiny (1×1, 1×2)"
        case 3...4: return "Small (2×2, 1×4)"
        case 5...8: return "Medium (2×4, 2×3)"
        case 9...16: return "Large (2×6 to 4×4)"
        default:    return "Extra Large (>4×4)"
        }
    }

    // MARK: - Helpers

    private static func stdDev(of values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count)
        return sqrt(variance)
    }
}
