import XCTest
@testable import Bricky

final class FavoritesStoreTests: XCTestCase {

    var store: FavoritesStore!

    @MainActor
    override func setUp() {
        super.setUp()
        store = FavoritesStore.shared
        // Clear any existing favorites for clean test state
        for id in store.favoritedProjectIds {
            store.toggle(id)
        }
    }

    @MainActor
    func testToggleFavorite() {
        let id = UUID()
        XCTAssertFalse(store.isFavorited(id))

        store.toggle(id)
        XCTAssertTrue(store.isFavorited(id))

        store.toggle(id)
        XCTAssertFalse(store.isFavorited(id))
    }

    @MainActor
    func testMultipleFavorites() {
        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()

        store.toggle(id1)
        store.toggle(id2)
        store.toggle(id3)

        XCTAssertTrue(store.isFavorited(id1))
        XCTAssertTrue(store.isFavorited(id2))
        XCTAssertTrue(store.isFavorited(id3))
        XCTAssertEqual(store.favoritedProjectIds.count, 3)

        store.toggle(id2)
        XCTAssertFalse(store.isFavorited(id2))
        XCTAssertEqual(store.favoritedProjectIds.count, 2)
    }

    @MainActor
    override func tearDown() {
        // Clean up
        for id in store.favoritedProjectIds {
            store.toggle(id)
        }
        super.tearDown()
    }
}
