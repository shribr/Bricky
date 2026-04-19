import XCTest
import UIKit
@testable import Bricky

@MainActor
final class MinifigureImageCacheTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MinifigureImageCache.shared.clear()
    }

    override func tearDown() {
        MinifigureImageCache.shared.clear()
        super.tearDown()
    }

    private func dummyImage() -> UIImage {
        let size = CGSize(width: 10, height: 10)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    func testStoreAndRetrieve() {
        let url = URL(string: "https://cdn.rebrickable.com/media/sets/fig-000001.jpg")!
        let img = dummyImage()

        MinifigureImageCache.shared.store(img, for: url, bytes: 1024)

        let retrieved = MinifigureImageCache.shared.image(for: url)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.size, img.size)
    }

    func testRetrieveMissReturnsNil() {
        let url = URL(string: "https://cdn.rebrickable.com/media/sets/fig-999999.jpg")!
        XCTAssertNil(MinifigureImageCache.shared.image(for: url))
    }

    func testClearEmptiesCache() {
        let url = URL(string: "https://cdn.rebrickable.com/media/sets/fig-000002.jpg")!
        MinifigureImageCache.shared.store(dummyImage(), for: url, bytes: 1024)
        XCTAssertNotNil(MinifigureImageCache.shared.image(for: url))

        MinifigureImageCache.shared.clear()
        XCTAssertNil(MinifigureImageCache.shared.image(for: url))
    }

    func testDifferentURLsAreCachedIndependently() {
        let u1 = URL(string: "https://cdn.rebrickable.com/media/sets/fig-000001.jpg")!
        let u2 = URL(string: "https://cdn.rebrickable.com/media/sets/fig-000002.jpg")!

        MinifigureImageCache.shared.store(dummyImage(), for: u1, bytes: 1024)
        XCTAssertNotNil(MinifigureImageCache.shared.image(for: u1))
        XCTAssertNil(MinifigureImageCache.shared.image(for: u2))
    }
}
