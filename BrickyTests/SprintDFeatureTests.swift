import XCTest
@testable import Bricky
import SwiftUI

final class SprintDFeatureTests: XCTestCase {

    // MARK: - Confidence Color Helpers

    func testConfidenceColorHighReturnsGreen() {
        let color = Color.confidenceColor(0.95)
        XCTAssertEqual(color, .green)
    }

    func testConfidenceColorMediumReturnsOrange() {
        let color = Color.confidenceColor(0.8)
        XCTAssertEqual(color, .orange)
    }

    func testConfidenceColorLowReturnsRed() {
        let color = Color.confidenceColor(0.5)
        XCTAssertEqual(color, .red)
    }

    func testConfidenceColorBoundaryAt90() {
        XCTAssertEqual(Color.confidenceColor(0.9), .green)
        XCTAssertEqual(Color.confidenceColor(0.89), .orange)
    }

    func testConfidenceColorBoundaryAt70() {
        XCTAssertEqual(Color.confidenceColor(0.7), .orange)
        XCTAssertEqual(Color.confidenceColor(0.69), .red)
    }

    func testConfidenceColorPerfect() {
        XCTAssertEqual(Color.confidenceColor(1.0), .green)
    }

    func testConfidenceColorZero() {
        XCTAssertEqual(Color.confidenceColor(0.0), .red)
    }

    // MARK: - Confidence Icon Helpers

    func testConfidenceIconHigh() {
        XCTAssertEqual(Color.confidenceIcon(0.95), "checkmark.seal.fill")
    }

    func testConfidenceIconMedium() {
        XCTAssertEqual(Color.confidenceIcon(0.8), "exclamationmark.triangle.fill")
    }

    func testConfidenceIconLow() {
        XCTAssertEqual(Color.confidenceIcon(0.5), "questionmark.circle.fill")
    }

    func testConfidenceIconBoundaryAt90() {
        XCTAssertEqual(Color.confidenceIcon(0.9), "checkmark.seal.fill")
        XCTAssertEqual(Color.confidenceIcon(0.89), "exclamationmark.triangle.fill")
    }

    func testConfidenceIconBoundaryAt70() {
        XCTAssertEqual(Color.confidenceIcon(0.7), "exclamationmark.triangle.fill")
        XCTAssertEqual(Color.confidenceIcon(0.69), "questionmark.circle.fill")
    }

    // MARK: - Confidence Distribution in Scan Session

    func testScanSessionConfidenceDistribution() {
        let session = ScanSession()

        // Add pieces with varying confidence
        let highConf = LegoPiece(
            partNumber: "3001", name: "Brick 2×4", category: .brick, color: .red,
            dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3),
            confidence: 0.95
        )
        let medConf = LegoPiece(
            partNumber: "3003", name: "Brick 2×2", category: .brick, color: .blue,
            dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3),
            confidence: 0.75
        )
        let lowConf = LegoPiece(
            partNumber: "3020", name: "Plate 2×4", category: .plate, color: .green,
            dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1),
            confidence: 0.5
        )

        session.addPiece(highConf)
        session.addPiece(medConf)
        session.addPiece(lowConf)

        let high = session.pieces.filter { $0.confidence >= 0.9 }.count
        let med = session.pieces.filter { $0.confidence >= 0.7 && $0.confidence < 0.9 }.count
        let low = session.pieces.filter { $0.confidence < 0.7 }.count

        XCTAssertEqual(high, 1)
        XCTAssertEqual(med, 1)
        XCTAssertEqual(low, 1)
    }

    func testScanSessionAllHighConfidence() {
        let session = ScanSession()

        for i in 0..<5 {
            let piece = LegoPiece(
                partNumber: "300\(i)", name: "Piece \(i)", category: .brick, color: .red,
                dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3),
                confidence: Double.random(in: 0.9...1.0)
            )
            session.addPiece(piece)
        }

        let lowConf = session.pieces.filter { $0.confidence < 0.7 }.count
        XCTAssertEqual(lowConf, 0)
    }

    // MARK: - LEGO Brand Colors Unchanged

    func testLegoRedColor() {
        let color = Color.legoRed
        XCTAssertNotNil(color)
    }

    func testLegoBlueColor() {
        let color = Color.legoBlue
        XCTAssertNotNil(color)
    }

    func testLegoYellowColor() {
        let color = Color.legoYellow
        XCTAssertNotNil(color)
    }

    func testLegoGreenColor() {
        let color = Color.legoGreen
        XCTAssertNotNil(color)
    }

    func testLegoOrangeColor() {
        let color = Color.legoOrange
        XCTAssertNotNil(color)
    }

    // MARK: - Color Hex Initialization

    func testHexColor6Digit() {
        let color = Color(hex: "FF0000")
        XCTAssertNotNil(color)
    }

    func testHexColor3Digit() {
        let color = Color(hex: "F00")
        XCTAssertNotNil(color)
    }

    func testHexColor8Digit() {
        let color = Color(hex: "80FF0000")
        XCTAssertNotNil(color)
    }

    func testHexColorWithHash() {
        let color = Color(hex: "#FF6834")
        XCTAssertNotNil(color)
    }

    // MARK: - LegoColor to Color Mapping

    func testLegoColorMappingAllCases() {
        for legoColor in LegoColor.allCases {
            let color = Color.legoColor(legoColor)
            XCTAssertNotNil(color, "Color mapping failed for \(legoColor.rawValue)")
        }
    }

    // MARK: - Confidence-Dependent Piece Behavior

    func testPieceDefaultConfidenceIsOne() {
        let piece = LegoPiece(
            partNumber: "3001", name: "Brick 2×4", category: .brick, color: .red,
            dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3)
        )
        XCTAssertEqual(piece.confidence, 1.0)
        XCTAssertEqual(Color.confidenceColor(piece.confidence), .green)
        XCTAssertEqual(Color.confidenceIcon(piece.confidence), "checkmark.seal.fill")
    }

    func testPieceLowConfidenceShowsWarning() {
        let piece = LegoPiece(
            partNumber: "3001", name: "Brick 2×4", category: .brick, color: .red,
            dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3),
            confidence: 0.65
        )
        XCTAssertEqual(Color.confidenceColor(piece.confidence), .red)
        XCTAssertEqual(Color.confidenceIcon(piece.confidence), "questionmark.circle.fill")
    }

    func testPieceMediumConfidenceShowsCaution() {
        let piece = LegoPiece(
            partNumber: "3001", name: "Brick 2×4", category: .brick, color: .red,
            dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3),
            confidence: 0.85
        )
        XCTAssertEqual(Color.confidenceColor(piece.confidence), .orange)
        XCTAssertEqual(Color.confidenceIcon(piece.confidence), "exclamationmark.triangle.fill")
    }

    // MARK: - Edge Cases

    func testConfidenceColorNegativeValue() {
        XCTAssertEqual(Color.confidenceColor(-0.1), .red)
    }

    func testConfidenceColorAboveOne() {
        // Values above 1.0 should still be treated as high confidence
        XCTAssertEqual(Color.confidenceColor(1.5), .green)
    }

    func testConfidenceIconNegativeValue() {
        XCTAssertEqual(Color.confidenceIcon(-0.1), "questionmark.circle.fill")
    }

    func testConfidenceIconAboveOne() {
        XCTAssertEqual(Color.confidenceIcon(1.5), "checkmark.seal.fill")
    }
}
