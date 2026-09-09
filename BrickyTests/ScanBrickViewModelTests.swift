import XCTest
@testable import Bricky

@MainActor
final class ScanBrickViewModelTests: XCTestCase {

    private func part(
        id: String,
        name: String,
        matchedPartNumber: String? = nil,
        matchedName: String? = nil,
        matchedCategory: PieceCategory? = nil,
        matchedDimensions: PieceDimensions? = nil,
        isCatalogMatch: Bool = false
    ) -> BrickognizeService.MatchedPart {
        BrickognizeService.MatchedPart(
            prediction: BrickognizeService.PredictionResult(
                brickLinkID: id, name: name, score: 0.9,
                imageURL: nil, brickLinkURL: nil, category: "Brick"
            ),
            matchedPartNumber: matchedPartNumber,
            matchedName: matchedName,
            matchedCategory: matchedCategory,
            matchedDimensions: matchedDimensions,
            isCatalogMatch: isCatalogMatch
        )
    }

    private struct StubIdentifier: PartIdentifying {
        let result: Result<[BrickognizeService.MatchedPart], Error>
        func identifyPart(image: UIImage, maxResults: Int) async throws -> [BrickognizeService.MatchedPart] {
            try result.get()
        }
    }

    private struct StubError: Error {}

    private var image: UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { ctx in
            UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    func testCloudDisabledShortCircuits() async {
        let vm = ScanBrickViewModel(
            identifier: StubIdentifier(result: .success([])),
            isCloudEnabled: { false }
        )
        await vm.identify(image: image)
        XCTAssertEqual(vm.phase, .cloudDisabled)
        XCTAssertTrue(vm.candidates.isEmpty)
    }

    func testSuccessfulIdentificationPopulatesResults() async {
        let vm = ScanBrickViewModel(
            identifier: StubIdentifier(result: .success([
                part(id: "3001", name: "Brick 2 x 4", matchedPartNumber: "3001", isCatalogMatch: true)
            ])),
            isCloudEnabled: { true }
        )
        await vm.identify(image: image)
        XCTAssertEqual(vm.phase, .results)
        XCTAssertEqual(vm.candidates.count, 1)
        XCTAssertEqual(vm.candidates.first?.matchedPartNumber, "3001")
    }

    func testEmptyResultsMapToEmptyPhase() async {
        let vm = ScanBrickViewModel(
            identifier: StubIdentifier(result: .success([])),
            isCloudEnabled: { true }
        )
        await vm.identify(image: image)
        XCTAssertEqual(vm.phase, .empty)
    }

    func testFailureMapsToFailedPhase() async {
        let vm = ScanBrickViewModel(
            identifier: StubIdentifier(result: .failure(StubError())),
            isCloudEnabled: { true }
        )
        await vm.identify(image: image)
        if case .failed = vm.phase {} else { XCTFail("Expected .failed, got \(vm.phase)") }
    }

    func testInventoryPieceUsesCatalogMatchThenColor() {
        let vm = ScanBrickViewModel(identifier: StubIdentifier(result: .success([])), isCloudEnabled: { true })
        let candidate = part(
            id: "3001", name: "raw",
            matchedPartNumber: "3001", matchedName: "Brick 2 x 4",
            matchedCategory: .brick,
            matchedDimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3),
            isCatalogMatch: true
        )
        let piece = vm.inventoryPiece(for: candidate, color: .red, quantity: 3)
        XCTAssertEqual(piece.partNumber, "3001")
        XCTAssertEqual(piece.name, "Brick 2 x 4")
        XCTAssertEqual(piece.color, LegoColor.red.rawValue)
        XCTAssertEqual(piece.quantity, 3)
        XCTAssertEqual(piece.studsLong, 4)
    }

    func testInventoryPieceFallsBackToRawPredictionWhenUnmatched() {
        let vm = ScanBrickViewModel(identifier: StubIdentifier(result: .success([])), isCloudEnabled: { true })
        let candidate = part(id: "99999", name: "Mystery Part", isCatalogMatch: false)
        let piece = vm.inventoryPiece(for: candidate, color: .blue)
        XCTAssertEqual(piece.partNumber, "99999")
        XCTAssertEqual(piece.name, "Mystery Part")
        XCTAssertEqual(piece.color, LegoColor.blue.rawValue)
        XCTAssertEqual(piece.quantity, 1)
    }

    func testConfirmAddsPieceToInventory() {
        let store = InventoryStore.shared
        let invId = store.createInventory(name: "ScanBrickTest-\(UUID().uuidString)")
        defer { store.deleteInventory(id: invId) }

        let vm = ScanBrickViewModel(identifier: StubIdentifier(result: .success([])), isCloudEnabled: { true })
        let candidate = part(id: "3001", name: "Brick 2 x 4", matchedPartNumber: "3001", isCatalogMatch: true)
        vm.confirm(candidate, color: .red, quantity: 2, into: invId, store: store)

        let inv = store.inventories.first(where: { $0.id == invId })
        XCTAssertEqual(inv?.pieces.count, 1)
        XCTAssertEqual(inv?.pieces.first?.partNumber, "3001")
        XCTAssertEqual(inv?.pieces.first?.quantity, 2)
    }

    func testConfirmRemembersLastUsedColor() {
        let suiteName = "ScanBrickColorTest-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = InventoryStore.shared
        let invId = store.createInventory(name: "ScanBrickColorTest-\(UUID().uuidString)")
        defer { store.deleteInventory(id: invId) }

        let vm = ScanBrickViewModel(
            identifier: StubIdentifier(result: .success([])),
            isCloudEnabled: { true },
            defaults: defaults
        )
        XCTAssertEqual(vm.lastUsedColor, .red, "Defaults to red before any confirm")

        let candidate = part(id: "3001", name: "Brick", matchedPartNumber: "3001", isCatalogMatch: true)
        vm.confirm(candidate, color: .blue, into: invId, store: store)
        XCTAssertEqual(vm.lastUsedColor, .blue)

        // A fresh VM on the same defaults reads the persisted color.
        let vm2 = ScanBrickViewModel(
            identifier: StubIdentifier(result: .success([])),
            isCloudEnabled: { true },
            defaults: defaults
        )
        XCTAssertEqual(vm2.lastUsedColor, .blue)
    }
}
