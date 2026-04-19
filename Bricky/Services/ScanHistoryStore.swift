import Foundation

/// Persists completed scan sessions so users can revisit past scan results.
@MainActor
final class ScanHistoryStore: ObservableObject {
    static let shared = ScanHistoryStore()

    struct HistoryEntry: Identifiable, Codable {
        let id: UUID
        let date: Date
        let pieces: [LegoPiece]
        let totalPiecesFound: Int
        let uniquePieceCount: Int
        let usedARMode: Bool

        // MARK: Optional location metadata (Sprint C — geolocation).
        // All are nil when location capture was disabled or unavailable.
        let latitude: Double?
        let longitude: Double?
        var placeName: String?
        let locationCapturedAt: Date?

        // MARK: Sprint 5 / F2 — free-form user tags.
        var tags: [String]

        var colorCount: Int {
            Set(pieces.map(\.color)).count
        }

        /// Whether this entry has a usable lat/lon pair.
        var hasLocation: Bool {
            latitude != nil && longitude != nil
        }

        init(id: UUID,
             date: Date,
             pieces: [LegoPiece],
             totalPiecesFound: Int,
             uniquePieceCount: Int,
             usedARMode: Bool = false,
             latitude: Double? = nil,
             longitude: Double? = nil,
             placeName: String? = nil,
             locationCapturedAt: Date? = nil,
             tags: [String] = []) {
            self.id = id
            self.date = date
            self.pieces = pieces
            self.totalPiecesFound = totalPiecesFound
            self.uniquePieceCount = uniquePieceCount
            self.usedARMode = usedARMode
            self.latitude = latitude
            self.longitude = longitude
            self.placeName = placeName
            self.locationCapturedAt = locationCapturedAt
            self.tags = tags
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            date = try container.decode(Date.self, forKey: .date)
            pieces = try container.decode([LegoPiece].self, forKey: .pieces)
            totalPiecesFound = try container.decode(Int.self, forKey: .totalPiecesFound)
            uniquePieceCount = try container.decode(Int.self, forKey: .uniquePieceCount)
            usedARMode = try container.decodeIfPresent(Bool.self, forKey: .usedARMode) ?? false
            latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
            longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
            placeName = try container.decodeIfPresent(String.self, forKey: .placeName)
            locationCapturedAt = try container.decodeIfPresent(Date.self, forKey: .locationCapturedAt)
            tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        }
    }

    @Published var entries: [HistoryEntry] = []

    private let storageURL: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        storageURL = docs.appendingPathComponent("scanHistory.json")
        loadFromDisk()
    }

    /// Save a completed scan session to history.
    func save(session: ScanSession, usedARMode: Bool = false) {
        guard !session.pieces.isEmpty else { return }
        let entry = HistoryEntry(
            id: session.id,
            date: session.startedAt,
            pieces: session.pieces,
            totalPiecesFound: session.totalPiecesFound,
            uniquePieceCount: session.uniquePieceCount,
            usedARMode: usedARMode,
            latitude: session.latitude,
            longitude: session.longitude,
            placeName: session.placeName,
            locationCapturedAt: session.locationCapturedAt
        )
        // Avoid duplicates (same session id)
        entries.removeAll { $0.id == entry.id }
        entries.insert(entry, at: 0)
        // Keep last 50; clean up assets for any pruned sessions.
        if entries.count > 50 {
            let dropped = entries.suffix(entries.count - 50)
            for old in dropped { ScanSessionAssetStore.shared.deleteAssets(for: old.id) }
            entries = Array(entries.prefix(50))
        }
        // Persist source images + boundaries so the "Find in Pile Photo"
        // pushpin still works after the app is killed and relaunched.
        ScanSessionAssetStore.shared.persist(session: session)
        saveToDisk()
    }

    func delete(id: UUID) {
        entries.removeAll { $0.id == id }
        ScanSessionAssetStore.shared.deleteAssets(for: id)
        saveToDisk()
    }

    /// Remove all scan history entries.
    func clearAll() {
        entries.removeAll()
        ScanSessionAssetStore.shared.deleteAllAssets()
        saveToDisk()
    }

    /// Update the reverse-geocoded place name for a saved scan. No-op if the
    /// session ID isn't in history (e.g., the scan wasn't saved).
    func updatePlaceName(sessionID: UUID, placeName: String) {
        guard let idx = entries.firstIndex(where: { $0.id == sessionID }) else { return }
        entries[idx].placeName = placeName
        saveToDisk()
    }

    /// Sprint 5 / F2 — replace the tag set for a saved scan.
    func updateTags(sessionID: UUID, tags: [String]) {
        guard let idx = entries.firstIndex(where: { $0.id == sessionID }) else { return }
        // Trim, drop empties, dedupe (case-insensitive).
        var seen = Set<String>()
        let cleaned = tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0.lowercased()).inserted }
        entries[idx].tags = cleaned
        saveToDisk()
    }

    /// All distinct tags across saved scans, sorted alphabetically.
    var allTags: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for entry in entries {
            for tag in entry.tags where seen.insert(tag.lowercased()).inserted {
                ordered.append(tag)
            }
        }
        return ordered.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Strip lat/lon/placeName from every saved entry. Used by the
    /// "Forget locations on existing scans" Settings action.
    func clearLocations() {
        entries = entries.map { entry in
            HistoryEntry(
                id: entry.id,
                date: entry.date,
                pieces: entry.pieces,
                totalPiecesFound: entry.totalPiecesFound,
                uniquePieceCount: entry.uniquePieceCount,
                usedARMode: entry.usedARMode,
                latitude: nil,
                longitude: nil,
                placeName: nil,
                locationCapturedAt: nil,
                tags: entry.tags
            )
        }
        saveToDisk()
    }

    /// Convert a history entry back into a ScanSession for display in ScanResultsView.
    /// Lazily restores any persisted source images / pile boundaries so the
    /// "Find in Pile Photo" feature works for archived scans.
    func toScanSession(_ entry: HistoryEntry) -> ScanSession {
        let session = ScanSession(
            id: entry.id,
            startedAt: entry.date,
            pieces: entry.pieces,
            isScanning: false
        )
        session.totalPiecesFound = entry.totalPiecesFound
        session.latitude = entry.latitude
        session.longitude = entry.longitude
        session.placeName = entry.placeName
        session.locationCapturedAt = entry.locationCapturedAt
        ScanSessionAssetStore.shared.restore(into: session)
        return session
    }

    // MARK: - Persistence

    private func saveToDisk() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let loaded = try? decoder.decode([HistoryEntry].self, from: data) {
            entries = loaded
        }
    }
}
