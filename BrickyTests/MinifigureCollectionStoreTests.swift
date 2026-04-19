import XCTest
@testable import Bricky

final class MinifigureCollectionStoreTests: XCTestCase {

    private func makeFigure(parts: [MinifigurePartRequirement] = []) -> Minifigure {
        Minifigure(
            id: "fig-test-\(UUID().uuidString.prefix(6))",
            name: "Test Figure",
            theme: "Test",
            year: 2024,
            partCount: parts.count,
            imgURL: nil,
            parts: parts
        )
    }

    private func req(slot: MinifigurePartSlot,
                     part: String,
                     color: String = "Red",
                     qty: Int = 1,
                     optional: Bool = false) -> MinifigurePartRequirement {
        MinifigurePartRequirement(
            slot: slot,
            partNumber: part,
            color: color,
            quantity: qty,
            optional: optional,
            displayName: "\(slot.displayName) \(part)"
        )
    }

    private func inventory(_ pieces: [(String, String, Int)]) -> InventoryStore.Inventory {
        let inventoryPieces = pieces.map { (part, color, qty) -> InventoryStore.InventoryPiece in
            InventoryStore.InventoryPiece(
                partNumber: part,
                name: "Piece \(part)",
                category: .minifigure,
                color: LegoColor(rawValue: color) ?? .red,
                quantity: qty,
                dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1)
            )
        }
        return InventoryStore.Inventory(
            id: UUID(),
            name: "Test Inventory",
            pieces: inventoryPieces,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    func testEmptyInventoryHasZeroCompletion() {
        let fig = makeFigure(parts: [
            req(slot: .torso, part: "973"),
            req(slot: .head, part: "3626")
        ])
        let pct = MinifigureCollectionStore.shared
            .completionPercentage(for: fig, inventories: [])
        XCTAssertEqual(pct, 0.0)
    }

    func testFullyOwnedReaches100Percent() {
        let fig = makeFigure(parts: [
            req(slot: .torso, part: "973"),
            req(slot: .head, part: "3626")
        ])
        let inv = inventory([("973", "Red", 1), ("3626", "Red", 1)])
        let pct = MinifigureCollectionStore.shared
            .completionPercentage(for: fig, inventories: [inv])
        XCTAssertEqual(pct, 100.0, accuracy: 0.01)
    }

    func testPartialOwnershipScalesLinearly() {
        let fig = makeFigure(parts: [
            req(slot: .torso, part: "973"),
            req(slot: .head, part: "3626")
        ])
        let inv = inventory([("973", "Red", 1)])
        let pct = MinifigureCollectionStore.shared
            .completionPercentage(for: fig, inventories: [inv])
        XCTAssertEqual(pct, 50.0, accuracy: 0.01)
    }

    func testOptionalPartsExcludedFromCompletion() {
        // Optional accessories shouldn't gate "complete" status.
        let fig = makeFigure(parts: [
            req(slot: .torso, part: "973"),
            req(slot: .accessory, part: "sword1", optional: true)
        ])
        let inv = inventory([("973", "Red", 1)])
        let pct = MinifigureCollectionStore.shared
            .completionPercentage(for: fig, inventories: [inv])
        XCTAssertEqual(pct, 100.0, accuracy: 0.01)
    }

    func testColorMustMatchExactly() {
        // Inventory has the right part number but wrong color → not owned.
        let fig = makeFigure(parts: [req(slot: .torso, part: "973", color: "Red")])
        let inv = inventory([("973", "Blue", 1)])
        let pct = MinifigureCollectionStore.shared
            .completionPercentage(for: fig, inventories: [inv])
        XCTAssertEqual(pct, 0.0)
    }

    func testMissingPartsReturnsOnlyMissing() {
        let fig = makeFigure(parts: [
            req(slot: .torso, part: "973"),
            req(slot: .head, part: "3626"),
            req(slot: .accessory, part: "sword1", optional: true)
        ])
        let inv = inventory([("973", "Red", 1)])
        let missing = MinifigureCollectionStore.shared
            .missingParts(for: fig, inventories: [inv])
        // Required head is missing; optional accessory excluded.
        XCTAssertEqual(missing.count, 1)
        XCTAssertEqual(missing.first?.partNumber, "3626")
    }

    func testSlotStatusesCoverAllRequirements() {
        let fig = makeFigure(parts: [
            req(slot: .torso, part: "973"),
            req(slot: .head, part: "3626")
        ])
        let inv = inventory([("973", "Red", 1)])
        let statuses = MinifigureCollectionStore.shared
            .slotStatuses(for: fig, inventories: [inv])
        XCTAssertEqual(statuses.count, 2)
        XCTAssertTrue(statuses.contains { $0.slot == .torso && $0.isOwned })
        XCTAssertTrue(statuses.contains { $0.slot == .head && !$0.isOwned })
    }
}
