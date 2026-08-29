import XCTest
@testable import Bricky

/// Bundled LDraw build models — load, validity, and project wiring.
final class LDrawModelLibraryTests: XCTestCase {

    func testChairModelLoadsAsValidAssembly() {
        guard let assembly = LDrawModelLibrary.assembly(forProjectNamed: "Chair") else {
            return XCTFail("Chair model should be bundled")
        }
        XCTAssertEqual(assembly.placements.count, 9)   // 4 legs + seat + 2×2 backrest
        XCTAssertEqual(assembly.stepCount, 4)
        XCTAssertTrue(assembly.placements.allSatisfy { $0.color == .brown })
        XCTAssertTrue(AssemblyValidator.validate(assembly).isValid)
    }

    func testCottageModelLoadsAsValidAssembly() {
        guard let assembly = LDrawModelLibrary.assembly(forProjectNamed: "Cozy Cottage") else {
            return XCTFail("Cottage model should be bundled")
        }
        XCTAssertEqual(assembly.placements.count, 19)  // 8 + 8 walls + 3 roof
        XCTAssertEqual(assembly.stepCount, 3)
        XCTAssertTrue(AssemblyValidator.validate(assembly).isValid)
    }

    func testTowerModelLoadsAsValidAssembly() {
        guard let assembly = LDrawModelLibrary.assembly(forProjectNamed: "Castle Tower") else {
            return XCTFail("Tower model should be bundled")
        }
        XCTAssertEqual(assembly.placements.count, 10)  // 6 body + 4 battlements
        XCTAssertEqual(assembly.stepCount, 7)
        XCTAssertTrue(AssemblyValidator.validate(assembly).isValid)
    }

    func testDeskModelLoadsAsValidAssembly() {
        guard let assembly = LDrawModelLibrary.assembly(forProjectNamed: "Desk") else {
            return XCTFail("Desk model should be bundled")
        }
        XCTAssertEqual(assembly.placements.count, 6)   // 4 legs + 2 top plates
        XCTAssertEqual(assembly.stepCount, 2)
        XCTAssertTrue(AssemblyValidator.validate(assembly).isValid)
    }

    func testUnknownProjectHasNoBundledModel() {
        XCTAssertNil(LDrawModelLibrary.assembly(forProjectNamed: "No Such Project"))
    }

    func testChairProjectResolvesToBundledModel() {
        guard let chair = BuildSuggestionEngine.shared.allProjects.first(where: { $0.name == "Chair" }) else {
            return XCTFail("Chair project should exist in the catalog")
        }
        // resolvedAssembly should prefer the bundled LDraw model over procedural.
        XCTAssertEqual(chair.resolvedAssembly.placements.count, 9)
        XCTAssertEqual(chair.resolvedAssembly.stepCount, 4)
    }
}
