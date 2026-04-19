import Foundation
import Combine

/// Tracks which minifigures the user has marked owned + computes completion
/// % vs an inventory. Mirrors the shape of `SetCollectionStore`.
final class MinifigureCollectionStore: ObservableObject {
    static let shared = MinifigureCollectionStore()

    struct CollectionEntry: Identifiable, Codable {
        let id: UUID
        let minifigId: String
        var owned: Bool
        var dateAdded: Date
        /// Anatomical slots the user has confirmed via scan.
        /// Defaults to empty for entries created via manual toggle.
        var scannedSlots: Set<MinifigurePartSlot> = []
        /// Last time a scan confirmation was logged for this figure.
        var lastScannedAt: Date? = nil

        enum CodingKeys: String, CodingKey {
            case id, minifigId, owned, dateAdded, scannedSlots, lastScannedAt
        }

        init(id: UUID, minifigId: String, owned: Bool, dateAdded: Date,
             scannedSlots: Set<MinifigurePartSlot> = [],
             lastScannedAt: Date? = nil) {
            self.id = id
            self.minifigId = minifigId
            self.owned = owned
            self.dateAdded = dateAdded
            self.scannedSlots = scannedSlots
            self.lastScannedAt = lastScannedAt
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try c.decode(UUID.self, forKey: .id)
            self.minifigId = try c.decode(String.self, forKey: .minifigId)
            self.owned = try c.decode(Bool.self, forKey: .owned)
            self.dateAdded = try c.decode(Date.self, forKey: .dateAdded)
            self.scannedSlots = try c.decodeIfPresent(Set<MinifigurePartSlot>.self,
                                                     forKey: .scannedSlots) ?? []
            self.lastScannedAt = try c.decodeIfPresent(Date.self, forKey: .lastScannedAt)
        }
    }

    @Published var collection: [CollectionEntry] = []

