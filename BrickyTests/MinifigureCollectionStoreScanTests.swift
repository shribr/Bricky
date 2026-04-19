import XCTest
@testable import Bricky

/// Tests for the new scan-tracking APIs on `MinifigureCollectionStore`.
@MainActor
final class MinifigureCollectionStoreScanTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Wipe shared singleton state between tests.
        MinifigureCollectionStore.shared.collection.removeAll()
    }

    override func tearDown() {
        MinifigureCollectionStore.shared.collection.removeAll()
        super.tearDown()
    }

    private func req(_ slot: MinifigurePartSlot, _ part: String) -> MinifigurePartRequirement {
        MinifigurePartRequirement(slot: slot, partNumber: part, color: "Red")
    }

    private func makeFigure(id: String = "fig-scan-test",
                            parts: [MinifigurePartRequirement]) -> Minifigure {
        Minifigure(
            id: id,
            name: "Scan Test Fig",
            theme: "Test",
            year: 2024,
            partCount: parts.count,
            imgURL: nil,
            parts: parts
        )
    }

    // MARK: - markScanned

    func testMarkScannedAddsEntryAndMarksOwned() {
        let store = MinifigureCollectionStore.shared
        XCTAssertFalse(store.isOwned("fig-A"))
        XCTAssertFalse(store.isScanned("fig-A"))

        store.markScanned("fig-A")

        XCTAssertTrue(store.isOwned("fig-A"))
        XCTAssertTrue(store.isScanned("fig-A"))
        XCTAssertEqual(store.scannedSlots(for: "fig-A"),
                       MinifigureCollectionStore.defaultScannedSlots)
        XCTAssertNotNil(store.lastScannedAt("fig-A"))
    }

    func testMarkScannedMergesSlotsOnRepeatedScan() {
        let store = MinifigureCollectionStore.shared
        store.markScanned("fig-B", slots: [.torso])
        store.markScanned("fig-B", slots: [.head, .hips])

        let slots = store.scannedSlots(for: "fig-B")
        XCTAssertTrue(slots.contains(.torso))
        XCTAssertTrue(slots.contains(.head))
        XCTAssertTrue(slots.contains(.hips))
    }

    func testMarkScannedDoesNotDuplicateEntries() {
        let store = MinifigureCollectionStore.shared
        store.markScanned("fig-C")
        store.markScanned("fig-C")
        XCTAssertEqual(store.collection.filter { $0.minifigId == "fig-C" }.count, 1)
    }

    // MARK: - toggleScannedSlot

    func testToggleScannedSlotAddsAndRemoves() {
        let store = MinifigureCollectionStore.shared
        store.toggleScannedSlot(.handLeft, for: "fig-D")
        XCTAssertTrue(store.scannedSlots(for: "fig-D").contains(.handLeft))
        XCTAssertTrue(store.isOwned("fig-D"))

        store.toggleScannedSlot(.handLeft, for: "fig-D")
        XCTAssertFalse(store.scannedSlots(for: "fig-D").contains(.handLeft))
    }

    // MARK: - isScanComplete

    func testIsScanCompleteWhenAllRequiredSlotsScanned() {
        let fig = makeFigure(id: "fig-E", parts: [
            req(.torso, "973"),
            req(.head, "3626"),
            req(.hips, "970")
        ])
        let store = MinifigureCollectionStore.shared

        XCTAssertFalse(store.isScanComplete(fig))

        store.markScanned(fig.id, slots: [.torso, .head, .hips])
        XCTAssertTrue(store.isScanComplete(fig))
    }

    func testIsScanCompleteIgnoresOptionalSlots() {
        let fig = makeFigure(id: "fig-F", parts: [
            req(.torso, "973"),
            MinifigurePartRequirement(slot: .accessory,
                                      partNumber: "wand",
                                      color: "Brown",
                                      optional: true)
        ])
        let store = MinifigureCollectionStore.shared
        store.markScanned(fig.id, slots: [.torso])
        XCTAssertTrue(store.isScanComplete(fig),
                      "Optional accessory should not block completion.")
    }

    func testIsScanCompleteFalseWhenPartiallyScanned() {
        let fig = makeFigure(id: "fig-G", parts: [
            req(.torso, "973"),
            req(.head, "3626"),
            req(.legLeft, "970l"),
            req(.legRight, "970r")
        ])
        let store = MinifigureCollectionStore.shared
        store.markScanned(fig.id, slots: [.torso, .head])
        XCTAssertFalse(store.isScanComplete(fig))
    }

    // MARK: - default coverage

    func testDefaultScannedSlotsCoverStandardBodyParts() {
        let defaults = MinifigureCollectionStore.defaultScannedSlots
        XCTAssertTrue(defaults.contains(.head))
        XCTAssertTrue(defaults.contains(.torso))
        XCTAssertTrue(defaults.contains(.hips))
        XCTAssertTrue(defaults.contains(.legLeft))
        XCTAssertTrue(defaults.contains(.legRight))
    }
}
