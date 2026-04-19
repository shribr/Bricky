import XCTest
@testable import Bricky

/// Sprint 5 — F1 (pile diff), F2 (tags), F5 (sorting), F6 (color calibration).
@MainActor
final class Sprint5FeatureTests: XCTestCase {

    // MARK: - Helpers

    private func makePiece(
        partNumber: String,
        name: String = "Brick",
        color: LegoColor = .red,
        category: PieceCategory = .brick,
        wide: Int = 2,
        long: Int = 4,
        height: Int = 3,
        quantity: Int = 1
    ) -> LegoPiece {
        LegoPiece(
            partNumber: partNumber,
            name: name,
            category: category,
            color: color,
            dimensions: PieceDimensions(studsWide: wide, studsLong: long, heightUnits: height),
            confidence: 0.9,
            quantity: quantity
        )
    }

    // MARK: - F1 — Pile diff

    func testDiffDetectsAddedPieces() {
        let baseline: [LegoPiece] = [makePiece(partNumber: "3001")]
        let current: [LegoPiece] = [
            makePiece(partNumber: "3001"),
            makePiece(partNumber: "3002")
        ]
        let result = PileDiffService.diff(baseline: baseline, current: current)
        XCTAssertEqual(result.added.count, 1)
        XCTAssertEqual(result.added.first?.key.partNumber, "3002")
        XCTAssertTrue(result.removed.isEmpty)
        XCTAssertEqual(result.unchanged.count, 1)
    }

    func testDiffDetectsRemovedPieces() {
        let baseline: [LegoPiece] = [
            makePiece(partNumber: "3001"),
            makePiece(partNumber: "3002")
        ]
        let current: [LegoPiece] = [makePiece(partNumber: "3001")]
        let result = PileDiffService.diff(baseline: baseline, current: current)
        XCTAssertEqual(result.removed.count, 1)
        XCTAssertEqual(result.removed.first?.key.partNumber, "3002")
        XCTAssertTrue(result.added.isEmpty)
    }

    func testDiffDetectsQuantityChange() {
        let baseline = [makePiece(partNumber: "3001", quantity: 5)]
        let current = [makePiece(partNumber: "3001", quantity: 8)]
        let result = PileDiffService.diff(baseline: baseline, current: current)
        XCTAssertEqual(result.increased.count, 1)
        XCTAssertEqual(result.increased.first?.delta, 3)
        XCTAssertTrue(result.decreased.isEmpty)
    }

    func testDiffSeparatesByColor() {
        // Same partNumber, different colors → counted as distinct entries
        let baseline = [makePiece(partNumber: "3001", color: .red, quantity: 2)]
        let current = [
            makePiece(partNumber: "3001", color: .red, quantity: 2),
            makePiece(partNumber: "3001", color: .blue, quantity: 1)
        ]
        let result = PileDiffService.diff(baseline: baseline, current: current)
        XCTAssertEqual(result.added.count, 1)
        XCTAssertEqual(result.added.first?.key.color, .blue)
        XCTAssertEqual(result.unchanged.count, 1)
    }

    func testDiffNetDelta() {
        let baseline = [
            makePiece(partNumber: "3001", quantity: 2),
            makePiece(partNumber: "3002", quantity: 3)
        ]
        let current = [
            makePiece(partNumber: "3001", quantity: 4),  // +2
            makePiece(partNumber: "3003", quantity: 1)   // +1 added; 3002 (3) removed
        ]
        let result = PileDiffService.diff(baseline: baseline, current: current)
        // Net = +2 (increased) + 1 (added) - 3 (removed) = 0
        XCTAssertEqual(result.netDelta, 0)
        XCTAssertEqual(result.totalAdded, 1)
        XCTAssertEqual(result.totalRemoved, 3)
    }

    // MARK: - F2 — Tags

