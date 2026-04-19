import XCTest
@testable import Bricky

@MainActor
final class MinifigureCatalogUserFiguresTests: XCTestCase {

    private var docsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("userMinifigures.json")
    }

    override func setUp() {
        super.setUp()
        // Wipe any prior persisted user figures + in-memory state.
        try? FileManager.default.removeItem(at: docsURL)
        let catalog = MinifigureCatalog.shared
        for fig in catalog.userFigures {
            catalog.removeUserFigure(id: fig.id)
        }
    }

    override func tearDown() {
        let catalog = MinifigureCatalog.shared
        for fig in catalog.userFigures {
            catalog.removeUserFigure(id: fig.id)
        }
        try? FileManager.default.removeItem(at: docsURL)
        super.tearDown()
    }

    private func makeUserFigure(name: String = "Custom Spaceman",
                                theme: String = "Custom") -> Minifigure {
        Minifigure(
            id: MinifigureCatalog.newUserFigureId(),
            name: name,
            theme: theme,
            year: 2026,
            partCount: 0,
            imgURL: nil,
            parts: []
        )
    }

    // MARK: - Id helpers

    func testNewUserFigureIdHasUserPrefix() {
        let id = MinifigureCatalog.newUserFigureId()
        XCTAssertTrue(id.hasPrefix(MinifigureCatalog.userFigureIdPrefix))
        XCTAssertTrue(MinifigureCatalog.isUserFigureId(id))
    }

    func testIsUserFigureIdRejectsBundledIds() {
        XCTAssertFalse(MinifigureCatalog.isUserFigureId("fig-001234"))
        XCTAssertFalse(MinifigureCatalog.isUserFigureId("sw0001a"))
    }

    // MARK: - CRUD

    func testAddUserFigurePersistsAndLooksUp() {
        let catalog = MinifigureCatalog.shared
        let fig = makeUserFigure()
        catalog.addUserFigure(fig)

        XCTAssertTrue(catalog.userFigures.contains(where: { $0.id == fig.id }))
        XCTAssertEqual(catalog.figure(id: fig.id)?.name, "Custom Spaceman")
    }

    func testAddUserFigureAppearsInAllFigures() {
        let catalog = MinifigureCatalog.shared
        let fig = makeUserFigure(name: "All-Figures Test")
        catalog.addUserFigure(fig)
        XCTAssertTrue(catalog.allFigures.contains(where: { $0.id == fig.id }))
    }

    func testAddUserFigureWithExistingIdReplaces() {
        let catalog = MinifigureCatalog.shared
        var fig = makeUserFigure(name: "Original")
        catalog.addUserFigure(fig)

        fig = Minifigure(id: fig.id,
                         name: "Updated",
                         theme: fig.theme,
                         year: fig.year,
                         partCount: fig.partCount,
                         imgURL: fig.imgURL,
                         parts: fig.parts)
        catalog.addUserFigure(fig)

        let matches = catalog.userFigures.filter { $0.id == fig.id }
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.name, "Updated")
    }

    func testRemoveUserFigureRemovesFromIndexes() {
        let catalog = MinifigureCatalog.shared
        let fig = makeUserFigure(name: "Doomed")
        catalog.addUserFigure(fig)
        XCTAssertNotNil(catalog.figure(id: fig.id))

        catalog.removeUserFigure(id: fig.id)

        XCTAssertNil(catalog.figure(id: fig.id))
        XCTAssertFalse(catalog.userFigures.contains(where: { $0.id == fig.id }))
        XCTAssertFalse(catalog.allFigures.contains(where: { $0.id == fig.id }))
    }

    func testRemoveBundledIdIsNoOp() {
        let catalog = MinifigureCatalog.shared
        let fig = makeUserFigure()
        catalog.addUserFigure(fig)
        // A bundled-style id should be ignored entirely.
        catalog.removeUserFigure(id: "fig-999999")
        XCTAssertNotNil(catalog.figure(id: fig.id))
    }

    // MARK: - Persistence

    func testUserFigureSurvivesReencode() {
        let catalog = MinifigureCatalog.shared
        let fig = makeUserFigure(name: "Persistence Probe")
        catalog.addUserFigure(fig)

        XCTAssertTrue(FileManager.default.fileExists(atPath: docsURL.path),
                      "userMinifigures.json should be written on add")

        // Round-trip through Codable to mirror cold-launch decode.
        let data = try! Data(contentsOf: docsURL)
        let decoded = try! JSONDecoder().decode([Minifigure].self, from: data)
        XCTAssertTrue(decoded.contains(where: { $0.id == fig.id && $0.name == "Persistence Probe" }))
    }
}
