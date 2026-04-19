import XCTest
@testable import Bricky

/// Tests for CameraViewModel state management, session control, and inventory persistence.
@MainActor
final class CameraViewModelTests: XCTestCase {

    var viewModel: CameraViewModel!
    var store: InventoryStore!
    var createdInventoryIds: [UUID] = []

    override func setUp() {
        super.setUp()
        viewModel = CameraViewModel()
        store = InventoryStore.shared
        createdInventoryIds = []
    }

    override func tearDown() {
        for id in createdInventoryIds {
            store.deleteInventory(id: id)
        }
        super.tearDown()
    }

    // MARK: - Helpers

    private func addPieceToSession(
        partNumber: String = "3001",
        name: String = "Brick 2×4",
        category: PieceCategory = .brick,
        color: LegoColor = .red,
        quantity: Int = 1
    ) {
        let piece = LegoPiece(
            partNumber: partNumber,
            name: name,
            category: category,
            color: color,
            dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3),
            quantity: quantity
        )
        viewModel.scanSession.addPiece(piece)
    }

    // MARK: - Initial State

    func testInitialState() {
        XCTAssertFalse(viewModel.isScanning)
        XCTAssertFalse(viewModel.showResults)
        XCTAssertEqual(viewModel.scanProgress, 0)
        XCTAssertEqual(viewModel.statusMessage, "Point camera at your LEGO pieces")
        XCTAssertEqual(viewModel.detectionCount, 0)
        XCTAssertNil(viewModel.lastCapturedImage)
        XCTAssertTrue(viewModel.liveDetections.isEmpty)
    }

    // MARK: - Start / Stop Scanning

    func testStartScanning() {
        viewModel.scanSettings.scanMode = .regular
        viewModel.startScanning()
        XCTAssertTrue(viewModel.isScanning)
        XCTAssertTrue(viewModel.scanSession.isScanning)
        XCTAssertTrue(viewModel.statusMessage.contains("Scanning"))
    }

    func testStopScanning() {
        viewModel.startScanning()
        viewModel.stopScanning()
        XCTAssertFalse(viewModel.isScanning)
        XCTAssertFalse(viewModel.scanSession.isScanning)
        XCTAssertEqual(viewModel.statusMessage, "Scan stopped")
    }

    func testStartStopToggle() {
        viewModel.startScanning()
        XCTAssertTrue(viewModel.isScanning)
        viewModel.stopScanning()
        XCTAssertFalse(viewModel.isScanning)
        viewModel.startScanning()
        XCTAssertTrue(viewModel.isScanning)
    }

    // MARK: - Analysis Mode

    func testSetAnalysisModeOffline() {
        viewModel.setAnalysisMode(.offline)
        XCTAssertEqual(viewModel.analysisMode, .offline)
    }

    func testSetAnalysisModeOnline() {
        viewModel.setAnalysisMode(.online)
        XCTAssertEqual(viewModel.analysisMode, .online)
    }

    func testSetAnalysisModeHybrid() {
        viewModel.setAnalysisMode(.hybrid)
        XCTAssertEqual(viewModel.analysisMode, .hybrid)
    }

    // MARK: - Reset Session

    func testResetSession() {
        // Simulate some scan state
        addPieceToSession()
        addPieceToSession(partNumber: "3003", name: "Brick 2×2", color: .blue)
        viewModel.detectionCount = 5
        viewModel.scanProgress = 0.8
        viewModel.showResults = true
        viewModel.statusMessage = "Found 5 pieces"

        viewModel.resetSession()

        XCTAssertTrue(viewModel.scanSession.pieces.isEmpty)
        XCTAssertEqual(viewModel.scanSession.totalPiecesFound, 0)
        XCTAssertEqual(viewModel.detectionCount, 0)
        XCTAssertEqual(viewModel.scanProgress, 0)
        XCTAssertFalse(viewModel.showResults)
        XCTAssertEqual(viewModel.statusMessage, "Point camera at your LEGO pieces")
    }

    func testResetDoesNotAffectCameraState() {
        viewModel.startScanning()
        viewModel.resetSession()
        // isScanning is not changed by reset
        XCTAssertTrue(viewModel.isScanning)
    }

    // MARK: - Save to Inventory

    func testSaveToInventoryCreatesInventory() {
        addPieceToSession(quantity: 3)
        addPieceToSession(partNumber: "3020", name: "Plate 2×4", category: .plate, color: .green, quantity: 2)

        let countBefore = store.inventories.count
        viewModel.saveToInventory(name: "Test Save")
        let countAfter = store.inventories.count
        XCTAssertEqual(countAfter, countBefore + 1)

        // Track for cleanup
        if let newInv = store.inventories.first(where: { $0.name == "Test Save" }) {
            createdInventoryIds.append(newInv.id)
            XCTAssertEqual(newInv.pieces.count, 2)
            XCTAssertEqual(newInv.totalPieces, 5) // 3 + 2
        } else {
            XCTFail("Saved inventory not found")
        }
    }

    func testSaveToInventoryDefaultName() {
        addPieceToSession()
        viewModel.saveToInventory()

        // Should create inventory with auto-generated name containing "Scan"
        if let newest = store.inventories.first(where: { $0.name.starts(with: "Scan") }) {
            createdInventoryIds.append(newest.id)
            XCTAssertTrue(newest.name.starts(with: "Scan"))
        } else {
            XCTFail("Auto-named inventory not found")
        }
    }

    // MARK: - Merge into Inventory

    func testMergeIntoInventory() {
        // Create existing inventory with a piece
        let existingId = store.createInventory(name: "Existing Inventory")
        createdInventoryIds.append(existingId)
        store.addPiece(
            InventoryStore.InventoryPiece(
                partNumber: "3001",
                name: "Brick 2×4",
                category: .brick,
                color: .red,
                quantity: 2,
                dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3)
            ),
            to: existingId
        )

        // Add pieces to scan session
        addPieceToSession(partNumber: "3001", color: .red, quantity: 3) // same piece, should merge
        addPieceToSession(partNumber: "3020", name: "Plate 2×4", category: .plate, color: .green, quantity: 1) // new piece

        viewModel.mergeIntoInventory(id: existingId)

        let inv = store.inventories.first(where: { $0.id == existingId })
        XCTAssertEqual(inv?.pieces.count, 2, "Should have original + new piece")
        let redBrick = inv?.pieces.first(where: { $0.partNumber == "3001" })
        XCTAssertEqual(redBrick?.quantity, 5, "Should merge: 2 + 3 = 5")
    }

    // MARK: - Scan Session Integration

    func testScanSessionPieceAddition() {
        addPieceToSession(quantity: 1)
        XCTAssertEqual(viewModel.scanSession.pieces.count, 1)
        XCTAssertEqual(viewModel.scanSession.totalPiecesFound, 1)
    }

    func testScanSessionDuplicateMerge() {
        // ScanSession.addPiece always increments by 1 on duplicate (scan-oriented)
        addPieceToSession(partNumber: "3001", color: .red, quantity: 2)
        addPieceToSession(partNumber: "3001", color: .red, quantity: 3)
        XCTAssertEqual(viewModel.scanSession.pieces.count, 1, "Same part+color should merge")
        XCTAssertEqual(viewModel.scanSession.pieces.first?.quantity, 3, "First insert qty=2, second adds +1 = 3")
        XCTAssertEqual(viewModel.scanSession.totalPiecesFound, 2)
    }
}
