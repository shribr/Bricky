import Foundation

/// Parses natural language queries into structured piece filters.
/// Supports queries like "red 2×4 bricks", "all blue plates", "large technic pieces".
final class NaturalLanguageSearchService {
    static let shared = NaturalLanguageSearchService()
    private init() {}

    struct ParsedQuery {
        var colors: [LegoColor] = []
        var categories: [PieceCategory] = []
        var minStudsWide: Int?
        var maxStudsWide: Int?
        var minStudsLong: Int?
        var maxStudsLong: Int?
        var sizeHint: SizeHint?
        var textFragments: [String] = []

        enum SizeHint {
            case small  // 1×1, 1×2
            case medium // 2×2, 2×4
            case large  // 4×4+
        }

        var isEmpty: Bool {
            colors.isEmpty && categories.isEmpty && minStudsWide == nil &&
            maxStudsWide == nil && minStudsLong == nil && maxStudsLong == nil &&
            sizeHint == nil && textFragments.isEmpty
        }
    }

    /// Parse a natural language query into structured filters
    func parse(_ query: String) -> ParsedQuery {
        let normalized = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return ParsedQuery() }

        var result = ParsedQuery()

        let tokens = tokenize(normalized)

        // Extract colors
        result.colors = extractColors(from: tokens)

        // Extract categories
        result.categories = extractCategories(from: tokens)

        // Extract dimensions (e.g., "2x4", "2×4", "1 by 2")
        extractDimensions(from: normalized, into: &result)

        // Extract size hints
        result.sizeHint = extractSizeHint(from: tokens)

        // Remaining tokens become text fragments for fuzzy matching
        let consumedWords = Set(
            result.colors.flatMap { colorSynonyms(for: $0) } +
            result.categories.flatMap { categorySynonyms(for: $0) } +
            sizeWords + dimensionWords + stopWords
        )
        result.textFragments = tokens.filter { !consumedWords.contains($0) && $0.count > 1 }

