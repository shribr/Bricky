import XCTest
@testable import Bricky

/// Unit tests for the gray-world white-balance transform used to reduce color
/// casts before LEGO-color classification. These prove the transform's math is
/// correct; they do NOT assert live-scan accuracy gains.
final class IlluminationNormalizerTests: XCTestCase {

    func testNeutralSceneYieldsIdentityGains() {
        let g = IlluminationNormalizer.gains(meanR: 128, meanG: 128, meanB: 128)
        XCTAssertEqual(g.r, 1, accuracy: 0.0001)
        XCTAssertEqual(g.g, 1, accuracy: 0.0001)
        XCTAssertEqual(g.b, 1, accuracy: 0.0001)
        XCTAssertTrue(g.isIdentity)
    }

    func testWarmCastBoostsBlueAndCutsRed() {
        // Warm light: lots of red, little blue. Gray-world should scale blue up
        // and red down so the corrected means move toward neutral.
        let g = IlluminationNormalizer.gains(meanR: 180, meanG: 120, meanB: 60)
        XCTAssertLessThan(g.r, 1, "red should be attenuated under a warm cast")
        XCTAssertGreaterThan(g.b, 1, "blue should be boosted under a warm cast")
        XCTAssertEqual(g.g, 1, accuracy: 0.02, "green near the gray mean stays ~1")
    }

    func testGainsAreClamped() {
        // Extreme cast (almost no blue) must not produce an unbounded gain.
        let g = IlluminationNormalizer.gains(meanR: 250, meanG: 250, meanB: 1)
        XCTAssertLessThanOrEqual(g.b, IlluminationNormalizer.maxGain)
        XCTAssertGreaterThanOrEqual(g.r, IlluminationNormalizer.minGain)
    }

    func testZeroMeanIsSafe() {
        let g = IlluminationNormalizer.gains(meanR: 0, meanG: 0, meanB: 0)
        XCTAssertTrue(g.isIdentity)
    }

    func testApplyCorrectsWarmCastTowardNeutral() {
        // A gray patch under a warm cast (r>g>b) should read closer to neutral
        // after applying gains derived from that same cast.
        let gains = IlluminationNormalizer.gains(meanR: 180, meanG: 120, meanB: 60)
        let (r, g, b) = IlluminationNormalizer.apply(gains, r: 180.0 / 255, g: 120.0 / 255, b: 60.0 / 255)
        // Corrected channels should be closer together than the raw ones.
        let rawSpread = (180.0 - 60.0) / 255
        let correctedSpread = max(r, g, b) - min(r, g, b)
        XCTAssertLessThan(correctedSpread, rawSpread)
    }

    func testApplyClampsToUnitRange() {
        let gains = WhiteBalanceGains(r: 1.8, g: 1, b: 1)
        let (r, _, _) = IlluminationNormalizer.apply(gains, r: 0.9, g: 0.5, b: 0.5)
        XCTAssertLessThanOrEqual(r, 1)
        XCTAssertGreaterThanOrEqual(r, 0)
    }

    func testIdentityGainsLeavePixelUnchanged() {
        let (r, g, b) = IlluminationNormalizer.apply(.identity, r: 0.4, g: 0.6, b: 0.2)
        XCTAssertEqual(r, 0.4, accuracy: 0.0001)
        XCTAssertEqual(g, 0.6, accuracy: 0.0001)
        XCTAssertEqual(b, 0.2, accuracy: 0.0001)
    }
}
