import XCTest
@testable import Bricky

final class VerificationReliabilityStoreTests: XCTestCase {
    private var directoryName = ""
    private var store: VerificationReliabilityStore!

    override func setUp() {
        super.setUp()
        directoryName = "reliabilityTest-\(UUID().uuidString)"
        store = VerificationReliabilityStore(directoryName: directoryName)
    }

    override func tearDown() {
        store.reset()
        store = nil
        super.tearDown()
    }

    func testFreshStoreIsEmpty() {
        XCTAssertNil(store.observedAccuracy)
        XCTAssertEqual(store.totalSamples, 0)
        XCTAssertEqual(store.totalCorrect, 0)
        XCTAssertEqual(store.buckets.count, 10)
    }

    func testRecordingMixedOutcomesComputesAccuracy() {
        store.record(predictedConfidence: 0.9, wasCorrect: true)
        store.record(predictedConfidence: 0.9, wasCorrect: false)
        store.record(predictedConfidence: 0.2, wasCorrect: true)

        XCTAssertEqual(store.totalSamples, 3)
        XCTAssertEqual(store.totalCorrect, 2)
        XCTAssertEqual(store.observedAccuracy ?? -1, 2.0 / 3.0, accuracy: 1e-9)
    }

    func testBucketAssignment() {
        store.record(predictedConfidence: 0.95, wasCorrect: true)
        XCTAssertEqual(store.buckets[9].total, 1)
        XCTAssertEqual(store.buckets[9].correct, 1)

        store.record(predictedConfidence: 0.0, wasCorrect: false)
        XCTAssertEqual(store.buckets[0].total, 1)
        XCTAssertEqual(store.buckets[0].correct, 0)

        // Edge: 1.0 clamps into bucket 9 (not out of range).
        store.record(predictedConfidence: 1.0, wasCorrect: true)
        XCTAssertEqual(store.buckets[9].total, 2)
        XCTAssertEqual(store.buckets[9].correct, 2)
    }

    func testPersistenceReloadsTotals() {
        store.record(predictedConfidence: 0.7, wasCorrect: true)
        store.record(predictedConfidence: 0.3, wasCorrect: false)

        let reloaded = VerificationReliabilityStore(directoryName: directoryName)
        XCTAssertEqual(reloaded.totalSamples, 2)
        XCTAssertEqual(reloaded.totalCorrect, 1)
        reloaded.reset()
    }

    func testResetZeroesEverything() {
        store.record(predictedConfidence: 0.8, wasCorrect: true)
        store.record(predictedConfidence: 0.4, wasCorrect: false)

        store.reset()

        XCTAssertEqual(store.totalSamples, 0)
        XCTAssertEqual(store.totalCorrect, 0)
        XCTAssertNil(store.observedAccuracy)
        XCTAssertEqual(store.buckets.count, 10)
        XCTAssertTrue(store.buckets.allSatisfy { $0.total == 0 && $0.correct == 0 })
    }
}
