import XCTest
@testable import Bricky

final class ClipEmbeddingServiceTests: XCTestCase {

    func testMergeHitsKeepsBestCosineAcrossLivePhotoCrops() {
        let merged = ClipEmbeddingService.mergeHits(
            [
                [
                    ClipEmbeddingIndex.Hit(figureId: "fig-a", cosine: 0.31),
                    ClipEmbeddingIndex.Hit(figureId: "fig-b", cosine: 0.52)
                ],
                [
                    ClipEmbeddingIndex.Hit(figureId: "fig-a", cosine: 0.68),
                    ClipEmbeddingIndex.Hit(figureId: "fig-c", cosine: 0.44)
                ]
            ],
            topK: 3
        )

        XCTAssertEqual(merged.map(\.figureId), ["fig-a", "fig-b", "fig-c"])
        XCTAssertEqual(merged.first?.cosine ?? 0, Float(0.68), accuracy: 0.001)
    }

    func testMergeHitsHonorsTopK() {
        let merged = ClipEmbeddingService.mergeHits(
            [
                [
                    ClipEmbeddingIndex.Hit(figureId: "fig-a", cosine: 0.31),
                    ClipEmbeddingIndex.Hit(figureId: "fig-b", cosine: 0.52),
                    ClipEmbeddingIndex.Hit(figureId: "fig-c", cosine: 0.44)
                ]
            ],
            topK: 2
        )

        XCTAssertEqual(merged.map(\.figureId), ["fig-b", "fig-c"])
    }
}