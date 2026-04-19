import XCTest
@testable import Bricky

@MainActor
final class MinifigureIdentificationServiceTests: XCTestCase {

    private func fig(_ id: String, _ name: String, theme: String = "Test") -> Minifigure {
        Minifigure(
            id: id,
            name: name,
            theme: theme,
            year: 2024,
            partCount: 0,
            imgURL: nil,
            parts: []
        )
    }

    // MARK: - Fuzzy score

    func testFuzzyScoreIdenticalStringsIsOne() {
        XCTAssertEqual(
            MinifigureIdentificationService.fuzzyScore("spaceman", "spaceman"),
            1.0,
            accuracy: 0.001
        )
    }

    func testFuzzyScoreOneEmptyIsZero() {
        XCTAssertEqual(
            MinifigureIdentificationService.fuzzyScore("anakin", ""),
            0.0
        )
        XCTAssertEqual(
            MinifigureIdentificationService.fuzzyScore("", "anakin"),
            0.0
        )
    }

    func testFuzzyScoreSimilarStringsAreClose() {
        // "spaceman" vs "spacemen" — one-char swap.
        let score = MinifigureIdentificationService.fuzzyScore("spaceman", "spacemen")
        XCTAssertGreaterThan(score, 0.8)
    }

    func testFuzzyScoreDifferentStringsAreFarApart() {
        let score = MinifigureIdentificationService.fuzzyScore("spaceman", "wizard")
        XCTAssertLessThan(score, 0.5)
    }
}
