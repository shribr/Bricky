import XCTest
@testable import Bricky

@MainActor
final class MinifigureCatalogTests: XCTestCase {

    func testBundledCatalogLoadsAtLeast10KFigures() async {
        let catalog = MinifigureCatalog.shared
        await catalog.load()
        XCTAssertTrue(catalog.isLoaded, "Catalog failed to load: \(catalog.loadError ?? "no error")")
        XCTAssertGreaterThan(catalog.allFigures.count, 10_000,
                             "Expected ≥10K figures, got \(catalog.allFigures.count)")
    }

    func testCatalogIndexesPopulated() async {
        let catalog = MinifigureCatalog.shared
        await catalog.load()
        XCTAssertFalse(catalog.themes.isEmpty)
        XCTAssertGreaterThan(catalog.yearRange.upperBound, catalog.yearRange.lowerBound)
    }

    func testSearchByName() async {
        let catalog = MinifigureCatalog.shared
        await catalog.load()
        // "Spaceman" has multiple classic-space results.
        let results = catalog.search(query: "spaceman", themes: [], yearRange: nil, sort: .nameAsc)
        XCTAssertFalse(results.isEmpty, "Expected at least one 'spaceman' result")
    }

    func testFigureLookupById() async {
        let catalog = MinifigureCatalog.shared
        await catalog.load()
        guard let first = catalog.allFigures.first else {
            XCTFail("Catalog empty")
            return
        }
        let fetched = catalog.figure(id: first.id)
        XCTAssertEqual(fetched?.id, first.id)
    }
}