    func testTagsRoundTripThroughCodable() throws {
        let entry = ScanHistoryStore.HistoryEntry(
            id: UUID(),
            date: Date(),
            pieces: [makePiece(partNumber: "3001")],
            totalPiecesFound: 1,
            uniquePieceCount: 1,
            tags: ["Yard Sale", "Friend's house"]
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(ScanHistoryStore.HistoryEntry.self, from: data)
        XCTAssertEqual(decoded.tags, ["Yard Sale", "Friend's house"])
    }

    func testTagsBackwardCompatibilityWithOldEntries() throws {
        // Old JSON without `tags` field should decode with empty array
        let json = """
        {"id":"\(UUID().uuidString)","date":"2026-01-01T00:00:00Z","pieces":[],"totalPiecesFound":0,"uniquePieceCount":0,"usedARMode":false}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ScanHistoryStore.HistoryEntry.self, from: json)
        XCTAssertEqual(decoded.tags, [])
    }

    // MARK: - F5 — Sorting suggestions

    func testSortingSuggestionsReturnsAllStrategies() {
        let pieces = [
            makePiece(partNumber: "1", color: .red),
            makePiece(partNumber: "2", color: .blue),
            makePiece(partNumber: "3", color: .green)
        ]
        let result = SortingSuggestionService.recommend(pieces: pieces)
        XCTAssertEqual(result.count, 3)
        let strategies = Set(result.map { $0.strategy })
        XCTAssertEqual(strategies, [.byColorFamily, .byCategory, .bySize])
    }

    func testSortingSuggestionsRanksMostBalancedFirst() {
        // 6 pieces evenly: 3 red, 3 blue → byColorFamily creates 2 balanced bins
        // All same category → byCategory creates 1 huge bin (worst balance)
        let pieces = (0..<3).map { makePiece(partNumber: "r\($0)", color: .red) }
            + (0..<3).map { makePiece(partNumber: "b\($0)", color: .blue) }
        let result = SortingSuggestionService.recommend(pieces: pieces)
        // Most balanced should not be byCategory (which creates 1 bin → stdDev 0
        // *if alone* but with 1 bin we treat as 0; actually 1 bin gives perfect
        // balance trivially). So just assert the result is sorted by score.
        for i in 1..<result.count {
            XCTAssertLessThanOrEqual(result[i - 1].balanceScore, result[i].balanceScore)
        }
    }

    func testSortingEmptyPiecesReturnsNoSuggestions() {
        XCTAssertTrue(SortingSuggestionService.recommend(pieces: []).isEmpty)
    }

    func testColorFamilyGrouping() {
        XCTAssertEqual(SortingSuggestionService.colorFamily(for: .red), "Reds & Warm")
        XCTAssertEqual(SortingSuggestionService.colorFamily(for: .pink), "Reds & Warm")
        XCTAssertEqual(SortingSuggestionService.colorFamily(for: .lime), "Greens")
        XCTAssertEqual(SortingSuggestionService.colorFamily(for: .lightBlue), "Blues & Purple")
        XCTAssertEqual(SortingSuggestionService.colorFamily(for: .transparent), "Transparent")
    }

    // MARK: - F6 — Color calibration

    func testColorCalibrationStoreRoundTrip() {
        let store = ColorCalibrationStore.shared
        store.clearAll()
        XCTAssertFalse(store.isCalibrated)

        store.recordSample(for: .red, red: 0.85, green: 0.1, blue: 0.05)
        XCTAssertTrue(store.isCalibrated)
        XCTAssertEqual(store.calibratedColorsCount, 1)

        let sample = store.sample(for: .red)
        XCTAssertNotNil(sample)
        XCTAssertEqual(sample?.red ?? -1, 0.85, accuracy: 0.001)

        store.clear(color: .red)
        XCTAssertFalse(store.isCalibrated)
    }

    func testColorCalibrationClampsValues() {
        let store = ColorCalibrationStore.shared
        store.clearAll()
        store.recordSample(for: .blue, red: -0.5, green: 1.5, blue: 0.5)
        let sample = store.sample(for: .blue)
        XCTAssertNotNil(sample)
        XCTAssertEqual(sample?.red ?? -1, 0.0)
        XCTAssertEqual(sample?.green ?? -1, 1.0)
        XCTAssertEqual(sample?.blue ?? -1, 0.5)
        store.clearAll()
    }

    func testAverageColorOnSolidImage() {
        // A 50x50 solid red image — averaging the center 20% should return red.
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 50, height: 50))
        let img = renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 50, height: 50))
        }
        guard let avg = ColorCalibrationWizardView.averageColor(from: img) else {
            return XCTFail("averageColor returned nil")
        }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        avg.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertGreaterThan(r, 0.9)
        XCTAssertLessThan(g, 0.1)
        XCTAssertLessThan(b, 0.1)
    }
}
