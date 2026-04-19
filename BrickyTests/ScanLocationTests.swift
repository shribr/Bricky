import XCTest
@testable import Bricky

/// Sprint C — geolocation. Verifies:
///  • Backward-compatible Codable for `ScanHistoryStore.HistoryEntry` (old
///    JSON without lat/lon must still decode).
///  • New entries round-trip with location intact.
///  • Haversine distance helper.
///  • `clearLocations()` strips coordinates from every saved entry.
///  • Reverse-geocoded place name backfill.
final class ScanLocationTests: XCTestCase {

    // MARK: - Backward-compat decode

    func testHistoryEntryDecodesLegacyJSONWithoutLocation() throws {
        // Legacy v1 entry — no latitude/longitude/placeName fields.
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "date": "2025-01-01T12:00:00Z",
          "pieces": [],
          "totalPiecesFound": 3,
          "uniquePieceCount": 2,
          "usedARMode": false
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entry = try decoder.decode(ScanHistoryStore.HistoryEntry.self, from: json)

        XCTAssertNil(entry.latitude)
        XCTAssertNil(entry.longitude)
        XCTAssertNil(entry.placeName)
        XCTAssertNil(entry.locationCapturedAt)
        XCTAssertFalse(entry.hasLocation)
    }

    func testHistoryEntryRoundTripsWithLocation() throws {
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        let original = ScanHistoryStore.HistoryEntry(
            id: UUID(),
            date: when,
            pieces: [],
            totalPiecesFound: 5,
            uniquePieceCount: 3,
            usedARMode: false,
            latitude: 47.6062,
            longitude: -122.3321,
            placeName: "Seattle, WA",
            locationCapturedAt: when
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ScanHistoryStore.HistoryEntry.self, from: data)

        XCTAssertEqual(decoded.latitude, 47.6062)
        XCTAssertEqual(decoded.longitude, -122.3321)
        XCTAssertEqual(decoded.placeName, "Seattle, WA")
        XCTAssertEqual(decoded.locationCapturedAt, when)
        XCTAssertTrue(decoded.hasLocation)
    }

    // MARK: - Haversine

    func testHaversineZeroDistance() {
        let d = LocationDistance.meters(lat1: 47.6, lon1: -122.3,
                                        lat2: 47.6, lon2: -122.3)
        XCTAssertEqual(d, 0, accuracy: 0.001)
    }

    func testHaversineKnownDistanceSeattleToBellevue() {
        // Seattle (47.6062, -122.3321) → Bellevue (47.6101, -122.2015)
        // Real great-circle distance ≈ 9.8 km.
        let d = LocationDistance.meters(lat1: 47.6062, lon1: -122.3321,
                                        lat2: 47.6101, lon2: -122.2015)
        XCTAssertEqual(d, 9_800, accuracy: 200)
    }

    func testHaversineAntipodalApproximatesHalfCircumference() {
        // Earth circumference ≈ 40_030 km; half ≈ 20_015 km.
        let d = LocationDistance.meters(lat1: 0, lon1: 0, lat2: 0, lon2: 180)
        XCTAssertEqual(d, 20_015_000, accuracy: 5_000)
    }

    // MARK: - clearLocations()

    @MainActor
    func testClearLocationsStripsAllCoordinates() {
        let store = ScanHistoryStore.shared
        // Snapshot existing entries so we can restore the test runs clean.
        let backup = store.entries
        defer { store.entries = backup }

        store.entries = [
            ScanHistoryStore.HistoryEntry(
                id: UUID(), date: Date(), pieces: [],
                totalPiecesFound: 1, uniquePieceCount: 1,
                latitude: 1.0, longitude: 2.0,
                placeName: "X", locationCapturedAt: Date()
            ),
            ScanHistoryStore.HistoryEntry(
                id: UUID(), date: Date(), pieces: [],
                totalPiecesFound: 2, uniquePieceCount: 2,
                latitude: 3.0, longitude: 4.0,
                placeName: "Y", locationCapturedAt: Date()
            )
        ]

        store.clearLocations()

        XCTAssertEqual(store.entries.count, 2, "clearLocations must not delete entries")
        XCTAssertTrue(store.entries.allSatisfy { !$0.hasLocation })
        XCTAssertTrue(store.entries.allSatisfy { $0.placeName == nil })
    }

    @MainActor
    func testUpdatePlaceNameUpdatesMatchingEntry() {
        let store = ScanHistoryStore.shared
        let backup = store.entries
        defer { store.entries = backup }

        let id = UUID()
        store.entries = [
            ScanHistoryStore.HistoryEntry(
                id: id, date: Date(), pieces: [],
                totalPiecesFound: 1, uniquePieceCount: 1,
                latitude: 1.0, longitude: 2.0,
                placeName: nil, locationCapturedAt: Date()
            )
        ]

        store.updatePlaceName(sessionID: id, placeName: "Tacoma, WA")

        XCTAssertEqual(store.entries.first?.placeName, "Tacoma, WA")
    }

    @MainActor
    func testUpdatePlaceNameNoOpForUnknownSession() {
        let store = ScanHistoryStore.shared
        let backup = store.entries
        defer { store.entries = backup }

        store.entries = []
        store.updatePlaceName(sessionID: UUID(), placeName: "Anywhere")
        XCTAssertTrue(store.entries.isEmpty)
    }

    // MARK: - ScanSession defaults

    func testNewScanSessionHasNilLocation() {
        let session = ScanSession()
        XCTAssertNil(session.latitude)
        XCTAssertNil(session.longitude)
        XCTAssertNil(session.placeName)
        XCTAssertNil(session.locationCapturedAt)
    }
}
