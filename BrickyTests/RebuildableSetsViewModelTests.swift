import XCTest
@testable import Bricky

@MainActor
final class RebuildableSetsViewModelTests: XCTestCase {

    private func bom(_ partNumber: String, _ color: LegoColor, qty: Int) -> LegoSet.SetPiece {
        LegoSet.SetPiece(partNumber: partNumber, color: color.rawValue, quantity: qty)
    }

    private struct StubProvider: SetBOMProviding {
        let boms: [String: [LegoSet.SetPiece]]
        let failing: Set<String>
        func fetchParts(for setNumber: String) async throws -> [LegoSet.SetPiece] {
            if failing.contains(setNumber) { throw StubError() }
            return boms[setNumber] ?? []
        }
    }

    private struct StubError: Error {}

    private func makeVM(
        boms: [String: [LegoSet.SetPiece]] = [:],
        failing: Set<String> = [],
        isConfigured: Bool = true
    ) -> RebuildableSetsViewModel {
        RebuildableSetsViewModel(
            bomProvider: StubProvider(boms: boms, failing: failing),
            isConfigured: isConfigured,
            setName: { "Set \($0)" }
        )
    }

    func testNotConfiguredShortCircuits() async {
        let vm = makeVM(isConfigured: false)
        await vm.load(ownedSetNumbers: ["111"], ownedCounts: [:])
        XCTAssertEqual(vm.phase, .notConfigured)
    }

    func testEmptyOwnedSetsMapsToEmpty() async {
        let vm = makeVM()
        await vm.load(ownedSetNumbers: [], ownedCounts: [:])
        XCTAssertEqual(vm.phase, .empty)
    }

    func testRowsRankedByCoverageDescending() async {
        let boms: [String: [LegoSet.SetPiece]] = [
            "full": [bom("3001", .red, qty: 1)],
            "half": [bom("3001", .red, qty: 1), bom("9999", .yellow, qty: 1)],
            "none": [bom("8888", .black, qty: 2)]
        ]
        let owned = ["3001|\(LegoColor.red.rawValue)": 5]
        let vm = makeVM(boms: boms)

        await vm.load(ownedSetNumbers: ["none", "half", "full"], ownedCounts: owned)

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.rows.map(\.setNumber), ["full", "half", "none"])
        XCTAssertTrue(vm.rows[0].completion.isComplete)
        XCTAssertEqual(vm.rows[1].completion.coverage, 0.5, accuracy: 0.0001)
        XCTAssertEqual(vm.fullyBuildableCount, 1)
        XCTAssertEqual(vm.evaluatedSetCount, 3)
    }

    func testFailingSetsAreSkippedButOthersEvaluated() async {
        let boms: [String: [LegoSet.SetPiece]] = ["ok": [bom("3001", .red, qty: 1)]]
        let owned = ["3001|\(LegoColor.red.rawValue)": 2]
        let vm = makeVM(boms: boms, failing: ["broken"])

        await vm.load(ownedSetNumbers: ["ok", "broken"], ownedCounts: owned)

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.rows.map(\.setNumber), ["ok"])
    }

    func testAllSetsFailingMapsToFailed() async {
        let vm = makeVM(failing: ["a", "b"])
        await vm.load(ownedSetNumbers: ["a", "b"], ownedCounts: [:])
        if case .failed = vm.phase {} else { XCTFail("Expected .failed, got \(vm.phase)") }
    }

    func testOwnedCountsAggregatesAcrossInventories() {
        let inv1 = InventoryStore.Inventory(
            id: UUID(), name: "A",
            pieces: [
                InventoryStore.InventoryPiece(
                    partNumber: "3001", name: "Brick", category: .brick, color: .red,
                    quantity: 2, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3)
                )
            ],
            createdAt: Date(), updatedAt: Date()
        )
        let inv2 = InventoryStore.Inventory(
            id: UUID(), name: "B",
            pieces: [
                InventoryStore.InventoryPiece(
                    partNumber: "3001", name: "Brick", category: .brick, color: .red,
                    quantity: 3, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3)
                ),
                InventoryStore.InventoryPiece(
                    partNumber: "3003", name: "Brick", category: .brick, color: .blue,
                    quantity: 1, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3)
                )
            ],
            createdAt: Date(), updatedAt: Date()
        )

        let counts = RebuildableSetsViewModel.ownedCounts(from: [inv1, inv2])
        XCTAssertEqual(counts["3001|\(LegoColor.red.rawValue)"], 5)
        XCTAssertEqual(counts["3003|\(LegoColor.blue.rawValue)"], 1)
    }
}
