import Foundation

/// Comprehensive LEGO parts catalog backed by `Resources/LegoPartsCatalog.json`.
///
/// The catalog ships ~1,000 deduplicated parts with real BrickLink part
/// numbers, dimensions, common colors, and search keywords. Loading is
/// done once on first access (or once per process if the singleton is
/// reset in tests) and the JSON file is bundled with the app — no
/// network calls.
///
/// History: previously this catalog was authored as ~10,000 LOC of inline
/// `CatalogPiece(...)` constructor calls split across 7 Swift files. That
/// inflated compile time and made data updates painful. The on-disk JSON
/// representation is ~330 KB (vs ~150 KB compiled into the binary as code)
/// and removes ~9,500 LOC of source.
final class LegoPartsCatalog {
    static let shared = LegoPartsCatalog()

    struct CatalogPiece: Identifiable {
        let id: String // partNumber
        let partNumber: String
        let name: String
        let category: PieceCategory
        let dimensions: PieceDimensions
        let commonColors: [LegoColor]
        let weight: Double // grams (approximate)
        let keywords: [String] // for search/matching

        init(partNumber: String, name: String, category: PieceCategory,
             dimensions: PieceDimensions, commonColors: [LegoColor],
             weight: Double = 0, keywords: [String] = []) {
            self.id = partNumber
            self.partNumber = partNumber
            self.name = name
            self.category = category
            self.dimensions = dimensions
            self.commonColors = commonColors
            self.weight = weight
            self.keywords = keywords
        }
    }

    private(set) var pieces: [CatalogPiece] = []
    private var partNumberIndex: [String: CatalogPiece] = [:]
    private var categoryIndex: [PieceCategory: [CatalogPiece]] = [:]
    private var dimensionIndex: [String: [CatalogPiece]] = [:]

    private init() {
        loadCatalog()
        buildIndices()
    }

    // MARK: - Lookup

    func piece(byPartNumber partNumber: String) -> CatalogPiece? {
        partNumberIndex[partNumber]
    }

    func pieces(inCategory category: PieceCategory) -> [CatalogPiece] {
        categoryIndex[category] ?? []
    }

    func findBestMatch(category: PieceCategory, dimensions: PieceDimensions, color: LegoColor) -> CatalogPiece? {
        // Exact match
        let key = "\(dimensions.studsWide)x\(dimensions.studsLong)x\(dimensions.heightUnits)"
        if let candidates = dimensionIndex[key] {
            if let exact = candidates.first(where: { $0.category == category }) {
                return exact
            }
            // Same dimensions, any category
            if let close = candidates.first { return close }
        }

        // Category + closest size
        let sameCat = categoryIndex[category] ?? []
        return sameCat.min(by: { a, b in
            let aDiff = abs(a.dimensions.studsWide - dimensions.studsWide) +
                        abs(a.dimensions.studsLong - dimensions.studsLong) +
                        abs(a.dimensions.heightUnits - dimensions.heightUnits)
            let bDiff = abs(b.dimensions.studsWide - dimensions.studsWide) +
                        abs(b.dimensions.studsLong - dimensions.studsLong) +
                        abs(b.dimensions.heightUnits - dimensions.heightUnits)
            return aDiff < bDiff
        })
    }

    func search(query: String) -> [CatalogPiece] {
        let q = query.lowercased()
        return pieces.filter { piece in
            piece.name.lowercased().contains(q) ||
            piece.partNumber.contains(q) ||
            piece.keywords.contains(where: { $0.contains(q) })
        }
    }

    // MARK: - Index Building

    private func buildIndices() {
        for piece in pieces {
            partNumberIndex[piece.partNumber] = piece
            categoryIndex[piece.category, default: []].append(piece)
            let key = "\(piece.dimensions.studsWide)x\(piece.dimensions.studsLong)x\(piece.dimensions.heightUnits)"
            dimensionIndex[key, default: []].append(piece)
        }
    }

    // MARK: - JSON Loading

    /// Color-set sentinels used in the JSON to avoid repeating the full
    /// 22-element color array on every basic brick. Resolved at decode
    /// time to the matching `[LegoColor]`.
    private enum ColorAlias: String {
        case all = "_all"
        case basic = "_basic"
        case structural = "_structural"
        case bright = "_bright"
        case trans = "_trans"

        var colors: [LegoColor] {
            switch self {
            case .all: return LegoColor.allCases
            case .basic: return [.red, .blue, .yellow, .green, .black, .white,
                                 .gray, .darkGray, .orange, .brown, .tan]
            case .structural: return [.black, .gray, .darkGray, .white, .tan, .brown]
            case .bright: return [.red, .blue, .yellow, .green, .orange, .lime,
                                  .purple, .pink, .lightBlue]
            case .trans: return [.transparent, .transparentBlue, .transparentRed]
            }
        }
    }

    /// JSON-decoded shape. `commonColors` may be either a sentinel string
    /// (e.g. `"_all"`) or an explicit `[String]` of `LegoColor` raw values.
    private struct JSONPiece: Decodable {
        let partNumber: String
        let name: String
        let category: PieceCategory
        let dimensions: PieceDimensions
        let commonColors: ColorList
        let weight: Double
        let keywords: [String]
    }

    private enum ColorList: Decodable {
        case alias(ColorAlias)
        case explicit([LegoColor])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let str = try? container.decode(String.self),
               let alias = ColorAlias(rawValue: str) {
                self = .alias(alias)
            } else if let names = try? container.decode([String].self) {
                self = .explicit(names.compactMap { LegoColor(fromString: $0) })
            } else {
                self = .explicit([])
            }
        }

        var resolved: [LegoColor] {
            switch self {
            case .alias(let a): return a.colors
            case .explicit(let arr): return arr
            }
        }
    }

    private func loadCatalog() {
        guard let url = Bundle.main.url(forResource: "LegoPartsCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            assertionFailure("LegoPartsCatalog.json missing from app bundle")
            pieces = []
            return
        }
        do {
            let decoded = try JSONDecoder().decode([JSONPiece].self, from: data)
            pieces = decoded.map { p in
                CatalogPiece(
                    partNumber: p.partNumber,
                    name: p.name,
                    category: p.category,
                    dimensions: p.dimensions,
                    commonColors: p.commonColors.resolved,
                    weight: p.weight,
                    keywords: p.keywords
                )
            }
        } catch {
            assertionFailure("Failed to decode LegoPartsCatalog.json: \(error)")
            pieces = []
        }
    }
}
