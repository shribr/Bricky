import XCTest
import UIKit
@testable import Bricky

final class PhotoVoxelizerTests: XCTestCase {

    private func solidImage(color: UIColor, size: CGSize = CGSize(width: 120, height: 120)) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    /// A distinct filled shape on a plain white background — the subject-isolation
    /// cascade (foreground/saliency) should latch onto the shape.
    private func subjectImage(color: UIColor = .systemBlue, size: CGSize = CGSize(width: 200, height: 200)) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            color.setFill()
            let inset = size.width * 0.22
            ctx.cgContext.fillEllipse(in: CGRect(x: inset, y: inset,
                                                 width: size.width - inset * 2,
                                                 height: size.height - inset * 2))
        }
    }

    func testCenterCroppedKeepsCentralRegion() throws {
        let cg = try XCTUnwrap(subjectImage(size: CGSize(width: 100, height: 80)).cgImage)
        let cropped = PhotoVoxelizer.centerCropped(cg, fraction: 0.5)
        XCTAssertEqual(cropped.width, Int((CGFloat(cg.width) * 0.5).rounded()))
        XCTAssertEqual(cropped.height, Int((CGFloat(cg.height) * 0.5).rounded()))
        XCTAssertLessThan(cropped.width, cg.width)
    }

    func testSolidImageStillProducesModelViaCenterCrop() throws {
        // No detectable subject → centre-crop fallback still yields a buildable
        // model (robust), rather than blocking the whole feature.
        let image = solidImage(color: UIColor(red: 0.79, green: 0.10, blue: 0.04, alpha: 1))
        let model = try PhotoVoxelizer.voxelize(image: image, size: .small, subject: "Red")
        XCTAssertFalse(model.isEmpty)
        XCTAssertEqual(model.source, .photo)
    }

    func testVoxelizeSubjectImageProducesModel() throws {
        let model = try PhotoVoxelizer.voxelize(image: subjectImage(), size: .small, subject: "Blob")
        XCTAssertFalse(model.isEmpty)
        XCTAssertEqual(model.source, .photo)
    }

    func testVoxelizeThenForgeProducesBuildableSet() throws {
        let model = try PhotoVoxelizer.voxelize(image: subjectImage(color: .systemGreen), size: .small, subject: "Blob")
        let set = try SetForgeEngine.shared.generate(from: model, size: .small, name: "Blob")
        XCTAssertGreaterThan(set.brickCount, 0)
        XCTAssertFalse(set.parts.isEmpty)
        XCTAssertFalse(set.steps.isEmpty)
    }

    func testGridRespectsSizePreset() throws {
        let image = subjectImage(color: .systemRed)
        let small = try PhotoVoxelizer.voxelize(image: image, size: .small, subject: "G")
        let large = try PhotoVoxelizer.voxelize(image: image, size: .large, subject: "G")
        XCTAssertGreaterThanOrEqual(large.width, small.width)
        XCTAssertLessThanOrEqual(small.width, VoxelModel.Size.small.maxDimension)
    }
}
