import SwiftUI

/// ViewModel for build suggestions
@MainActor
final class BuildSuggestionsViewModel: ObservableObject {
    @Published var suggestions: [BuildSuggestionEngine.BuildSuggestion] = []
    @Published var aiIdeas: [AzureAIService.AIBuildIdea] = []
    @Published var selectedCategory: ProjectCategory?
    @Published var selectedDifficulty: Difficulty?
    @Published var showOnlyCompletable = false
    @Published var isLoading = false
    @Published var isLoadingAI = false
    @Published var aiError: String?

    private let engine = BuildSuggestionEngine.shared
    private let aiService = AzureAIService.shared
    private let config = AzureConfiguration.shared

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

    var canUseAI: Bool {
        config.canUseOnlineMode
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

    func generateAIIdeas(from pieces: [LegoPiece]) {
        guard !pieces.isEmpty else {
            aiError = "Scan some pieces first to get AI build ideas."
            return
        }
        isLoadingAI = true
        aiError = nil

        Task {
            do {
                let ideas = try await aiService.generateBuildIdeas(from: pieces)
                self.aiIdeas = ideas
            } catch {
                self.aiError = error.localizedDescription
            }
            self.isLoadingAI = false
        }
    }
}