        return result
    }

    /// Filter pieces using a parsed query
    func filter(_ pieces: [LegoPiece], with query: ParsedQuery) -> [LegoPiece] {
        guard !query.isEmpty else { return pieces }

        return pieces.filter { piece in
            // Color filter
            if !query.colors.isEmpty && !query.colors.contains(piece.color) {
                return false
            }

            // Category filter
            if !query.categories.isEmpty && !query.categories.contains(piece.category) {
                return false
            }

            // Dimension filters
            if let min = query.minStudsWide, piece.dimensions.studsWide < min { return false }
            if let max = query.maxStudsWide, piece.dimensions.studsWide > max { return false }
            if let min = query.minStudsLong, piece.dimensions.studsLong < min { return false }
            if let max = query.maxStudsLong, piece.dimensions.studsLong > max { return false }

            // Size hint
            if let hint = query.sizeHint {
                let area = piece.dimensions.studsWide * piece.dimensions.studsLong
                switch hint {
                case .small: if area > 2 { return false }
                case .medium: if area < 3 || area > 8 { return false }
                case .large: if area < 9 { return false }
                }
            }

            // Text fragment matching (name, part number)
            if !query.textFragments.isEmpty {
                let searchable = "\(piece.name) \(piece.partNumber)".lowercased()
                let matched = query.textFragments.allSatisfy { searchable.contains($0) }
                if !matched { return false }
            }

            return true
        }
    }

    /// Convenience: parse + filter in one call
    func search(_ pieces: [LegoPiece], query: String) -> [LegoPiece] {
        let parsed = parse(query)
        return filter(pieces, with: parsed)
    }

    // MARK: - Tokenization

    private func tokenize(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Color Extraction

    private let colorMap: [String: LegoColor] = [
        "red": .red, "scarlet": .red, "crimson": .red,
        "blue": .blue, "azure": .blue,
        "yellow": .yellow, "gold": .yellow, "golden": .yellow,
        "green": .green, "emerald": .green,
        "black": .black, "dark": .darkGray,
        "white": .white, "ivory": .white,
        "gray": .gray, "grey": .gray, "silver": .gray,
        "orange": .orange,
        "brown": .brown, "chocolate": .brown,
        "tan": .tan, "beige": .tan, "sand": .tan,
        "purple": .purple, "violet": .purple, "magenta": .purple,
        "pink": .pink, "rose": .pink,
        "lime": .lime, "neon": .lime,
        "transparent": .transparent, "trans": .transparent, "clear": .transparent,
    ]

    private func extractColors(from tokens: [String]) -> [LegoColor] {
        var colors: [LegoColor] = []

        // Handle compound colors
        let joined = tokens.joined(separator: " ")
        if joined.contains("dark blue") || joined.contains("navy") { colors.append(.darkBlue) }
        if joined.contains("dark green") || joined.contains("forest") { colors.append(.darkGreen) }
        if joined.contains("dark red") || joined.contains("maroon") { colors.append(.darkRed) }
        if joined.contains("dark gray") || joined.contains("dark grey") || joined.contains("charcoal") { colors.append(.darkGray) }
        if joined.contains("light blue") || joined.contains("sky blue") || joined.contains("baby blue") { colors.append(.lightBlue) }
        if joined.contains("trans blue") || joined.contains("transparent blue") { colors.append(.transparentBlue) }
        if joined.contains("trans red") || joined.contains("transparent red") { colors.append(.transparentRed) }

        // Simple color tokens (skip if already matched as compound)
        let compoundColorWords = Set(["dark", "light", "sky", "baby", "trans", "transparent", "forest", "navy"])
        for token in tokens where !compoundColorWords.contains(token) {
            if let color = colorMap[token], !colors.contains(color) {
                colors.append(color)
            }
        }

        return colors
    }

    private func colorSynonyms(for color: LegoColor) -> [String] {
        colorMap.filter { $0.value == color }.map { $0.key }
    }

    // MARK: - Category Extraction

    private let categoryMap: [String: PieceCategory] = [
        "brick": .brick, "bricks": .brick, "block": .brick, "blocks": .brick,
        "plate": .plate, "plates": .plate, "flat": .plate,
        "tile": .tile, "tiles": .tile, "smooth": .tile,
        "slope": .slope, "slopes": .slope, "angled": .slope, "ramp": .slope,
        "arch": .arch, "arches": .arch, "curved": .arch,
        "round": .round, "circular": .round, "cylinder": .round,
        "technic": .technic, "technical": .technic, "beam": .technic,
        "specialty": .specialty, "special": .specialty,
        "minifig": .minifigure, "minifigure": .minifigure, "figure": .minifigure, "person": .minifigure,
        "window": .window, "door": .window,
        "wheel": .wheel, "wheels": .wheel, "tire": .wheel, "tires": .wheel,
        "connector": .connector, "connectors": .connector, "pin": .connector,
        "hinge": .hinge, "hinges": .hinge,
        "bracket": .bracket, "brackets": .bracket,
        "wedge": .wedge, "wedges": .wedge,
    ]

    private func extractCategories(from tokens: [String]) -> [PieceCategory] {
        var categories: [PieceCategory] = []
        for token in tokens {
            if let cat = categoryMap[token], !categories.contains(cat) {
                categories.append(cat)
            }
        }
        return categories
    }

    private func categorySynonyms(for category: PieceCategory) -> [String] {
        categoryMap.filter { $0.value == category }.map { $0.key }
    }

    // MARK: - Dimension Extraction

    private let dimensionWords = ["by", "x", "×", "wide", "long", "stud", "studs"]

    private func extractDimensions(from text: String, into result: inout ParsedQuery) {
        // Normalize × (U+00D7) to x for regex matching
        let normalized = text.replacingOccurrences(of: "\u{00D7}", with: "x")
        // Match patterns: "2x4", "2 x 4", "2 by 4"
        let patterns = [
            #"(\d+)\s*x\s*(\d+)"#,
            #"(\d+)\s+by\s+(\d+)"#,
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)) {
                if let r1 = Range(match.range(at: 1), in: normalized),
                   let r2 = Range(match.range(at: 2), in: normalized),
                   let w = Int(normalized[r1]), let l = Int(normalized[r2]) {
                    result.minStudsWide = w
                    result.maxStudsWide = w
                    result.minStudsLong = l
                    result.maxStudsLong = l
                    return
                }
            }
        }
    }

    // MARK: - Size Hints

    private let sizeWords = ["small", "tiny", "little", "medium", "normal", "standard", "large", "big", "huge", "giant"]

    private func extractSizeHint(from tokens: [String]) -> ParsedQuery.SizeHint? {
        for token in tokens {
            switch token {
            case "small", "tiny", "little": return .small
            case "medium", "normal", "standard": return .medium
            case "large", "big", "huge", "giant": return .large
            default: continue
            }
        }
        return nil
    }

    private let stopWords = Set([
        "the", "a", "an", "all", "my", "me", "show", "find",
        "get", "give", "display", "list", "search", "for",
        "of", "with", "in", "and", "or", "that", "are", "is",
        "have", "has", "i", "piece", "pieces", "lego", "any",
    ])
}
