import XCTest
@testable import Bricky

@MainActor
final class CorrectionIndexServiceTests: XCTestCase {

    /// Returns a preset fetch result (or nil) regardless of the `since` version.
    private struct MockDownloader: CorrectionIndexDownloader {
        let result: CorrectionIndexFetchResult?
        func fetch(since version: String) async -> CorrectionIndexFetchResult? { result }
    }

    private func uniqueDir() -> String { "indexTest-\(UUID().uuidString)" }

    private func sampleIndex(version: String = "5") -> ServerCorrectionIndex {
        ServerCorrectionIndex(
            version: version,
            generatedAt: "2026-09-03T00:00:00Z",
            entries: [
                ServerCorrectionEntry(
                    clusterId: "c1", embeddingBase64: "AAAA", shapeLabel: "3001",
                    colorLabel: "Red", members: 12, shapeConfidence: 0.9, colorConfidence: 0.8
                ),
                ServerCorrectionEntry(
                    clusterId: "c2", embeddingBase64: "BBBB", shapeLabel: nil,
                    colorLabel: "Blue", members: 4, shapeConfidence: 0.0, colorConfidence: 0.7
                )
            ]
        )
    }

    func testRefreshWithNewIndexUpdatesAndPersists() async {
        let dir = uniqueDir()
        let index = sampleIndex(version: "5")
        let service = CorrectionIndexService(directoryName: dir,
                                             downloader: MockDownloader(result: .index(index)))
        await service.refresh()

        XCTAssertEqual(service.version, "5")
        XCTAssertEqual(service.entries.count, 2)
        XCTAssertEqual(service.entries.first?.clusterId, "c1")

        // A fresh service on the same directory loads the persisted cache.
        let reloaded = CorrectionIndexService(directoryName: dir,
                                              downloader: MockDownloader(result: nil))
        XCTAssertEqual(reloaded.version, "5")
        XCTAssertEqual(reloaded.entries.count, 2)
        XCTAssertEqual(reloaded.entries.last?.colorLabel, "Blue")
    }

    func testRefreshUpToDateLeavesCacheUnchanged() async {
        let dir = uniqueDir()
        let seed = CorrectionIndexService(directoryName: dir,
                                          downloader: MockDownloader(result: .index(sampleIndex(version: "3"))))
        await seed.refresh()

        let service = CorrectionIndexService(directoryName: dir,
                                             downloader: MockDownloader(result: .upToDate))
        await service.refresh()

        XCTAssertEqual(service.version, "3")
        XCTAssertEqual(service.entries.count, 2)
    }

    func testRefreshFailureLeavesCacheUnchanged() async {
        let dir = uniqueDir()
        let seed = CorrectionIndexService(directoryName: dir,
                                          downloader: MockDownloader(result: .index(sampleIndex(version: "7"))))
        await seed.refresh()

        let service = CorrectionIndexService(directoryName: dir,
                                             downloader: MockDownloader(result: nil))
        await service.refresh()

        XCTAssertEqual(service.version, "7")
        XCTAssertEqual(service.entries.count, 2)
    }

    func testFreshServiceWithNoCacheIsEmpty() {
        let service = CorrectionIndexService(directoryName: uniqueDir(),
                                             downloader: MockDownloader(result: nil))
        XCTAssertEqual(service.version, "0")
        XCTAssertTrue(service.entries.isEmpty)
    }
}
