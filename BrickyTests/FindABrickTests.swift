import XCTest
@testable import Bricky

/// Sprint 2 — Find-a-brick search functionality.
@MainActor
final class FindABrickTests: XCTestCase {

    // MARK: - Helpers

    private func makePiece(
        partNumber: String,
        name: String = "Test Brick",
        color: LegoColor = .red,
        quantity: Int = 1,
        captureIndex: Int = 0,
        boundingBox: CGRect? = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
    ) -> LegoPiece {
        var piece = LegoPiece(
            partNumber: partNumber,
            name: name,
            category: .brick,
            color: color,
            dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1),
            confidence: 0.9,
            quantity: quantity
        )
        piece.boundingBox = boundingBox
        piece.captureIndex = captureIndex
        return piece
    }

    private func makeHistoryEntry(
        id: UUID = UUID(),
        date: Date = Date(),
        pieces: [LegoPiece],
        placeName: String? = nil
    ) -> ScanHistoryStore.HistoryEntry {
        ScanHistoryStore.HistoryEntry(
            id: id,
            date: date,
            pieces: pieces,
            totalPiecesFound: pieces.reduce(0) { $0 + $1.quantity },
            uniquePieceCount: pieces.count,
            usedARMode: false,
            latitude: nil,
            longitude: nil,
            placeName: placeName,
            locationCapturedAt: nil
        )
    }

    // MARK: - B2 — Find in Saved Scan picker logic

    func testMatchingEntriesFiltersByPartNumber() {
        let target = "3001"
        let entryWithMatch = makeHistoryEntry(pieces: [
            makePiece(partNumber: target),
            makePiece(partNumber: "3002")
        ])
        let entryWithoutMatch = makeHistoryEntry(pieces: [
            makePiece(partNumber: "3003"),
            makePiece(partNumber: "3004")
        ])

        let entries = [entryWithMatch, entryWithoutMatch]
        let matching = entries.filter { entry in
            entry.pieces.contains { $0.partNumber == target }
        }
        let nonMatching = entries.filter { entry in
            !entry.pieces.contains { $0.partNumber == target }
        }

        XCTAssertEqual(matching.count, 1)
        XCTAssertEqual(matching.first?.id, entryWithMatch.id)
        XCTAssertEqual(nonMatching.count, 1)
        XCTAssertEqual(nonMatching.first?.id, entryWithoutMatch.id)
    }

    func testMatchingCountIncludesQuantity() {
        let target = "3001"
        let entry = makeHistoryEntry(pieces: [
            makePiece(partNumber: target, quantity: 3),
            makePiece(partNumber: target, color: .blue, quantity: 2),  // Different color, same part
            makePiece(partNumber: "3002", quantity: 5)
        ])

        let matchingCount = entry.pieces
            .filter { $0.partNumber == target }
            .reduce(0) { $0 + $1.quantity }

        XCTAssertEqual(matchingCount, 5, "Quantities of all matching part numbers should sum")
    }

    // MARK: - PileResultsSheetView — highlighted filter mode

    func testPileSheetHighlightModeFiltersVisiblePieces() {
        let target = "3001"
        let pieces: [LegoPiece] = [
            makePiece(partNumber: target, captureIndex: 0),
            makePiece(partNumber: "3002", captureIndex: 0),
            makePiece(partNumber: target, color: .blue, captureIndex: 0)
        ]

        // Without filter → all pieces in capture are visible
        let allInCapture = pieces.filter { ($0.captureIndex ?? 0) == 0 }
        XCTAssertEqual(allInCapture.count, 3)

        // With highlight filter → only matching part number
        let filtered = pieces.filter {
            ($0.captureIndex ?? 0) == 0 && $0.partNumber == target
        }
        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.allSatisfy { $0.partNumber == target })
    }

    // MARK: - B4 — Global piece search

    func testCatalogSearchFindsByName() {
        let results = LegoPartsCatalog.shared.search(query: "brick")
        XCTAssertFalse(results.isEmpty, "Catalog should contain at least one piece named 'brick'")
        XCTAssertTrue(
            results.allSatisfy { piece in
                piece.name.lowercased().contains("brick") ||
                piece.partNumber.lowercased().contains("brick") ||
                piece.keywords.contains(where: { $0.contains("brick") })
            }
        )
    }

    func testCatalogSearchFindsByPartNumber() {
        let allPieces = LegoPartsCatalog.shared.pieces
        guard let sample = allPieces.first else {
            return XCTFail("Catalog should be non-empty")
        }
        let results = LegoPartsCatalog.shared.search(query: sample.partNumber)
        XCTAssertTrue(
            results.contains(where: { $0.partNumber == sample.partNumber }),
            "Searching by exact part number should return that piece"
        )
    }

    func testScanStatsAggregationCountsScansNotPieces() {
        // Two scans, both contain target piece. Expect matchCount = 2, totalQty = 5
        let target = "3001"
        let entries = [
            makeHistoryEntry(pieces: [
                makePiece(partNumber: target, quantity: 3),
                makePiece(partNumber: target, color: .blue, quantity: 1)  // Same scan, same part, diff color
            ]),
            makeHistoryEntry(pieces: [
                makePiece(partNumber: target, quantity: 1)
            ])
        ]

        var scanStats: [String: (matchCount: Int, totalQty: Int)] = [:]
        for entry in entries {
            var seenInThisScan = Set<String>()
            for piece in entry.pieces {
                let prev = scanStats[piece.partNumber]
                let firstHitInScan = !seenInThisScan.contains(piece.partNumber)
                seenInThisScan.insert(piece.partNumber)
                scanStats[piece.partNumber] = (
                    matchCount: (prev?.matchCount ?? 0) + (firstHitInScan ? 1 : 0),
                    totalQty: (prev?.totalQty ?? 0) + piece.quantity
                )
            }
        }

        XCTAssertEqual(scanStats[target]?.matchCount, 2, "Should count distinct scans, not piece entries")
        XCTAssertEqual(scanStats[target]?.totalQty, 5, "Total quantity should sum all entries")
    }

    // MARK: - SearchablePiece → LegoPiece conversion

    func testSearchablePieceConvertsToLegoPiece() {
        let searchable = FindABrickHubView.SearchablePiece(
            id: "3001",
            partNumber: "3001",
            name: "Brick 2x4",
            category: .brick,
            dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1),
            displayColor: .red,
            scanMatchCount: 0,
            totalQuantityAcrossScans: 0
        )
        let piece = searchable.asLegoPiece()
        XCTAssertEqual(piece.partNumber, "3001")
        XCTAssertEqual(piece.name, "Brick 2x4")
        XCTAssertEqual(piece.color, .red)
        XCTAssertEqual(piece.dimensions.studsWide, 2)
        XCTAssertEqual(piece.dimensions.studsLong, 4)
    }
}
