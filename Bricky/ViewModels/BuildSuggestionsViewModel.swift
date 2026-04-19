import SwiftUI

/// ViewModel for build suggestions
@MainActor
final class BuildSuggestionsViewModel: ObservableObject {
    @Published var suggestions: [BuildSuggestionEngine.BuildSuggestion] = []
    @Published var selectedCategory: ProjectCategory?
    @Published var selectedDifficulty: Difficulty?
    @Published var showOnlyCompletable = false
    @Published var isLoading = false

    private let engine = BuildSuggestionEngine.shared

    var filteredSuggestions: [BuildSuggestionEngine.BuildSuggestion] {
        var result = suggestions

        if let category = selectedCategory {
            result = result.filter { $0.project.category == category }
        }

        if let difficulty = selectedDifficulty {
            result = result.filter { $0.project.difficulty == difficulty }
        }

        if showOnlyCompletable {
            result = result.filter { $0.isCompleteBuild }
        }

        return result
    }

    var completeBuildCount: Int {
        suggestions.filter { $0.isCompleteBuild }.count
    }

    var partialBuildCount: Int {
        suggestions.filter { !$0.isCompleteBuild }.count
    }

    func generateSuggestions(from pieces: [LegoPiece]) {
        isLoading = true
        // Simulate a brief loading for better UX
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            self.suggestions = self.engine.getSuggestions(for: pieces)
            self.isLoading = false
        }
    }

    func refreshSuggestions(from pieces: [LegoPiece]) {
        suggestions = engine.getSuggestions(for: pieces)
    }
}
