import XCTest
@testable import Bricky

/// Tests for Sprint I: Data & Sync features —
/// Export (CSV, PDF, BrickLink XML), Import (CSV, BrickLink XML),
/// Set Collection, Storage Bins, and CloudSync manager.
@MainActor final class SprintIDataSyncTests: XCTestCase {

    // MARK: - Test Helpers

    private func sampleInventory() -> InventoryStore.Inventory {
        let pieces = [
            InventoryStore.InventoryPiece(
                partNumber: "3001", name: "Brick 2×4", category: .brick,
                color: .red, quantity: 10,
                dimensions: PieceDimensions(studsWide: 4, studsLong: 2, heightUnits: 3)
            ),
            InventoryStore.InventoryPiece(
                partNumber: "3020", name: "Plate 2×4", category: .plate,
                color: .blue, quantity: 5,
                dimensions: PieceDimensions(studsWide: 4, studsLong: 2, heightUnits: 1)
            ),
            InventoryStore.InventoryPiece(
                partNumber: "3040", name: "Slope 45° 2×1", category: .slope,
                color: .green, quantity: 3,
                dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 2)
            ),
        ]
        return InventoryStore.Inventory(
            id: UUID(),
            name: "Test Inventory",
            pieces: pieces,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    // MARK: - CSV Export

    func testCSVExportContainsHeader() {
        let inv = sampleInventory()
        let csv = InventoryExporter.csv(from: inv)
        let lines = csv.components(separatedBy: "\n")
        XCTAssertTrue(lines[0].contains("Part Number"))
        XCTAssertTrue(lines[0].contains("Name"))
        XCTAssertTrue(lines[0].contains("Category"))
        XCTAssertTrue(lines[0].contains("Color"))
        XCTAssertTrue(lines[0].contains("Quantity"))
    }

    func testCSVExportContainsAllPieces() {
        let inv = sampleInventory()
        let csv = InventoryExporter.csv(from: inv)
        let lines = csv.components(separatedBy: "\n")
        // 1 header + 3 pieces
        XCTAssertEqual(lines.count, 4)
    }

    func testCSVExportContainsPartNumbers() {
        let inv = sampleInventory()
        let csv = InventoryExporter.csv(from: inv)
        XCTAssertTrue(csv.contains("3001"))
        XCTAssertTrue(csv.contains("3020"))
        XCTAssertTrue(csv.contains("3040"))
    }

    func testCSVExportContainsQuantities() {
        let inv = sampleInventory()
        let csv = InventoryExporter.csv(from: inv)
        XCTAssertTrue(csv.contains(",10,"))
        XCTAssertTrue(csv.contains(",5,"))
        XCTAssertTrue(csv.contains(",3,"))
    }

    func testCSVFileURLReturnsValidURL() {
        let inv = sampleInventory()
        let url = InventoryExporter.csvFileURL(from: inv)
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.lastPathComponent.hasSuffix(".csv"))
    }

    func testCSVEscapesCommasInNames() {
        let piece = InventoryStore.InventoryPiece(
            partNumber: "3001", name: "Brick, Large 2×4", category: .brick,
            color: .red, quantity: 1,
            dimensions: PieceDimensions(studsWide: 4, studsLong: 2, heightUnits: 3)
        )
        let inv = InventoryStore.Inventory(
            id: UUID(), name: "Test", pieces: [piece],
            createdAt: Date(), updatedAt: Date()
        )
        let csv = InventoryExporter.csv(from: inv)
        XCTAssertTrue(csv.contains("\"Brick, Large 2×4\""))
    }

    // MARK: - BrickLink XML Export

    func testBrickLinkXMLContainsHeader() {
        let inv = sampleInventory()
        let xml = InventoryExporter.brickLinkXML(from: inv)
        XCTAssertTrue(xml.hasPrefix("<?xml version=\"1.0\""))
        XCTAssertTrue(xml.contains("<INVENTORY>"))
        XCTAssertTrue(xml.contains("</INVENTORY>"))
    }

