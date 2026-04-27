import XCTest
@testable import Bricky

final class PhotoSubjectClassifierTests: XCTestCase {

    private typealias Subject = PhotoSubjectClassifier.Subject
    private typealias Label = PhotoSubjectClassifier.ScoredLabel

    func testEmptyLabelsAreAmbiguous() {
        XCTAssertEqual(PhotoSubjectClassifier.classify(labels: []), .ambiguous)
    }

    func testStrongMinifigureLabelsClassifyAsMinifigure() {
        let labels = [
            Label(identifier: "figurine",       confidence: 0.55),
            Label(identifier: "action_figure",  confidence: 0.20),
            Label(identifier: "block",          confidence: 0.05)
        ]
        XCTAssertEqual(PhotoSubjectClassifier.classify(labels: labels), .minifigure)
    }

    func testStrongBrickLabelsClassifyAsBrick() {
        let labels = [
            Label(identifier: "toy_block",       confidence: 0.45),
            Label(identifier: "building_block",  confidence: 0.25),
            Label(identifier: "construction_toy",confidence: 0.10),
            Label(identifier: "doll",            confidence: 0.04)
        ]
        XCTAssertEqual(PhotoSubjectClassifier.classify(labels: labels), .brick)
    }

    func testCloseScoresAreAmbiguous() {
        // Both buckets land within the 0.15 margin → ambiguous.
        let labels = [
            Label(identifier: "figurine", confidence: 0.30),
            Label(identifier: "block",    confidence: 0.25)
        ]
        XCTAssertEqual(PhotoSubjectClassifier.classify(labels: labels), .ambiguous)
    }

    func testIrrelevantLabelsAreAmbiguous() {
        let labels = [
            Label(identifier: "table",  confidence: 0.40),
            Label(identifier: "carpet", confidence: 0.20)
        ]
        XCTAssertEqual(PhotoSubjectClassifier.classify(labels: labels), .ambiguous)
    }

    func testSubstringMatchingPicksUpCompoundLabels() {
        // "lego_brick" should still score in the brick bucket via "brick".
        let labels = [
            Label(identifier: "lego_brick", confidence: 0.50),
            Label(identifier: "plastic",    confidence: 0.10)
        ]
        XCTAssertEqual(PhotoSubjectClassifier.classify(labels: labels), .brick)
    }
}
