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

    // MARK: - Search / Filter

    enum OwnershipFilter: String, CaseIterable {
        case all = "All"
        case owned = "Owned"
        case inProgress = "In Progress"
        case complete = "Complete"
        case notStarted = "Not Started"
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
            results = results.filter {
                $0.name.lowercased().contains(q) ||
                $0.theme.lowercased().contains(q) ||
                $0.id.lowercased().contains(q)
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
