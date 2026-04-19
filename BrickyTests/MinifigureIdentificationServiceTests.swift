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

    // MARK: - Resolver

    func testResolveByExactId() {
        let figures = [fig("fig-000001", "Classic Spaceman")]
        let byId: (String) -> Minifigure? = { id in
            figures.first { $0.id == id }
        }
        let candidate = AzureAIService.MinifigureCandidate(
            figId: "fig-000001",
            name: "anything",
            confidence: 0.9,
            reasoning: ""
        )
        let resolved = MinifigureIdentificationService.shared
            .resolve(candidate: candidate, in: figures, byId: byId)
        XCTAssertEqual(resolved?.id, "fig-000001")
    }

    func testResolveByExactNameCaseInsensitive() {
        let figures = [fig("fig-000001", "Classic Spaceman")]
        let candidate = AzureAIService.MinifigureCandidate(
            figId: "",
            name: "CLASSIC SPACEMAN",
            confidence: 0.9,
            reasoning: ""
        )
        let resolved = MinifigureIdentificationService.shared
            .resolve(candidate: candidate, in: figures, byId: { _ in nil })
        XCTAssertEqual(resolved?.id, "fig-000001")
    }

    func testResolveBySubstring() {
        let figures = [fig("fig-000001", "Classic Spaceman, White Suit")]
        let candidate = AzureAIService.MinifigureCandidate(
            figId: "",
            name: "Classic Spaceman",
            confidence: 0.9,
            reasoning: ""
        )
        let resolved = MinifigureIdentificationService.shared
            .resolve(candidate: candidate, in: figures, byId: { _ in nil })
        XCTAssertEqual(resolved?.id, "fig-000001")
    }

    func testResolveByFuzzyMatch() {
        let figures = [
            fig("fig-000001", "Classic Spaceman"),
            fig("fig-000002", "Wizard")
        ]
        let candidate = AzureAIService.MinifigureCandidate(
            figId: "",
            name: "clasic spacman",   // typos
            confidence: 0.9,
            reasoning: ""
        )
        let resolved = MinifigureIdentificationService.shared
            .resolve(candidate: candidate, in: figures, byId: { _ in nil })
        XCTAssertEqual(resolved?.id, "fig-000001")
    }

    func testResolveReturnsNilWhenNoMatch() {
        let figures = [fig("fig-000001", "Wizard")]
        let candidate = AzureAIService.MinifigureCandidate(
            figId: "",
            name: "totally unrelated content here",
            confidence: 0.9,
            reasoning: ""
        )
        let resolved = MinifigureIdentificationService.shared
            .resolve(candidate: candidate, in: figures, byId: { _ in nil })
        XCTAssertNil(resolved)
    }

    // MARK: - resolveAll (multi-match)

    func testResolveAllReturnsEveryExactNameMatch() {
        // "Island Warrior" appears multiple times in the catalog (different
        // releases / variants). All should be returned.
        let figures = [
            fig("fig-IW-1", "Island Warrior"),
            fig("fig-IW-2", "Island Warrior"),
            fig("fig-IW-3", "Island Warrior"),
            fig("fig-WIZ", "Wizard")
        ]
        let candidate = AzureAIService.MinifigureCandidate(
            figId: "",
            name: "Island Warrior",
            confidence: 0.95,
            reasoning: ""
        )
        let matches = MinifigureIdentificationService.shared
            .resolveAll(candidate: candidate, in: figures, byId: { _ in nil })

        let ids = Set(matches.map(\.figure.id))
        XCTAssertEqual(ids, ["fig-IW-1", "fig-IW-2", "fig-IW-3"])
        // All exact name matches should be in the exactName tier
        XCTAssertTrue(matches.allSatisfy { $0.tier == .exactName })
    }

    func testResolveAllExactIdShortCircuits() {
        let figures = [
            fig("fig-IW-1", "Island Warrior"),
            fig("fig-IW-2", "Island Warrior")
        ]
        let candidate = AzureAIService.MinifigureCandidate(
            figId: "fig-IW-2",
            name: "Island Warrior",
            confidence: 0.99,
            reasoning: ""
        )
        let matches = MinifigureIdentificationService.shared
            .resolveAll(candidate: candidate,
                        in: figures,
                        byId: { id in figures.first { $0.id == id } })
        XCTAssertEqual(matches.map(\.figure.id), ["fig-IW-2"])
        XCTAssertEqual(matches.first?.tier, .exactId)
    }

    func testResolveAllSubstringIncludesAllVariants() {
        let figures = [
            fig("fig-1", "Island Warrior, Red Mask"),
            fig("fig-2", "Island Warrior, Yellow Mask"),
            fig("fig-3", "Castle Wizard")
        ]
        let candidate = AzureAIService.MinifigureCandidate(
            figId: "",
            name: "Island Warrior",
            confidence: 0.9,
            reasoning: ""
        )
        let matches = MinifigureIdentificationService.shared
            .resolveAll(candidate: candidate, in: figures, byId: { _ in nil })
        let ids = Set(matches.map(\.figure.id))
        XCTAssertTrue(ids.contains("fig-1"))
        XCTAssertTrue(ids.contains("fig-2"))
        XCTAssertFalse(ids.contains("fig-3"))
        // Substring matches should be in the substring tier
        XCTAssertTrue(matches.allSatisfy { $0.tier == .substring })
    }

    func testResolveAllReturnsEmptyWhenNoMatch() {
        let figures = [fig("fig-1", "Wizard")]
        let candidate = AzureAIService.MinifigureCandidate(
            figId: "",
            name: "totally unrelated content here",
            confidence: 0.9,
            reasoning: ""
        )
        let matches = MinifigureIdentificationService.shared
            .resolveAll(candidate: candidate, in: figures, byId: { _ in nil })
        XCTAssertTrue(matches.isEmpty)
    }
}
