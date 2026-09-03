import Foundation

/// One promoted consensus entry from the server (mirror of the backend
/// CorrectionIndexEntry). `embeddingBase64` is the cluster-centroid Vision
/// feature print; labels are null when that channel wasn't promoted.
struct ServerCorrectionEntry: Codable, Identifiable {
    let clusterId: String
    let embeddingBase64: String
    let shapeLabel: String?     // promoted part number
    let colorLabel: String?     // promoted LegoColor rawValue
    let members: Int
    let shapeConfidence: Double
    let colorConfidence: Double
    var id: String { clusterId }
}

struct ServerCorrectionIndex: Codable {
    let version: String
    let generatedAt: String?
    let entries: [ServerCorrectionEntry]

    static let empty = ServerCorrectionIndex(version: "0", generatedAt: nil, entries: [])
}

/// Result of a fetch: either we're already current, or a new index.
enum CorrectionIndexFetchResult {
    case upToDate
    case index(ServerCorrectionIndex)
}

/// Downloads the correction index. Injectable for tests.
protocol CorrectionIndexDownloader: Sendable {
    func fetch(since version: String) async -> CorrectionIndexFetchResult?  // nil on failure
}

/// Caches the server correction index on disk and refreshes it. The reranker
/// reads `entries` to apply global consensus corrections. Read access is open
/// (improvements are for all users; only contributing is gated).
final class CorrectionIndexService: ObservableObject {
    static let shared = CorrectionIndexService()

    @Published private(set) var index: ServerCorrectionIndex
    var entries: [ServerCorrectionEntry] { index.entries }
    var version: String { index.version }

    private let fileURL: URL
    private let downloader: CorrectionIndexDownloader

    init(directoryName: String = "correctionIndex",
         downloader: CorrectionIndexDownloader = URLSessionCorrectionIndexDownloader()) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent(directoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("index.json")
        self.downloader = downloader
        self.index = Self.load(from: fileURL) ?? .empty
    }

    /// Download since the cached version; persist + publish only if newer.
    func refresh() async {
        let result = await downloader.fetch(since: index.version)
        switch result {
        case nil, .upToDate:
            return  // keep the cache
        case .index(let newIndex)?:
            index = newIndex
            save()
        }
    }

    // MARK: - Persistence

    private static func load(from url: URL) -> ServerCorrectionIndex? {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(ServerCorrectionIndex.self, from: data) else { return nil }
        return decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(index) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// Default downloader — GETs the correction index from the proxy, tolerating the
/// server's three response shapes (full index / already-current / none yet).
struct URLSessionCorrectionIndexDownloader: CorrectionIndexDownloader {
    func fetch(since version: String) async -> CorrectionIndexFetchResult? {
        guard let base = AppConfig.correctionIndexEndpoint,
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "since", value: version)]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }

            // The server sends `{ version, upToDate: true }` when the caller is
            // already current; otherwise a full `{ version, generatedAt, entries }`.
            struct UpToDateResponse: Decodable { let upToDate: Bool? }
            if let flag = try? JSONDecoder().decode(UpToDateResponse.self, from: data), flag.upToDate == true {
                return .upToDate
            }
            let index = try JSONDecoder().decode(ServerCorrectionIndex.self, from: data)
            return .index(index)
        } catch {
            return nil
        }
    }
}
