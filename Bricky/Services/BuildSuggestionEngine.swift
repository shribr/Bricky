import Foundation

/// Engine that suggests buildable projects from `Resources/BuildProjects.json`.
///
/// History: previously the project library was authored as ~4,300 LOC of
/// inline `LegoProject(...)` constructor calls split across 4 Swift files
/// (the engine plus three "Extended" pagination files). The library is
/// pure data, so it now lives in a JSON resource instead.
final class BuildSuggestionEngine {
    static let shared = BuildSuggestionEngine()

    private(set) var allProjects: [LegoProject] = []

    private init() {
        loadProjects()
    }

    /// Get build suggestions sorted by match percentage
    func getSuggestions(for pieces: [LegoPiece]) -> [BuildSuggestion] {
        allProjects.map { project in
            BuildSuggestion(
                project: project,
                matchPercentage: project.matchPercentage(with: pieces),
                missingPieces: project.missingPieces(from: pieces)
            )
        }
        .filter { $0.matchPercentage > 0.3 } // At least 30% match
        .sorted { $0.matchPercentage > $1.matchPercentage }
    }

    /// Get projects that can be fully built
    func getCompleteBuildable(for pieces: [LegoPiece]) -> [LegoProject] {
        allProjects.filter { $0.matchPercentage(with: pieces) >= 1.0 }
    }

    struct BuildSuggestion: Identifiable {
        let id = UUID()
        let project: LegoProject
        let matchPercentage: Double
        let missingPieces: [RequiredPiece]

        var isCompleteBuild: Bool { matchPercentage >= 1.0 }
        var percentageText: String { "\(Int(matchPercentage * 100))%" }
    }

    // MARK: - JSON Loading

    private func loadProjects() {
        guard let url = Bundle.main.url(forResource: "BuildProjects", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            assertionFailure("BuildProjects.json missing from app bundle")
            allProjects = []
            return
        }
        do {
            allProjects = try JSONDecoder().decode([LegoProject].self, from: data)
        } catch {
            assertionFailure("Failed to decode BuildProjects.json: \(error)")
            allProjects = []
        }
    }
}