    func testBrickLinkXMLContainsItems() {
        let inv = sampleInventory()
        let xml = InventoryExporter.brickLinkXML(from: inv)
        XCTAssertTrue(xml.contains("<ITEM>"))
        XCTAssertTrue(xml.contains("<ITEMID>3001</ITEMID>"))
        XCTAssertTrue(xml.contains("<ITEMID>3020</ITEMID>"))
        XCTAssertTrue(xml.contains("<ITEMID>3040</ITEMID>"))
    }

    func testBrickLinkXMLContainsQuantities() {
        let inv = sampleInventory()
        let xml = InventoryExporter.brickLinkXML(from: inv)
        XCTAssertTrue(xml.contains("<MINQTY>10</MINQTY>"))
        XCTAssertTrue(xml.contains("<MINQTY>5</MINQTY>"))
        XCTAssertTrue(xml.contains("<MINQTY>3</MINQTY>"))
    }

    func testBrickLinkXMLContainsColorIds() {
        let inv = sampleInventory()
        let xml = InventoryExporter.brickLinkXML(from: inv)
        // Red = 5, Blue = 7, Green = 6
        XCTAssertTrue(xml.contains("<COLOR>5</COLOR>"))
        XCTAssertTrue(xml.contains("<COLOR>7</COLOR>"))
        XCTAssertTrue(xml.contains("<COLOR>6</COLOR>"))
    }

