import XCTest
import UIKit
@testable import Bricky

final class BrickCorrectionStoreTests: XCTestCase {

    private var directoryName: String!
    private var store: BrickCorrectionStore!

    override func setUp() {
        super.setUp()
        directoryName = "brickCorrectionsTest-\(UUID().uuidString)"
        store = BrickCorrectionStore(directoryName: directoryName)
    }

    override func tearDown() {
        store.clear()
        store = nil
        directoryName = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeImage(color: UIColor = .red, size: CGSize = CGSize(width: 32, height: 32)) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    // MARK: - Tests

    func testRecordAddsCorrectionWithMatchingFields() {
        let correction = store.record(
            crop: makeImage(),
            partNumber: "3001",
            name: "Brick 2x4",
            category: .brick,
            color: .red,
            studsWide: 2,
            studsLong: 4,
            heightUnits: 3,
            correctedShape: true,
            correctedColor: false
        )

        XCTAssertEqual(store.count, 1)
        XCTAssertEqual(correction.partNumber, "3001")
        XCTAssertEqual(correction.name, "Brick 2x4")
        XCTAssertEqual(correction.category, .brick)
        XCTAssertEqual(correction.color, .red)
        XCTAssertEqual(correction.studsWide, 2)
        XCTAssertEqual(correction.studsLong, 4)
        XCTAssertEqual(correction.heightUnits, 3)
        XCTAssertTrue(correction.correctedShape)
        XCTAssertFalse(correction.correctedColor)
    }

    func testImageForReturnsNonNilAfterRecord() {
        let correction = store.record(
            crop: makeImage(color: .blue),
            partNumber: "3020",
            name: "Plate 2x4",
            category: .plate,
            color: .blue,
            studsWide: 2,
            studsLong: 4,
            heightUnits: 1,
            correctedShape: false,
            correctedColor: true
        )

        XCTAssertNotNil(store.image(for: correction))
    }

    func testPersistenceRoundTripAcrossInstances() {
        _ = store.record(
            crop: makeImage(color: .green),
            partNumber: "3005",
            name: "Brick 1x1",
            category: .brick,
            color: .green,
            studsWide: 1,
            studsLong: 1,
            heightUnits: 3,
            correctedShape: true,
            correctedColor: true
        )

        let reloaded = BrickCorrectionStore(directoryName: directoryName)
        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(reloaded.corrections.first?.partNumber, "3005")
        XCTAssertEqual(reloaded.corrections.first?.color, .green)
    }

    func testClearEmptiesCorrections() {
        _ = store.record(
            crop: makeImage(),
            partNumber: "3001",
            name: "Brick 2x4",
            category: .brick,
            color: .red,
            studsWide: 2,
            studsLong: 4,
            heightUnits: 3,
            correctedShape: true,
            correctedColor: true
        )
        XCTAssertEqual(store.count, 1)

        store.clear()
        XCTAssertEqual(store.count, 0)
        XCTAssertTrue(store.corrections.isEmpty)
    }
}
