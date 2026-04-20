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

    /// fig-000697 is the iconic Classic Town Police Officer (black cap,
    /// sunglasses, zipper-jacket-with-sheriff-star torso, black legs).
    /// The Rebrickable name is purely descriptive, so the alias map is
    /// what lets users find it via the colloquial name.
    func testSearchByAliasFindsClassicTownPoliceOfficer() async {
        let catalog = MinifigureCatalog.shared
        await catalog.load()
        let results = catalog.search(
            query: "classic town police officer",
            themes: [],
            yearRange: nil,
            sort: .nameAsc
        )
        XCTAssertTrue(
            results.contains(where: { $0.id == "fig-000697" }),
            "Expected fig-000697 to be returned for the alias 'classic town police officer'."
        )
    }
}
