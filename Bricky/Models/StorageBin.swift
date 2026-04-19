import Foundation

/// A storage bin for organizing LEGO pieces by physical location.
struct StorageBin: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var color: String // display color name
    var location: String // e.g. "Shelf A", "Drawer 3"
    var pieceIds: [UUID] // references to InventoryPiece ids
    var createdAt: Date

    init(id: UUID = UUID(), name: String, color: String = "Blue",
         location: String = "", pieceIds: [UUID] = [], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.color = color
        self.location = location
        self.pieceIds = pieceIds
        self.createdAt = createdAt
    }
}

/// Persists storage bins to disk.
final class StorageBinStore: ObservableObject {
    static let shared = StorageBinStore()

    @Published var bins: [StorageBin] = []

    private let storageURL: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        storageURL = docs.appendingPathComponent("storageBins.json")
        loadFromDisk()
    }

    // MARK: - CRUD

    func createBin(name: String, color: String = "Blue", location: String = "") -> UUID {
        let bin = StorageBin(name: name, color: color, location: location)
        bins.append(bin)
        saveToDisk()
        return bin.id
    }

    func deleteBin(id: UUID) {
        bins.removeAll { $0.id == id }
        saveToDisk()
    }

    func updateBin(id: UUID, name: String? = nil, color: String? = nil, location: String? = nil) {
        guard let idx = bins.firstIndex(where: { $0.id == id }) else { return }
        if let name { bins[idx].name = name }
        if let color { bins[idx].color = color }
        if let location { bins[idx].location = location }
        saveToDisk()
    }

    // MARK: - Piece Assignment

    func assignPiece(_ pieceId: UUID, toBin binId: UUID) {
        guard let idx = bins.firstIndex(where: { $0.id == binId }) else { return }
        if !bins[idx].pieceIds.contains(pieceId) {
            bins[idx].pieceIds.append(pieceId)
            saveToDisk()
        }
    }

    func removePiece(_ pieceId: UUID, fromBin binId: UUID) {
        guard let idx = bins.firstIndex(where: { $0.id == binId }) else { return }
        bins[idx].pieceIds.removeAll { $0 == pieceId }
        saveToDisk()
    }

    func bins(forPiece pieceId: UUID) -> [StorageBin] {
        bins.filter { $0.pieceIds.contains(pieceId) }
    }

    func bin(forId id: UUID) -> StorageBin? {
        bins.first(where: { $0.id == id })
    }

    // MARK: - Persistence

    private func saveToDisk() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(bins) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let loaded = try? decoder.decode([StorageBin].self, from: data) {
            bins = loaded
        }
    }
}