    private let storageURL: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        storageURL = docs.appendingPathComponent("minifigureCollection.json")
        loadFromDisk()
    }

    // MARK: - Slot status

    struct SlotStatus: Identifiable, Hashable {
        let slot: MinifigurePartSlot
        let requirement: MinifigurePartRequirement
        let isOwned: Bool
        let haveQuantity: Int

        var id: String { "\(slot.rawValue)|\(requirement.partNumber)|\(requirement.color)" }
    }

    // MARK: - CRUD

    func addMinifigure(_ id: String) {
        guard !collection.contains(where: { $0.minifigId == id }) else { return }
        collection.append(CollectionEntry(id: UUID(), minifigId: id, owned: true, dateAdded: Date()))
        saveToDisk()
    }

    func removeMinifigure(_ id: String) {
        collection.removeAll { $0.minifigId == id }
        saveToDisk()
    }

    func toggleOwned(_ id: String) {
        if let idx = collection.firstIndex(where: { $0.minifigId == id }) {
            collection[idx].owned.toggle()
        } else {
            addMinifigure(id)
        }
        saveToDisk()
    }

    func isOwned(_ id: String) -> Bool {
        collection.first(where: { $0.minifigId == id })?.owned ?? false
    }

    // MARK: - Scan tracking

    /// Default body slots covered by a single torso/full-figure scan.
    /// Hands, headgear, and accessories are excluded — the user can confirm
    /// those individually in the detail view.
    static let defaultScannedSlots: Set<MinifigurePartSlot> = [
        .head, .torso, .hips, .legLeft, .legRight
    ]

    /// Record a scan confirmation for the given minifig. Marks it owned,
    /// merges the slots into the entry, and stamps `lastScannedAt`.
    func markScanned(_ minifigId: String,
                     slots: Set<MinifigurePartSlot> = defaultScannedSlots) {
        if let idx = collection.firstIndex(where: { $0.minifigId == minifigId }) {
            collection[idx].owned = true
            collection[idx].scannedSlots.formUnion(slots)
            collection[idx].lastScannedAt = Date()
        } else {
            collection.append(CollectionEntry(
                id: UUID(),
                minifigId: minifigId,
                owned: true,
                dateAdded: Date(),
                scannedSlots: slots,
                lastScannedAt: Date()
            ))
        }
        saveToDisk()
    }

    /// Toggle whether a single slot has been scan-confirmed for a figure.
    /// Used by the detail view's tap-on-slot interaction.
    func toggleScannedSlot(_ slot: MinifigurePartSlot, for minifigId: String) {
        if let idx = collection.firstIndex(where: { $0.minifigId == minifigId }) {
            if collection[idx].scannedSlots.contains(slot) {
                collection[idx].scannedSlots.remove(slot)
            } else {
                collection[idx].scannedSlots.insert(slot)
                collection[idx].owned = true
                collection[idx].lastScannedAt = Date()
            }
        } else {
            collection.append(CollectionEntry(
                id: UUID(),
                minifigId: minifigId,
                owned: true,
                dateAdded: Date(),
                scannedSlots: [slot],
                lastScannedAt: Date()
            ))
        }
        saveToDisk()
    }

    func scannedSlots(for minifigId: String) -> Set<MinifigurePartSlot> {
        collection.first(where: { $0.minifigId == minifigId })?.scannedSlots ?? []
    }

    func isScanned(_ minifigId: String) -> Bool {
        !scannedSlots(for: minifigId).isEmpty
    }

    /// True when every required (non-optional) slot of the figure has been
    /// scan-confirmed.
    func isScanComplete(_ fig: Minifigure) -> Bool {
        let scanned = scannedSlots(for: fig.id)
        guard !scanned.isEmpty else { return false }
        let required = Set(fig.requiredParts.map(\.slot))
        return required.isSubset(of: scanned)
    }

    func lastScannedAt(_ minifigId: String) -> Date? {
        collection.first(where: { $0.minifigId == minifigId })?.lastScannedAt
    }

    // MARK: - Completion calculations

    /// Completion percentage of a minifigure against an inventory (0–100).
    /// Optional parts (accessories) are excluded.
    func completionPercentage(for fig: Minifigure,
                              inventory: InventoryStore.Inventory) -> Double {
        let required = fig.requiredParts
        guard !required.isEmpty else { return 0 }

        var matched = 0
        var total = 0
        for req in required {
            total += req.quantity
            let have = inventoryQuantity(of: req, in: inventory)
            matched += min(have, req.quantity)
        }
        guard total > 0 else { return 0 }
        return Double(matched) / Double(total) * 100
    }

    /// Completion percentage against the union of multiple inventories.
    func completionPercentage(for fig: Minifigure,
                              inventories: [InventoryStore.Inventory]) -> Double {
        guard !inventories.isEmpty else { return 0 }
        let combined = combinedQuantities(from: inventories)
        let required = fig.requiredParts
        guard !required.isEmpty else { return 0 }

        var matched = 0
        var total = 0
        for req in required {
            total += req.quantity
            let key = matchKey(partNumber: req.partNumber, color: req.color)
            let have = combined[key] ?? 0
            matched += min(have, req.quantity)
        }
        guard total > 0 else { return 0 }
        return Double(matched) / Double(total) * 100
    }

    /// Per-slot status (owned vs missing) for the silhouette layout.
    func slotStatuses(for fig: Minifigure,
                      inventories: [InventoryStore.Inventory]) -> [SlotStatus] {
        let combined = combinedQuantities(from: inventories)
        return fig.parts.map { req in
            let key = matchKey(partNumber: req.partNumber, color: req.color)
            let have = combined[key] ?? 0
            return SlotStatus(slot: req.slot,
                              requirement: req,
                              isOwned: have >= req.quantity,
                              haveQuantity: have)
        }
    }

    /// Required parts that are still missing.
    func missingParts(for fig: Minifigure,
                      inventories: [InventoryStore.Inventory]) -> [MinifigurePartRequirement] {
        let combined = combinedQuantities(from: inventories)
        return fig.requiredParts.filter { req in
            let key = matchKey(partNumber: req.partNumber, color: req.color)
            return (combined[key] ?? 0) < req.quantity
        }
    }

    // MARK: - Helpers

    private func inventoryQuantity(of req: MinifigurePartRequirement,
                                   in inventory: InventoryStore.Inventory) -> Int {
        inventory.pieces.first(where: {
            $0.partNumber == req.partNumber && $0.color == req.color
        })?.quantity ?? 0
    }

    private func combinedQuantities(from inventories: [InventoryStore.Inventory]) -> [String: Int] {
        var result: [String: Int] = [:]
        for inv in inventories {
            for piece in inv.pieces {
                let key = matchKey(partNumber: piece.partNumber, color: piece.color)
                result[key, default: 0] += piece.quantity
            }
        }
        return result
    }

    private func matchKey(partNumber: String, color: String) -> String {
        "\(partNumber)|\(color)"
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
