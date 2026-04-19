import XCTest
@testable import Bricky

final class BrickLinkURLTests: XCTestCase {

    // MARK: - Parts (BrickLink)

    func testPartURL() {
        let url = BrickLinkService.partURL("3001")
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.absoluteString.contains("P=3001"),
                      "Got: \(url!.absoluteString)")
        XCTAssertTrue(url!.absoluteString.hasPrefix("https://www.bricklink.com/v2/catalog/catalogitem.page"))
    }

    func testPartSearchURLUsesSearchPageWithPartsCategory() {
        let url = BrickLinkService.partSearchURL("973pb1234c01")
        XCTAssertNotNil(url)
        let s = url!.absoluteString
        XCTAssertTrue(s.contains("search.page"), "Got: \(s)")
        XCTAssertTrue(s.contains("q=973pb1234c01"), "Got: \(s)")
        XCTAssertTrue(s.contains("category"), "Got: \(s)")
        XCTAssertTrue(s.contains("=P"), "Got: \(s)")
    }

    func testPartURLWithColor() {
        let url = BrickLinkService.partURL("3001", color: .red)
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.absoluteString.contains("P=3001"))
        XCTAssertTrue(url!.absoluteString.contains("idColor=5"))
    }

    func testPriceGuideURL() {
        let url = BrickLinkService.priceGuideURL(part: "3001", color: .blue)
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.absoluteString.contains("3001"))
        XCTAssertTrue(url!.absoluteString.contains("idColor=7"))
        XCTAssertTrue(url!.absoluteString.contains("#T=P"))
    }

    func testPartIdWithSpecialCharsIsEscaped() {
        // Some BL part numbers contain letters (e.g. "970c00").
        let url = BrickLinkService.partURL("970c00")
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.absoluteString.contains("970c00"))
    }

    // MARK: - Minifigures (Rebrickable)

    func testRebrickableMinifigureURL() {
        let url = BrickLinkService.rebrickableMinifigureURL("fig-001234")
        XCTAssertNotNil(url)
        XCTAssertEqual(url!.absoluteString,
                       "https://rebrickable.com/minifigs/fig-001234/")
    }

    func testRebrickableMinifigureURLPreservesFigPrefix() {
        // The old (broken) BrickLink code stripped "fig-" but Rebrickable
        // NEEDS the full id including the prefix.
        let url = BrickLinkService.rebrickableMinifigureURL("fig-000001")
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.absoluteString.contains("fig-000001"))
    }

    // MARK: - Minifigures (BrickLink search)

    func testBrickLinkMinifigureSearchURLFormat() {
        let url = BrickLinkService.brickLinkMinifigureSearchURL(name: "Classic Spaceman")
        XCTAssertNotNil(url)
        let s = url!.absoluteString
        XCTAssertTrue(s.hasPrefix("https://www.bricklink.com/v2/search.page"))
        XCTAssertTrue(s.contains("q=Classic"))
        XCTAssertTrue(s.contains("Spaceman"))
        // Minifigure category filter (M)
        XCTAssertTrue(s.contains("category"))
        XCTAssertTrue(s.contains("=M"))
    }

    func testBrickLinkMinifigureSearchURLEscapesSpecialChars() {
        let url = BrickLinkService.brickLinkMinifigureSearchURL(name: "Star Wars & Rebels")
        XCTAssertNotNil(url)
        let s = url!.absoluteString
        // Ampersand must be percent-encoded so it doesn't split queries.
        XCTAssertTrue(s.contains("%26"),
                      "Expected '&' to be escaped as %26, got: \(s)")
    }
}
