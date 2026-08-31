import XCTest
import CoreGraphics
@testable import Bricky

/// Unit tests for the pure crop-geometry helpers behind PhotoVoxelizer's
/// subject-isolation cascade.
///
/// NOTE: The Vision requests themselves (person segmentation, foreground
/// instance mask, saliency) do not run meaningfully in the iOS Simulator, so
/// they are intentionally NOT exercised here. Only the deterministic, pure
/// helpers — `alphaBounds` and `pixelRect` — are covered.
final class PhotoVoxelizerSubjectTests: XCTestCase {

    // MARK: - alphaBounds

    /// Builds an RGBA (premultiplied-last) buffer with a rectangular opaque
    /// region; every other pixel is fully transparent.
    private func rgba(
        width: Int,
        height: Int,
        opaque: CGRect
    ) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                guard opaque.contains(CGPoint(x: x, y: y)) else { continue }
                let base = (y * width + x) * 4
                bytes[base + 0] = 200
                bytes[base + 1] = 100
                bytes[base + 2] = 50
                bytes[base + 3] = 255
            }
        }
        return bytes
    }

    func testAlphaBoundsTightlyWrapsOpaqueRegion() throws {
        // 10×10 image, opaque block spanning x:2...5, y:3...7.
        let opaque = CGRect(x: 2, y: 3, width: 4, height: 5)
        let bytes = rgba(width: 10, height: 10, opaque: opaque)

        let result = try XCTUnwrap(PhotoVoxelizer.alphaBounds(rgba: bytes, width: 10, height: 10))
        XCTAssertEqual(result.rect, CGRect(x: 2, y: 3, width: 4, height: 5))
        // 20 opaque pixels out of 100.
        XCTAssertEqual(result.coverage, 0.20, accuracy: 0.0001)
    }

    func testAlphaBoundsFullyOpaqueImageIsWholeFrame() throws {
        let bytes = rgba(width: 6, height: 4, opaque: CGRect(x: 0, y: 0, width: 6, height: 4))
        let result = try XCTUnwrap(PhotoVoxelizer.alphaBounds(rgba: bytes, width: 6, height: 4))
        XCTAssertEqual(result.rect, CGRect(x: 0, y: 0, width: 6, height: 4))
        XCTAssertEqual(result.coverage, 1.0, accuracy: 0.0001)
    }

    func testAlphaBoundsFullyTransparentReturnsNil() {
        let bytes = [UInt8](repeating: 0, count: 8 * 8 * 4)
        XCTAssertNil(PhotoVoxelizer.alphaBounds(rgba: bytes, width: 8, height: 8))
    }

    func testAlphaBoundsRespectsAlphaThreshold() {
        // Single pixel with alpha = 10; threshold of 40 should reject it.
        var bytes = [UInt8](repeating: 0, count: 4 * 4 * 4)
        let base = (1 * 4 + 1) * 4
        bytes[base + 3] = 10
        XCTAssertNil(PhotoVoxelizer.alphaBounds(rgba: bytes, width: 4, height: 4, alphaThreshold: 40))

        // Same pixel clears a threshold of 5.
        let hit = PhotoVoxelizer.alphaBounds(rgba: bytes, width: 4, height: 4, alphaThreshold: 5)
        XCTAssertEqual(hit?.rect, CGRect(x: 1, y: 1, width: 1, height: 1))
    }

    func testAlphaBoundsRejectsUndersizedBuffer() {
        // Buffer too small for the declared dimensions → nil, no crash.
        let bytes = [UInt8](repeating: 255, count: 4)
        XCTAssertNil(PhotoVoxelizer.alphaBounds(rgba: bytes, width: 10, height: 10))
    }

    // MARK: - pixelRect (Vision normalized → CGImage pixel space)

    func testPixelRectFlipsVisionOriginToTopLeft() {
        // Vision rect at the TOP-LEFT of a 100×200 image: normalized origin is
        // bottom-left, so a top-left quadrant is x:0, y:0.5, w:0.5, h:0.5.
        let normalized = CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        let rect = PhotoVoxelizer.pixelRect(fromNormalized: normalized, imageWidth: 100, imageHeight: 200)
        // Top-left origin: x = 0, width = 50, height = 100, y flipped:
        // y = (1 - maxY) * h = (1 - 1.0) * 200 = 0.
        XCTAssertEqual(rect, CGRect(x: 0, y: 0, width: 50, height: 100))
    }

    func testPixelRectBottomLeftRegionMapsToBottomOfImage() {
        // Vision bottom-left quadrant → bottom-left in top-left space.
        let normalized = CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        let rect = PhotoVoxelizer.pixelRect(fromNormalized: normalized, imageWidth: 100, imageHeight: 200)
        // y = (1 - 0.5) * 200 = 100.
        XCTAssertEqual(rect, CGRect(x: 0, y: 100, width: 50, height: 100))
    }

    func testPixelRectFullFrameIsWholeImage() {
        let rect = PhotoVoxelizer.pixelRect(
            fromNormalized: CGRect(x: 0, y: 0, width: 1, height: 1),
            imageWidth: 320, imageHeight: 240
        )
        XCTAssertEqual(rect, CGRect(x: 0, y: 0, width: 320, height: 240))
    }
}
