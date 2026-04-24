import Foundation
import SwiftUI

/// Persists scanned piece inventories to disk using JSON.
/// Each inventory is a named collection of pieces the user has scanned.
final class InventoryStore: ObservableObject {
    static let shared = InventoryStore()

    struct Inventory: Identifiable, Codable {
        let id: UUID
        var name: String
        var pieces: [InventoryPiece]
        var createdAt: Date
        var updatedAt: Date

        var totalPieces: Int { pieces.reduce(0) { $0 + $1.quantity } }
        var uniquePieces: Int { pieces.count }
    }

    struct InventoryPiece: Identifiable, Codable {
        let id: UUID
        let partNumber: String
        let name: String
        let category: String
        let color: String
        var quantity: Int
        let studsWide: Int
        let studsLong: Int
        let heightUnits: Int

        init(partNumber: String, name: String, category: PieceCategory,
             color: LegoColor, quantity: Int, dimensions: PieceDimensions) {
            self.id = UUID()
            self.partNumber = partNumber
            self.name = name
            self.category = category.rawValue
            self.color = color.rawValue
            self.quantity = quantity
            self.studsWide = dimensions.studsWide
            self.studsLong = dimensions.studsLong
            self.heightUnits = dimensions.heightUnits
        }

        var pieceCategory: PieceCategory { PieceCategory(rawValue: category) ?? .brick }
        var pieceColor: LegoColor { LegoColor(fromString: color) ?? .gray }
        var dimensions: PieceDimensions {
            PieceDimensions(studsWide: studsWide, studsLong: studsLong, heightUnits: heightUnits)
        }
    }

    @Published var inventories: [Inventory] = []
    @Published var activeInventoryId: UUID?

    var activeInventory: Inventory? {
        inventories.first(where: { $0.id == activeInventoryId })
    }

    private let storageURL: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        storageURL = docs.appendingPathComponent("inventories.json")
        loadFromDisk()
    }

    // MARK: - CRUD

    func createInventory(name: String) -> UUID {
        let inv = Inventory(id: UUID(), name: name, pieces: [], createdAt: Date(), updatedAt: Date())
        inventories.insert(inv, at: 0)
        activeInventoryId = inv.id
        saveToDisk()
        return inv.id
    }

    func deleteInventory(id: UUID) {
        inventories.removeAll { $0.id == id }
        if activeInventoryId == id { activeInventoryId = inventories.first?.id }
        saveToDisk()
    }

    func renameInventory(id: UUID, name: String) {
        guard let idx = inventories.firstIndex(where: { $0.id == id }) else { return }
        inventories[idx].name = name
        inventories[idx].updatedAt = Date()
        saveToDisk()
    }

    // MARK: - Piece management

    func addPiece(_ piece: InventoryPiece, to inventoryId: UUID) {
        guard let idx = inventories.firstIndex(where: { $0.id == inventoryId }) else { return }

        // If same part + color exists, increment quantity
        if let pieceIdx = inventories[idx].pieces.firstIndex(where: {
            $0.partNumber == piece.partNumber && $0.color == piece.color
        }) {
            inventories[idx].pieces[pieceIdx].quantity += piece.quantity
        } else {
            inventories[idx].pieces.append(piece)
        }
        inventories[idx].updatedAt = Date()
        saveToDisk()
    }

    func addPieces(_ pieces: [InventoryPiece], to inventoryId: UUID) {
        for piece in pieces {
            addPiece(piece, to: inventoryId)
        }
    }

    /// Replace all pieces in an inventory (used by auto-save to update incrementally)
    func replacePieces(_ pieces: [InventoryPiece], in inventoryId: UUID) {
        guard let idx = inventories.firstIndex(where: { $0.id == inventoryId }) else { return }
        inventories[idx].pieces = pieces
        inventories[idx].updatedAt = Date()
        saveToDisk()
    }

    func removePiece(id: UUID, from inventoryId: UUID) {
        guard let idx = inventories.firstIndex(where: { $0.id == inventoryId }) else { return }
        inventories[idx].pieces.removeAll { $0.id == id }
        inventories[idx].updatedAt = Date()
        saveToDisk()
    }

    func updatePieceQuantity(pieceId: UUID, inventoryId: UUID, quantity: Int) {
        guard let invIdx = inventories.firstIndex(where: { $0.id == inventoryId }),
              let pieceIdx = inventories[invIdx].pieces.firstIndex(where: { $0.id == pieceId }) else { return }
        if quantity <= 0 {
            inventories[invIdx].pieces.remove(at: pieceIdx)
        } else {
            inventories[invIdx].pieces[pieceIdx].quantity = quantity
        }
        inventories[invIdx].updatedAt = Date()
        saveToDisk()
    }

    /// Convert active inventory pieces to LegoPiece array for build suggestion matching
    func activePiecesAsLegoPieces() -> [LegoPiece] {
        guard let inv = activeInventory else { return [] }
        return inv.pieces.map { p in
            LegoPiece(
                id: p.id,
                partNumber: p.partNumber,
                name: p.name,
                category: p.pieceCategory,
                color: p.pieceColor,
                dimensions: p.dimensions,
                quantity: p.quantity
            )
        }
    }

    // MARK: - Similarity Detection

    /// Calculate how similar a set of pieces is to an existing inventory (0.0 to 1.0).
    /// Uses Jaccard-like similarity on piece type+color fingerprints weighted by quantity.
    func similarity(between pieces: [InventoryPiece], and inventoryId: UUID) -> Double {
        guard let idx = inventories.firstIndex(where: { $0.id == inventoryId }) else { return 0 }
        let existing = inventories[idx].pieces

        guard !existing.isEmpty && !pieces.isEmpty else { return 0 }

        // Build fingerprint maps: "partNumber|color" → quantity
        let existingMap = Dictionary(
            existing.map { ("\($0.partNumber)|\($0.color)", $0.quantity) },
            uniquingKeysWith: +
        )
        let newMap = Dictionary(
            pieces.map { ("\($0.partNumber)|\($0.color)", $0.quantity) },
            uniquingKeysWith: +
        )

        // Count matching piece types
        let allKeys = Set(existingMap.keys).union(Set(newMap.keys))
        var intersectionCount = 0
        var unionCount = 0

        for key in allKeys {
            let existQty = existingMap[key] ?? 0
            let newQty = newMap[key] ?? 0
            intersectionCount += min(existQty, newQty)
            unionCount += max(existQty, newQty)
        }

        guard unionCount > 0 else { return 0 }
        return Double(intersectionCount) / Double(unionCount)
    }

    /// Calculate similarity using LegoPiece array (convenience for ScanSession)
    func similarity(ofScanPieces scanPieces: [LegoPiece], to inventoryId: UUID) -> Double {
        let invPieces = scanPieces.map { piece in
            InventoryPiece(
                partNumber: piece.partNumber,
                name: piece.name,
                category: piece.category,
                color: piece.color,
                quantity: piece.quantity,
                dimensions: piece.dimensions
            )
        }
        return similarity(between: invPieces, and: inventoryId)
    }

    // MARK: - Persistence

    private func saveToDisk() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(inventories) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let loaded = try? decoder.decode([Inventory].self, from: data) {
            inventories = loaded
            activeInventoryId = inventories.first?.id
        }
    }
}
