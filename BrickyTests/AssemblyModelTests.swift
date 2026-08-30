import XCTest
@testable import Bricky

/// Phase 0 — assembly data model: decoding, derivation, and back-compat.
final class AssemblyModelTests: XCTestCase {

    private func placement(
        _ category: PieceCategory = .brick,
        _ w: Int = 2, _ l: Int = 4, _ h: Int = 3,
        color: LegoColor = .red,
        x: Int = 0, y: Int = 0, z: Int = 0,
        step: Int
    ) -> BrickPlacement {
        BrickPlacement(
            category: category,
            dimensions: PieceDimensions(studsWide: w, studsLong: l, heightUnits: h),
            color: color,
            position: GridPosition(x: x, y: y, z: z),
            step: step
        )
    }

    // MARK: - Derivation

    func testStepCountAndPerStepGrouping() {
        let model = AssemblyModel(placements: [
            placement(step: 1),
            placement(step: 1),
            placement(step: 2),
            placement(step: 3)
        ])
        XCTAssertEqual(model.stepCount, 3)
        XCTAssertEqual(model.placements(inStep: 1).count, 2)
        XCTAssertEqual(model.placements(inStep: 2).count, 1)
        XCTAssertEqual(model.cumulativePlacements(throughStep: 2).count, 3)
        XCTAssertEqual(model.cumulativePlacements(throughStep: 3).count, 4)
    }

    func testEmptyModelDerivations() {
        let model = AssemblyModel(placements: [])
        XCTAssertEqual(model.stepCount, 0)
        XCTAssertTrue(model.bounds.isEmpty)
        XCTAssertTrue(model.derivedRequiredPieces.isEmpty)
    }

    func testBoundsSpanAllPlacements() {
        let model = AssemblyModel(placements: [
            placement(x: 0, y: 0, z: 0, step: 1),
            placement(x: 4, y: 3, z: 2, step: 2),
            placement(x: -2, y: 6, z: 8, step: 3)
        ])
        XCTAssertEqual(model.bounds.min, GridPosition(x: -2, y: 0, z: 0))
        XCTAssertEqual(model.bounds.max, GridPosition(x: 4, y: 6, z: 8))
    }

    func testDerivedRequiredPiecesAggregatesByPartColor() {
        let model = AssemblyModel(placements: [
            placement(.brick, 2, 4, 3, color: .red, step: 1),
            placement(.brick, 2, 4, 3, color: .red, step: 1),
            placement(.brick, 2, 4, 3, color: .blue, step: 2),
            placement(.plate, 2, 2, 1, color: .red, step: 3)
        ])
        let derived = model.derivedRequiredPieces
        XCTAssertEqual(derived.count, 3)
        // Total quantity preserved across aggregation.
        XCTAssertEqual(derived.reduce(0) { $0 + $1.quantity }, 4)

        let redBrick = derived.first {
            $0.category == .brick && $0.colorPreference == .red
        }
        XCTAssertEqual(redBrick?.quantity, 2)
        XCTAssertEqual(redBrick?.flexible, false)
    }

    // MARK: - Entities (connected components)

    func testEntitiesSeparatesDisconnectedClusters() {
        let model = AssemblyModel(placements: [
            placement(.brick, 1, 1, 1, x: 0, z: 0, step: 1),
            placement(.brick, 1, 1, 1, x: 1, z: 0, step: 2),    // touches (0,0)
            placement(.brick, 1, 1, 1, x: 10, z: 10, step: 3)   // far away
        ])
        XCTAssertEqual(model.entities.count, 2)
    }

    func testEntitiesConnectsTouchingBricks() {
        let model = AssemblyModel(placements: [
            placement(.brick, 1, 1, 1, x: 0, z: 0, step: 1),
            placement(.brick, 1, 1, 1, x: 1, z: 0, step: 2),
            placement(.brick, 1, 1, 1, x: 0, z: 1, step: 3)
        ])
        XCTAssertEqual(model.entities.count, 1)
    }

    func testStepEntityIndicesDistinguishSeparateEntities() {
        let model = AssemblyModel(placements: [
            placement(.brick, 1, 1, 1, x: 0, z: 0, step: 1),    // entity A
            placement(.brick, 1, 1, 1, x: 10, z: 10, step: 2)   // entity B
        ])
        let idx = model.stepEntityIndices()
        XCTAssertEqual(idx.count, 2)
        XCTAssertNotEqual(idx[0], idx[1])
    }

    func testEmptyModelHasNoEntities() {
        XCTAssertTrue(AssemblyModel(placements: []).entities.isEmpty)
    }

    // MARK: - Codable round-trip

    func testAssemblyModelRoundTrips() throws {
        let model = AssemblyModel(placements: [
            placement(x: 1, y: 0, z: 2, step: 1),
            BrickPlacement(
                category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1),
                color: .brown, partNumber: "3022",
                position: GridPosition(x: 0, y: 3, z: 0), rotationDegrees: 90, step: 2
            )
        ])
        let data = try JSONEncoder().encode(model)
        let decoded = try JSONDecoder().decode(AssemblyModel.self, from: data)
        XCTAssertEqual(decoded, model)
    }

    // MARK: - LegoProject integration & back-compat

    func testProjectWithAssemblyDerivesRequiredPieces() {
        let assembly = AssemblyModel(placements: [
            placement(.brick, 2, 4, 3, color: .red, step: 1),
            placement(.brick, 2, 4, 3, color: .red, step: 2)
        ])
        let project = LegoProject(
            name: "Test", description: "", difficulty: .beginner, category: .vehicle,
            estimatedTime: "5 min", requiredPieces: [], instructions: [],
            imageSystemName: "car.fill", assembly: assembly
        )
        XCTAssertEqual(project.effectiveRequiredPieces.count, 1)
        XCTAssertEqual(project.effectiveRequiredPieces.first?.quantity, 2)
    }

    func testLegacyProjectJSONWithoutAssemblyDecodes() throws {
        // No "assembly" key — must decode with assembly == nil and fall back to
        // the stored required-pieces list.
        let json = """
        {
          "id": "4B27F1CA-7D6E-4D48-84A3-48C3F43935C5",
          "name": "Legacy",
          "description": "",
          "difficulty": "Easy",
          "category": "Vehicles",
          "estimatedTime": "15 min",
          "requiredPieces": [
            { "category": "Brick",
              "colorPreference": "Red",
              "dimensions": { "heightUnits": 3, "studsLong": 4, "studsWide": 2 },
              "flexible": false, "quantity": 2 }
          ],
          "instructions": [],
          "imageSystemName": "car.fill",
          "isFavorited": false
        }
        """
        let project = try JSONDecoder().decode(LegoProject.self, from: Data(json.utf8))
        XCTAssertNil(project.assembly)
        XCTAssertEqual(project.effectiveRequiredPieces.count, 1)
        XCTAssertEqual(project.effectiveRequiredPieces.first?.quantity, 2)
    }
}
