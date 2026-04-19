import Foundation

/// Model for a LEGO set in the catalog.
struct LegoSet: Identifiable, Codable, Hashable {
    let id: String // set number (e.g. "10297")
    let setNumber: String
    let name: String
    let theme: String
    let year: Int
    let pieceCount: Int
    let pieces: [SetPiece]

    struct SetPiece: Codable, Hashable {
        let partNumber: String
        let color: String // LegoColor raw value
        let quantity: Int
    }
}

/// Tracks which LEGO sets a user owns and their completion status vs inventory.
final class SetCollectionStore: ObservableObject {
    static let shared = SetCollectionStore()

    struct CollectionEntry: Identifiable, Codable {
        let id: UUID
        let setNumber: String
        var owned: Bool
        var dateAdded: Date
    }

    @Published var collection: [CollectionEntry] = []

    private let storageURL: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        storageURL = docs.appendingPathComponent("setCollection.json")
        loadFromDisk()
    }

    // MARK: - CRUD

    func addSet(_ setNumber: String) {
        guard !collection.contains(where: { $0.setNumber == setNumber }) else { return }
        let entry = CollectionEntry(id: UUID(), setNumber: setNumber, owned: true, dateAdded: Date())
        collection.append(entry)
        saveToDisk()
    }

    func removeSet(_ setNumber: String) {
        collection.removeAll { $0.setNumber == setNumber }
        saveToDisk()
    }

    func toggleOwned(_ setNumber: String) {
        guard let idx = collection.firstIndex(where: { $0.setNumber == setNumber }) else { return }
        collection[idx].owned.toggle()
        saveToDisk()
    }

    func isInCollection(_ setNumber: String) -> Bool {
        collection.contains(where: { $0.setNumber == setNumber })
    }

    /// Calculate completion % of a set against an inventory.
    func completionPercentage(for legoSet: LegoSet, inventory: InventoryStore.Inventory) -> Double {
        guard !legoSet.pieces.isEmpty else { return 0 }

        var matched = 0
        var total = 0

        for setPiece in legoSet.pieces {
            total += setPiece.quantity
            let inventoryMatch = inventory.pieces.first(where: {
                $0.partNumber == setPiece.partNumber && $0.color == setPiece.color
            })
            if let match = inventoryMatch {
                matched += min(match.quantity, setPiece.quantity)
            }
        }

        guard total > 0 else { return 0 }
        return Double(matched) / Double(total) * 100
    }

    /// Get pieces the user is missing for a set from their inventory.
    func missingPieces(for legoSet: LegoSet, inventory: InventoryStore.Inventory) -> [(partNumber: String, color: String, needed: Int, have: Int)] {
        var missing: [(partNumber: String, color: String, needed: Int, have: Int)] = []

        for setPiece in legoSet.pieces {
            let have = inventory.pieces.first(where: {
                $0.partNumber == setPiece.partNumber && $0.color == setPiece.color
            })?.quantity ?? 0

            if have < setPiece.quantity {
                missing.append((
                    partNumber: setPiece.partNumber,
                    color: setPiece.color,
                    needed: setPiece.quantity,
                    have: have
                ))
            }
        }

        return missing
    }

    // MARK: - Persistence

    private func saveToDisk() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(collection) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let loaded = try? decoder.decode([CollectionEntry].self, from: data) {
            collection = loaded
        }
    }
}
