import Foundation
import Compression

/// Runtime loader for the bundled minifigure catalog (~16K figures).
/// Decompresses + decodes `MinifigureCatalog.json.gz` from the app bundle on
/// the first `load()` call, then keeps the figures + indexes in memory.
@MainActor
final class MinifigureCatalog: ObservableObject {
    static let shared = MinifigureCatalog()

    @Published private(set) var allFigures: [Minifigure] = []
    @Published private(set) var isLoaded: Bool = false
    @Published private(set) var loadError: String?

    /// Sorted list of unique themes (used for filter pickers).
    @Published private(set) var themes: [String] = []
    /// Earliest..latest year (used for year filter slider).
    @Published private(set) var yearRange: ClosedRange<Int> = 1978...2026

    /// User-added figures (persisted to Documents). Merged into `allFigures`
    /// and the lookup indexes whenever the bundled catalog is rebuilt.
    @Published private(set) var userFigures: [Minifigure] = []

    /// Stable id prefix for user-added figures so callers can distinguish
    /// them from Rebrickable / BrickLink ids.
    static let userFigureIdPrefix = "user-"

    /// Index by fig id (Rebrickable `fig-XXXXXX` ids).
    private var byId: [String: Minifigure] = [:]
    /// Index by torso part number (used by `MinifigureIdentificationService`).
    private var byTorsoPart: [String: [Minifigure]] = [:]
    /// Index by theme (top-level).
    private var byTheme: [String: [Minifigure]] = [:]

