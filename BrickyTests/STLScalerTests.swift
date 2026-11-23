import XCTest
import simd
@testable import Bricky

final class STLScalerTests: XCTestCase {

    private func brick(_ x: Int, _ y: Int, _ z: Int, length: Int = 1) -> PlacedBrick {
        PlacedBrick(x: x, y: y, z: z, length: length, color: .red)
    }

    func testIdentityScaleReturnsSameBytes() {
        let data = SetForgeSTLExporter.export([brick(0, 0, 0, length: 2)])
        XCTAssertEqual(STLScaler.scaled(data, by: 1), data)
    }

    func testScalesVertexPositionsUniformly() throws {
        let data = SetForgeSTLExporter.export([brick(0, 0, 0, length: 2)])
        let originalSize = try XCTUnwrap(STLBounds.size(of: data))

        let halved = STLScaler.scaled(data, by: 0.5)
        let halvedSize = try XCTUnwrap(STLBounds.size(of: halved))

        XCTAssertEqual(halvedSize.x, originalSize.x * 0.5, accuracy: 0.001)
        XCTAssertEqual(halvedSize.y, originalSize.y * 0.5, accuracy: 0.001)
        XCTAssertEqual(halvedSize.z, originalSize.z * 0.5, accuracy: 0.001)
    }

    func testPreservesTriangleCountAndIsDeterministic() {
        let data = SetForgeSTLExporter.export([brick(0, 0, 0), brick(1, 0, 0, length: 3)])
        let scaledOnce = STLScaler.scaled(data, by: 0.75)
        let scaledTwice = STLScaler.scaled(data, by: 0.75)
        XCTAssertEqual(scaledOnce.count, data.count, "Scaling must not change the triangle count/byte layout")
        XCTAssertEqual(scaledOnce, scaledTwice, "Deterministic: same input and factor always yields identical bytes")
    }

    func testMalformedDataReturnsUnchanged() {
        XCTAssertEqual(STLScaler.scaled(Data(), by: 0.5), Data())

        var truncated = SetForgeSTLExporter.export([brick(0, 0, 0)])
        truncated.removeLast()
        XCTAssertEqual(STLScaler.scaled(truncated, by: 0.5), truncated)
    }
}
