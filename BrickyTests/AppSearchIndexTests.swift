import XCTest
@testable import Bricky

@MainActor
final class AppSearchIndexTests: XCTestCase {

    private var service: AppSearchService { AppSearchService.shared }

    private func group(_ category: AppSearchCategory, in groups: [AppSearchGroup]) -> AppSearchGroup? {
        groups.first { $0.category == category }
    }

    // MARK: - Cross-app coverage

    func testThreeDSearchSpansFeaturesSettingsHelpAndTutorials() {
        let groups = service.search("3D")
        let categories = Set(groups.map(\.category))

        XCTAssertTrue(categories.contains(.feature), "Pro \"3D Model Export\" / Set Forge features should match")
        XCTAssertTrue(categories.contains(.setting), "\"3D Reconstruction\" setting should match")
        XCTAssertTrue(categories.contains(.helpArticle), "\"What is the 3D model viewer?\" should match")
        XCTAssertTrue(categories.contains(.tutorial), "\"Follow 3D instructions\" should match")
    }

    func testThreeDSearchFindsSpecificItems() {
        let groups = service.search("3D")
        let settingTitles = group(.setting, in: groups)?.results.map(\.entry.title) ?? []
        let helpTitles = group(.helpArticle, in: groups)?.results.map(\.entry.title) ?? []

        XCTAssertTrue(settingTitles.contains("3D Reconstruction"))
        XCTAssertTrue(helpTitles.contains("What is the 3D model viewer?"))
    }

    func testGroupsAreOrderedByCategory() {
        let groups = service.search("scan")
        let order = AppSearchCategory.allCases
        let indexes = groups.compactMap { order.firstIndex(of: $0.category) }
        XCTAssertEqual(indexes, indexes.sorted())
        XCTAssertFalse(groups.isEmpty)
    }

    func testEveryResultBelongsToItsGroup() {
        for group in service.search("brick") {
            XCTAssertFalse(group.results.isEmpty)
            for result in group.results {
                XCTAssertEqual(result.entry.category, group.category)
            }
        }
    }

    // MARK: - Query handling

    func testTooShortQueryReturnsNothing() {
        XCTAssertTrue(service.search("").isEmpty)
        XCTAssertTrue(service.search("a").isEmpty)
        XCTAssertTrue(service.search("   ").isEmpty)
    }

    func testNonsenseQueryReturnsNothing() {
        XCTAssertTrue(service.search("zzqxjvkw").isEmpty)
    }

    func testSearchIsCaseInsensitive() {
        let lower = service.search("icloud").flatMap(\.results).map(\.entry.id)
        let upper = service.search("ICLOUD").flatMap(\.results).map(\.entry.id)
        XCTAssertFalse(lower.isEmpty)
        XCTAssertEqual(Set(lower), Set(upper))
    }

    func testMultipleWordsMustAllMatch() {
        let both = service.search("offline scan").flatMap(\.results)
        XCTAssertFalse(both.isEmpty)
        let none = service.search("offline zzqxjvkw")
        XCTAssertTrue(none.isEmpty)
    }

    func testTitleMatchRanksAboveBodyMatch() {
        let features = group(.feature, in: service.search("Scanner"))?.results ?? []
        XCTAssertEqual(features.first?.entry.title, "Scanner")
    }

    // MARK: - Destinations

    func testSettingResultsPointAtTheirSection() {
        let results = service.search("Color Theme").flatMap(\.results)
        let theme = results.first { $0.entry.title == "Color Theme" }
        XCTAssertEqual(theme?.entry.destination, .setting(.appearance))
    }

    func testHelpResultsCarryTheirQuestion() {
        let results = service.search("How do I scan my LEGO pieces").flatMap(\.results)
        let article = results.first { $0.entry.category == .helpArticle }
        XCTAssertEqual(article?.entry.destination, .helpArticle(question: "How do I scan my LEGO pieces?"))
    }

    func testBuildExplainerIsReachableFromFeatureResult() {
        let results = service.search("See What You Can Build").flatMap(\.results)
        let feature = results.first { $0.entry.id == "feature.seeWhatYouCanBuild" }
        XCTAssertEqual(feature?.entry.destination, .tutorial(.buildExplainer))
    }

    // MARK: - Caps

    func testCatalogGroupsAreCapped() {
        for group in service.search("an") where group.category.isCapped {
            XCTAssertLessThanOrEqual(group.results.count, AppSearchService.maxResultsPerCategory)
            XCTAssertGreaterThanOrEqual(group.totalCount, group.results.count)
        }
    }

    // MARK: - Text helpers

    func testWordStartBeatsInsideMatch() {
        XCTAssertEqual(AppSearchText.match("3d", in: "3d model export"), .wordStart)
        XCTAssertEqual(AppSearchText.match("3d", in: "export 3d model"), .wordStart)
        XCTAssertEqual(AppSearchText.match("rick", in: "brick"), .inside)
        XCTAssertEqual(AppSearchText.match("xyz", in: "brick"), .none)
    }

    func testFoldingIgnoresCaseAndDiacritics() {
        XCTAssertEqual(AppSearchText.fold("Café"), AppSearchText.fold("cafe"))
        XCTAssertEqual(AppSearchText.tokens("  Foo   BAR "), ["foo", "bar"])
    }

    func testSnippetCentersOnMatch() {
        let text = String(repeating: "lorem ipsum ", count: 30) + "needle in the haystack " + String(repeating: "dolor sit ", count: 30)
        let snippet = AppSearchText.snippet(of: text, tokens: ["needle"])
        XCTAssertTrue(snippet.contains("needle"))
        XCTAssertLessThan(snippet.count, text.count)
        XCTAssertTrue(snippet.hasPrefix("…"))
    }

    func testMatchRangesFindEveryOccurrence() {
        let text = "3D and 3d and 3D"
        XCTAssertEqual(AppSearchText.matchRanges(of: ["3d"], in: text).count, 3)
    }
}