    private var userStorageURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("userMinifigures.json")
    }

    private init() {
        loadUserFigures()
    }

    // MARK: - Loading

    /// Decompress and decode the bundled catalog on a background queue.
    /// Safe to call multiple times — only loads once.
    func load() async {
        guard !isLoaded, loadError == nil else { return }

        let result: Result<[Minifigure], Error> = await Task.detached(priority: .userInitiated) {
            do {
                // Try Bundle.main (app context) first, then this class's bundle
                // (test-runner context where Bundle.main is xctrunner).
                let candidates: [Bundle] = [.main, Bundle(for: MinifigureCatalog.self)]
                let url = candidates.lazy.compactMap {
                    $0.url(forResource: "MinifigureCatalog", withExtension: "json.gz")
                }.first
                guard let url else {
                    return .failure(GzipError.bundleResourceMissing)
                }
                let gzipped = try Data(contentsOf: url)
                let decompressed = try Self.gunzip(gzipped)
                let decoder = JSONDecoder()
                let payload = try decoder.decode(CatalogPayload.self, from: decompressed)
                return .success(payload.figures)
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success(let figs):
            self.allFigures = figs + userFigures
            self.applyImageOverrides()
            self.buildIndexes(self.allFigures)
            self.isLoaded = true
        case .failure(let err):
            self.loadError = "Catalog load failed: \(err.localizedDescription)"
        }
    }

    private func buildIndexes(_ figs: [Minifigure]) {
        var byId: [String: Minifigure] = [:]
        var byTorsoPart: [String: [Minifigure]] = [:]
        var byTheme: [String: [Minifigure]] = [:]
        var themesSet = Set<String>()
        var minYear = Int.max
        var maxYear = Int.min

        for fig in figs {
            byId[fig.id] = fig
            if let torso = fig.torsoPart {
                byTorsoPart[torso.partNumber, default: []].append(fig)
            }
            byTheme[fig.theme, default: []].append(fig)
            themesSet.insert(fig.theme)
            if fig.year > 0 {
                minYear = min(minYear, fig.year)
                maxYear = max(maxYear, fig.year)
            }
        }

        self.byId = byId
        self.byTorsoPart = byTorsoPart
        self.byTheme = byTheme
        self.themes = themesSet.sorted()
        if minYear < Int.max && maxYear > Int.min {
            self.yearRange = minYear...maxYear
        }
    }

    // MARK: - Lookup

    func figure(id: String) -> Minifigure? {
        byId[id]
    }

    func figures(usingTorsoPart partNumber: String) -> [Minifigure] {
        byTorsoPart[partNumber] ?? []
    }

    func figures(inTheme theme: String) -> [Minifigure] {
        byTheme[theme] ?? []
    }

    /// Find figures related to the given figure by name keywords and theme.
    /// Returns figures that share significant name tokens (e.g., "Island Warrior")
    /// or belong to the same theme, excluding the source figure itself.
    func relatedFigures(to figure: Minifigure, limit: Int = 20) -> [Minifigure] {
        let nameTokens = extractSignificantNameTokens(figure.name)
        var scored: [(Minifigure, Int)] = []

        for fig in allFigures where fig.id != figure.id {
            var score = 0
            let figTokens = extractSignificantNameTokens(fig.name)
            // Count shared significant name tokens
            let shared = nameTokens.intersection(figTokens)
            score += shared.count * 3 // strong signal

            // Same theme bonus
            if fig.theme == figure.theme { score += 2 }

            // Same sub-theme (theme names often have hierarchy like "Super Heroes")
            if !figure.theme.isEmpty && fig.name.lowercased().contains(figure.theme.lowercased()) {
                score += 1
            }

            if score >= 3 { scored.append((fig, score)) }
        }

        scored.sort { $0.1 > $1.1 }
        return scored.prefix(limit).map(\.0)
    }

    /// Extract significant multi-word name tokens for matching.
    /// Strips generic LEGO terms and returns meaningful identifier phrases.
    private func extractSignificantNameTokens(_ name: String) -> Set<String> {
        let stopWords: Set<String> = [
            "minifigure", "minifig", "figure", "fig", "with", "and", "the",
            "in", "on", "of", "for", "set", "from", "series", "version",
            "new", "old", "small", "large", "mini", "lego", "brick",
            "printed", "pattern", "torso", "legs", "head", "hair", "helmet",
            "accessory", "accessories", "piece", "part", "type", "number"
        ]
        let words = name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 && !stopWords.contains($0) }
        return Set(words)
    }

    /// Find figures by name similarity — useful for expanding scan results
    /// to include all variants of an identified character.
    func figuresByNamePrefix(_ prefix: String, excludingIds: Set<String> = []) -> [Minifigure] {
        let q = prefix.lowercased()
        return allFigures.filter { fig in
            !excludingIds.contains(fig.id) && fig.name.lowercased().contains(q)
        }
    }

    // MARK: - Aliases

    /// Colloquial / community / BrickLink names for figures whose Rebrickable
    /// catalog name is purely descriptive ("Policeman, Black Jacket with
    /// Zipper and Badge, Black Cap, Sunglasses") and therefore unlikely to
    /// surface for natural search terms a kid or adult collector would type
    /// ("classic town police officer", "cop031").
    ///
    /// Keep entries focused on widely-recognized names. The map is small on
    /// purpose — it's an escape hatch for high-traffic figures, NOT a place
    /// to put every collector nickname. Add entries when a figure that's
    /// clearly in the catalog isn't being found via search.
    nonisolated static let figureAliases: [String: [String]] = [
        // Classic Town Police Officer (BrickLink cop031): the iconic
        // black-jacket / zipper / sheriff-star / black-cap / sunglasses
        // figure shipped in many late-90s / early-2000s Town Police sets.
        "fig-000697": [
            "Classic Town Police Officer",
            "Town Police Officer",
            "cop031",
            "Sheriff",
            "Police Sheriff"
        ]
    ]

    /// Aliases for a specific figure id (empty array if none).
    nonisolated static func aliases(for figureID: String) -> [String] {
        figureAliases[figureID] ?? []
    }


    enum OwnershipFilter: String, CaseIterable {
        case all = "All"
        case owned = "Owned"
        case inProgress = "In Progress"
        case complete = "Complete"
        case notStarted = "Not Started"
    }
    enum ImageFilter: String, CaseIterable {
        case all = "All"
        case withImages = "With Images"
        case missingImages = "Missing Images"
    }

    enum SortOrder: String, CaseIterable {
        case nameAsc = "Name"
        case yearDesc = "Year (Newest)"
        case yearAsc = "Year (Oldest)"
        case completionDesc = "Completion %"
        case partCountDesc = "Part Count"
    }

    /// Apply text query + theme + year filters. Ownership filtering and
    /// completion-based sort are applied by the caller (need inventory context).
    func search(query: String,
                themes: Set<String>,
                yearRange: ClosedRange<Int>?,
                sort: SortOrder) -> [Minifigure] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var results = allFigures

        if !themes.isEmpty {
            results = results.filter { themes.contains($0.theme) }
        }
        if let yearRange {
            results = results.filter { $0.year == 0 || yearRange.contains($0.year) }
        }
        if !q.isEmpty {
            results = results.filter { fig in
                if fig.name.lowercased().contains(q) { return true }
                if fig.theme.lowercased().contains(q) { return true }
                if fig.id.lowercased().contains(q) { return true }
                // Alias match: lets natural search terms ("classic town
                // police officer", "cop031") find figures whose catalog
                // name is purely descriptive.
                for alias in Self.aliases(for: fig.id) {
                    if alias.lowercased().contains(q) { return true }
                }
                return false
            }
        }

        switch sort {
        case .nameAsc:
            results.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .yearDesc:
            results.sort { $0.year > $1.year }
        case .yearAsc:
            results.sort { $0.year < $1.year }
        case .partCountDesc:
            results.sort { $0.partCount > $1.partCount }
        case .completionDesc:
            // Completion-based sort handled by caller.
            results.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        return results
    }

    // MARK: - User-added figures

    /// Generate a fresh, unique id for a user-added figure
    /// (e.g. `user-A1B2C3D4`).
    static func newUserFigureId() -> String {
        "\(userFigureIdPrefix)\(UUID().uuidString.prefix(8))"
    }

    /// True when the id was minted by `newUserFigureId()`.
    static func isUserFigureId(_ id: String) -> Bool {
        id.hasPrefix(userFigureIdPrefix)
    }

    /// Persist a user-created figure and merge it into the live catalog.
    /// Returns the figure that was actually stored (id may be assigned).
    @discardableResult
    func addUserFigure(_ figure: Minifigure) -> Minifigure {
        // Replace if id already exists; otherwise append.
        if let idx = userFigures.firstIndex(where: { $0.id == figure.id }) {
            userFigures[idx] = figure
        } else {
            userFigures.append(figure)
        }
        saveUserFigures()
        rebuildAfterUserChange()
        return figure
    }

    /// Remove a user-added figure (no-op for bundled-catalog ids).
    func removeUserFigure(id: String) {
        guard Self.isUserFigureId(id) else { return }
        userFigures.removeAll { $0.id == id }
        saveUserFigures()
        rebuildAfterUserChange()
    }

    /// Update the image URL for any figure (bundled or user-added).
    /// For bundled figures, creates a user-level override that persists
    /// across app launches.
    func updateFigureImage(id: String, imageURL: String) {
        if Self.isUserFigureId(id) {
            // User figure — update in place
            if let idx = userFigures.firstIndex(where: { $0.id == id }) {
                userFigures[idx] = userFigures[idx].withImageURL(imageURL)
                saveUserFigures()
                rebuildAfterUserChange()
            }
        } else {
            // Bundled figure — store override
            var overrides = loadImageOverrides()
            overrides[id] = imageURL
            saveImageOverrides(overrides)
            // Apply to live data
            if let idx = allFigures.firstIndex(where: { $0.id == id }) {
                allFigures[idx] = allFigures[idx].withImageURL(imageURL)
                buildIndexes(allFigures)
            }
        }
    }

    /// Check if a figure has a user-supplied image override.
    func hasImageOverride(id: String) -> Bool {
        let overrides = loadImageOverrides()
        return overrides[id] != nil
    }

    private func rebuildAfterUserChange() {
        // Strip any prior user figs from the live array, then re-append.
        let bundled = allFigures.filter { !Self.isUserFigureId($0.id) }
        allFigures = bundled + userFigures
        buildIndexes(allFigures)
    }

    private func loadUserFigures() {
        guard let data = try? Data(contentsOf: userStorageURL) else { return }
        let decoder = JSONDecoder()
        if let figs = try? decoder.decode([Minifigure].self, from: data) {
            userFigures = figs
        }
    }

    private func saveUserFigures() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(userFigures) else { return }
        try? data.write(to: userStorageURL, options: .atomic)
    }

    // MARK: - Image overrides (bundled figures)

    private var imageOverridesURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("minifigureImageOverrides.json")
    }

    private func loadImageOverrides() -> [String: String] {
        guard let data = try? Data(contentsOf: imageOverridesURL) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private func saveImageOverrides(_ overrides: [String: String]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(overrides) else { return }
        try? data.write(to: imageOverridesURL, options: .atomic)
    }

    /// Apply any saved image overrides to the loaded catalog figures.
    private func applyImageOverrides() {
        let overrides = loadImageOverrides()
        guard !overrides.isEmpty else { return }
        for i in allFigures.indices {
            if let newURL = overrides[allFigures[i].id] {
                allFigures[i] = allFigures[i].withImageURL(newURL)
            }
        }
    }

    // MARK: - JSON payload

    private struct CatalogPayload: Decodable {
        let version: Int
        let source: String
        let figureCount: Int
        let figures: [Minifigure]
    }

    // MARK: - Gzip helper (Compression framework streaming API)

    nonisolated private static func gunzip(_ data: Data) throws -> Data {
        guard data.count > 18, data[0] == 0x1f, data[1] == 0x8b else {
            throw GzipError.invalidHeader
        }

        // Parse gzip header (RFC 1952). Fixed 10 bytes + optional FEXTRA,
        // FNAME, FCOMMENT, FHCRC sections per the FLG byte.
        let flg = data[3]
        var headerEnd = 10

        // FEXTRA (bit 2) — 2-byte length followed by that many bytes.
        if flg & 0x04 != 0 {
            guard headerEnd + 2 <= data.count else { throw GzipError.invalidHeader }
            let xlen = Int(data[headerEnd]) | (Int(data[headerEnd + 1]) << 8)
            headerEnd += 2 + xlen
        }
        // FNAME (bit 3) — null-terminated string.
        if flg & 0x08 != 0 {
            while headerEnd < data.count, data[headerEnd] != 0 { headerEnd += 1 }
            headerEnd += 1
        }
        // FCOMMENT (bit 4) — null-terminated string.
        if flg & 0x10 != 0 {
            while headerEnd < data.count, data[headerEnd] != 0 { headerEnd += 1 }
            headerEnd += 1
        }
        // FHCRC (bit 1) — 2-byte CRC of header.
        if flg & 0x02 != 0 {
            headerEnd += 2
        }

        guard headerEnd < data.count - 8 else { throw GzipError.invalidHeader }
        let payload = data.subdata(in: headerEnd..<(data.count - 8))

        // Output size hint from gzip ISIZE trailer (mod 2^32).
        let isize: UInt32 = {
            var v: UInt32 = 0
            for i in 0..<4 {
                v |= UInt32(data[data.count - 4 + i]) << (8 * i)
            }
            return v
        }()
        let outCap = max(Int(isize), payload.count * 6) + 4096

        let outBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: outCap)
        defer { outBuffer.deallocate() }

        let written: Int = payload.withUnsafeBytes { rawPtr -> Int in
            guard let srcBase = rawPtr.bindMemory(to: UInt8.self).baseAddress else {
                return 0
            }
            return compression_decode_buffer(outBuffer, outCap,
                                             srcBase, payload.count,
                                             nil, COMPRESSION_ZLIB)
        }

        guard written > 0 else {
            throw GzipError.decompressionFailed
        }
        return Data(bytes: outBuffer, count: written)
    }

    enum GzipError: Error, LocalizedError {
        case invalidHeader
        case decompressionFailed
        case bundleResourceMissing

        var errorDescription: String? {
            switch self {
            case .invalidHeader: return "Catalog gzip header invalid"
            case .decompressionFailed: return "Catalog decompression failed"
            case .bundleResourceMissing: return "MinifigureCatalog.json.gz missing from bundle"
            }
        }
    }
}
