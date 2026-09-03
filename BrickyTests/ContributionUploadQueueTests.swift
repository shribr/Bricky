import XCTest
import UIKit
@testable import Bricky

@MainActor
final class ContributionUploadQueueTests: XCTestCase {

    private actor MockUploader: ContributionUploader {
        private(set) var uploaded: [ContributionObservation] = []
        private let succeed: Bool
        init(succeed: Bool) { self.succeed = succeed }
        func upload(_ observation: ContributionObservation, entitlementToken: String?) async -> Bool {
            uploaded.append(observation)
            return succeed
        }
        var count: Int { uploaded.count }
    }

    private func makeQueue(
        dir: String = "contribTest-\(UUID().uuidString)",
        uploader: ContributionUploader,
        sharing: Bool
    ) -> ContributionUploadQueue {
        ContributionUploadQueue(
            directoryName: dir,
            uploader: uploader,
            consent: { sharing },
            tokenProvider: { nil }
        )
    }

    private func sampleObservation() -> ContributionObservation {
        ContributionObservation(
            id: UUID(), createdAt: Date(), embeddingBase64: "AAAA",
            action: "correct", predictedPartNumber: "3001", predictedColor: "Red",
            predictedConfidence: 0.6, userPartNumber: "3001", userColor: "Blue",
            userStudsWide: 2, userStudsLong: 4, correctedShape: false, correctedColor: true,
            appVersion: "1.0", anonUserId: "anon"
        )
    }

    func testEnqueueIsNoOpWhenSharingOff() {
        let q = makeQueue(uploader: MockUploader(succeed: true), sharing: false)
        q.enqueue(sampleObservation())
        XCTAssertEqual(q.pendingCount, 0)
    }

    func testEnqueuePersistsAcrossInstances() {
        let dir = "contribTest-\(UUID().uuidString)"
        let q1 = makeQueue(dir: dir, uploader: MockUploader(succeed: true), sharing: true)
        q1.enqueue(sampleObservation())
        XCTAssertEqual(q1.pendingCount, 1)
        let q2 = makeQueue(dir: dir, uploader: MockUploader(succeed: true), sharing: true)
        XCTAssertEqual(q2.pendingCount, 1)
        q2.clear()
    }

    func testFlushDropsSuccessfulUploads() async {
        let uploader = MockUploader(succeed: true)
        let q = makeQueue(uploader: uploader, sharing: true)
        q.enqueue(sampleObservation())
        q.enqueue(sampleObservation())
        await q.flush()
        XCTAssertEqual(q.pendingCount, 0)
        let count = await uploader.count
        XCTAssertEqual(count, 2)
    }

    func testFlushKeepsFailures() async {
        let q = makeQueue(uploader: MockUploader(succeed: false), sharing: true)
        q.enqueue(sampleObservation())
        q.enqueue(sampleObservation())
        await q.flush()
        XCTAssertEqual(q.pendingCount, 2)
    }

    func testClearEmptiesQueue() {
        let q = makeQueue(uploader: MockUploader(succeed: false), sharing: true)
        q.enqueue(sampleObservation())
        q.clear()
        XCTAssertEqual(q.pendingCount, 0)
    }

    func testEnqueueCorrectionIsNoOpWhenSharingOff() {
        let q = makeQueue(uploader: MockUploader(succeed: true), sharing: false)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32), format: format).image { ctx in
            UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        let piece = LegoPiece(
            partNumber: "3001", name: "Brick 2×4", category: .brick, color: .red,
            dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3)
        )
        q.enqueueCorrection(
            crop: img, action: "confirm", predicted: piece,
            userPartNumber: "3001", userColor: .red,
            userStudsWide: 2, userStudsLong: 4,
            correctedShape: false, correctedColor: false
        )
        XCTAssertEqual(q.pendingCount, 0)
    }
}
