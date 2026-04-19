import XCTest
@testable import Bricky

/// Tests for InventoryStore CRUD, piece management, merge logic, and computed properties.
final class InventoryStoreTests: XCTestCase {

    var store: InventoryStore!
    var createdInventoryIds: [UUID] = []

    @MainActor
    override func setUp() {
        super.setUp()
        store = InventoryStore.shared
        createdInventoryIds = []
    }

    @MainActor
    override func tearDown() {
        // Clean up any inventories created during tests
        for id in createdInventoryIds {
            store.deleteInventory(id: id)
        }
        super.tearDown()
    }

    // MARK: - Helpers

    @MainActor
    @discardableResult
    private func createTrackedInventory(name: String) -> UUID {
        let id = store.createInventory(name: name)
        createdInventoryIds.append(id)
        return id
    }

    private func makePiece(
        partNumber: String = "3001",
        name: String = "Brick 2×4",
        category: PieceCategory = .brick,
        color: LegoColor = .red,
        quantity: Int = 1
    ) -> InventoryStore.InventoryPiece {
        InventoryStore.InventoryPiece(
            partNumber: partNumber,
            name: name,
            category: category,
            color: color,
            quantity: quantity,
            dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3)
        )
    }

    // MARK: - Create

    @MainActor
    func testCreateInventory() {
        let id = createTrackedInventory(name: "Test Inventory")
        let inv = store.inventories.first(where: { $0.id == id })
        XCTAssertNotNil(inv)
        XCTAssertEqual(inv?.name, "Test Inventory")
        XCTAssertEqual(inv?.pieces.count, 0)
    }

    @MainActor
    func testCreateInventorySetsActive() {
        let id = createTrackedInventory(name: "Active Test")
        XCTAssertEqual(store.activeInventoryId, id)
    }

    @MainActor
    func testCreateInventoryInsertsAtFront() {
        let id1 = createTrackedInventory(name: "First")
        let id2 = createTrackedInventory(name: "Second")
        XCTAssertEqual(store.inventories.first(where: { $0.id == id2 })?.name, "Second")
        // Most recent is first
        let firstTwo = store.inventories.prefix(2)
        let ids = firstTwo.map { $0.id }
        XCTAssertTrue(ids.contains(id1))
        XCTAssertTrue(ids.contains(id2))
    }

    // MARK: - Delete

    @MainActor
    func testDeleteInventory() {
        let id = createTrackedInventory(name: "Delete Me")
        store.deleteInventory(id: id)
        createdInventoryIds.removeAll { $0 == id }
        XCTAssertNil(store.inventories.first(where: { $0.id == id }))
    }

    @MainActor
    func testDeleteActiveInventoryReassignsActive() {
        let id1 = createTrackedInventory(name: "First")
        let id2 = createTrackedInventory(name: "Second")
        XCTAssertEqual(store.activeInventoryId, id2)
        store.deleteInventory(id: id2)
        createdInventoryIds.removeAll { $0 == id2 }
        // Active should fall back to another inventory
        XCTAssertNotEqual(store.activeInventoryId, id2)
        _ = id1 // suppress unused warning
    }

    // MARK: - Rename

    @MainActor
    func testRenameInventory() {
        let id = createTrackedInventory(name: "Original")
        store.renameInventory(id: id, name: "Renamed")
        let inv = store.inventories.first(where: { $0.id == id })
        XCTAssertEqual(inv?.name, "Renamed")
    }

    // MARK: - Add Piece

    @MainActor
    func testAddPiece() {
        let id = createTrackedInventory(name: "Pieces Test")
        let piece = makePiece()
        store.addPiece(piece, to: id)
        let inv = store.inventories.first(where: { $0.id == id })
        XCTAssertEqual(inv?.pieces.count, 1)
        XCTAssertEqual(inv?.pieces.first?.partNumber, "3001")
    }

    @MainActor
    func testAddPieceMergesDuplicates() {
        let id = createTrackedInventory(name: "Merge Test")
        let piece1 = makePiece(quantity: 3)
        let piece2 = makePiece(quantity: 2) // same partNumber + color
        store.addPiece(piece1, to: id)
        store.addPiece(piece2, to: id)
        let inv = store.inventories.first(where: { $0.id == id })
        XCTAssertEqual(inv?.pieces.count, 1, "Duplicate should be merged")
        XCTAssertEqual(inv?.pieces.first?.quantity, 5, "Quantities should sum")
    }

    @MainActor
    func testAddPieceDifferentColorNotMerged() {
        let id = createTrackedInventory(name: "Color Test")
        let redPiece = makePiece(color: .red)
        let bluePiece = makePiece(color: .blue)
        store.addPiece(redPiece, to: id)
        store.addPiece(bluePiece, to: id)
        let inv = store.inventories.first(where: { $0.id == id })
        XCTAssertEqual(inv?.pieces.count, 2, "Different colors should not merge")
    }

    @MainActor
    func testAddPieces() {
        let id = createTrackedInventory(name: "Bulk Add")
        let pieces = [
            makePiece(partNumber: "3001", color: .red, quantity: 2),
            makePiece(partNumber: "3003", name: "Brick 2×2", color: .blue, quantity: 3),
            makePiece(partNumber: "3001", color: .red, quantity: 1), // merge with first
        ]
        store.addPieces(pieces, to: id)
        let inv = store.inventories.first(where: { $0.id == id })
        XCTAssertEqual(inv?.pieces.count, 2, "Should merge same partNumber+color")
        let redPiece = inv?.pieces.first(where: { $0.color == LegoColor.red.rawValue })
        XCTAssertEqual(redPiece?.quantity, 3, "Merged red pieces: 2 + 1 = 3")
    }

    // MARK: - Remove Piece

    @MainActor
    func testRemovePiece() {
        let id = createTrackedInventory(name: "Remove Test")
        let piece = makePiece()
        store.addPiece(piece, to: id)
        let inv = store.inventories.first(where: { $0.id == id })
        guard let pieceId = inv?.pieces.first?.id else {
            XCTFail("No piece to remove")
            return
        }
        store.removePiece(id: pieceId, from: id)
        let updated = store.inventories.first(where: { $0.id == id })
        XCTAssertEqual(updated?.pieces.count, 0)
    }

    // MARK: - Update Quantity

    @MainActor
    func testUpdatePieceQuantity() {
        let id = createTrackedInventory(name: "Qty Test")
        let piece = makePiece(quantity: 5)
        store.addPiece(piece, to: id)
        let inv = store.inventories.first(where: { $0.id == id })
        guard let pieceId = inv?.pieces.first?.id else {
            XCTFail("No piece to update")
            return
        }
        store.updatePieceQuantity(pieceId: pieceId, inventoryId: id, quantity: 10)
        let updated = store.inventories.first(where: { $0.id == id })
        XCTAssertEqual(updated?.pieces.first?.quantity, 10)
    }

    @MainActor
    func testUpdatePieceQuantityToZeroRemoves() {
        let id = createTrackedInventory(name: "Zero Qty")
        let piece = makePiece(quantity: 3)
        store.addPiece(piece, to: id)
        let inv = store.inventories.first(where: { $0.id == id })
        guard let pieceId = inv?.pieces.first?.id else {
            XCTFail("No piece")
            return
        }
        store.updatePieceQuantity(pieceId: pieceId, inventoryId: id, quantity: 0)
        let updated = store.inventories.first(where: { $0.id == id })
        XCTAssertEqual(updated?.pieces.count, 0, "Zero quantity should remove piece")
    }

    // MARK: - Computed Properties

    @MainActor
    func testInventoryTotalPieces() {
        let id = createTrackedInventory(name: "Totals")
        store.addPiece(makePiece(partNumber: "3001", color: .red, quantity: 5), to: id)
        store.addPiece(makePiece(partNumber: "3003", name: "Brick 2×2", color: .blue, quantity: 3), to: id)
        let inv = store.inventories.first(where: { $0.id == id })
        XCTAssertEqual(inv?.totalPieces, 8)
        XCTAssertEqual(inv?.uniquePieces, 2)
    }

    @MainActor
    func testActiveInventory() {
        let id = createTrackedInventory(name: "Active")
        store.activeInventoryId = id
        XCTAssertNotNil(store.activeInventory)
        XCTAssertEqual(store.activeInventory?.id, id)
    }

    @MainActor
    func testActivePiecesAsLegoPieces() {
        let id = createTrackedInventory(name: "Convert Test")
        store.activeInventoryId = id
        store.addPiece(makePiece(partNumber: "3001", color: .red, quantity: 4), to: id)
        store.addPiece(makePiece(partNumber: "3020", name: "Plate 2×4", category: .plate, color: .green, quantity: 2), to: id)
        let legoPieces = store.activePiecesAsLegoPieces()
        XCTAssertEqual(legoPieces.count, 2)
        let redBrick = legoPieces.first(where: { $0.color == .red })
        XCTAssertEqual(redBrick?.quantity, 4)
        XCTAssertEqual(redBrick?.category, .brick)
    }

    // MARK: - InventoryPiece Computed Properties

    func testInventoryPieceCategoryConversion() {
        let piece = makePiece(category: .technic)
        XCTAssertEqual(piece.pieceCategory, .technic)
    }

    func testInventoryPieceColorConversion() {
        let piece = makePiece(color: .darkBlue)
        XCTAssertEqual(piece.pieceColor, .darkBlue)
    }

    func testInventoryPieceDimensionsConversion() {
        let piece = InventoryStore.InventoryPiece(
            partNumber: "3001",
            name: "Brick 2×4",
            category: .brick,
            color: .red,
            quantity: 1,
            dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3)
        )
        let dims = piece.dimensions
        XCTAssertEqual(dims.studsWide, 2)
        XCTAssertEqual(dims.studsLong, 4)
        XCTAssertEqual(dims.heightUnits, 3)
    }
}
