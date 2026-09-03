import XCTest
import UIKit
@testable import Bricky

@MainActor
final class BrickCorrectionRerankerTests: XCTestCase {

    private var store: BrickCorrectionStore!
    private var reranker: BrickCorrectionReranker!

    override func setUp() {
        super.setUp()
        store = BrickCorrectionStore(directoryName: "brickCorrectionsRerankTest-\(UUID().uuidString)")
        reranker = BrickCorrectionReranker(store: store)
    }

    override func tearDown() {
        store.clear()
        super.tearDown()
    }

    /// Scale-1 gradient so the CGImage is exactly `size` pixels (no Retina
    /// upscaling) and non-trivial enough for a valid Vision feature print.
    private func gradientImage(size: CGSize = CGSize(width: 64, height: 64)) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cs = CGColorSpaceCreateDeviceRGB()
            let colors = [UIColor.red.cgColor, UIColor.systemBlue.cgColor, UIColor.green.cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 0.5, 1])!
            ctx.cgContext.drawLinearGradient(
                gradient, start: .zero,
                end: CGPoint(x: size.width, y: size.height), options: []
            )
        }
    }

    private func detection(size: CGFloat = 64) -> BrickClassificationPipeline.BrickDetection {
        BrickClassificationPipeline.BrickDetection(
            boundingBox: CGRect(x: 0, y: 0, width: 1, height: 1),
            pixelRect: CGRect(x: 0, y: 0, width: size, height: size),
            partNumber: "9999",
            name: "Wrong Guess",
            category: .brick,
            color: .red,
            dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3),
            confidence: 0.5,
            colorHistogram: [.red: 1.0]
        )
    }

    func testEmptyStoreLeavesDetectionsUnchanged() {
        let out = reranker.apply(to: [detection()], in: gradientImage(), using: store.corrections)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].category, .brick)
        XCTAssertEqual(out[0].color, .red)
    }

    func testMatchingCropAppliesShapeAndColorCorrection() throws {
        let img = gradientImage()
        guard let cg = img.cgImage, BrickCorrectionReranker.featurePrint(for: cg) != nil else {
            throw XCTSkip("Vision feature prints unavailable in this environment")
        }
        store.record(
            crop: img, partNumber: "3001", name: "Plate 2×6",
            category: .plate, color: .blue, studsWide: 2, studsLong: 6,
            heightUnits: 1, correctedShape: true, correctedColor: true
        )
        let out = reranker.apply(to: [detection()], in: img, using: store.corrections)
        XCTAssertEqual(out[0].partNumber, "3001")
        XCTAssertEqual(out[0].category, .plate)
        XCTAssertEqual(out[0].color, .blue)
        XCTAssertEqual(out[0].dimensions.studsLong, 6)
        XCTAssertEqual(out[0].shapeConfidence, 0.97, accuracy: 0.0001)
        XCTAssertEqual(out[0].colorConfidence, 0.97, accuracy: 0.0001)
    }

    func testColorOnlyCorrectionLeavesShapeUntouched() throws {
        let img = gradientImage()
        guard let cg = img.cgImage, BrickCorrectionReranker.featurePrint(for: cg) != nil else {
            throw XCTSkip("Vision feature prints unavailable in this environment")
        }
        store.record(
            crop: img, partNumber: "3001", name: "Plate",
            category: .plate, color: .blue, studsWide: 2, studsLong: 6,
            heightUnits: 1, correctedShape: false, correctedColor: true
        )
        let out = reranker.apply(to: [detection()], in: img, using: store.corrections)
        XCTAssertEqual(out[0].color, .blue, "color should be corrected")
        XCTAssertEqual(out[0].category, .brick, "shape must be untouched")
        XCTAssertEqual(out[0].partNumber, "9999", "shape must be untouched")
    }

    // MARK: - Deterministic override logic (no Vision dependency)

    private func correction(
        correctedShape: Bool,
        correctedColor: Bool
    ) -> BrickCorrection {
        BrickCorrection(
            id: UUID(), date: Date(), imageName: "x.jpg",
            partNumber: "3001", name: "Plate 2×6",
            category: .plate, color: .blue,
            studsWide: 2, studsLong: 6, heightUnits: 1,
            correctedShape: correctedShape, correctedColor: correctedColor
        )
    }

    func testApplyCorrectionOverridesBothWhenBothCorrected() {
        let out = reranker.applyCorrection(correction(correctedShape: true, correctedColor: true), to: detection())
        XCTAssertEqual(out.partNumber, "3001")
        XCTAssertEqual(out.category, .plate)
        XCTAssertEqual(out.color, .blue)
        XCTAssertEqual(out.dimensions.studsLong, 6)
        XCTAssertEqual(out.shapeConfidence, 0.97, accuracy: 0.0001)
        XCTAssertEqual(out.colorConfidence, 0.97, accuracy: 0.0001)
    }

    func testApplyCorrectionShapeOnlyKeepsColor() {
        let out = reranker.applyCorrection(correction(correctedShape: true, correctedColor: false), to: detection())
        XCTAssertEqual(out.category, .plate, "shape corrected")
        XCTAssertEqual(out.color, .red, "color untouched")
        XCTAssertEqual(out.shapeConfidence, 0.97, accuracy: 0.0001)
        XCTAssertEqual(out.colorConfidence, 0.5, accuracy: 0.0001, "color confidence unchanged")
    }

    func testApplyCorrectionColorOnlyKeepsShape() {
        let out = reranker.applyCorrection(correction(correctedShape: false, correctedColor: true), to: detection())
        XCTAssertEqual(out.color, .blue, "color corrected")
        XCTAssertEqual(out.category, .brick, "shape untouched")
        XCTAssertEqual(out.partNumber, "9999", "shape untouched")
        XCTAssertEqual(out.colorConfidence, 0.97, accuracy: 0.0001)
        XCTAssertEqual(out.shapeConfidence, 0.5, accuracy: 0.0001, "shape confidence unchanged")
    }

    // MARK: - Server correction index

    func testL2AndDecodeFloat32() {
        XCTAssertEqual(BrickCorrectionReranker.l2([0, 0], [3, 4]) ?? -1, 5, accuracy: 0.0001)
        let vals: [Float] = [1, -2.5, 3.25]
        let data = vals.withUnsafeBytes { Data($0) }
        XCTAssertEqual(BrickCorrectionReranker.decodeFloat32(data), vals)
    }

    func testApplyServerEntryOverridesShapeAndColor() throws {
        let part = try XCTUnwrap(LegoPartsCatalog.shared.pieces.first)
        let entry = ServerCorrectionEntry(
            clusterId: "c1", embeddingBase64: "", shapeLabel: part.partNumber,
            colorLabel: LegoColor.blue.rawValue, members: 5,
            shapeConfidence: 0.9, colorConfidence: 0.8
        )
        let out = reranker.applyServerEntry(entry, to: detection())
        XCTAssertEqual(out.partNumber, part.partNumber)
        XCTAssertEqual(out.category, part.category)
        XCTAssertEqual(out.color, .blue)
        XCTAssertGreaterThanOrEqual(out.shapeConfidence, 0.9 - 0.0001)
        XCTAssertGreaterThanOrEqual(out.colorConfidence, 0.8 - 0.0001)
    }

    func testApplyServerEntryColorOnlyLeavesShape() {
        let entry = ServerCorrectionEntry(
            clusterId: "c2", embeddingBase64: "", shapeLabel: nil,
            colorLabel: LegoColor.blue.rawValue, members: 3,
            shapeConfidence: 0, colorConfidence: 0.7
        )
        let out = reranker.applyServerEntry(entry, to: detection())
        XCTAssertEqual(out.color, .blue, "color corrected")
        XCTAssertEqual(out.category, .brick, "shape untouched")
        XCTAssertEqual(out.partNumber, "9999", "shape untouched")
    }

    func testApplyServerIndexEmptyEntriesIsNoOp() {
        let out = reranker.applyServerIndex(to: [detection()], in: gradientImage(), using: [])
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].color, .red)
    }
}
