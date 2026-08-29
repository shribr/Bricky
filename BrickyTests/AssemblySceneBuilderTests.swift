import XCTest
import SceneKit
@testable import Bricky

/// Phase 5 — shared scene builder placement math.
final class AssemblySceneBuilderTests: XCTestCase {

    func testContentNodeHasOneChildPerPlacement() {
        let model = AssemblyModel(placements: [
            BrickPlacement(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3),
                           color: .red, position: GridPosition(x: 0, y: 0, z: 0), step: 1),
            BrickPlacement(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3),
                           color: .blue, position: GridPosition(x: 0, y: 3, z: 0), step: 2),
        ])
        let node = AssemblySceneBuilder.contentNode(for: model)
        XCTAssertEqual(node.childNodes.count, 2)
    }

    func testBrickNodeCentersFootprintAtGridPosition() {
        // 2×4 brick at grid (0,0,0): container sits at footprint centre
        // (x+w/2, y, z+l/2) × pitch = (1*8, 0, 2*8).
        let placement = BrickPlacement(
            category: .brick,
            dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3),
            color: .red,
            position: GridPosition(x: 0, y: 0, z: 0),
            step: 1
        )
        let node = AssemblySceneBuilder.brickNode(for: placement)
        let pitch = BrickGeometryGenerator.studPitch
        XCTAssertEqual(node.position.x, 1 * pitch, accuracy: 0.001)
        XCTAssertEqual(node.position.z, 2 * pitch, accuracy: 0.001)
    }

    func testRotatedFootprintSwapsCenterAxes() {
        // 1×4 brick rotated 90°: footprint spans 4 along X, 1 along Z, so the
        // centre offsets swap → (x + 4/2, .., z + 1/2) × pitch.
        let placement = BrickPlacement(
            category: .brick,
            dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 3),
            color: .red,
            position: GridPosition(x: 0, y: 0, z: 0),
            rotationDegrees: 90,
            step: 1
        )
        let node = AssemblySceneBuilder.brickNode(for: placement)
        let pitch = BrickGeometryGenerator.studPitch
        XCTAssertEqual(node.position.x, 2 * pitch, accuracy: 0.001) // 4/2
        XCTAssertEqual(node.position.z, 0.5 * pitch, accuracy: 0.001) // 1/2
    }
}