    func testBrickLinkXMLFileURLReturnsValidURL() {
        let inv = sampleInventory()
        let url = InventoryExporter.brickLinkXMLFileURL(from: inv)
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.lastPathComponent.hasSuffix(".xml"))
    }

    // MARK: - PDF Export

    func testPDFDataIsNonEmpty() {
        let inv = sampleInventory()
        let data = InventoryExporter.pdfData(from: inv)
        XCTAssertTrue(data.count > 100, "PDF data should be substantial")
    }

    func testPDFDataStartsWithPDFHeader() {
        let inv = sampleInventory()
        let data = InventoryExporter.pdfData(from: inv)
        let header = String(data: data.prefix(5), encoding: .ascii)
        XCTAssertEqual(header, "%PDF-")
    }

    func testPDFFileURLReturnsValidURL() {
        let inv = sampleInventory()
        let url = InventoryExporter.pdfFileURL(from: inv)
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.lastPathComponent.hasSuffix(".pdf"))
    }

    // MARK: - BrickLink Color Mapping

    func testBrickLinkColorMappingCoversAllColors() {
        for color in LegoColor.allCases {
            let id = InventoryExporter.brickLinkColorId(for: color)
            XCTAssertGreaterThan(id, 0, "Color \(color.rawValue) should have a valid BrickLink ID")
        }
    }

    // MARK: - CSV Import

    func testCSVImportBrickyFormat() throws {
        let csv = """
        Part Number,Name,Category,Color,Quantity,Studs Wide,Studs Long,Height Units
        3001,Brick 2×4,brick,Red,10,4,2,3
        3020,Plate 2×4,plate,Blue,5,4,2,1
        """
        let pieces = try InventoryImporter.importCSV(csv)
        XCTAssertEqual(pieces.count, 2)
        XCTAssertEqual(pieces[0].partNumber, "3001")
        XCTAssertEqual(pieces[0].name, "Brick 2×4")
        XCTAssertEqual(pieces[0].quantity, 10)
        XCTAssertEqual(pieces[1].partNumber, "3020")
    }

    func testCSVImportFlexibleHeaders() throws {
        let csv = """
        ItemID,Description,Type,Colour,Qty
        3001,Brick 2×4,brick,Red,10
        """
        let pieces = try InventoryImporter.importCSV(csv)
        XCTAssertEqual(pieces.count, 1)
        XCTAssertEqual(pieces[0].partNumber, "3001")
    }

    func testCSVImportMinimalColumns() throws {
        let csv = """
        Part Number,Quantity
        3001,5
        3020,3
        """
        let pieces = try InventoryImporter.importCSV(csv)
        XCTAssertEqual(pieces.count, 2)
        XCTAssertEqual(pieces[0].quantity, 5)
        XCTAssertEqual(pieces[1].quantity, 3)
    }

    func testCSVImportHandlesQuotedFields() throws {
        let csv = """
        Part Number,Name,Category,Color,Quantity,Studs Wide,Studs Long,Height Units
        3001,"Brick, Large 2×4",brick,Red,1,4,2,3
        """
        let pieces = try InventoryImporter.importCSV(csv)
        XCTAssertEqual(pieces.count, 1)
        XCTAssertEqual(pieces[0].name, "Brick, Large 2×4")
    }

    func testCSVImportRejectsEmptyCSV() {
        XCTAssertThrowsError(try InventoryImporter.importCSV("")) { error in
            XCTAssertTrue(error.localizedDescription.contains("header"))
        }
    }

    func testCSVImportRejectsHeaderOnly() {
        let csv = "Part Number,Name,Category"
        XCTAssertThrowsError(try InventoryImporter.importCSV(csv))
    }

    // MARK: - BrickLink XML Import

    func testBrickLinkXMLImport() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <INVENTORY>
          <ITEM>
            <ITEMTYPE>P</ITEMTYPE>
            <ITEMID>3001</ITEMID>
            <COLOR>5</COLOR>
            <MINQTY>10</MINQTY>
            <CONDITION>N</CONDITION>
            <REMARKS>Brick 2×4</REMARKS>
          </ITEM>
          <ITEM>
            <ITEMTYPE>P</ITEMTYPE>
            <ITEMID>3020</ITEMID>
            <COLOR>7</COLOR>
            <MINQTY>5</MINQTY>
            <CONDITION>N</CONDITION>
            <REMARKS>Plate 2×4</REMARKS>
          </ITEM>
        </INVENTORY>
        """
        let pieces = try InventoryImporter.importBrickLinkXML(xml)
        XCTAssertEqual(pieces.count, 2)
        XCTAssertEqual(pieces[0].partNumber, "3001")
        XCTAssertEqual(pieces[0].name, "Brick 2×4")
        XCTAssertEqual(pieces[0].quantity, 10)
        XCTAssertEqual(pieces[1].partNumber, "3020")
        XCTAssertEqual(pieces[1].quantity, 5)
    }

    func testBrickLinkXMLImportColorMapping() throws {
        let xml = """
        <?xml version="1.0"?>
        <INVENTORY>
          <ITEM><ITEMID>3001</ITEMID><COLOR>5</COLOR><MINQTY>1</MINQTY></ITEM>
        </INVENTORY>
        """
        let pieces = try InventoryImporter.importBrickLinkXML(xml)
        XCTAssertEqual(pieces[0].color, "Red") // BrickLink color 5 = Red
    }

    func testBrickLinkXMLImportRejectsEmptyInventory() {
        let xml = """
        <?xml version="1.0"?>
        <INVENTORY></INVENTORY>
        """
        XCTAssertThrowsError(try InventoryImporter.importBrickLinkXML(xml))
    }

    // MARK: - Round-trip Export → Import

    func testCSVRoundTrip() throws {
        let inv = sampleInventory()
        let csv = InventoryExporter.csv(from: inv)
        let imported = try InventoryImporter.importCSV(csv)
        XCTAssertEqual(imported.count, inv.pieces.count)

        for original in inv.pieces {
            let match = imported.first(where: { $0.partNumber == original.partNumber })
            XCTAssertNotNil(match, "Should find \(original.partNumber)")
            XCTAssertEqual(match?.quantity, original.quantity)
            XCTAssertEqual(match?.color, original.color)
        }
    }

    func testBrickLinkXMLRoundTrip() throws {
        let inv = sampleInventory()
        let xml = InventoryExporter.brickLinkXML(from: inv)
        let imported = try InventoryImporter.importBrickLinkXML(xml)
        XCTAssertEqual(imported.count, inv.pieces.count)

        for original in inv.pieces {
            let match = imported.first(where: { $0.partNumber == original.partNumber })
            XCTAssertNotNil(match, "Should find \(original.partNumber)")
            XCTAssertEqual(match?.quantity, original.quantity)
        }
    }

    // MARK: - LegoSet Model

    func testLegoSetDecoding() throws {
        let json = """
        {
            "id": "42183",
            "setNumber": "42183",
            "name": "Bugatti Bolide",
            "theme": "Technic",
            "year": 2024,
            "pieceCount": 905,
            "pieces": [
                {"partNumber": "3003", "color": "Blue", "quantity": 12}
            ]
        }
        """
        let data = json.data(using: .utf8)!
        let set = try JSONDecoder().decode(LegoSet.self, from: data)
        XCTAssertEqual(set.setNumber, "42183")
        XCTAssertEqual(set.name, "Bugatti Bolide")
        XCTAssertEqual(set.theme, "Technic")
        XCTAssertEqual(set.pieces.count, 1)
        XCTAssertEqual(set.pieces[0].quantity, 12)
    }

    func testLegoSetCodableRoundTrip() throws {
        let setPiece = LegoSet.SetPiece(partNumber: "3001", color: "Red", quantity: 5)
        let set = LegoSet(id: "10001", setNumber: "10001", name: "Test Set",
                          theme: "Test", year: 2024, pieceCount: 100, pieces: [setPiece])
        let data = try JSONEncoder().encode(set)
        let decoded = try JSONDecoder().decode(LegoSet.self, from: data)
        XCTAssertEqual(decoded.setNumber, "10001")
        XCTAssertEqual(decoded.name, "Test Set")
        XCTAssertEqual(decoded.pieces.count, 1)
    }

    // MARK: - Set Catalog

    func testSetCatalogLoads() {
        let catalog = LegoSetCatalog.shared
        XCTAssertGreaterThanOrEqual(catalog.sets.count, 20, "Should have at least 20 sets")
    }

    func testSetCatalogLookupByNumber() {
        let catalog = LegoSetCatalog.shared
        let result = catalog.set(byNumber: "75192")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "Millennium Falcon")
    }

    func testSetCatalogThemeIndex() {
        let catalog = LegoSetCatalog.shared
        let starWars = catalog.sets(byTheme: "Star Wars")
        XCTAssertGreaterThan(starWars.count, 0)
        XCTAssertTrue(starWars.allSatisfy { $0.theme == "Star Wars" })
    }

    func testSetCatalogSearch() {
        let catalog = LegoSetCatalog.shared
        let results = catalog.search("Bugatti")
        XCTAssertGreaterThan(results.count, 0)
        XCTAssertTrue(results.allSatisfy { $0.name.lowercased().contains("bugatti") })
    }

    func testSetCatalogAllThemesNonEmpty() {
        let catalog = LegoSetCatalog.shared
        XCTAssertGreaterThan(catalog.allThemes.count, 5)
    }

    // MARK: - Set Collection Completion

    func testSetCompletionPercentage() {
        let store = SetCollectionStore.shared

        let legoSet = LegoSet(
            id: "test", setNumber: "test", name: "Test", theme: "Test",
            year: 2024, pieceCount: 10,
            pieces: [
                .init(partNumber: "3001", color: "Red", quantity: 10),
                .init(partNumber: "3020", color: "Blue", quantity: 5),
            ]
        )

        let inv = InventoryStore.Inventory(
            id: UUID(), name: "Test", pieces: [
                InventoryStore.InventoryPiece(
                    partNumber: "3001", name: "Brick", category: .brick,
                    color: .red, quantity: 10,
                    dimensions: PieceDimensions(studsWide: 4, studsLong: 2, heightUnits: 3)
                ),
                InventoryStore.InventoryPiece(
                    partNumber: "3020", name: "Plate", category: .plate,
                    color: .blue, quantity: 3,
                    dimensions: PieceDimensions(studsWide: 4, studsLong: 2, heightUnits: 1)
                ),
            ],
            createdAt: Date(), updatedAt: Date()
        )

        let pct = store.completionPercentage(for: legoSet, inventory: inv)
        // Have 10/10 of 3001 and 3/5 of 3020 = 13/15 = 86.7%
        XCTAssertEqual(pct, 13.0 / 15.0 * 100, accuracy: 0.1)
    }

    func testSetCompletionFullMatch() {
        let store = SetCollectionStore.shared

        let legoSet = LegoSet(
            id: "t2", setNumber: "t2", name: "Test2", theme: "Test",
            year: 2024, pieceCount: 5,
            pieces: [.init(partNumber: "3001", color: "Red", quantity: 5)]
        )

        let inv = InventoryStore.Inventory(
            id: UUID(), name: "Test", pieces: [
                InventoryStore.InventoryPiece(
                    partNumber: "3001", name: "Brick", category: .brick,
                    color: .red, quantity: 10,
                    dimensions: PieceDimensions(studsWide: 4, studsLong: 2, heightUnits: 3)
                )
            ],
            createdAt: Date(), updatedAt: Date()
        )

        let pct = store.completionPercentage(for: legoSet, inventory: inv)
        XCTAssertEqual(pct, 100.0, accuracy: 0.01)
    }

    func testMissingPiecesReturnsCorrectDeficit() {
        let store = SetCollectionStore.shared

        let legoSet = LegoSet(
            id: "t3", setNumber: "t3", name: "Test3", theme: "Test",
            year: 2024, pieceCount: 10,
            pieces: [
                .init(partNumber: "3001", color: "Red", quantity: 10),
                .init(partNumber: "9999", color: "Black", quantity: 2),
            ]
        )

        let inv = InventoryStore.Inventory(
            id: UUID(), name: "Test", pieces: [
                InventoryStore.InventoryPiece(
                    partNumber: "3001", name: "Brick", category: .brick,
                    color: .red, quantity: 7,
                    dimensions: PieceDimensions(studsWide: 4, studsLong: 2, heightUnits: 3)
                )
            ],
            createdAt: Date(), updatedAt: Date()
        )

        let missing = store.missingPieces(for: legoSet, inventory: inv)
        XCTAssertEqual(missing.count, 2)

        let missingBrick = missing.first(where: { $0.partNumber == "3001" })
        XCTAssertNotNil(missingBrick)
        XCTAssertEqual(missingBrick?.needed, 10)
        XCTAssertEqual(missingBrick?.have, 7)

        let missing9999 = missing.first(where: { $0.partNumber == "9999" })
        XCTAssertNotNil(missing9999)
        XCTAssertEqual(missing9999?.have, 0)
        XCTAssertEqual(missing9999?.needed, 2)
    }

    // MARK: - StorageBin Model

    func testStorageBinCodableRoundTrip() throws {
        let bin = StorageBin(name: "Red Bin", color: "Red", location: "Shelf A",
                             pieceIds: [UUID(), UUID()])
        let data = try JSONEncoder().encode(bin)
        let decoded = try JSONDecoder().decode(StorageBin.self, from: data)
        XCTAssertEqual(decoded.name, "Red Bin")
        XCTAssertEqual(decoded.color, "Red")
        XCTAssertEqual(decoded.location, "Shelf A")
        XCTAssertEqual(decoded.pieceIds.count, 2)
    }

    func testStorageBinDefaultValues() {
        let bin = StorageBin(name: "Test")
        XCTAssertEqual(bin.color, "Blue")
        XCTAssertEqual(bin.location, "")
        XCTAssertTrue(bin.pieceIds.isEmpty)
    }

    // MARK: - CloudSync Manager

    func testCloudSyncManagerDefaultState() {
        let manager = CloudSyncManager.shared
        XCTAssertEqual(manager.syncStatus, .idle)
        XCTAssertNil(manager.syncError)
    }

    func testCloudSyncManagerAvailabilityCheck() {
        // On simulator, iCloud may or may not be available
        let manager = CloudSyncManager.shared
        // Just verify it doesn't crash
        _ = manager.isCloudAvailable
    }

    // MARK: - Color Inference

    func testCSVImportColorInference() throws {
        let csv = """
        Part Number,Name,Category,Color,Quantity
        3001,Brick,brick,Dark Blue,1
        """
        let pieces = try InventoryImporter.importCSV(csv)
        XCTAssertEqual(pieces[0].color, "Dark Blue")
    }

    func testCSVImportCategoryInference() throws {
        let csv = """
        Part Number,Name,Quantity
        3020,Large Plate,5
        """
        let pieces = try InventoryImporter.importCSV(csv)
        // "Large Plate" should infer .plate category
        XCTAssertEqual(pieces[0].category, PieceCategory.plate.rawValue)
    }
}
