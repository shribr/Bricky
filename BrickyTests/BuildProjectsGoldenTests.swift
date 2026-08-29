import XCTest
@testable import Bricky

/// Phase 6 — golden / regression coverage: every catalog project must resolve to
/// a valid, coherent assembly whose steps match its pieces, and generation must
/// be deterministic so renders don't drift between launches.
final class BuildProjectsGoldenTests: XCTestCase {

    private var projects: [LegoProject] { BuildSuggestionEngine.shared.allProjects }

    func testCatalogLoaded() {
        XCTAssertFalse(projects.isEmpty, "BuildProjects.json should load some projects")
    }

    func testEveryProjectResolvesToAValidAssembly() {
        for project in projects {
            let assembly = project.resolvedAssembly

            // Structurally sound: gapless steps, all stepped, nothing floats.
            let result = AssemblyValidator.validate(assembly)
            XCTAssertTrue(result.isValid, "\(project.name): \(result.issues)")
            XCTAssertFalse(assembly.placements.isEmpty, "\(project.name): should have placements")

            // Procedurally-generated projects place exactly their required
            // pieces; authored / bundled-LDraw models are their own source of
            // truth and may differ.
            let isProcedural = project.assembly == nil
                && !LDrawModelLibrary.hasModel(forProjectNamed: project.name)
            if isProcedural {
                let requiredTotal = project.requiredPieces.reduce(0) { $0 + $1.quantity }
                XCTAssertEqual(assembly.placements.count, requiredTotal,
                               "\(project.name): placement count should equal total required pieces")
            }
        }
    }

    func testEveryProjectProducesUsableSteps() {
        for project in projects where !project.requiredPieces.isEmpty {
            let assembly = project.resolvedAssembly
            let steps = BuildStepPlanner.steps(for: assembly)

            XCTAssertEqual(steps.count, assembly.stepCount, "\(project.name): one BuildStep per step")
            // Gapless, monotonic step numbers.
            XCTAssertEqual(steps.map(\.stepNumber), Array(1...steps.count), "\(project.name): steps must be 1…N")
            // Non-empty instruction + piece list per step.
            for step in steps {
                XCTAssertFalse(step.instruction.isEmpty, "\(project.name) step \(step.stepNumber): empty instruction")
                XCTAssertFalse(step.piecesUsed.isEmpty, "\(project.name) step \(step.stepNumber): empty piece list")
            }
        }
    }

    func testGenerationIsDeterministic() {
        // The same project must generate byte-identical placements each time, so
        // the 3D preview / instructions never drift between app launches.
        guard let project = projects.first(where: { !$0.requiredPieces.isEmpty }) else {
            return XCTFail("No project with pieces to check")
        }
        let a = ProceduralAssemblyGenerator.generate(from: project.requiredPieces)
        let b = ProceduralAssemblyGenerator.generate(from: project.requiredPieces)
        XCTAssertEqual(a.placements.map(\.position), b.placements.map(\.position))
        XCTAssertEqual(a.placements.map(\.step), b.placements.map(\.step))
        XCTAssertEqual(a.placements.map(\.color), b.placements.map(\.color))
    }

    func testDerivedPieceTotalsMatchTheBuild() {
        // Pieces summarised across all steps must equal the placements rendered.
        for project in projects {
            let assembly = project.resolvedAssembly
            let stepTotal = (1...max(1, assembly.stepCount))
                .reduce(0) { $0 + assembly.placements(inStep: $1).count }
            XCTAssertEqual(stepTotal, assembly.placements.count,
                           "\(project.name): steps must cover every placement")
        }
    }
}
